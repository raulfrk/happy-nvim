#!/usr/bin/env bash
# scripts/test-integration.sh — shared local+CI integration test entry point.
#
# Runs pytest against tests/integration/. Tmux + XDG isolation managed
# by tests/integration/conftest.py fixtures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }
python3 -m pytest --version >/dev/null 2>&1 || {
  echo "pytest required: pip install --user pytest" >&2
  exit 2
}

exec python3 -m pytest tests/integration/ -v "$@"
