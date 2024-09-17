"""
This script converts DocNames inferences to a human-readable CSV form for error analysis.
"""
import logging
from argparse import ArgumentParser
from collections import defaultdict
import csv
from dataclasses import dataclass, asdict, fields
from pathlib import Path
from typing import Any, Iterable, Optional

from scripts.evaluate_docnames import join_medicare_names
from scripts.utils.jsonl import read_jsonl


logger = logging.getLogger(__name__)


def _n_names(inference: dict[str, Any]) -> int:
    return len(inference["extracted_info"]["names"])


def _n_cities(inference: dict[str, Any]) -> int:
    return len(inference["extracted_info"]["cities"])


def _compute_fieldnames(max_names: int, max_cities: int) -> list[str]:
    result = ["Sentence", "Typos In Sentence?", "True Name", "True City", "City Included?", "# Extracted Names", "# Extracted Cities"]

    for i in range(1, max_names + 1):
        result.extend([f"Extracted Name {i}", f"Extracted Name {i} Correct?"])

    for i in range(1, max_cities + 1):
        result.extend([f"Extracted City {i}", f"Extracted City {i} Correct?"])

    return result


def _make_row(inference: dict[str, Any]) -> dict[str, Any]:
    """Convert inferences into CSV rows."""
    true_name = join_medicare_names(inference["generation_features"])
    true_city = inference["generation_features"].get("City/Town")
    result = {
        "Sentence": inference["sentence"],
        "Typos In Sentence?": inference["attempted_to_typo"],
        "True Name": true_name,
        "True City": true_city,
        "City Included?": "City/Town" in inference["generation_features"],
        "# Extracted Names": len(inference["extracted_info"]["names"]),
        "# Extracted Cities": len(inference["extracted_info"]["cities"]),
    }

    for i, name in enumerate(inference["extracted_info"]["names"], start=1):
        result[f"Extracted Name {i}"] = name
        result[f"Extracted Name {i} Correct?"] = true_name and name.upper() == true_name

    for i, city in enumerate(inference["extracted_info"]["cities"], start=1):
        result[f"Extracted City {i}"] = city
        result[f"Extracted City {i} Correct?"] = true_city and city.upper() == true_city

    return result


def main() -> None:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "inferences_path",
        type=Path,
        help="Paths to inference file to evaluate",
    )
    parser.add_argument(
        "write_readable_form_to",
        type=Path,
        help="Path to write CSV output",
    )
    parser.add_argument(
        "--logging-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Set the logging level",
    )
    args = parser.parse_args()

    logging.basicConfig(level=args.logging_level,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    inferences_path: Path = args.inferences_path
    write_readable_form_to: Path = args.write_readable_form_to

    if not inferences_path.is_file():
        raise FileNotFoundError(f"Inference file not found: {path}")

    if write_readable_form_to.exists() and not write_readable_form_to.is_file():
        raise NotADirectoryError(f"Output path is not a file: {write_readable_form_to}")

    write_readable_form_to.parent.mkdir(exist_ok=True, parents=True)

    logger.info("Processing inference file: %s", inferences_path)
    rows = []
    max_names = 0
    max_cities = 0
    for inference in read_jsonl(inferences_path):
        rows.append(_make_row(inference))
        max_names = max(max_names, _n_names(inference))
        max_cities = max(max_cities, _n_cities(inference))

    logger.info("Found most %d names and at most %d cities in any one inference", max_names, max_cities)

    fieldnames = _compute_fieldnames(max_names=max_names, max_cities=max_cities)
    logger.info("Fields to be included in CSV output: %s", fieldnames)

    logger.info("Writing CSV output to: %s", write_readable_form_to)
    with write_readable_form_to.open(mode="w", newline="") as csv_out:
        writer = csv.DictWriter(csv_out, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    logger.info("Done.")


if __name__ == "__main__":
    main()
