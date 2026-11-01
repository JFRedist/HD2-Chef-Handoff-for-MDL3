#!/usr/bin/env bash
# Runs the hand-off addon (handoff/chef_handoff.lua) on the REAL Chef Shared Loader, inside Chef's own simulator
# (tools/modsim), under stand-ins for another loader's boot (tests/fixtures/handoff/mdl3_boot_*.lua). The simulator runs
# the `boot` of the highest patch, as the game does; the stand-in is deployed above Chef, so Chef's own boot does not run
# and, without the hand-off, no Chef mod would start.
#
#   tests/handoff_sim.sh <path to a Chef-Shared-Loader checkout> [scratch dir]
#
# Optional: HUDDLE_LUA=/path/to/the/HUDdle/lua/resource also starts the real HUDdle (not part of this repository: take it
# out of your own copy of the mod with tools/inspect_patch.py).
# Needs python3 with Pillow (Chef's build uses it) and lua5.1. Nothing in the checkout is changed: it is copied first.
# This runs code from the Chef checkout (its simulator, its build script and the loader). Read it before you run it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
CHEF=${1:?usage: tests/handoff_sim.sh <path to a Chef-Shared-Loader checkout> [scratch dir]}
SCRATCH=${2:-$(mktemp -d)}
HANDOFF_LUA=${HANDOFF_LUA:-$HERE/handoff/chef_handoff.lua}      # (another copy of the addon, to try a changed or older one)
command -v lua5.1 >/dev/null || { echo 'needs lua5.1 on the PATH' >&2; exit 2; }
[ -f "$CHEF/tools/modsim/modsim.py" ] || { echo "$CHEF is not a Chef Shared Loader checkout (no tools/modsim/modsim.py)" >&2; exit 2; }

rm -rf "$SCRATCH/chef" "$SCRATCH/fix" && mkdir -p "$SCRATCH/chef" "$SCRATCH/fix"
( cd "$CHEF" && tar --exclude=.git -cf - . ) | tar -xf - -C "$SCRATCH/chef"
# the fixtures, with the addon under test next to them
cp "$HERE"/tests/fixtures/handoff/*.lua "$HERE"/tests/fixtures/handoff/*.json "$SCRATCH/fix/"
cp "$HANDOFF_LUA" "$SCRATCH/fix/chef_handoff.lua"
sed -i 's#\.\./\.\./\.\./handoff/chef_handoff\.lua#chef_handoff.lua#' "$SCRATCH"/fix/mod_*.json
FIX="$SCRATCH/fix"

fails=0
need()    { if grep -Eq -- "$1" "$2"; then echo "  ok    $3"; else echo "  FAIL  $3   (no line matches: $1)"; fails=$((fails + 1)); fi; }
refuse()  { if grep -Eq -- "$1" "$2"; then echo "  FAIL  $3   (found: $(grep -E -m1 -- "$1" "$2" | cut -c1-170))"; fails=$((fails + 1)); else echo "  ok    $3"; fi; }
sim()     { python3 -I "$SCRATCH/chef/tools/modsim/modsim.py" "$@"; }
ran()     { if [ "$1" = 0 ]; then echo '  ok    the simulated game ran to the end'; else echo "  FAIL  the simulated game ended with exit $1"; fails=$((fails + 1)); fi; }
kept()    { find "$1" -name "*$2" -type f | head -1; }       # a file of the kept game folder, by its name's end

run_variant() {   # name, mod json, extra files...
  local name=$1 json=$2; shift 2
  sim "$@" "$FIX/$json" --seconds 60 --full-log --keep "$SCRATCH/keep_$name" > "$SCRATCH/$name.txt" 2>&1
  ran $?
}

echo '== A: the other loader starts its addons in init; Chef is handed the game on the first frames after 6 s'
run_variant a mod_a.json "$FIX/standin_chef_addon.lua"
A="$SCRATCH/a.txt"
need '\[stand-in mdl3\] init' "$A" 'the stand-in loaders boot ran (not Chefs stub)'
need '\[stand-in mdl3\] mods/jfredist/chef_handoff -> loaded' "$A" 'it started the hand-off addon'
need 'started by MDL3 chef_handoff 0\.1\.0, which handed off to me' "$A" 'Chef says it was handed the game, and by whom'
need 'boot scripts of mine, not run: .*my start-up stub' "$A" 'Chefs own boot stub is not run (the other loaders boot is the one the game ran)'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$A" 'a mod made for Chef starts'
need '\[mods/jfredist/handoff_standin\] stand-in addon started on Chef Shared Loader 1\.4\.1' "$A" 'and runs on Chefs API'
need 'mods/jfredist/chef_handoff: already started by .* not started again' "$A" 'Chef does not start the hand-off addon a second time'
need 'running the callbacks the boot script in .* set before it started me \(3\)' "$A" 'the callbacks the other loader set keep running: update, render, shutdown (not init, which the game has called already)'
need 'stand-in addon: [0-9]{3,} frames' "$A" 'the stand-in addon ran for the whole session'
need 'drawn: [1-9][0-9]* rects' "$A" 'and drew in the mission'
need '\[stand-in mdl3\] shutdown; updates seen: (1[7-9][0-9]{2}|[2-9][0-9]{3})' "$A" 'the other loaders update went on being called every frame (about 3600 in 60 s)'
need 'mods/jfredist/handoff_standin	running		addon	0\.0\.1	0	' "$A" 'the loader lists the mod as running with 0 errors'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$A" 'no crash, no ERR, nothing blocked'
hl=$(kept "$SCRATCH/keep_a" 'chef_handoff.log'); hs=$(kept "$SCRATCH/keep_a" 'chef_handoff_state.txt')
if [ -n "$hl" ]; then
  need 'chef_handoff 0\.1\.0 loaded; the game.s update is a function' "$hl" 'chef_handoff.log: the addon says it loaded and found an update to hook'
  need 'CowboyBingusModLoader = table\(' "$hl" 'and lists the loader table it found'
  need ' 6\.[0-9] s \| handing off: require' "$hl" 'and that it handed off after the 6 s delay'
  need 'Chef Shared Loader 1\.4\.1 started' "$hl" 'and that Chef started'
else echo '  FAIL  chef_handoff.log was not written'; fails=$((fails + 1)); fi
if [ -n "$hs" ] && grep -q '^ok 0.1.0' "$hs"; then echo '  ok    chef_handoff_state.txt says ok'; else echo '  FAIL  chef_handoff_state.txt does not say ok'; fails=$((fails + 1)); fi

echo '== B: the other loader starts every addon in its boot, tries the Chef mod with a plain require first'
run_variant b mod_b.json "$FIX/standin_chef_addon.lua"
B="$SCRATCH/b.txt"
need '\[stand-in mdl3\] mods/jfredist/handoff_standin -> loaded' "$B" 'the plain require of a Chef mod under the other loader does nothing (the mod stops at once without the chef table)'
need '\[stand-in mdl3\] boot done; init ran yet\? nil' "$B" 'the hand-off addon was started before the game called init'
need 'started by MDL3 chef_handoff 0\.1\.0, which handed off to me' "$B" 'the hand-off still comes, on the first frames after the delay'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$B" 'and Chef starts the mod made for it although the other loader already tried it'
need 'running the callbacks the boot script in .* set before it started me \(3\)' "$B" 'with the other loader callbacks kept, init not among them'
need 'stand-in addon: [0-9]{3,} frames' "$B" 'it ran'
need '\[stand-in mdl3\] init' "$B" 'the games own init ran once (not dropped by the hand-off)'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$B" 'no crash, no ERR, nothing blocked'
test "$(grep -c '^\[stand-in mdl3\] init' "$B")" = 1 && echo '  ok    init ran exactly once' || { echo '  FAIL  init did not run exactly once'; fails=$((fails + 1)); }

echo '== C: the other loader hands off to Chef itself, in its boot: the addon leaves it alone'
run_variant c mod_c.json "$FIX/standin_chef_addon.lua"
C="$SCRATCH/c.txt"
need 'started by stand-in MDL3 \(own hand-off\), which handed off to me' "$C" 'Chef was started by the other loader'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$C" 'the Chef mod runs'
refuse 'started by MDL3 chef_handoff' "$C" 'the hand-off addon did not hand off a second time'
hl=$(kept "$SCRATCH/keep_c" 'chef_handoff.log')
if [ -n "$hl" ]; then need 'Chef Shared Loader is running already' "$hl" 'chef_handoff.log: it saw Chef running and did nothing'; else echo '  FAIL  chef_handoff.log was not written'; fails=$((fails + 1)); fi
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$C" 'no crash, no ERR, nothing blocked'

if [ -n "${HUDDLE_LUA:-}" ] && [ -f "$HUDDLE_LUA" ]; then
  echo '== D (optional): the real HUDdle, in the same arrangement as A'
  run_variant d mod_a.json "$HUDDLE_LUA"
  D="$SCRATCH/d.txt"
  need 'started mods/rosensterner/minimal_hud ' "$D" 'HUDdle starts under Chef under the other loader'
  need 'HUDdle [0-9.]+ on Chef Shared Loader 1\.4\.1' "$D" 'and runs on it'
  refuse 'GAME CRASH|would have ended' "$D" 'no crash'
else
  echo '== D (optional, HUDDLE_LUA not set): skipped'
fi

echo
[ "$fails" = 0 ] && echo "all checks passed (output in $SCRATCH)" || echo "$fails check(s) failed (output in $SCRATCH)"
exit $((fails != 0))
