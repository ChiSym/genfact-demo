import json
from pathlib import Path
from typing import Any, Iterable, Iterator

def read_jsonl(jsonl_path: Path) -> Iterator[dict[str, Any]]:
    """
    Read the given JSONL file.
    """
    with jsonl_path.open(mode="r", encoding="utf-8") as jsonl_in:
        for line in jsonl_in:
            yield json.loads(line.strip())


def write_jsonl(data: Iterable[dict[str, Any]], write_to_path: Path) -> int:
    """
    Write an iterable of dicts to a path as JSONL, returning the number written.
    """
    result = 0
    with write_to_path.open(mode="w", encoding="utf-8") as jsonl_out:
        for datum in data:
            jsonl_out.write(json.dumps(datum))
            jsonl_out.write("\n")
            result += 1
    return result