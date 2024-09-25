"""
A script for benchmarking spaCy and ReFinED speed and memory usage.

https://linear.app/chi-fro/issue/FACT-57/benchmark-spacy-and-refined
"""
from argparse import ArgumentParser
import csv
from dataclasses import dataclass
from pathlib import Path
import json
import logging
import math
import timeit
import tracemalloc
from typing import Any

import numpy as np
from refined.inference.processor import Refined
import spacy
import torch

from scripts.utils.jsonl import read_jsonl


logger = logging.getLogger(__name__)


BYTES_PER_MIB = 1024 ** 2


@dataclass
class DatasetConfig:
    path: Path
    claim_key: str


@dataclass
class BenchmarkConfig:
    datasets: dict[str, DatasetConfig]


@dataclass
class BenchmarkResult:
    dataset_name: str


DATASET_COLUMN = "Dataset"
SYSTEM_COLUMN = "System (spaCy/ReFinED)"
MODEL_COLUMN = "Model"
GPU_COLUMN = "GPUs"
BATCH_SIZE_COLUMN = "Claim processing batch size"

AVG_RUNTIME_PER_CLAIM_COLUMN = "Avg. running time per claim (ms)"
MAX_RUNTIME_PER_CLAIM_COLUMN = "Max running time per claim (ms)"
MODEL_MEMORY_COLUMN = "Model memory usage (MiB)"
PEAK_PROCESSING_MEMORY_COLUMN = "Peak processing memory usage (bytes) @ this batch size"

N_DATASET_CLAIMS_COLUMN = "# dataset claims"
AVG_CLAIM_LENGTH_COLUMN = "Avg. claim length in characters"
STDEV_CLAIM_LENGTH_COLUMN = "Stdev. of claim length in characters"
N_DATASET_SENTENCES_COLUMN = "# dataset sentences"
AVG_SENTENCES_PER_CLAIM_COLUMN = "Avg. sentences per dataset claim"
STDEV_SENTENCES_PER_CLAIM_COLUMN = "Stdev. of sentences per dataset claim"
AVG_SENTENCES_LENGTH_COLUMN = "Avg. sentence length in characters"
STDEV_SENTENCES_LENGTH_COLUMN = "Stdev. of sentence length in characters"

BENCHMARK_COLUMNS = (
    # General info
    DATASET_COLUMN,
    SYSTEM_COLUMN,
    MODEL_COLUMN,
    GPU_COLUMN,
    BATCH_SIZE_COLUMN,

    # Performance measures
    AVG_RUNTIME_PER_CLAIM_COLUMN,
    MAX_RUNTIME_PER_CLAIM_COLUMN,
    MODEL_MEMORY_COLUMN,
    PEAK_PROCESSING_MEMORY_COLUMN,

    # Dataset info
    N_DATASET_CLAIMS_COLUMN,
    AVG_CLAIM_LENGTH_COLUMN,
    STDEV_CLAIM_LENGTH_COLUMN,
    N_DATASET_SENTENCES_COLUMN,
    AVG_SENTENCES_PER_CLAIM_COLUMN,
    STDEV_SENTENCES_PER_CLAIM_COLUMN,
    AVG_SENTENCES_LENGTH_COLUMN,
    STDEV_SENTENCES_LENGTH_COLUMN,
)


def resolve_relative_to(maybe_relative: Path, root: Path) -> Path:
    return (maybe_relative if maybe_relative.is_absolute() else root / maybe_relative).resolve()


def load_benchmark_config(benchmark_config_path: Path) -> BenchmarkConfig:
    """
    Loads a benchmark config.
    """
    with benchmark_config_path.open(mode="r", encoding="utf-8") as bc_in:
        raw = json.load(bc_in)

    resolve_relative_to_ = benchmark_config_path.resolve().parent
    result = BenchmarkConfig(
        datasets={
            dataset_name: DatasetConfig(path=resolve_relative_to(Path(dataset_config["path"]), resolve_relative_to_), claim_key=dataset_config["claim_key"])
            for dataset_name, dataset_config in raw["datasets"].items()
        }
    )
    return result


def load_json(path: Path) -> list[dict[str, Any]]:
    """
    Load JSONL-like data from a simple JSON file.
    """
    with path.open(mode="r", encoding="utf-8") as json_in:
        result = json.load(json_in)

    return result


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "benchmark_config_path",
        type=Path,
        help="The benchmarking config to use.",
    )
    parser.add_argument(
        "save_results_to",
        type=Path,
        help="Where to save the CSV file of results.",
    )
    parser.add_argument(
        "--batch-size",
        default=64,
        type=int,
        help="Number of claims to process in one batch. For fair comparison spaCy and ReFinED use the same batch "
        "size.",
    )
    parser.add_argument(
        "--spacy-model",
        default="en_core_web_trf",
        help="Which spaCy model to use.",
    )
    parser.add_argument(
        "--refined-model",
        default="wikipedia_model_with_numbers",
        help="Which ReFinED model to use.",
    )
    parser.add_argument(
        "--refined-entity-set",
        default="wikipedia",
        help="Which entity set to use for ReFinED linking.",
    )
    parser.add_argument(
        "--logging-level",
        type=str,
        default="INFO",
        help="Logging level to use.",
    )
    args = parser.parse_args()

    benchmark_config_path: Path = args.benchmark_config_path
    save_results_to: Path = args.save_results_to
    batch_size: int = args.batch_size
    spacy_model: str = args.spacy_model
    refined_model: str = args.refined_model
    refined_entity_set: str = args.refined_entity_set

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format="%(asctime)s - %(levelname)s - %(name)s -   %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Load spaCy
    tracemalloc.start()
    base_size, _spacy_peak = tracemalloc.get_traced_memory()
    spacy.require_cpu()
    nlp = spacy.load(spacy_model)
    spacy_size, _spacy_peak = tracemalloc.get_traced_memory()
    tracemalloc.reset_peak()
    spacy_size = spacy_size - base_size
    logger.info("Loaded spaCy model `%s` occupying %d bytes", spacy_model, spacy_size)

    spacy_on_gpu = False
    if torch.cuda.is_available():
        try:
            spacy.require_gpu()
        except ValueError as e:
            logger.error("Couldn't load spaCy on GPU")
            gpu_nlp = None
        else:
            gpu_nlp = spacy.load(spacy_model)
            logger.info("Loaded spaCy copy on GPU")
            spacy_on_gpu = True

    # Load ReFinED
    refined = Refined.from_pretrained(
        model_name=refined_model,
        entity_set=refined_entity_set,
        device="cpu",
    )
    refined_size, _refined_peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    refined_size = refined_size - base_size
    logger.info(
        "Loaded ReFinED model `%s` with entity set `%s`, size %d", refined_model, refined_entity_set, refined_size
    )

    refined_on_gpu = False
    if torch.cuda.is_available():
        gpu_refined = Refined.from_pretrained(
            model_name=refined_model,
            entity_set=refined_entity_set,
            device="cuda",
        )
        logger.info("Loaded ReFinED copy on GPU")
        refined_on_gpu = True

    benchmark_config = load_benchmark_config(benchmark_config_path)
    logger.info("Loaded benchmark config from %s", benchmark_config_path)

    with save_results_to.open(mode="w", encoding="utf-8", newline="") as save_to_file:
        logger.info("Writing to `%s`", save_results_to)
        writer = csv.DictWriter(save_to_file, fieldnames=BENCHMARK_COLUMNS, dialect=csv.excel)
        writer.writeheader()

        for dataset_name, dataset_config in benchmark_config.datasets.items():
            claims: list[str] = [
                row[dataset_config.claim_key] for row in (
                    read_jsonl(dataset_config.path)
                    if dataset_config.path.suffix == ".jsonl"
                    else load_json(dataset_config.path)
                )
            ]

            logger.info("Computing stats for dataset `%s`", dataset_name)
            claim_docs = list(nlp.pipe(claims))
            dataset_stats = {
                N_DATASET_CLAIMS_COLUMN: len(claims),
                AVG_CLAIM_LENGTH_COLUMN: np.mean([len(claim) for claim in claims]),
                STDEV_CLAIM_LENGTH_COLUMN: np.std([len(claim) for claim in claims], ddof=1),
                N_DATASET_SENTENCES_COLUMN: sum(sum(1 for _ in claim_doc.sents) for claim_doc in claim_docs),
                AVG_SENTENCES_PER_CLAIM_COLUMN: np.mean([sum(1 for _ in claim_doc.sents) for claim_doc in claim_docs]),
                STDEV_SENTENCES_PER_CLAIM_COLUMN: np.std(
                    [sum(1 for _ in claim_doc.sents) for claim_doc in claim_docs], ddof=1
                ),
                AVG_SENTENCES_LENGTH_COLUMN: np.mean(
                    [len(str(sent)) for claim_doc in claim_docs for sent in claim_doc.sents]
                ),
                STDEV_SENTENCES_LENGTH_COLUMN: np.std(
                    [len(str(sent)) for claim_doc in claim_docs for sent in claim_doc.sents], ddof=1
                ),
            }
            logger.info("Getting results for dataset `%s` with %d claims", dataset_name, dataset_stats[N_DATASET_CLAIMS_COLUMN])

            spacy_per_claim_times_s = []
            refined_per_claim_times_s = []
            gpu_spacy_per_claim_times_s = []
            gpu_refined_per_claim_times_s = []
            spacy_per_claim_peaks_bytes = []
            refined_per_claim_peaks_bytes = []
            gpu_spacy_per_claim_peaks_bytes = []
            gpu_refined_per_claim_peaks_bytes = []
            for i in range(0, math.ceil(len(claims) / batch_size)):
                logger.info("Processing batch %d / %d", i + 1, math.ceil(len(claims) / batch_size))
                batch = claims[i:i * batch_size + batch_size]
                max_claim_length = max(len(claim) for claim in batch)

                spacy_per_claim_times_s.append(timeit.Timer(lambda: nlp.pipe(batch)).timeit(number=1) / len(batch))
                refined_per_claim_times_s.append(timeit.Timer(lambda: refined.process_text_batch(batch)).timeit(number=1) / len(batch))
                if spacy_on_gpu:
                    gpu_spacy_per_claim_times_s.append(timeit.Timer(lambda: gpu_nlp.pipe(batch)).timeit(number=1) / len(batch))
                if refined_on_gpu:
                    gpu_refined_per_claim_times_s.append(timeit.Timer(lambda: gpu_refined.process_text_batch(batch)).timeit(number=1) / len(batch))

                tracemalloc.start()
                _spacy_docs = nlp.pipe(batch)
                _spacy_size, spacy_peak_bytes = tracemalloc.get_traced_memory()
                tracemalloc.stop()
                spacy_per_claim_peaks_bytes.append(spacy_peak_bytes / (batch_size * max_claim_length))

                tracemalloc.start()
                _refined_docs = refined.process_text_batch(batch)
                _refined_size, refined_peak_bytes = tracemalloc.get_traced_memory()
                tracemalloc.stop()
                refined_per_claim_peaks_bytes.append(refined_peak_bytes / (batch_size * max_claim_length))

                if spacy_on_gpu:
                    tracemalloc.start()
                    _gpu_spacy_docs = gpu_nlp.pipe(batch)
                    _gpu_spacy_size, gpu_spacy_peak_bytes = tracemalloc.get_traced_memory()
                    tracemalloc.stop()
                    gpu_spacy_per_claim_peaks_bytes.append(gpu_spacy_peak_bytes / (batch_size * max_claim_length))

                if refined_on_gpu:
                    tracemalloc.start()
                    _gpu_refined_docs = gpu_refined.process_text_batch(batch)
                    _gpu_refined_size, gpu_refined_peak_bytes = tracemalloc.get_traced_memory()
                    tracemalloc.stop()
                    gpu_refined_per_claim_peaks_bytes.append(gpu_refined_peak_bytes / (batch_size * max_claim_length))

            system = "spacy"
            model = spacy_model
            used_gpu = False
            avg_runtime_per_claim_ms = np.mean(spacy_per_claim_times_s) * 1000.
            max_runtime_per_claim_ms = max(spacy_per_claim_times_s) * 1000.
            model_memory = spacy_size / BYTES_PER_MIB
            peak_processing_memory = np.mean(spacy_per_claim_peaks_bytes)
            writer.writerow({
                DATASET_COLUMN: dataset_name,
                SYSTEM_COLUMN: system,
                MODEL_COLUMN: model,
                GPU_COLUMN: used_gpu,
                BATCH_SIZE_COLUMN: batch_size,
                AVG_RUNTIME_PER_CLAIM_COLUMN: avg_runtime_per_claim_ms,
                MAX_RUNTIME_PER_CLAIM_COLUMN: max_runtime_per_claim_ms,
                MODEL_MEMORY_COLUMN: model_memory,
                PEAK_PROCESSING_MEMORY_COLUMN: peak_processing_memory,
                **dataset_stats,
            })
            if spacy_on_gpu:
                system = "spacy"
                model = spacy_model
                used_gpu = True
                avg_runtime_per_claim_ms = np.mean(gpu_spacy_per_claim_times_s) * 1000.
                max_runtime_per_claim_ms = max(gpu_spacy_per_claim_times_s) * 1000.
                model_memory = spacy_size / BYTES_PER_MIB
                peak_processing_memory = np.mean(gpu_spacy_per_claim_peaks_bytes)
                writer.writerow({
                    DATASET_COLUMN: dataset_name,
                    SYSTEM_COLUMN: system,
                    MODEL_COLUMN: model,
                    GPU_COLUMN: used_gpu,
                    BATCH_SIZE_COLUMN: batch_size,
                    AVG_RUNTIME_PER_CLAIM_COLUMN: avg_runtime_per_claim_ms,
                    MAX_RUNTIME_PER_CLAIM_COLUMN: max_runtime_per_claim_ms,
                    MODEL_MEMORY_COLUMN: model_memory,
                    PEAK_PROCESSING_MEMORY_COLUMN: peak_processing_memory,
                    **dataset_stats,
                })

            system = "refined"
            model = refined_model
            used_gpu = False
            avg_runtime_per_claim_ms = np.mean(refined_per_claim_times_s) * 1000.
            max_runtime_per_claim_ms = max(refined_per_claim_times_s) * 1000.
            model_memory = refined_size / BYTES_PER_MIB
            peak_processing_memory = np.mean(refined_per_claim_peaks_bytes)
            writer.writerow({
                DATASET_COLUMN: dataset_name,
                SYSTEM_COLUMN: system,
                MODEL_COLUMN: model,
                GPU_COLUMN: used_gpu,
                BATCH_SIZE_COLUMN: batch_size,
                AVG_RUNTIME_PER_CLAIM_COLUMN: avg_runtime_per_claim_ms,
                MAX_RUNTIME_PER_CLAIM_COLUMN: max_runtime_per_claim_ms,
                MODEL_MEMORY_COLUMN: model_memory,
                PEAK_PROCESSING_MEMORY_COLUMN: peak_processing_memory,
                **dataset_stats,
            })
            if refined_on_gpu:
                system = "refined"
                model = refined_model
                used_gpu = True
                avg_runtime_per_claim_ms = np.mean(gpu_refined_per_claim_times_s) * 1000.
                max_runtime_per_claim_ms = max(gpu_refined_per_claim_times_s) * 1000.
                model_memory = refined_size / BYTES_PER_MIB
                peak_processing_memory = np.mean(gpu_refined_per_claim_peaks_bytes)
                writer.writerow({
                    DATASET_COLUMN: dataset_name,
                    SYSTEM_COLUMN: system,
                    MODEL_COLUMN: model,
                    GPU_COLUMN: used_gpu,
                    BATCH_SIZE_COLUMN: batch_size,
                    AVG_RUNTIME_PER_CLAIM_COLUMN: avg_runtime_per_claim_ms,
                    MAX_RUNTIME_PER_CLAIM_COLUMN: max_runtime_per_claim_ms,
                    MODEL_MEMORY_COLUMN: model_memory,
                    PEAK_PROCESSING_MEMORY_COLUMN: peak_processing_memory,
                    **dataset_stats,
                })

    logger.info("Done.")


if __name__ == "__main__":
    main()
