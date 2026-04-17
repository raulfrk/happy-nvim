#!/usr/bin/env bash
# scripts/smoke.sh — run before tagging a release.
set -euo pipefail

echo "1. stylua check"
stylua --check .

echo "2. selene check"
selene .

echo "3. plenary tests"
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!' 2>&1 | tee /tmp/happy-smoke-plenary.log
grep -q 'Failed: 0' /tmp/happy-smoke-plenary.log
grep -q 'Errors: 0' /tmp/happy-smoke-plenary.log

echo "4. headless startup"
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.config"
ln -sfn "$PWD" "$TMPHOME/.config/nvim"
HOME="$TMPHOME" nvim --headless -c 'Lazy sync' -c 'qa!' 2>&1 | tee /tmp/happy-smoke-startup.log
! grep -Ei 'Error|E[0-9]+:' /tmp/happy-smoke-startup.log

echo "5. checkhealth"
HOME="$TMPHOME" nvim --headless -c 'checkhealth happy-nvim' -c 'qa!' 2>&1 | tee /tmp/happy-smoke-health.log
! grep -i 'ERROR:' /tmp/happy-smoke-health.log

echo "6. Lazy profile under 200ms"
HOME="$TMPHOME" nvim --headless --startuptime /tmp/happy-smoke-startup.time -c 'qa!'
tail -1 /tmp/happy-smoke-startup.time
# extract last number — startup time in ms — check < 200
last=$(tail -1 /tmp/happy-smoke-startup.time | awk '{print $1}')
awk -v t="$last" 'BEGIN { exit (t < 200) ? 0 : 1 }'

rm -rf "$TMPHOME"
echo "ALL OK"
