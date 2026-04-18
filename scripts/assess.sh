#!/usr/bin/env bash
# scripts/assess.sh — "is happy-nvim broken?" aggregator.
#
# Runs every verification layer in order (cheap first), prints a pass/fail
# table + total time, exits nonzero on any failure.
#
# Layers:
#   1. shell syntax       (bash -n scripts/*.sh)
#   2. python syntax      (ast.parse tests/integration/*.py + scripts/*.py)
#   3. init.lua bootstrap (nvim --headless -c qa!)
#   4. plenary unit+smoke (tests/*_spec.lua)
#   5. pytest integration (tests/integration/)
#   6. :checkhealth       (happy-nvim probe)
#
# Every layer runs even if an earlier one fails, so the final table shows
# the complete picture. Exit code is nonzero iff any layer failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Single shared scratch dir for all layers. Bootstraps Lazy + plugins ONCE.
# Subsequent layers reuse the same data dir (no re-clone, no TS rebuild).
# This is the big win over per-layer tmpdirs (saves ~10 min on CI matrix).
ASSESS_SCRATCH="$(mktemp -d -t happy-assess.XXXXXX)"
export XDG_CONFIG_HOME="$ASSESS_SCRATCH/cfg"
export XDG_DATA_HOME="$ASSESS_SCRATCH/data"
export XDG_CACHE_HOME="$ASSESS_SCRATCH/cache"
export XDG_STATE_HOME="$ASSESS_SCRATCH/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
# Install repo as the config so Lazy finds lua/plugins/ via stdpath('config')
mkdir -p "$XDG_CONFIG_HOME/nvim"
cp -r . "$XDG_CONFIG_HOME/nvim/"
trap "rm -rf '$ASSESS_SCRATCH'" EXIT

# One-shot Lazy sync + TS build. Every subsequent nvim invocation below
# inherits these XDG dirs and hits the cache.
echo '=== bootstrap: Lazy! sync (once) ==='
nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -5 || true

declare -A LAYER_STATUS
declare -A LAYER_DURATION
declare -a LAYER_ORDER

run_layer() {
  local name="$1"
  shift
  LAYER_ORDER+=( "$name" )
  echo
  echo "=== $name ==="
  local start
  start=$(date +%s)
  if "$@"; then
    LAYER_STATUS[$name]=PASS
  else
    LAYER_STATUS[$name]=FAIL
  fi
  local end
  end=$(date +%s)
  LAYER_DURATION[$name]=$(( end - start ))
  echo "=== $name: ${LAYER_STATUS[$name]} (${LAYER_DURATION[$name]}s) ==="
}


# Layer 0: stylua + selene (fastest lint); gracefully skip if tools missing
layer_lint() {
  local rc=0
  if command -v stylua >/dev/null 2>&1; then
    stylua --check . || rc=1
  else
    echo 'layer_lint: stylua not on $PATH — skipping format check'
  fi
  if command -v selene >/dev/null 2>&1; then
    selene . || rc=1
  else
    echo 'layer_lint: selene not on $PATH — skipping static analysis'
  fi
  return $rc
}

# Layer 1: shell syntax
layer_shell_syntax() {
  local rc=0
  while IFS= read -r -d '' f; do
    bash -n "$f" || rc=1
  done < <(find scripts tests -name '*.sh' -print0)
  return $rc
}

# Layer 2: python syntax
layer_python_syntax() {
  local rc=0
  while IFS= read -r -d '' f; do
    python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$f" || rc=1
  done < <(find scripts tests -name '*.py' -print0)
  return $rc
}

# Layer 3: init.lua bootstrap — reuses the shared XDG dirs
layer_init_bootstrap() {
  nvim --headless -c 'qa!' 2>&1 | tee "$ASSESS_SCRATCH/startup.log"
  ! grep -Eiq 'E[0-9]+:' "$ASSESS_SCRATCH/startup.log"
}

# Layer 4: plenary unit+smoke — reuses shared XDG dirs (no Lazy re-sync)
layer_plenary() {
  HAPPY_NVIM_LOAD_CONFIG=1 \
    nvim --headless -u tests/minimal_init.lua \
      -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
      2>&1 | sed -r 's/\x1b\[[0-9;]*m//g' | tee "$ASSESS_SCRATCH/plenary.log"
  grep -q 'Success:' "$ASSESS_SCRATCH/plenary.log" || return 1
  ! grep -qE 'Failed *: *[1-9]|Errors *: *[1-9]' "$ASSESS_SCRATCH/plenary.log"
}

# Layer 5: pytest integration (delegates to existing wrapper)
# Note: test-integration.sh sets its OWN XDG redirects, which is intentional
# — it runs a tmux server on an isolated socket w/ fake-claude on PATH.
layer_integration() {
  bash scripts/test-integration.sh
}

# Layer 6: :checkhealth — reuses shared XDG dirs
layer_checkhealth() {
  nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | tee "$ASSESS_SCRATCH/health.log"
  ! grep -Eiq '^\s*ERROR\b' "$ASSESS_SCRATCH/health.log"
}

run_layer 'lint'              layer_lint
run_layer 'shell-syntax'      layer_shell_syntax
run_layer 'python-syntax'     layer_python_syntax
run_layer 'init-bootstrap'    layer_init_bootstrap
run_layer 'plenary'           layer_plenary
run_layer 'integration'       layer_integration
run_layer 'checkhealth'       layer_checkhealth

# Final table
echo
echo '================================================================'
printf ' %-20s %-6s %s\n' LAYER STATUS DURATION
echo '----------------------------------------------------------------'
overall=0
for name in "${LAYER_ORDER[@]}"; do
  printf ' %-20s %-6s %ds\n' "$name" "${LAYER_STATUS[$name]}" "${LAYER_DURATION[$name]}"
  [[ "${LAYER_STATUS[$name]}" == FAIL ]] && overall=1
done
echo '================================================================'
if (( overall == 0 )); then
  echo 'ASSESS: ALL LAYERS PASS'
else
  echo 'ASSESS: FAILURES DETECTED'
fi
exit $overall
