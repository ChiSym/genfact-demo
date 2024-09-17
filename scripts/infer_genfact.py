"""
Run GenFact name finding on some sentences and save the extracted information.

The input and output are both JSONL.
"""
from argparse import ArgumentParser
from copy import deepcopy
import json
import logging
import os
from pathlib import Path
import string
import time
from typing import Any, Iterable, Iterator, Optional, Sequence

import genparse
import requests
from requests.auth import HTTPBasicAuth
from transformers import AutoTokenizer, PreTrainedTokenizer

from scripts.utils.jsonl import read_jsonl, write_jsonl


logger = logging.getLogger(__name__)


REPO_ROOT = Path(__file__).resolve().parent.parent
GENPARSE_SERVER_MODEL = "meta-llama/Meta-Llama-3.1-8B-Instruct"
GRAMMAR = (REPO_ROOT / "resources" / "json_grammar.lark").read_text(encoding="utf-8")
JSON_PROMPT_TEMPLATE = string.Template(
    (REPO_ROOT / "resources" / "templates" / "json_prompt_template.txt").read_text(encoding="utf-8").replace(
        "{{{:sentence}}}", "$sentence"
    )
)

PROPOSAL_NAME = "character"
SAMPLING_METHOD = "smc-standard"
DEFAULT_BATCH_SIZE = 8
DEFAULT_RESTART_SERVER_EVERY = 120
CONNECT_TIMEOUT_SECONDS = 3.05
DEFAULT_RESTART_REQUEST_TIMEOUT_SECONDS = 30
DEFAULT_RESTART_REQUEST_WAIT_TIME_SECONDS = 90
DEFAULT_N_PARTICLES = 15
MAX_TOKENS = 128
DEFAULT_TEMPERATURE = 1.0
WAIT_FOR_GENPARSE_REBOOT = 60


def _join_names(genparse_output: dict[str, Any]) -> Optional[str]:
    """
    Given a single Genparse inference, return the joined doctor name.
    """
    names = []
    if genparse_output.get("first") is not None:
        names.append(genparse_output["first"])
    if genparse_output.get("last") is not None:
        names.append(genparse_output["last"])
    if names:
        result = " ".join(names)
    else:
        result = None
    return result


def make_prompt(sentence_datum: dict[str, Any], *, tokenizer: PreTrainedTokenizer) -> str:
    """
    Given a sentence datum and tokenizer, format the prompt appropriately to prompt the model.
    """
    result = tokenizer.apply_chat_template(
        [{"role": "user", "content": JSON_PROMPT_TEMPLATE.substitute(sentence=sentence_datum["sentence"])}], tokenize=False
    )
    return result


# Translated from GenFact server code, src/genparse/extract_entities.jl.
# Current as of 8895efe5f5e51d5bfdd0300d8d4ffd7e0568f2aa
def _normalize_json_object(json_string: str) -> str:
    """
    Normalize a raw JSON object string into a standard form.

    This parses the string as an object, sorts by keys, then re-serializes it to eliminate variation in whitespace.
    """
    return json.dumps(dict(sorted(json.loads(json_string).items(), key=lambda t: t[0])))


# Translated from GenFact server code, src/genparse/extract_entities.jl.
# Current as of 8895efe5f5e51d5bfdd0300d8d4ffd7e0568f2aa
def _sort_posterior(posterior: dict[str, float]) -> dict[str, float]:
    """Sort a posterior distribution so the highest likelihood output comes first.

    Breaks ties by preferring the alphabetically earliest inference. This does not explicitly handle Unicode and so
    it will probably sort in UTF-8 code unit order instead of in collation order.

    The posterior should be a dict-like object mapping strings-like objects to float-likes.
    This returns a value in the same format.
    """
    return dict(sorted(posterior.items(), key=lambda t: (t[1], t[0]), reverse=True))


# Translated from GenFact server code, src/genparse/extract_entities.jl.
# Current as of 8895efe5f5e51d5bfdd0300d8d4ffd7e0568f2aa
def _aggregate_identical_json(posterior: dict[str, float]) -> dict[str, float]:
    """Convert a raw-JSON posterior into a normalized-JSON posterior.

    The posterior should be a dict-like object mapping strings-like objects (unparsed JSON) to float-likes.
    This returns a value in the same format.
    """
    result = {}
    for inference, likelihood in posterior.items():
        normalized = _normalize_json_object(inference)
        result.setdefault(normalized, 0.0)
        result[normalized] += likelihood
    return _sort_posterior(result)



class NotCodeError(Exception):
    pass



# Translated from GenFact server code, src/genparse/extract_entities.jl,
# the function extract_code_from_response(text::String)::String.
# Current as of 8895efe5f5e51d5bfdd0300d8d4ffd7e0568f2aa
def _extract_code_from_inference(text: str) -> str:
    """Extract code from the code block in a chatty Genparse generation."""
    result = text.strip().removeprefix("<|start_header_id|>assistant<|end_header_id|>")
    try:
        json.loads(result)
    except json.decoder.JSONDecodeError as e:
	    raise NotCodeError("Not formatted properly -- expected chat turn prefix followed by JSON.") from e
    return result


# Translated from GenFact server code, src/genparse/extract_entities.jl.
# Current as of 8895efe5f5e51d5bfdd0300d8d4ffd7e0568f2aa
def _get_aggregate_likelihoods(posterior: dict[str, float]) -> dict[str, float]:
    """Convert a raw-text posterior into a code-only posterior.

    This extracts the code block from each inference and aggregates the likelihoods from identical code blocks.

    The posterior should be a dict-like object mapping strings-like objects to float-likes.
    This returns a value in the same format.
    """
    result = {}
    n_nocode = 0
    nocode_likelihood = 0.0
    for inference, likelihood in posterior.items():
        try:
            code_only = _extract_code_from_inference(inference)
        except NotCodeError as e:
            logger.debug("Inference is not code: `%s`", inference)
            n_nocode += 1
            nocode_likelihood += likelihood
        else:
            result.setdefault(code_only, 0.0)
            result[code_only] += likelihood

    for inference in result.keys():
        result[inference] += nocode_likelihood / max(n_nocode, 1)

    assert result

    return _sort_posterior(result)



def cleanup_genparse_output(posterior: dict[str, float]) -> dict[str, float]:
    """
    Clean up Genparse output.

    This attempts to imitate what the GenFact server does to clean up the Genparse output as of 2024-09-10.
    It does not attempt to perform PClean-related cleanup, because for evaluation purposes we don't need that for our
    pure information extraction evaluation. This therefore only filters for actual JSON respones and aggregates
    likelihoods over functionally identical outputs.
    """
    return _aggregate_identical_json(_get_aggregate_likelihoods(posterior))


def get_map_output(posterior: dict[str, float]) -> str:
    """
    Given a posterior, get the maximum a posteriori output.

    If there is a tie for maximum, we prefer the output that sorts first alphabetically.
    """
    # Can't get the max directly because it would prefer the output that sorts last alphabetically. There is no easy
    # way to fix this in the key function.
    #
    # Instead, we negate the values and get the minimum. This should get us a MAP output still because when we negate
    # the values the max becomes the min. However, because we also key on the strings, now we get the alphabetically
    # first MAP inference.
    #
    # Trick: The value is a number but
    return min(posterior.items(), key=lambda t: (-t[1], t[0]))[0]


def convert_to_extracted_info(sentence_datum: dict[str, Any]) -> dict[str, Any]:
    """
    Convert Genparse output into "extracted_info" form like we save for spaCy.
    """
    name = _join_names(sentence_datum)
    city_key = "city_name"
    cities = [sentence_datum[city_key]] if sentence_datum.get(city_key) is not None else []
    result = {
        "names": [name] if name is not None else [],
        "cities": cities
    }
    return result


def augment_sentence_with_genparse_output(sentence_datum: dict[str, Any], posterior: dict[str, Any]) -> dict[str, Any]:
    """
    Given Genparse's posterior for a sentence, extract a Genparse output for that sentence.
    """
    cleaned_genparse_output = json.loads(get_map_output(cleanup_genparse_output(posterior)))
    extracted_info = {
        **sentence_datum.get("extracted_info", {}),
        **convert_to_extracted_info(cleaned_genparse_output),
    }
    return {
        **sentence_datum,
        "raw_genparse_output": posterior,
        "cleaned_genparse_output": cleaned_genparse_output,
        "extracted_info": extracted_info,
    }


def extract_info_with_genparse_locally(
    sentence_datum: dict[str, Any],
    *,
    server: str,
    inference_setup: genparse.InferenceSetupVLLM,
    tokenizer: PreTrainedTokenizer,
    temperature: float,
    n_particles: int,
    max_new_tokens: int = MAX_TOKENS,
) -> dict[str, Any]:
    """
    Process sentences using Genparse locally and extract relevant information.
    """
    prompt = make_prompt(sentence_datum, tokenizer=tokenizer)
    posterior = inference_setup(
        prompt, method="smc-standard", temperature=temperature, n_particles=n_particles, max_tokens=max_new_tokens
    ).posterior
    result = augment_sentence_with_genparse_output(sentence_datum, posterior)
    result["genparse_prompt"] = prompt
    return result


def inference_endpoint(server_ip_or_hostname: str) -> str:
    """
    Get the inference endpoint URL for the given server IP or hostname.
    """
    return f"http://{server_ip_or_hostname}:8888/infer"


def restart_endpoint(server_ip_or_hostname: str) -> str:
    """
    Get the endpoint URL to restart the Genparse inference server on the given IP or hostname.
    """
    return f"http://{server_ip_or_hostname}:9999/restart"


def _get_restart_user():
    return os.getenv('GENPARSE_USER')


def _get_restart_password():
    return os.getenv('GENPARSE_PASSWORD')


def _request_timeout(timeout):
    return (CONNECT_TIMEOUT_SECONDS, timeout)


def _restart_server(
    server_ip_or_hostname: str,
    *,
    restart_request_timeout_seconds: int = DEFAULT_RESTART_REQUEST_TIMEOUT_SECONDS,
    sleep_after_restart_seconds: float = DEFAULT_RESTART_REQUEST_WAIT_TIME_SECONDS,
) -> None:
    """
    Get the inference endpoint URL for the given server IP or hostname.
    """
    logger.info("Restarting Genparse server: %s", server_ip_or_hostname)
    url = restart_endpoint(server_ip_or_hostname)
    basic = HTTPBasicAuth(_get_restart_user(), _get_restart_password())
    response = requests.post(url, auth=basic, timeout=_request_timeout(restart_request_timeout_seconds))
    assert response.status_code == 200
    time.sleep(sleep_after_restart_seconds)


def await_restart() -> None:
    """
    Get the inference endpoint URL for the given server IP or hostname.
    """
    logger.debug('Sleeping for %d waiting for genparse to reboot', WAIT_FOR_GENPARSE_REBOOT)
    time.sleep(WAIT_FOR_GENPARSE_REBOOT)


def extract_info_with_genparse_server(
    sentence_datum: dict[str, Any],
    *,
    server: str,
    tokenizer: PreTrainedTokenizer,
    temperature: float,
    n_particles: int,
    max_new_tokens: int = MAX_TOKENS,
) -> dict[str, Any]:
    """
    Process sentences using Genparse inference server and extract relevant information.
    """
    prompt = make_prompt(sentence_datum, tokenizer=tokenizer)
    inference_params = {
        "prompt": prompt,
        "method": SAMPLING_METHOD,
        "n_particles": n_particles,
        "lark_grammar": GRAMMAR,
        "proposal_name": PROPOSAL_NAME,
        "proposal_args": {},
        "max_tokens": max_new_tokens,
        "temperature": temperature,
    }
    response = requests.post(
        inference_endpoint(server), headers={"Content-Type": "application/json"}, json=inference_params
    )
    posterior = response.json()["posterior"]
    result = augment_sentence_with_genparse_output(sentence_datum, posterior)
    result["genparse_prompt"] = prompt
    return result


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("sentences_path", type=Path, help="Path to the JSONL file containing the sentences.")
    parser.add_argument("write_to_path", type=Path, help="Path to write the processed JSONL file to.")
    parser.add_argument(
        "--model", type=str, default=GENPARSE_SERVER_MODEL, help="Language model to use for information extraction."
    )
    parser.add_argument(
        "--genparse-server",
        type=str,
        default=None,
        help="Genparse server to use for inference. If none, run inference locally.",
    )
    parser.add_argument(
        "--restart-server-every",
        type=int,
        default=DEFAULT_RESTART_SERVER_EVERY,
        help="How many instances to send to the server before restarting the server.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=DEFAULT_BATCH_SIZE,
        help="Batch size to use for inference. Only relevant when running inference locally.",
    )
    parser.add_argument(
        "--n-particles", type=int, default=DEFAULT_N_PARTICLES, help="Number of particles to use for inference."
    )
    parser.add_argument(
        "--temperature", type=float, default=DEFAULT_TEMPERATURE, help="Temperature to use for inference."
        )
    parser.add_argument(
        "--logging-level", type=str, default="INFO", help="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)."
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    sentences_path: Path = args.sentences_path
    write_to_path: Path = args.write_to_path
    model: str = args.model
    genparse_server: Optional[str] = args.genparse_server
    restart_server_every: int = args.restart_server_every
    batch_size: int = args.batch_size
    n_particles: int = args.n_particles
    temperature: float = args.temperature

    assert restart_server_every > 0
    assert batch_size > 0
    assert n_particles > 0
    assert temperature >= 0.0

    genparse_params = {"n_particles": args.n_particles, "temperature": temperature}

    if not sentences_path.exists() or not sentences_path.is_file():
        raise FileNotFoundError(f"Input file does not exist or is not a file: {sentences_path}")
    if write_to_path.exists() and write_to_path.is_dir():
        raise ValueError(f"Output path is a directory, not a file: {write_to_path}")

    if genparse_server:
        assert model == GENPARSE_SERVER_MODEL
        logger.info("Using Genparse server %s", genparse_server)
    else:
        logger.info(f"Loading model `%s`", model)
        inference_setup = genparse.InferenceSetupVLLM(
            model, GRAMMAR, proposal_name="character", batch_size=batch_size
        )
        nlp = spacy.load(spacy_model)
        logger.info("Successfully loaded model `%s`", model)

    logger.info("Loading tokenizer for model `%s`", model)
    tokenizer = AutoTokenizer.from_pretrained(model)
    logger.info("Successfully loaded tokenizer for model `%s`", model)

    logger.info("Loading JSONL data from: `%s`", sentences_path)
    sentence_data = read_jsonl(sentences_path)
    n_written: int = 0
    if genparse_server:
        n_written = write_jsonl(
            # jac: Weird hack to restart the server every so often within a generator expression.
            #
            # When i > 0 and i % restart_server_every != 0 evaluates to false, that means we're on
            # a `restart_server_every`-th iteration. Then the or means we restart the server.
            # We then AND this with the result of extract_... so that the generator yields the extracted info objects,
            # i.e. the values we actually care about.
            ((i == 0 or i % restart_server_every != 0 or _restart_server(genparse_server) is None)
             and extract_info_with_genparse_server(
                sentence_datum, server=genparse_server, tokenizer=tokenizer, **genparse_params
            ) for i, sentence_datum in enumerate(sentence_data)),
            write_to_path
        )
    else:
        n_written = write_jsonl(
            (extract_info_with_genparse_locally(
                sentence_datum, inference_setup=inference_setup, tokenizer=tokenizer, **genparse_params
            ) for sentence_datum in sentence_data),
            write_to_path
        )

    logger.info("Wrote %d sentences to `%s` augmented with GenFact entities", n_written, write_to_path)


if __name__ == "__main__":
    main()
