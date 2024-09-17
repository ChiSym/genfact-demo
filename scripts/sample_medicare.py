"""
A script meant for sampling the Medicare dataset.
"""
from argparse import ArgumentParser
import csv
from pathlib import Path
import logging
import random
from typing import AbstractSet, Any, Collection, Iterator, TextIO


logger = logging.getLogger(__name__)


DEFAULT_SEED = 42
DEFAULT_N_SAMPLE_ROWS = 1000


def medicare_csv_reader(medicare_csv_in: TextIO) -> csv.DictReader:
    """
    Create an appropriate CSV reader for reading the Medicare dataset.
    """
    return csv.DictReader(medicare_csv_in, dialect=csv.excel)


def count_rows(csv_path: Path) -> int:
    """
    Count rows in the CSV file at the given path.
    """
    with csv_path.open(mode="r", encoding="utf-8", newline="") as csv_in:
        reader = medicare_csv_reader(csv_in)
        result = sum(1 for _line in reader)
    return result


def read_fieldnames(csv_path: Path) -> int:
    """
    Read fieldnames in the CSV file at the given path.
    """
    with csv_path.open(mode="r", encoding="utf-8", newline="") as csv_in:
        reader = csv.reader(csv_in, dialect=csv.excel)
        result = next(reader)
    return result


def sample_rows(medicare_csv_in: TextIO, rows_to_sample: AbstractSet[int]) -> Iterator[dict[str, Any]]:
    """
    Sample the given set of lines from the given textfile.
    """
    matched = 0
    reader = medicare_csv_reader(medicare_csv_in)
    for row_no, row in enumerate(reader):
        if row_no in rows_to_sample:
            matched += 1
            yield row
    assert matched == len(rows_to_sample)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "medicare_csv",
         type=Path,
          help="The path to the Medicare dataset.",
          )
    parser.add_argument(
        "sample_csv",
        type=Path,
        help="Where to save the sampled data.",
    )
    parser.add_argument(
        "--random-seed",
        type=int,
        help="The seed used to sample the dataset rows.",
        default=DEFAULT_SEED,
    )
    parser.add_argument(
        "--n-sample-rows",
        type=int,
        help="The number of sample rows to collect.",
        default=DEFAULT_N_SAMPLE_ROWS,
    )
    parser.add_argument(
        "--logging-level",
        type=str,
        default="INFO",
        help="Logging level to use.",
    )
    args = parser.parse_args()

    medicare_csv_path: Path = args.medicare_csv
    sample_csv_path: Path = args.sample_csv
    random_seed: int = args.random_seed
    n_sample_rows: int = args.n_sample_rows

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if not medicare_csv_path.exists():
        raise FileNotFoundError(f"[Medicare CSV] No such file: {medicare_csv_path}")
    elif not medicare_csv_path.is_file():
        raise FileNotFoundError(f"[Medicare CSV] Not a file: {medicare_csv_path}")

    try:
        sample_csv_path.open(mode="w", encoding="utf-8")
    except OSError:
        raise ValueError("Couldn't create output (sample CSV) file {sample_csv_path}")

    rng = random.Random(random_seed)

    fieldnames = read_fieldnames(medicare_csv_path)
    logger.debug("Got Medicare CSV field names: %s", fieldnames)
    dataset_lines = count_rows(medicare_csv_path)
    logger.info("Sampling from %d rows of Medicare CSV in %s", dataset_lines, medicare_csv_path)
    rows_to_sample = set(rng.sample(range(1, dataset_lines), k=n_sample_rows))
    with (
        medicare_csv_path.open(mode="r", encoding="utf-8", newline="") as medicare_csv_in,
        sample_csv_path.open(mode="w", encoding="utf-8", newline="") as sample_csv_out,
    ):
        writer = csv.DictWriter(sample_csv_out, fieldnames=fieldnames, dialect=csv.excel)
        writer.writeheader()
        writer.writerows(sample_rows(medicare_csv_in, rows_to_sample))
        logger.info("Wrote %d rows sampled rows to %s", len(rows_to_sample), sample_csv_path)


if __name__ == "__main__":
    main()