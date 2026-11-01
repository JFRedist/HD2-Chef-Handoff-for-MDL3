#!/usr/bin/env bash
# Runs the probe on the REAL Chef Shared Loader, inside Chef's own simulator (tools/modsim), over a scratch copy of the
# simulator extended with walking enemies, state machines and game objects (tools/modsim_extend.py).
#
#   tests/chef_sim.sh <path to a Chef-Shared-Loader checkout> [scratch dir]
#
# Needs python3 with Pillow (Chef's build uses it) and lua5.1. Nothing in the checkout is changed: it is copied first.
# This runs code from the Chef checkout (its simulator, its build script and the loader). Read it before you run it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
CHEF=${1:?usage: tests/chef_sim.sh <path to a Chef-Shared-Loader checkout> [scratch dir]}
SCRATCH=${2:-$(mktemp -d)}
PROBE_DIR=${PROBE_DIR:-$HERE/probe}        # (another copy of probe/, to try a changed or older probe)
command -v lua5.1 >/dev/null || { echo 'needs lua5.1 on the PATH' >&2; exit 2; }
[ -f "$CHEF/tools/modsim/modsim.py" ] || { echo "$CHEF is not a Chef Shared Loader checkout (no tools/modsim/modsim.py)" >&2; exit 2; }

rm -rf "$SCRATCH/chef" && mkdir -p "$SCRATCH/chef"
( cd "$CHEF" && tar --exclude=.git -cf - . ) | tar -xf - -C "$SCRATCH/chef"
python3 -I "$HERE/tools/modsim_extend.py" "$SCRATCH/chef/tools/modsim/modsim.lua" || exit 2
# the same probe with the risky stage on from the start (the F9 row cannot be clicked in the simulator)
sed "s/toggle('enemyobj', 'Enemy game objects (MAY END THE GAME)', false,/toggle('enemyobj', 'Enemy game objects (MAY END THE GAME)', true,/" \
  "$PROBE_DIR/bfv_chef_probe.lua" > "$SCRATCH/probe_risky.lua"
cmp -s "$SCRATCH/probe_risky.lua" "$PROBE_DIR/bfv_chef_probe.lua" && { echo 'the risky-stage copy did not differ: its toggle line changed' >&2; exit 2; }

fails=0
need()    { if grep -Eq -- "$1" "$2"; then echo "  ok    $3"; else echo "  FAIL  $3   (no line matches: $1)"; fails=$((fails + 1)); fi; }
refuse()  { if grep -Eq -- "$1" "$2"; then echo "  FAIL  $3   (found: $(grep -E -m1 -- "$1" "$2" | cut -c1-160))"; fails=$((fails + 1)); else echo "  ok    $3"; fi; }
sim()     { python3 -I "$SCRATCH/chef/tools/modsim/modsim.py" "$@"; }

echo '== a mission with fire, a kill, a mark, a destroyed unit and a charger death (risky stage off)'
sim "$PROBE_DIR/mod.json" --seconds 100 --click left@60.4 --press f6@61.5 --keep "$SCRATCH/keep_a" > "$SCRATCH/a.txt" 2>&1
code=$?
[ "$code" = 0 ] && echo '  ok    the simulated game ran to the end' || { echo "  FAIL  the simulated game ended with exit $code"; fails=$((fails + 1)); }
need 'started mods/jfredist/bfv_chef_probe 0\.1\.0' "$SCRATCH/a.txt" 'the loader found, compiled and started the probe'
need 'CAPS after_startup=1 .* ray_box=1 ' "$SCRATCH/a.txt" 'the capability line lists what the real loader has'
need 'KIND kind=1a7fcdff98c664b0 mover=true sm=true n=3 tier=heavy' "$SCRATCH/a.txt" 'a heavy from the tier table is found moving, with its tier'
need 'FIRE down #1' "$SCRATCH/a.txt" 'a shot is logged'
need 'AIM n=1 aaaa0000#[0-9]+:[0-9.]+m@0\.0' "$SCRATCH/a.txt" 'the aim ray finds the bug straight ahead'
need 'UNIT why=sm->none kind=aaaa000000000001 .* st=7,0,0,0 hist=\[-[0-9.]+:1,0,0,0\|-[0-9.]+:7,0,0,0\] fire=[0-9.]+s ago' "$SCRATCH/a.txt" 'the state machine of the target going away is logged with its state history'
need 'UNIT why=alive->false kind=aaaa000000000001' "$SCRATCH/a.txt" 'a destroyed bug is logged'
need 'UNIT why=sm->none kind=1a7fcdff98c664b0 .* st=12,0,0,0 .* tier=heavy' "$SCRATCH/a.txt" 'the charger death keeps its last state and its tier'
need 'OBJ id=100 sig=[0-9]+ \| 3: 0 -> 1' "$SCRATCH/a.txt" 'the player object kill counter 0 -> 1 is logged'
need 'MARK KILL #1 ' "$SCRATCH/a.txt" 'the mark key works'
need 'bfv_chef_probe	running		addon	0\.1\.0	0	' "$SCRATCH/a.txt" 'the loader lists the probe as running with 0 errors'
refuse 'GAME CRASH|would have ended' "$SCRATCH/a.txt" 'no engine call that would end the game'
refuse ' ERR ' "$SCRATCH/a.txt" 'no ERR lines from the probe'
refuse 'blocked:' "$SCRATCH/a.txt" 'the loader blocked nothing the probe did'
[ -n "$(find "$SCRATCH/keep_a" -name '*bfv_probe_api.txt' -size +100c)" ] && echo '  ok    bfv_probe_api.txt was written' || { echo '  FAIL  bfv_probe_api.txt is missing'; fails=$((fails + 1)); }
[ -n "$(find "$SCRATCH/keep_a" -name '*bfv_probe_summary.txt' -size +100c)" ] && echo '  ok    bfv_probe_summary.txt was written' || { echo '  FAIL  bfv_probe_summary.txt is missing'; fails=$((fails + 1)); }

echo '== the same with the risky stage on'
sim "$SCRATCH/probe_risky.lua" --seconds 100 --click left@60.4 --press f6@61.5 --keep "$SCRATCH/keep_b" > "$SCRATCH/b.txt" 2>&1
[ "$?" = 0 ] && echo '  ok    the simulated game ran to the end' || { echo '  FAIL  the simulated game ended early'; fails=$((fails + 1)); }
need 'EOBJ enemy object stage is on' "$SCRATCH/b.txt" 'the stage announces itself'
need 'EOBJ follow id=2[0-9]+ unit_kind=aaaa000000000001' "$SCRATCH/b.txt" 'enemy objects are found through the unit synchronizer'
need 'EOBJ id=2[0-9]+ sig=\? unit=[0-9a-f]+ \| 1: 100 -> 40' "$SCRATCH/b.txt" 'an enemy object health change 100 -> 40 is logged'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$SCRATCH/b.txt" 'no crash, no ERR, nothing blocked'

echo '== a new mission world replaces the old one (asking a unit of the old one counts as a crash)'
sim "$SCRATCH/probe_risky.lua" --scenario next_mission --seconds 120 --click left@60.4 --keep "$SCRATCH/keep_c" > "$SCRATCH/c.txt" 2>&1
[ "$?" = 0 ] && echo '  ok    the simulated game ran to the end' || { echo '  FAIL  the simulated game ended early'; fails=$((fails + 1)); }
refuse 'GAME CRASH|would have ended' "$SCRATCH/c.txt" 'no unit of the old world was asked anything'
need 'MISSION end world=3' "$SCRATCH/c.txt" 'the first mission ended'
need 'WORLD id=4 in_mission=true' "$SCRATCH/c.txt" 'the new mission world was noticed'
need 'bfv_chef_probe	running		addon	0\.1\.0	0	' "$SCRATCH/c.txt" 'the probe is still running with 0 errors'

echo
[ "$fails" = 0 ] && echo "all checks passed (output in $SCRATCH)" || echo "$fails check(s) failed (output in $SCRATCH)"
exit $((fails != 0))
