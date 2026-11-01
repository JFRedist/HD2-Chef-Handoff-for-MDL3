#!/usr/bin/env bash
# Runs the probe on the REAL Chef Shared Loader, inside Chef's own simulator (tools/modsim), over a scratch copy of the
# simulator extended with a battlefield modelled on the first real run (tools/modsim_extend.py): enemies that walk, sit
# in a death state for 5 s and then lose their state machine, parts that come and go with them, short-lived units, and
# a host that owns about 300 game objects. This is the main check of the probe; tests/test_probe.lua is the quick one.
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
# the same probe with the row for other players' objects on from the start (the F9 row cannot be clicked in the simulator)
sed "s/toggle('remote', \"Other players' game objects (MAY END THE GAME)\", false,/toggle('remote', \"Other players' game objects (MAY END THE GAME)\", true,/" \
  "$PROBE_DIR/bfv_chef_probe.lua" > "$SCRATCH/probe_remote.lua"
cmp -s "$SCRATCH/probe_remote.lua" "$PROBE_DIR/bfv_chef_probe.lua" && { echo 'the remote-row copy did not differ: its toggle line changed' >&2; exit 2; }

fails=0
need()    { if grep -Eq -- "$1" "$2"; then echo "  ok    $3"; else echo "  FAIL  $3   (no line matches: $1)"; fails=$((fails + 1)); fi; }
refuse()  { if grep -Eq -- "$1" "$2"; then echo "  FAIL  $3   (found: $(grep -E -m1 -- "$1" "$2" | cut -c1-160))"; fails=$((fails + 1)); else echo "  ok    $3"; fi; }
exactly() { local n; n=$(grep -Ec -- "$1" "$2"); if [ "$n" = "$3" ]; then echo "  ok    $4"; else echo "  FAIL  $4   ($n lines match, wanted $3: $1)"; fails=$((fails + 1)); fi; }
atmost()  { local n; n=$(grep -Ec -- "$1" "$2"); if [ "$n" -le "$3" ]; then echo "  ok    $4 ($n)"; else echo "  FAIL  $4   ($n lines match, at most $3: $1)"; fails=$((fails + 1)); fi; }
sim()     { python3 -I "$SCRATCH/chef/tools/modsim/modsim.py" "$@"; }
ran()     { if [ "$1" = 0 ]; then echo '  ok    the simulated game ran to the end'; else echo "  FAIL  the simulated game ended with exit $1"; fails=$((fails + 1)); fi; }

echo '== a mission: shots at hive guards and warriors, kills on and off the crosshair, a hunter that flickers, a kind to learn'
sim "$PROBE_DIR/mod.json" --seconds 110 --press f6@61.5 --keep "$SCRATCH/keep_a" > "$SCRATCH/a.txt" 2>&1
ran $?
A="$SCRATCH/a.txt"
need 'started mods/jfredist/bfv_chef_probe 0\.2\.0' "$A" 'the loader found, compiled and started the probe'
need 'CAPS after_startup=1 .* ray_box=1 ' "$A" 'the capability line lists what the real loader has'
need 'SESSION peer=string host=me \(string\) peers=1 other_peers=0' "$A" 'the session is described: this game is the host'
need 'OBJ game objects listed: 3[0-9][0-9] ' "$A" 'the object list of a host is counted'
need 'OBJ all 3[0-9][0-9] game objects looked at once' "$A" 'every one of them is looked at (0.1.0 saw 40)'
need 'OBJSIG sig=[0-9]+ first_object=611 ' "$A" 'the player object (a late id, missed by the 40-object limit) is found'
need 'OBJSIG sig=[0-9]+ first_object=612 ' "$A" 'its avatar object is found'
need ' OBJ id=611 sig=[0-9]+ \| 3: 0 -> 1' "$A" 'a counter of the player object going 0 -> 1 is logged'
need ' OBJ id=359 sig=[0-9]+ \| 3: 32 -> 31' "$A" 'the weapon object following a shot is logged'
need 'OBJSIG sig=[0-9]+ field 2\.[xy] muted: ' "$A" 'a noisy field of a shared layout is muted'
atmost ' GRP id=[0-9]+ sig=[0-9]+ \| .*2\.[xy]: ' "$A" 80 'the noise costs a few lines per layout before it is muted'
need 'KIND kind=1a7fcdff98c664b0 mover=true sm=true n=1 tier=heavy' "$A" 'a heavy from the tier table is found moving, with its tier'
need 'KIND kind=09872e66d1276e1f mover=true sm=true ' "$A" 'a kind of the first run is found moving with a state machine'
refuse 'KIND kind=(40ae90fff236865b|d40f23a128bd988d|620769fb47f74906)' "$A" 'the kinds of the ignore list are never classified or followed'
refuse 'UNIT .* kind=(40ae90fff236865b|d40f23a128bd988d|620769fb47f74906)' "$A" '... and never logged'
need 'IGNORE kind=f00dfeed00000001 is not followed from now on' "$A" 'a short-lived kind without a state machine is ignored by itself'
need 'FIRE down #1' "$A" 'a shot is logged'
need 'AIM n=[0-9]+ .*09872e66#[0-9]+:[0-9.]+m@0\.0' "$A" 'the aim ray finds the warrior straight ahead'
need 'DEATH id=[0-9]+ kind=09872e66d1276e1f st=26,0,0,35 src=seed d=30\.0 ang=0\.0 .* cone=0\.[0-9]+ ray=0\.[0-9]+ fire=[0-9.]+s ago .* obj=1000' "$A" 'a kill on the crosshair is noticed when the death state is entered, with the crosshair evidence and the game object'
need 'DEATH id=[0-9]+ kind=09872e66d1276e1f st=26,0,0,35 src=seed .* cone=- ray=-' "$A" 'a kill off the crosshair says so'
need 'UNIT why=sm->none kind=09872e66d1276e1f .* dying=[45]\.[0-9] ' "$A" 'the state machine going away is logged about 5 s after the DEATH'
need 'DEATH id=[0-9]+ kind=a1f37bf2a40fbde4 st=26,0,0,35 src=seed .*tier=light obj=1008' "$A" 'the hive guard that took four shots dies with its tier'
need 'DEATH id=[0-9]+ kind=1a7fcdff98c664b0 st=12,0,15,30 src=seed .*tier=heavy' "$A" 'the charger death keeps its tier'
need 'DEATH cancel id=[0-9]+ kind=a478d36a62a861f4 was=0,0,0,1 now=8,0,32,1 after=1\.' "$A" 'a hunter that passes through its death state and comes back is taken back'
need 'DEATH learned kind=583ecde0d7718126 st=20,3,0,7 ' "$A" 'a death state that is not in the seeds is learned'
need 'DEATH id=[0-9]+ kind=583ecde0d7718126 st=20,3,0,7 src=learned' "$A" '... and used for the next unit'
need ' STATE id=[0-9]+ kind=09872e66 12,0,0,19 -> 5,0,0,7 ' "$A" 'the state changes of the unit under the crosshair (a hit reaction) are logged'
need 'SIGKIND sig=[0-9]+ kind=09872e66d1276e1f ' "$A" 'the object layout of a unit kind is learned through the unit synchronizer'
need 'AIMOBJ first look id=1008 sig=[0-9]+ unit#[0-9]+ kind=a1f37bf2 ' "$A" 'the object of the unit under the crosshair is looked at'
need 'AIMOBJ id=1008 sig=[0-9]+ unit#[0-9]+ kind=a1f37bf2 \| .*22: 600 -> 440' "$A" 'the first of four hits on the hive guard shows in its game object (hit points 600 -> 440)'
need 'AIMOBJ id=1008 sig=[0-9]+ unit#[0-9]+ kind=a1f37bf2 \| .*22: 120 -> -40' "$A" '... and the fourth'
need 'AIMOBJ id=[0-9]+ sig=[0-9]+ death unit#[0-9]+ kind=' "$A" 'the object is read again when the unit enters its death state'
need ' GRP id=10[0-9]+ sig=[0-9]+ \| 22: [0-9]+ -> 0' "$A" 'hit points of an enemy nobody aimed at reaching 0 show up in the sweep of the shared layouts'
need ' NEW id=' "$A" 'objects made during the mission are logged'
need ' GONE id=1000 sig=' "$A" 'objects that went away are logged'
need ' LINK no object for unit#[0-9]+ ' "$A" 'a unit without a game object is reported (a few times)'
need 'MARK KILL #1 fire=.* deaths6s=\[09872e66#[0-9]+:[0-9.]+s' "$A" 'the mark key works and lists the deaths of the last seconds'
need ' SUM scans=' "$A" 'a SUM line is written'
need 'bfv_chef_probe	running		addon	0\.2\.0	0	' "$A" 'the loader lists the probe as running with 0 errors'
refuse 'GAME CRASH|would have ended' "$A" 'no engine call that would end the game'
refuse ' ERR ' "$A" 'no ERR lines from the probe'
refuse 'blocked:' "$A" 'the loader blocked nothing the probe did'
msavg=$(awk -F'\t' '$1 ~ /bfv_chef_probe/ { print $7 }' "$A" | tail -1)
if [ -n "$msavg" ] && awk -v v="$msavg" 'BEGIN { exit !(v < 0.5) }'; then echo "  ok    the loader measures ${msavg} ms a frame on average (plain Lua here, the game's is faster)"; else echo "  FAIL  the probe's average time a frame is '${msavg}' ms"; fails=$((fails + 1)); fi
api=$(find "$SCRATCH/keep_a" -name '*bfv_probe_api.txt' -size +100c)
sumf=$(find "$SCRATCH/keep_a" -name '*bfv_probe_summary.txt' -size +100c)
[ -n "$api" ] && echo '  ok    bfv_probe_api.txt was written' || { echo '  FAIL  bfv_probe_api.txt is missing'; fails=$((fails + 1)); }
[ -n "$sumf" ] && echo '  ok    bfv_probe_summary.txt was written' || { echo '  FAIL  bfv_probe_summary.txt is missing'; fails=$((fails + 1)); }
if [ -n "$sumf" ]; then
  need '^stage errors: none' "$sumf" 'the summary says no stage raised an error'
  need '^lines dropped by tag caps: none' "$sumf" 'and that no line was dropped by a cap'
  need '^## death states' "$sumf" 'the summary has the death state table'
  need '^09872e66d1276e1f +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +4\.9[0-9] +26,0,0,35\(seed\)' "$sumf" 'with the seconds between the death state and the machine going away (about 5)'
  need '^40ae90fff236865b .* part ' "$sumf" 'the ignored kinds are listed as such'
  need '^sig=[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ \| .*22:[0-9]+ \| ' "$sumf" 'the object layout table lists the fields that changed'
fi

echo "== a second player joins and the row for other players' objects is on"
sim "$SCRATCH/probe_remote.lua" --seconds 110 --join 66 --press f6@61.5 --keep "$SCRATCH/keep_b" > "$SCRATCH/b.txt" 2>&1
ran $?
B="$SCRATCH/b.txt"
need 'OBJSIG sig=[0-9]+ first_object=9001 ' "$B" "the other player's objects are looked at"
need ' NEW id=9001 ' "$B" '... when they appear'
refuse 'GAME CRASH|would have ended| ERR |blocked:' "$B" 'no crash, no ERR, nothing blocked'
refuse 'first_object=9001' "$A" 'with the row off (default) they are not read'

echo '== a new mission world replaces the old one (asking a unit of the old one counts as a crash)'
sim "$PROBE_DIR/mod.json" --scenario next_mission --seconds 130 --click left@60.4 --keep "$SCRATCH/keep_c" > "$SCRATCH/c.txt" 2>&1
ran $?
C="$SCRATCH/c.txt"
refuse 'GAME CRASH|would have ended' "$C" 'no unit of the old world was asked anything'
need 'MISSION end world=3' "$C" 'the first mission ended'
need 'WORLD id=4 in_mission=true' "$C" 'the new mission world was noticed'
exactly ' SESSION ' "$C" 2 'the session is described once for each mission world'
refuse 't=88\.0[0-9] UNIT ' "$C" 'the units of the old world are not reported as deaths when the new world starts'
exactly 'KIND kind=09872e66d1276e1f ' "$C" 1 'a kind is reported once per launch, not once per world'
need 'UNIT why=sm->none kind=[0-9a-f]+ .* dying=[45]\.' "$C" 'deaths are followed in the second world too'
need 'bfv_chef_probe	running		addon	0\.2\.0	0	' "$C" 'the probe is still running with 0 errors'
refuse ' ERR |blocked:' "$C" 'no ERR, nothing blocked'

echo
[ "$fails" = 0 ] && echo "all checks passed (output in $SCRATCH)" || echo "$fails check(s) failed (output in $SCRATCH)"
exit $((fails != 0))
