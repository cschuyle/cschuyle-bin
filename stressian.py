#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["ruaccent"]
# ///
"""Add Russian stress marks to Cyrillic text using the ruaccent model."""
import os
import re
import sys

os.environ.setdefault("TRANSFORMERS_NO_ADVISORY_WARNINGS", "1")

from ruaccent import RUAccent

text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()

accentizer = RUAccent()
accentizer.load(omograph_model_size="turbo", use_dictionary=True)
raw = accentizer.process_all(text)
accented = re.sub(r"\+(.)", lambda m: m.group(1) + "́", raw)
print(accented)
