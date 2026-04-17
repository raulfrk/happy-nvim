#!/usr/bin/env python3
"""Deterministic claude(1) stub for integration tests.

Reads stdin line-by-line. For each non-empty line:
  1. echoes "> <line>" (mimics user-input echo from the real CLI)
  2. sleeps DELAY seconds (default 0.5, 2.0 with --slow, or --delay N)
  3. echoes "Assistant: ACK:<line>"
  4. prints the next "> " prompt

Exits 0 on EOF. No network, no hidden state, no filesystem writes.
Used by tests/integration/test_*.py via the pytest fixtures in conftest.py.
"""
from __future__ import annotations

import argparse
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slow", action="store_true", help="use 2.0s delay")
    parser.add_argument("--delay", type=float, default=0.5, help="seconds (default 0.5)")
    args = parser.parse_args()

    delay = 2.0 if args.slow else args.delay

    print("> ", end="", flush=True)
    for raw in sys.stdin:
        line = raw.rstrip("\n")
        if not line:
            print("> ", end="", flush=True)
            continue
        print(f"> {line}", flush=True)
        time.sleep(delay)
        print(f"Assistant: ACK:{line}", flush=True)
        print("", flush=True)
        print("> ", end="", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
