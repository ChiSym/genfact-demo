"""
Script to convert DocNames JSONL data to CSV for easier reading.
"""
from argparse import ArgumentParser
import csv
from pathlib import Path
import json
import logging
from typing import Any, Iterator

from scripts.utils.medicare_data import (
    firstname_feature,
    lastname_feature,
    specialty_feature,
    legalname_feature,
    city_feature,
    zip_feature,
    addr_feature,
)
from scripts.utils.docnames_data import PromptedSentence


logger = logging.getLogger(__name__)


sentence_col = "Sentence"
raw_gen_col = "Raw Generation"
comment_col = "Notes/Comments"
prompt_col = "Prompt"
chatty_prompt_col = "Prompt With Chat Tags"
doctor_first_col = "Provider First Name"
doctor_last_col = "Provider Last Name"
doctor_spec_col = "Specialty"
legal_name_col = "Org. Legal Name"
city_col = "City"
zip_col = "ZIP Code"
address_col = "Address"

def included_col(col: str) -> str:
    """Given column, produce column name for 'did we use this to generate the sentence?'"""
    return f"Generated Using {col}?"

CSV_COLUMNS = (
    sentence_col,
    raw_gen_col,
    comment_col,
    prompt_col,
    chatty_prompt_col,
    doctor_first_col,
    included_col(doctor_first_col),
    doctor_last_col,
    included_col(doctor_last_col),
    doctor_spec_col,
    included_col(doctor_spec_col),
    legal_name_col,
    included_col(legal_name_col),
    city_col,
    included_col(city_col),
    zip_col,
    included_col(zip_col),
    address_col,
    included_col(address_col),
)


def load_jsonl(jsonl_path: Path) -> Iterator[dict[str, Any]]:
    """
    Load JSON objects from the given JSONL file.
    """
    with jsonl_path.open(mode="r", encoding="utf-8") as jsonl_in:
        for line in jsonl_in:
            yield json.loads(line.strip())


def _prompted_sentence_from_json(json_: dict[str, Any]) -> PromptedSentence:
    """
    Workaround to produce `nochat_prompt` for compatibility with old DocNames data.
    """
    if "nochat_prompt" not in json_:
        json_ = json_.copy()
        json_["nochat_prompt"] = json_[
            "prompt"
        ].removeprefix("<bos><start_of_turn>user\n\n").strip().removesuffix("<end_of_turn>").strip()
    return PromptedSentence(**json_)


def prompted_sentence_to_human_readable(prompted_sentence: PromptedSentence) -> dict[str, Any]:
    """
    Convert a prompted sentence to a dict that can be rendered as human-readable CSV.
    """
    result = {
        sentence_col: prompted_sentence.sentence,
        raw_gen_col: prompted_sentence.raw_generation,
        comment_col: "",
        prompt_col: prompted_sentence.nochat_prompt,
        chatty_prompt_col: prompted_sentence.prompt,
    }
    for (col, feature) in [
        (doctor_first_col, firstname_feature),
        (doctor_last_col, lastname_feature),
        (doctor_spec_col, specialty_feature),
        (legal_name_col, legalname_feature),
        (city_col, city_feature),
        (zip_col, zip_feature),
        (address_col, addr_feature),
    ]:
        result[col] = prompted_sentence.full_features[feature]
        result[included_col(col)] = "Y" if feature in prompted_sentence.generation_features else "N"
    assert set(CSV_COLUMNS).issubset(result.keys())
    return result



def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("docnames_path", type=Path, help="Path to the DocNames JSONL file.")
    parser.add_argument("csv_path", type=Path, help="Where to save the resulting human-readable CSV.")
    parser.add_argument(
        "--logging-level",
        type=str,
        default="INFO",
        help="Logging level to use.",
    )
    args = parser.parse_args()

    docnames_path = args.docnames_path
    csv_path = args.csv_path

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    docnames_sentences = (_prompted_sentence_from_json(**datum) for datum in load_jsonl(docnames_path))
    csv_rows = (prompted_sentence_to_human_readable(sentence) for sentence in docnames_sentences)

    with csv_path.open(mode="w", encoding="utf-8", newline="") as csv_out:
        writer = csv.DictWriter(csv_out, fieldnames=CSV_COLUMNS, dialect=csv.excel)
        writer.writeheader()
        writer.writerows(csv_rows)


if __name__ == "__main__":
    main()