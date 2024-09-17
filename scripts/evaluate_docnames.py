"""
This script scores DocNames information extraction results.

It takes a list of JSONL inference files and produces a pretty-printed table, and also optionally produces a CSV file
of the results.

It scores the extracted person names and city names separately on precision and recall.
"""
from argparse import ArgumentParser
from collections import defaultdict
import csv
import logging
from pathlib import Path
from typing import Any, Iterable, Optional

from scripts.utils.jsonl import read_jsonl


logger = logging.getLogger(__name__)


def join_medicare_names(generation_features: dict[str, Any]) -> str:
    """
    Given the generation features, return the joined doctor name.
    """
    names = [generation_features["Provider Last Name"]]
    if "Provider First Name" in generation_features:
        names.insert(0, generation_features["Provider First Name"])
    result = " ".join(names)
    return result


def get_precision(correct: int, predicted: int) -> float:
    """Compute precision."""
    return correct / predicted if predicted > 0 else 1.0


def get_recall(correct: int, total: int) -> float:
    """Compute recall."""
    return correct / total if total > 0 else 1.0


def calculate_metrics(inferences: Iterable[dict[str, Any]]) -> dict[str, float]:
    """
    Calculate metrics for the given list of inferences.

    Currently this means precision and recall for names and cities.
    """
    metrics = defaultdict(lambda: {"correct": 0, "total": 0, "extracted": 0})

    for inference in inferences:
        for entity_type, true_value, extracted_values in [
            ("name", join_medicare_names(inference["generation_features"]), [v.upper() for v in inference["extracted_info"]["names"]]),
            ("city", inference["generation_features"].get("City/Town"), [v.upper() for v in inference["extracted_info"]["cities"]]),
        ]:
            if true_value is not None:
                metrics[entity_type]["total"] += 1
                metrics[entity_type]["correct"] += extracted_values.count(true_value.upper())
            metrics[entity_type]["extracted"] += len(extracted_values)

    results = {}
    for entity_type, counts in metrics.items():
        results[f"{entity_type.capitalize()} Extracted Count"] = counts["extracted"]
        results[f"# Sentences With {entity_type.capitalize()}"] = counts["total"]
        results[f"{entity_type.capitalize()} Precision"] = get_precision(counts["correct"], counts["extracted"])
        results[f"{entity_type.capitalize()} Recall"] = get_recall(counts["correct"], counts["total"])

    return results


def process_inference_file(inference_path: Path) -> dict[str, Any]:
    """Process a single inference file and return metrics."""
    metrics = calculate_metrics(read_jsonl(inference_path))
    metrics["Run"] = inference_path.stem
    metrics["(Debug) Full Path"] = str(inference_path.resolve())
    metrics["# of sentences"] = sum(1 for _ in read_jsonl(inference_path))
    return metrics


def write_csv_output(results: list[dict[str, Any]], output_path: Path) -> None:
    """Write results to a CSV file."""
    fieldnames = [
        "Run", "(Debug) Full Path", "# of sentences",
        "Name Precision", "Name Recall", "City Precision", "City Recall", "# Sentences With Name", "Name Extracted Count", "# Sentences With City", "City Extracted Count"
    ]

    with output_path.open('w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for result in results:
            writer.writerow(result)


def format_markdown_table(results: list[dict[str, Any]]) -> str:
    """
    Format results as a GitHub Flavored Markdown table.

    We assume each result includes a run name (Run), a number of sentences, a name precision, a name recall, a city precision, and a city recall.
    """
    headers = ["Run", "# of sentences", "Name Precision", "Name Recall", "City Precision", "City Recall"]

    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["-" * len(header) for header in headers]) + " |")

    for result in results:
        row = [
            result["Run"],
            format(result["# of sentences"], "14d"),
            f"{result['Name Precision']:.4f}",
            f"{result['Name Recall']:.4f}",
            f"{result['City Precision']:.4f}",
            f"{result['City Recall']:.4f}"
        ]
        lines.append("| " + " | ".join(row) + " |")

    result = "\n".join(lines)
    return result


def main() -> None:
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--inferences-path", nargs="+", type=Path, required=True,
                        help="Paths to inference files to evaluate")
    parser.add_argument("--write-scores-to", type=Path,
                        help="Path to write CSV output")
    parser.add_argument("--logging-level", default="INFO",
                        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
                        help="Set the logging level")
    args = parser.parse_args()

    logging.basicConfig(level=args.logging_level,
                        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    inference_paths: list[Path] = args.inferences_path
    output_path: Optional[Path] = args.write_scores_to

    for path in inference_paths:
        if not path.is_file():
            raise FileNotFoundError(f"Inference file not found: {path}")

    if output_path:
        if output_path.exists() and not output_path.is_file():
            raise NotADirectoryError(f"Output path is not a file: {output_path}")

    if output_path:
        output_path.parent.mkdir(exist_ok=True, parents=True)

    results = []
    for inference_path in inference_paths:
        logger.info("Processing inference file: %s", inference_path)
        result = process_inference_file(inference_path)
        results.append(result)

    if output_path:
        logger.info("Writing CSV output to: %s", output_path)
        write_csv_output(results, output_path)

    logger.info("Pretty-printing results.")
    print(format_markdown_table(results))
    logger.info("Done.")


if __name__ == "__main__":
    main()