"""
Functions and helpers related to the Docnames Data.
"""
from dataclasses import dataclass
from typing import Any

@dataclass
class PromptedSentence:
    """An output sentence plus some metadata about how it was generated."""

    sentence: str
    raw_generation: str
    prompt: str
    nochat_prompt: str
    generation_features: dict[str, Any]
    full_features: dict[str, Any]
    attempted_to_typo: bool
