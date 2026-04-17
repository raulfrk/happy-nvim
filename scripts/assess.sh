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

# Layer 3: init.lua bootstrap
layer_init_bootstrap() {
  local tmp
  tmp=$(mktemp -d -t happy-assess.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'qa!' 2>&1 | tee "$tmp/startup.log"
  ! grep -Eiq 'E[0-9]+:' "$tmp/startup.log"
}

# Layer 4: plenary unit+smoke
layer_plenary() {
  local tmp
  tmp=$(mktemp -d -t happy-assess-plenary.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'Lazy! sync' -c 'qa!' 2>&1 | tail -3 || true
  HAPPY_NVIM_LOAD_CONFIG=1 \
    XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -u tests/minimal_init.lua \
      -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
      2>&1 | sed -r 's/\x1b\[[0-9;]*m//g' | tee "$tmp/plenary.log"
  grep -q 'Success:' "$tmp/plenary.log" || return 1
  ! grep -qE 'Failed *: *[1-9]|Errors *: *[1-9]' "$tmp/plenary.log"
}

# Layer 5: pytest integration (delegates to existing wrapper)
layer_integration() {
  bash scripts/test-integration.sh
}

# Layer 6: :checkhealth
layer_checkhealth() {
  local tmp
  tmp=$(mktemp -d -t happy-assess-health.XXXXXX)
  trap "rm -rf '$tmp'" RETURN
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/cfg" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" \
    nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | tee "$tmp/health.log"
  ! grep -Eiq '^\s*ERROR\b' "$tmp/health.log"
}

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
