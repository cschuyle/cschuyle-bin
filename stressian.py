#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["ruaccent", "truststore"]
# ///
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
