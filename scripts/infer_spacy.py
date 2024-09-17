"""
Run spaCy name finding on some sentences and save the extracted information.

This extracts both person names (PERSON entities) and city names (GPE entities). It does not attempt to do rule-based
cleanup of Spacy's extracted information.

The input and output are both JSONL.
"""
from argparse import ArgumentParser
import json
import logging
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

import spacy
from spacy.language import Language

from scripts.utils.jsonl import read_jsonl, write_jsonl


logger = logging.getLogger(__name__)


def extract_info_with_spacy(sentence_data: Iterable[dict[str, Any]], nlp: Language) -> Iterator[dict[str, Any]]:
    """
    Process sentences using spaCy and extract relevant NER entities.

    We assume the sentence is under the "sentence" key and add info under "extracted_info", adding to any extracted
    info already present.
    """
    for sentence_datum in sentence_data:
        doc = nlp(sentence_datum["sentence"])
        names = [ent.text for ent in doc.ents if ent.label_ == "PERSON"]
        cities = [ent.text for ent in doc.ents if ent.label_ == "GPE"]
        extracted_info = {
            **sentence_datum.get("extracted_info", {}),
            "names": names,
            "cities": cities
        }
        yield {**sentence_datum, "extracted_info": extracted_info}


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("sentences_path", type=Path, help="Path to the JSONL file containing the sentences")
    parser.add_argument("write_to_path", type=Path, help="Path to write the processed JSONL file to")
    parser.add_argument("--spacy-model", type=str, default="en_web_core_sm", help="spaCy model to use for processing")
    parser.add_argument(
        "--logging-level", type=str, default="INFO", help="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    sentences_path: Path = args.sentences_path
    write_to_path: Path = args.write_to_path
    spacy_model: str = args.spacy_model

    if not sentences_path.exists() or not sentences_path.is_file():
        raise FileNotFoundError(f"Input file does not exist or is not a file: {sentences_path}")
    if write_to_path.exists() and write_to_path.is_dir():
        raise ValueError(f"Output path is a directory, not a file: {write_to_path}")

    logger.info(f"Loading spaCy model `%s`", spacy_model)
    nlp = spacy.load(spacy_model)
    logger.info("Successfully loaded spaCy model `%s`", spacy_model)

    logger.info("Loading JSONL data from: `%s`", sentences_path)
    sentence_data = read_jsonl(sentences_path)
    augmented_sentence_data = extract_info_with_spacy(sentence_data, nlp)
    n_written = write_jsonl(augmented_sentence_data, write_to_path)
    logger.info("Wrote %d sentences to `%s` augmented with spaCy entities", n_written, write_to_path)


if __name__ == "__main__":
    main()
