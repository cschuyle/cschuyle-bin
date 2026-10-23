#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#     "ruaccent",
#     "numpy",
#     "onnxruntime",
#     "transformers",
#     "truststore",
#     "huggingface_hub<2",
# ]
# ///
# ruaccent declares no runtime deps of its own, so numpy/onnxruntime/transformers
# (which it imports) must be listed here or the import fails with ModuleNotFoundError.
# requires-python: onnxruntime/transformers wheels lag new CPython releases, so pin
# to an interpreter they publish wheels for rather than whatever (e.g. 3.15) is default.
# huggingface_hub<2: every modern transformers caps hub <2, so without this uv
# backtracks to transformers 4.12.2 -> tokenizers 0.10.3, which has no wheels and
# fails trying to build from source with Rust.
"""Add Russian stress marks to Cyrillic text using the ruaccent model."""
import os
import pathlib
import re
import signal
import sys


def _on_sigint(signum, frame):
    sys.stderr.write("Process was interrupted and terminated before completion.\n")
    sys.stderr.flush()
    # Die by SIGINT (not exit status) so a calling shell script aborts too.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    os.kill(os.getpid(), signal.SIGINT)


# Top-level script (no main()), so handle Ctrl-C via a handler rather than try/except.
signal.signal(signal.SIGINT, _on_sigint)

# Validate TLS against the OS trust store (macOS Security framework) instead of
# certifi. ruaccent's first-run model download goes over httpx, which otherwise
# rejects a corporate MITM (Netskope) root cert that the OS already trusts. Must
# run before importing ruaccent (and thus huggingface_hub/httpx).
import truststore

truststore.inject_into_ssl()

os.environ.setdefault("TRANSFORMERS_NO_ADVISORY_WARNINGS", "1")

from ruaccent import RUAccent

text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()

# Cache the ~473 MB model in a durable dir (mirrors ~/.dus, ~/.gar) rather than
# ruaccent's default inside uv's prunable env cache, so `uv cache` cleanups don't
# force a re-download. Override with STRESSIAN_WORKDIR.
workdir = os.environ.get("STRESSIAN_WORKDIR") or str(pathlib.Path.home() / ".stressian")
os.makedirs(workdir, exist_ok=True)

accentizer = RUAccent()
accentizer.load(omograph_model_size="turbo", use_dictionary=True, workdir=workdir)
raw = accentizer.process_all(text)
accented = re.sub(r"\+(.)", lambda m: m.group(1) + "́", raw)
print(accented)
