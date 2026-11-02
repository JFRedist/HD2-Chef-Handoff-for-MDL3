#!/usr/bin/env bash
# Runs every test: the Python tests for the patch tools, a Lua 5.1 syntax check and the Chef hand-off addon's tests.
# (tests/handoff_sim.sh runs the addon on a real Chef checkout and is separate.)
#   tests/run_all.sh
# Needs python3 and a Lua 5.1 interpreter (lua5.1, with luac5.1 for the syntax check).
# To also rebuild real mod patches byte for byte: HD2_FIXTURE_PATCHES="/path/a.patch_0:/path/b.patch_0" tests/run_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo '== python: patch tools'
python3 -I -m unittest discover -s tests -v

LUAC=$(command -v luac5.1 || command -v luac || true)
LUA=$(command -v lua5.1 || command -v lua || true)
if [ -z "$LUA" ]; then echo 'no Lua 5.1 interpreter found: skipping the Lua tests' >&2; exit 0; fi

echo '== lua 5.1: syntax'
if [ -n "$LUAC" ]; then "$LUAC" -p handoff/*.lua tests/*.lua tests/fixtures/handoff/*.lua && echo 'ok'; else echo '(no luac: skipped)'; fi

echo '== lua 5.1: the Chef hand-off addon'
"$LUA" tests/test_handoff.lua
