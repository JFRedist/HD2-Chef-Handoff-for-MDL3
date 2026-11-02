#!/usr/bin/env bash
# Runs the hand-off addon (handoff/chef_handoff.lua) on the REAL Chef Shared Loader, inside Chef's own simulator
# (tools/modsim), under stand-ins for another loader's boot (tests/fixtures/handoff/mdl3_boot_*.lua). The simulator runs
# the `boot` of the highest patch, as the game does; the stand-in is deployed above Chef, so Chef's own boot does not run
# and, without the hand-off, no Chef mod would start.
#
#   tests/handoff_sim.sh <path to a Chef-Shared-Loader checkout> [scratch dir]
#
# HANDOFF_LUA=<another copy of the addon> runs that one instead: variant F fails for 0.2.0 on Chef 1.5.x (the hang watchdog stops the
# other loader's update chain), which is what it is there to catch.
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
VER=$(sed -n "s/^local VERSION = '\([^']*\)'.*/\1/p" "$HANDOFF_LUA" | head -1)      # the addon's version, with its dots escaped for grep
VERRE=${VER//./\\.}

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
run_variant a mod_a.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
A="$SCRATCH/a.txt"
need '\[stand-in mdl3\] init' "$A" 'the stand-in loaders boot ran (not Chefs stub)'
need '\[stand-in mdl3\] mods/jfredist/chef_handoff -> loaded' "$A" 'it started the hand-off addon'
need "started by MDL3 chef_handoff $VERRE, which handed off to me" "$A" 'Chef says it was handed the game, and by whom'
need 'boot scripts of mine, not run: .*my start-up stub' "$A" 'Chefs own boot stub is not run (the other loaders boot is the one the game ran)'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$A" 'a mod made for Chef starts'
need '\[mods/jfredist/handoff_standin\] stand-in addon started on Chef Shared Loader 1\.[0-9]+\.[0-9]+' "$A" 'and runs on Chefs API'
need 'mods/jfredist/chef_handoff: already started by .* not started again' "$A" 'Chef does not start the hand-off addon a second time'
refuse 'running the callbacks the boot script in .* set before it started me' "$A" 'Chef is not given the other loaders callbacks to keep (Chef from 1.5.0 would run them under its hang watchdog)'
need 'stand-in addon: [0-9]{3,} frames' "$A" 'the stand-in addon ran for the whole session'
need 'drawn: [1-9][0-9]* rects' "$A" 'and drew in the mission'
need '\[stand-in mdl3\] shutdown; updates seen: (1[7-9][0-9]{2}|[2-9][0-9]{3})' "$A" 'the other loaders update went on being called every frame (about 3600 in 60 s)'
need 'mods/jfredist/handoff_standin	running		addon	0\.0\.1	0	' "$A" 'the loader lists the mod as running with 0 errors'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$A" 'no crash, no ERR, nothing blocked'
hl=$(kept "$SCRATCH/keep_a" 'chef_handoff.log'); hs=$(kept "$SCRATCH/keep_a" 'chef_handoff_state.txt')
if [ -n "$hl" ]; then
  need "chef_handoff $VERRE loaded; the game.s update is a function" "$hl" 'chef_handoff.log: the addon says it loaded and found an update to hook'
  need 'CowboyBingusModLoader = table\(' "$hl" 'and lists the loader table it found'
  need ' 6\.[0-9] s \| handing off: require' "$hl" 'and that it handed off after the 6 s delay'
  need "the game.s update, render, shutdown now run behind Chef.s own" "$hl" 'and that the other loaders callbacks run behind Chefs own'
  need 'Chef Shared Loader 1\.[0-9]+\.[0-9]+ started' "$hl" 'and that Chef started'
  need 'the game.s callbacks before: init=[^ ]+ \[boot:[0-9]+\] update=[^ ]+ \[mods/jfredist/chef_handoff:[0-9]+\]' "$hl" 'it names the callbacks before the hand-off (the boots, and its own hook on update)'
  need 'the game.s callbacks after Chef loaded: init=[^ ]+ \[mods/chef_shared_loader/core_1:[0-9]+\] update=[^ ]+ \[mods/chef_shared_loader/core_1:' "$hl" 'and after it: Chefs own'
  refuse 'still on the globals|the one taken off' "$hl" 'nothing stayed on the globals, and nothing taken off came back before Chef was done'
  need 'around the globals: metatable of _G: none; _G is the global table: yes, this addon runs in it: yes; require: [^ ]+ \[C\]' "$hl" 'it describes the globals and require (the simulators: plain)'
  need 'the game.s update chain ran 600 times in Chef.s first 600 updates: once a frame' "$hl" 'the other loaders update chain then runs once a frame: Chef does not run it as well'
else echo '  FAIL  chef_handoff.log was not written'; fails=$((fails + 1)); fi
if [ -n "$hs" ] && grep -q "^ok $VERRE" "$hs"; then echo '  ok    chef_handoff_state.txt says ok'; else echo '  FAIL  chef_handoff_state.txt does not say ok'; fails=$((fails + 1)); fi

echo '== B: the other loader starts every addon in its boot, tries the Chef mod with a plain require first'
run_variant b mod_b.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
B="$SCRATCH/b.txt"
need '\[stand-in mdl3\] mods/jfredist/handoff_standin -> loaded' "$B" 'the plain require of a Chef mod under the other loader does nothing (the mod stops at once without the chef table)'
need '\[stand-in mdl3\] boot done; init ran yet\? nil' "$B" 'the hand-off addon was started before the game called init'
need "started by MDL3 chef_handoff $VERRE, which handed off to me" "$B" 'the hand-off still comes, on the first frames after the delay'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$B" 'and Chef starts the mod made for it although the other loader already tried it'
refuse 'running the callbacks the boot script in .* set before it started me' "$B" 'the other loaders callbacks are not given to Chef to keep either'
need 'stand-in addon: [0-9]{3,} frames' "$B" 'it ran'
need '\[stand-in mdl3\] mods/jfredist/handoff_standin2 -> loaded' "$B" 'the second stand-in (no HD2-Requires line, like Treasure Radar) survives the other loader plain require: it is "started" without Chef'
need 'started mods/jfredist/handoff_standin2 0\.0\.2' "$B" 'and Chef starts it all the same, because the hand-off addon took it off package.loaded'
refuse 'mods/jfredist/handoff_standin2: already started by another loader' "$B" 'Chef does not skip it as started by another loader'
need 'stand-in 2: [0-9]{3,} frames' "$B" 'it ran on Chef for the whole session'
need '\[stand-in mdl3\] init' "$B" 'the games own init ran once (not dropped by the hand-off)'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$B" 'no crash, no ERR, nothing blocked'
test "$(grep -c '^\[stand-in mdl3\] init' "$B")" = 1 && echo '  ok    init ran exactly once' || { echo '  FAIL  init did not run exactly once'; fails=$((fails + 1)); }

echo '== E: as the real MDL3 showed itself in the first real run: a plain require leaves only package.loaded behind, no modules table entries'
run_variant e mod_e.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
E="$SCRATCH/e.txt"
grep -n 'modules\[' "$FIX/mdl3_boot_e.lua" > /dev/null && { echo '  FAIL  the E stand-in must not touch a modules table'; fails=$((fails + 1)); }
need '\[stand-in mdl3\] mods/jfredist/handoff_standin2 -> loaded' "$E" 'the stand-in Chef addon without an HD2-Requires line is "started" without Chef (as Treasure Radar was)'
need "started by MDL3 chef_handoff $VERRE, which handed off to me" "$E" 'the hand-off comes'
need 'started mods/jfredist/handoff_standin2 0\.0\.2' "$E" 'and Chef starts it all the same'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$E" 'and the one with the HD2-Requires line'
refuse 'mods/jfredist/handoff_standin2?: already started by another loader' "$E" 'Chef skips neither as started by another loader'
need 'stand-in 2: [0-9]{3,} frames' "$E" 'the second one ran on Chef for the whole session'
need 'taken off package.loaded, so that Chef starts them: .*handoff_standin2' "$(kept "$SCRATCH/keep_e" 'chef_handoff.log')" 'chef_handoff.log: it says it took them off the list'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$E" 'no crash, no ERR, nothing blocked'

echo '== F: the other loader has one slow update call (3.6 s of CPU time, 15 s in): Chef from 1.5.0 would stop a chain it ran itself'
run_variant f mod_f.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
F="$SCRATCH/f.txt"
need "started by MDL3 chef_handoff $VERRE, which handed off to me" "$F" 'the hand-off comes'
need 'started mods/jfredist/handoff_standin 0\.0\.1' "$F" 'and Chef starts the mod made for it'
need '\[stand-in mdl3\] the slow update call ended' "$F" 'the slow call was allowed to finish'
refuse 'stopped by the hang watchdog|switched off .* for this session|stopped after [0-9]+ errors' "$F" 'the hang watchdog did not stop the other loaders update'
need '\[stand-in mdl3\] shutdown; updates seen: (3[0-9]{3}|[4-9][0-9]{3})' "$F" 'and its update went on being called every frame afterwards (about 3600 in 60 s)'
need 'stand-in addon: [0-9]{3,} frames' "$F" 'the Chef mod ran for the whole session'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$F" 'no crash, no ERR, nothing blocked'
hl=$(kept "$SCRATCH/keep_f" 'chef_handoff.log')
if [ -n "$hl" ]; then need 'took [0-9]+ ms of CPU time' "$hl" 'chef_handoff.log: the slow call is written down'; else echo '  FAIL  chef_handoff.log was not written'; fails=$((fails + 1)); fi

echo '== G: the other loader puts its render and shutdown back whenever something opens a file (a guess at the first real run on Chef 1.5.1)'
run_variant g mod_g.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
GV="$SCRATCH/g.txt"
need "started by MDL3 chef_handoff $VERRE, which handed off to me" "$GV" 'the hand-off comes'
need 'started mods/jfredist/handoff_standin2 0\.0\.2' "$GV" 'and Chef starts the mods made for it'
refuse 'running the callbacks the boot script in .* set before it started me' "$GV" 'Chef finds no callbacks to keep (with 0.2.1 it finds 2 here, as in the real run)'
need '\[stand-in mdl3\] shutdown; updates seen: (3[0-9]{3}|[4-9][0-9]{3}); callbacks put back: 0' "$GV" 'nothing opened a file while they were off: the loader never had to put one back'
test "$(grep -c '^\[stand-in mdl3\] shutdown' "$GV")" = 1 && echo '  ok    its shutdown ran once (with 0.2.1: twice, from Chef that kept it and from behind Chef)' \
  || { echo '  FAIL  its shutdown did not run exactly once'; fails=$((fails + 1)); }
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$GV" 'no crash, no ERR, nothing blocked'

echo '== C: the other loader hands off to Chef itself, in its boot: the addon leaves it alone'
run_variant c mod_c.json "$FIX/standin_chef_addon.lua" "$FIX/standin_chef_addon_norequires.lua"
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
  need 'HUDdle [0-9.]+ on Chef Shared Loader 1\.[0-9]+\.[0-9]+' "$D" 'and runs on it'
  refuse 'GAME CRASH|would have ended' "$D" 'no crash'
else
  echo '== D (optional, HUDDLE_LUA not set): skipped'
fi

echo
[ "$fails" = 0 ] && echo "all checks passed (output in $SCRATCH)" || echo "$fails check(s) failed (output in $SCRATCH)"
exit $((fails != 0))
