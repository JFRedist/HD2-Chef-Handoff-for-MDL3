-- Runs the BFV Chef Probe in tests/probe_harness.lua's simulated session and checks what it wrote.
--   lua5.1 tests/test_probe.lua            (from the repository root)
-- This tests the addon's own logic and that it stays inside what a Chef mod may touch. It does not test the game or the
-- real Chef Shared Loader: see README.md for what is and isn't verified.
local H = dofile('tests/probe_harness.lua')
local ADDON = os.getenv('PROBE_ADDON') or 'probe/bfv_chef_probe.lua'
local OUT = os.getenv('PROBE_TEST_OUT') or '/tmp/bfv_probe_test'

local checks, failures = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if cond then print('  ok    ' .. msg) else failures = failures + 1; print('  FAIL  ' .. msg) end
end
local function first(list, pattern)
  for _, line in ipairs(list or {}) do if line:find(pattern) then return line end end
end
local function count(list, pattern)
  local n = 0
  for _, line in ipairs(list or {}) do if line:find(pattern) then n = n + 1 end end
  return n
end
local function num(line, key)
  return line and tonumber(line:match(key .. '=(-?[%d%.]+)'))
end

local BUG_A, BUG_B = 'aaaa000000000001', 'aaaa000000000002'
local HULK, PROP, SQUAD, RUNTIME = '1a7fcdff98c664b0', 'cccc000000000001', 'dddd000000000001', '46cab355bd8d4d37'

-- a mission: bugs that wander (12 of kind A, 8 of B), a hulk, squadmates, props that never move, a runtime-built unit,
-- and the network objects of a player (and, owned by the host, one object for each bug)
local function populate(S)
  S.bugs = {}
  for i = 1, 12 do
    local u = S:unit(BUG_A, (i * 7) % 50 - 25, 10 + (i * 5) % 40, 0,
      { sm = true, state = { 1, 0, 0, 0 }, vx = 0.6 + (i % 3) * 0.4, vy = 0.3, objid = 1000 + i })
    S.bugs[i] = u
    S.objects[1000 + i] = { owner = 7, fields = { [1] = 100, [2] = 0 } }
  end
  -- bug 3 stands still straight ahead of the camera (which is at 0,-30 looking along +y): the aim target
  local b3 = S.bugs[3]
  b3.x, b3.y, b3.z, b3.vx, b3.vy = 0, 15, 0, 0.0001, 0.0001
  for i = 1, 8 do
    S:unit(BUG_B, (i * 9) % 60 - 30, 20 + i * 4, 0, { sm = true, state = { 2, 0, 0, 0 }, vx = -0.5, vy = 0.2 })
  end
  S.hulk = S:unit(HULK, 12, 30, 0, { sm = true, state = { 5, 0, 0, 0 }, vx = 0.2, vy = 0.1 })
  for i = 1, 2 do S:unit(SQUAD, -5 + i, -20, 0, { sm = true, state = { 7, 0, 0, 0 }, vx = 0.3, vy = 0.3 }) end
  for i = 1, 10 do S:unit(PROP, i * 6 - 30, 25, 0, {}) end
  S:unit(RUNTIME, 0, 0, 0, {})
  S:unit(BUG_A, 300, 300, 0, { sm = true, state = { 1, 0, 0, 0 }, vx = 1, vy = 1 })      -- far away: never followed
  S.objects[100] = { owner = 7, fields = { [1] = 1, [2] = 42, [3] = 0, [4] = 0, [5] = 0, [6] = false, [7] = true } }
  S.objects[101] = { owner = 7, fields = { [1] = S:vec(0, 0, 0), [2] = 0.0, [3] = 100, [64] = { [25] = 32767, [26] = 3 } } }
  S.objects[102] = { owner = 7, fields = { [1] = 30, [2] = 'rifle' } }
  for i = 150, 170 do S.objects[i] = { owner = 7, fields = { [1] = 0, [2] = 0 } } end
end

local function wander(S, dt)
  for _, u in ipairs(S.units) do
    if u.vx and not u.removed and u.sm then
      u.x, u.y = u.x + u.vx * dt, u.y + u.vy * dt
      if u.x > 60 or u.x < -60 then u.vx = -u.vx end
      if u.y > 80 or u.y < -40 then u.vy = -u.vy end
    end
  end
  local a = S.objects[101]
  if a then                                   -- the avatar moves every frame: its fields are noise
    a.fields[1] = S:vec(S.t, 0, 0)
    a.fields[2] = S.t
  end
end

-- ===========================================================================================================
print('== scenario 1: a mission with fire, kills, marks, a new mission world and the link stage')
local S = H.new{ dir = OUT .. '/full', addon = ADDON }
S.script = function(s)
  local t = s.t
  if not s.started and t >= 12 then s.started = true; s:new_world(true); populate(s) end
  if not s.in_mission then return end
  wander(s, 1 / 60)
  s.mouse.left = (t >= 20 and t < 21.2)
  local p = s.objects[100]
  if p then
    if t >= 20.2 and not s.h1 then s.h1 = true; p.fields[5] = p.fields[5] + 1 end
    if t >= 20.5 and not s.h2 then s.h2 = true; p.fields[5] = p.fields[5] + 1 end
    if t >= 21.1 and not s.k1 then s.k1 = true; p.fields[3] = 1 end
  end
  if t >= 21.0 and not s.d3 then s.d3 = true; s.bugs[3].sm = false; s.bugs[3].state = {} end
  if t >= 22.0 and not s.m1 then s.m1 = true; s.binds.mark_kill.fire = true end
  if t >= 25 and not s.d7 then s.d7 = true; s.bugs[7].removed = true end
  if t >= 35 and not s.hs then s.hs = true; s.hulk.state = { 12, 0, 0, 0 } end
  if t >= 38 and not s.hd then s.hd = true; s.hulk.sm = false end
  if t >= 43 and not s.hp then
    s.hp = true
    for id, o in pairs(s.objects) do if id >= 1000 then o.fields[1] = 60 end end
  end
  if t >= 50 and not s.w3 then s.w3 = true; s:end_mission(); s:new_world(true); populate(s) end
  -- a death in the new world soon after it started: the kinds are already known, so it must be followed at once
  if t >= 53 and not s.d5 then s.d5 = true; s.bugs[5].sm = false end
  if t >= 75 and not s.left then s.left = true; s:end_mission() end
end
S:run(90)
S:shutdown()
S:save_logs()
local log = S.logs.bfv_probe or {}
local api = S:read('bfv_probe_api.txt')
local sum = S:read('bfv_probe_summary.txt')

check(S.title == 'BFV Chef Probe', 'the F9 menu heading is set')
check(S.rows.units and S.rows.player and S.rows.wide and S.rows.aim and S.rows.link and S.rows.remote and S.rows.hud, 'the menu rows exist')
check(S.rows.remote.spec.default == false, "the risky row (other players' objects) is off by default")
check(S.rows.link.spec.default == true and S.rows.wide.spec.default == true, 'the unit-to-object lookups and the all-objects sweep are on by default')
check(S.binds.mark_kill and S.binds.mark_hit and S.binds.mark_other, 'three mark keys are bound')
check(S.rows.dump_api and S.rows.dump_sum, 'the two buttons exist')
check(#log > 50, 'the probe wrote its own log (' .. #log .. ' lines)')
check(S.crashed == nil, 'no call would have ended the game: ' .. tostring(S.crashed))
check(count(log, ' ERR ') == 0, 'no ERR lines in the log')
check(count(log, 'BANNER probe=') == 1 and count(log, ' CAPS ') == 1 and count(log, ' ENV ') == 1, 'banner, capabilities and environment lines')
check(first(log, ' CAPS after_startup=1 ') and first(log, ' ray_box=1 ') and first(log, ' option_folds=1$'), 'the capability line lists every capability by asking chef.has (capabilities itself is a read-only proxy)')
check(count(log, ' WORLD id=') >= 3, 'every world change is logged (' .. count(log, ' WORLD id=') .. ')')
check(count(log, 'MISSION start') == 2 and count(log, 'MISSION end') == 2, 'mission start/end events are logged')

check(api and api:find('WwiseWorld', 1, true) and api:find('trigger_event', 1, true), 'the API file lists the Wwise functions')
check(api and api:find('Localizer=false', 1, true), 'a table the loader keeps from mods is reported as blocked')
check(api and api:find('## every engine table', 1, true), 'the API file lists every engine table')
check(first(log, ' API at start%-up: %d+ tables'), 'the API dump is announced in the log')

check(first(log, 'KIND kind=' .. BUG_A .. ' mover=true sm=true'), 'bugs of kind A are recognised as moving units with a state machine')
check(first(log, 'KIND kind=' .. HULK .. ' mover=true sm=true n=1 tier=heavy'), 'a heavy from the tier table is recognised as a mover and its tier is shown')
check(first(log, 'KIND kind=' .. BUG_A .. ' mover=true sm=true n=%d+ tier=%?'), 'a kind the tier table does not know shows tier=?')
check(count(log, 'KIND kind=' .. BUG_A) == 1, 'a kind is reported once per launch, not once per world')
check(count(log, 'UNIT why=sm%->none kind=' .. BUG_A) >= 2, 'a death early in the second mission world is followed (kinds were kept)')
check(count(log, 'KIND kind=' .. PROP) == 0, 'props are never reported as movers')
check(count(log, 'KIND kind=' .. RUNTIME) == 0, 'the runtime-built unit is left alone')

local u3 = first(log, 'UNIT why=sm%->none kind=' .. BUG_A .. ' id=%d+ age=[%d%.]+ d=[%d%.]+ ang=[%d%.]+ st=1,0,0,0 hist=%[%-?[%d%.]+:1,0,0,0%]')
check(u3 ~= nil, 'bug 3 is logged when its state machine goes away, with the last state it was in')
local deaths_a = {}
for _, line in ipairs(log) do if line:find('UNIT why=sm%->none kind=' .. BUG_A) then deaths_a[#deaths_a + 1] = line end end
local aimed
for _, line in ipairs(deaths_a) do if (num(line, 'ang') or 99) < 3 then aimed = line end end
check(aimed and aimed:find('fire=') and (aimed:find('held') or aimed:find('ago')), 'its crosshair angle is small and the last fire is noted: ' .. tostring(aimed and aimed:match('ang=%S+ ') .. aimed:match('fire=.*$')))
check(first(log, 'UNIT why=alive%->false kind=' .. BUG_A) or first(log, 'UNIT why=gone kind=' .. BUG_A), 'a destroyed bug is logged')
local hulk = first(log, 'UNIT why=sm%->none kind=' .. HULK)
check(hulk and hulk:find('hist=%[%-[%d%.]+:5,0,0,0|%-[%d%.]+:12,0,0,0%]') and hulk:find('tier=heavy dying=%-'), 'the hulk death keeps its state history 5 -> 12, in seconds before the event, and its tier')

check(count(log, ' OBJSIG sig=') >= 3, 'game object field layouts are described (' .. count(log, ' OBJSIG sig=') .. ' signatures)')
check(not table.concat(log, '\n'):find('rifle', 1, true) and first(log, '2=str#%d+:5'), 'text values of game objects are not written to the log, only a numbered stand-in with the length')
local kill_field = first(log, ' OBJ id=100 sig=%d+ | 3: 0 %-> 1')
check(kill_field ~= nil, 'a counter field of my own player object changing 0 -> 1 is logged')
check(first(log, ' OBJ id=100 sig=%d+ | 5: 0 %-> 1') and first(log, ' OBJ id=100 sig=%d+ | 5: 1 %-> 2'), 'hit counter changes are logged')
check(first(log, ' OBJ id=101 [%d%.]+ muted'), 'a field that changes every frame is muted')
check(count(log, ' OBJ id=101 sig=%d+ | 1:') <= 24, 'the noisy field does not flood the log (' .. count(log, ' OBJ id=101 sig=%d+ | 1:') .. ' lines in two worlds)')
check(count(log, ' OBJ id=15%d') == 0, 'objects of the crowd layout are not followed')

check(count(log, ' FIRE down') == 1 and count(log, ' FIRE up held=') == 1, 'one burst of fire is logged')
local aim = first(log, ' AIM n=%d+ aaaa0000#%d+:[%d%.]+m@[%d%.]+')
check(aim ~= nil, 'the aim ray test finds the bug straight ahead while firing')
local mark = first(log, ' MARK KILL #1 fire=')
check(mark and mark:find('near=%[%x+#%d+ d=[%d%.]+ ang=[%d%.]+ alive=true sm=true st=%d'), 'the kill mark lists the nearest followed units with their state')
check(S.notices[1] and S.notices[1].text:find('MARK KILL 1', 1, true), 'a mark shows a notice on screen')
local ki, mi
for i, line in ipairs(log) do
  if not ki and line == kill_field then ki = i end
  if not mi and line:find(' MARK KILL #1', 1, true) then mi = i end
end
check(ki and mi and ki < mi, 'the counter change is logged before the mark that follows it')

check(first(log, ' SESSION peer=number host=me '), 'the session is described once per world (peer type, host)')
check(count(log, ' SESSION ') == 2, '... for each of the two mission worlds')
check(first(log, ' SIGKIND sig=%d+ kind=' .. BUG_A .. ' tier=%?'), 'the layout of the bugs\' game objects is tied to their kind')
check(first(log, ' AIMOBJ first look id=1003 sig=%d+ unit#%d+ kind=' .. BUG_A:sub(1, 8)), 'the object of the unit under the crosshair is looked at')
check(first(log, ' GRP id=1%d%d%d sig=%d+ | 1: 100 %-> 60'), 'a field change in an object that shares its layout with others (hit points 100 -> 60) is logged')
check(count(log, ' GRP ') < 200 and count(log, ' AIMOBJ ') < 200, 'the object stages log a bounded amount')
check((S.foreign_reads or 0) == 0, 'no object owned by another player was read')

check(sum and sum:find('## unit kinds seen', 1, true) and sum:find(PROP .. '%s+%d+%s+%d+%s+false'), 'the summary lists props as not moving')
check(sum and not sum:find(PROP .. '%s+%d+%s+%d+%s+nil'), 'a prop kind that is being looked at again is not shown as unknown (false* or false)')
local a_deaths = sum and tonumber(sum:match(BUG_A .. '%s+%d+%s+%d+%s+true%s+true%s+(%d+)'))
check(a_deaths and a_deaths >= 2, 'the summary keeps the deaths per kind across worlds (' .. tostring(a_deaths) .. ')')
check(sum and sum:find('units (all worlds):', 1, true), 'the summary counts all worlds together')
check(sum and sum:find('moving unit kinds: 4, with a tier in the MDL3 build', 1, true) and sum:find('heavy=1', 1, true), 'the summary reports how many moving kinds the tier table covers')
check(sum and sum:find('moving kinds WITHOUT a tier: ' .. BUG_A, 1, true), 'and lists the moving kinds without a tier, the most numerous first')
check(sum and sum:find('stage errors: none', 1, true), 'the summary says no stage raised an error')
check(sum and sum:find('input: clicks=1 marks kill=1', 1, true), 'the summary counts the click and the mark')
check(first(log, ' SUM scans='), 'a SUM line is written')
local bytes = 0
for _, line in ipairs(log) do bytes = bytes + #line + 1 end
check(bytes < 900000, 'the log stays under its budget (' .. bytes .. ' bytes)')
local ms = (S.cpu / S.frame) * 1000
print(string.format('  info  average time in the addon: %.3f ms a frame on this machine (plain Lua, fake engine)', ms))
check(ms < 5, 'the addon is cheap per frame')
check(S.last_text and S.last_text:find('BFV PROBE', 1, true), 'the status line is drawn')

-- ===========================================================================================================
print('== scenario 2: every engine call refused')
S = H.new{ dir = OUT .. '/refused', addon = ADDON, customize = function(s) s.refuse_all = true end }
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); populate(s) end
  if s.in_mission then s.mouse.left = (s.t > 8 and s.t < 9) end
end
S:run(40)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
sum = S:read('bfv_probe_summary.txt')
check(count(log, ' ERR ') == 0, 'no ERR lines')
check(first(log, 'World.units gave no list'), 'the missing unit list is said once')
check(count(log, 'World.units gave no list') == 1, '... and only once')
check(sum and sum:find('World.units %-> refused by the test'), 'refusals are counted by reason in the summary')
check(S.crashed == nil, 'nothing crashed')

-- ===========================================================================================================
print('== scenario 3: an old loader (no chef.has, events, own log, menu, bindings, notices)')
S = H.new{ dir = OUT .. '/old', addon = ADDON, old_loader = true }
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); populate(s) end
  if s.in_mission then wander(s, 1 / 60) end
  if s.t >= 15 and not s.dd then s.dd = true; s.bugs[1].sm = false end
end
S:run(40)
S:shutdown()
S:save_logs()
log = S.logs.chef_loader or {}
check(#log > 5, 'it logs to the loader log when there is no own log (' .. #log .. ' lines)')
check(count(log, ' ERR ') == 0, 'no ERR lines')
check(first(log, 'UNIT why=sm%->none kind=' .. BUG_A), 'it still follows units')
check(S:read('bfv_probe_api.txt') ~= nil, 'the API file is written without after_startup')
check(S.crashed == nil, 'nothing crashed')

-- ===========================================================================================================
print('== scenario 4: odd data from the engine, no camera')
S = H.new{ dir = OUT .. '/garbage', addon = ADDON, customize = function(s)
  s.camera_on = false
  local real_units = s.engine.World.units
  s.engine.World.units = function(w)
    local l = real_units(w)
    table.insert(l, 1, 42)
    table.insert(l, 2, 'text')
    l[#l + 1] = { weird = true }
    return l
  end
  s.engine.Unit.animation_get_state = function() return end
  s.engine.GameSession.objects_owned_by = function() return { a = 100, b = 'x', c = 101, d = 5.5 } end
  s.engine.GameSession.game_object_field_batched = function(_, id)
    return { [1] = function() end, [2] = { { 1 }, { 2 } }, [3] = id, name = 'x', [4] = 0 / 0, [5] = true }
  end
end }
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); populate(s) end
  if s.in_mission then wander(s, 1 / 60); s.mouse.left = (s.t > 12 and s.t < 14) end
end
S:run(40)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
check(count(log, ' ERR ') == 0, 'no ERR lines (' .. tostring((first(log, ' ERR '))) .. ')')
check(S.crashed == nil, 'nothing crashed: ' .. tostring(S.crashed))
check(S:read('bfv_probe_summary.txt') ~= nil, 'the summary is still written')

-- ===========================================================================================================
print('== scenario 5: a flood of deaths must not pass the line caps')
S = H.new{ dir = OUT .. '/flood', addon = ADDON }
local wave = 0
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); s.objects[100] = { owner = 7, fields = { [1] = 1 } } end
  if not s.in_mission then return end
  -- every 5 s a new batch of 120 wandering bugs near the camera, each dying one second after the scan that follows it
  if s.t >= 3 + wave * 5 then
    wave = wave + 1
    for i = 1, 120 do
      s:unit(BUG_A, (i % 40) - 20, 10 + (i % 30), 0, { sm = true, state = { 1, 0, 0, 0 }, vx = 0.5, vy = 0.2, die_at = s.t + 6 + (i % 3) })
    end
  end
  for _, u in ipairs(s.units) do
    if u.die_at and s.t >= u.die_at and u.sm then u.sm = false end
    if u.vx and u.sm and not u.removed then u.x = u.x + u.vx / 60 end
  end
end
S:run(200)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
sum = S:read('bfv_probe_summary.txt')
check(count(log, ' UNIT ') <= 800, 'UNIT lines stay within their cap (' .. count(log, ' UNIT ') .. ')')
check(count(log, ' UNIT ') >= 750, 'the cap is reached in this flood, so the test exercises it')
check(sum and sum:find('lines dropped by tag caps: .*UNIT=%d+'), 'the summary says how many UNIT lines were dropped')
check(count(log, ' ERR ') == 0, 'no ERR lines')

-- ===========================================================================================================
print('== scenario 6: a stage that keeps raising rests, the others go on')
S = H.new{ dir = OUT .. '/boom', addon = ADDON, customize = function(_, chef)
  chef.unit_position = function() error('boom') end
end }
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); populate(s) end
  if s.in_mission then
    wander(s, 1 / 60)
    local p = s.objects[100]
    if p and s.t > 10 and not s.k then s.k = true; p.fields[3] = 5 end
  end
end
S:run(30)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
sum = S:read('bfv_probe_summary.txt')
check(count(log, ' ERR units: ') >= 1 and count(log, ' ERR units: ') <= 5, 'only the first 5 errors of a stage are written in full (' .. count(log, ' ERR units: ') .. ')')
check(first(log, ' ERR units raised 8 errors in 10 s: resting for 60 s'), 'the failing stage rests')
check(first(log, ' OBJ id=100 sig=%d+ | 3: 0 %-> 5'), 'the other stages go on (my own object field change is still logged)')
check(sum and sum:find('stage errors: units=', 1, true), 'the summary names the stage that failed')
check(S.crashed == nil, 'nothing crashed')

-- ===========================================================================================================
print('== scenario 7: a host that owns hundreds of objects (enemies, projectiles)')
local function distinct(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
function host_script(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s:new_world(true)
    populate(s)
    for id = 200, 899 do s.objects[id] = { owner = 7, fields = { [1] = id, [2] = 0, [3] = id % 7 } } end   -- 700 more
  end
  if s.in_mission then wander(s, 1 / 60) end
end
S = H.new{ dir = OUT .. '/host', addon = ADDON }
S.script = host_script
S:run(30)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
check(distinct(S.batched_ids) >= 700, 'every object of a host is looked at once, 700 more than a player has (' .. distinct(S.batched_ids) .. ')')
check((S.max_batched_frame or 99) <= 40, 'but never more than 40 object reads in one frame (' .. tostring(S.max_batched_frame) .. ')')
check(first(log, ' OBJ game objects listed: 7%d%d '), 'the object count is reported (' .. tostring((first(log, ' OBJ game objects listed'))) .. ')')
check(first(log, ' OBJ all 7%d%d game objects looked at once'), 'the end of the first look at everything is reported')
check(S.batched_ids[100] and S.batched_ids[101] and S.batched_ids[102], 'the player objects are among them')
check(count(log, ' OBJSIG sig=') <= 12, 'the layouts stay few (' .. count(log, ' OBJSIG sig=') .. ')')
-- the same with the all-objects row off: only the 40 oldest
S = H.new{ dir = OUT .. '/narrow', addon = ADDON, options = { wide = false } }
S.script = host_script
S:run(30)
check(distinct(S.batched_ids) <= 40, 'with the all-objects row off at most 40 objects are ever read (' .. distinct(S.batched_ids) .. ')')
check(S.batched_ids[100] and S.batched_ids[101] and S.batched_ids[102], 'the lowest ids, which are the oldest objects, are among them')
-- short-lived objects come and go (50 of them over 25 s), then the avatar is replaced by one with a high id
S = H.new{ dir = OUT .. '/churn', addon = ADDON }
local k = 0
S.script = function(s)
  if not s.started and s.t >= 2 then s.started = true; s:new_world(true); populate(s) end
  if not s.in_mission then return end
  wander(s, 1 / 60)
  if k < 50 and s.t >= 3 + k * 0.5 then
    k = k + 1
    s.objects[300 + k] = { owner = 7, fields = { [1] = k } }
    if k > 6 then s.objects[300 + k - 6] = nil end
  end
  if s.t >= 30 and not s.respawn then
    s.respawn = true
    s.objects[101] = nil
    s.objects[5000] = { owner = 7, fields = { [1] = s:vec(1, 2, 3), [2] = 0.5, [3] = 77, [64] = { [25] = 1 } } }
  end
end
S:run(40)
S:save_logs()
log = S.logs.bfv_probe or {}
check(distinct(S.batched_ids) > 60, 'objects that come and go are all looked at (' .. distinct(S.batched_ids) .. ')')
check(S.batched_ids and S.batched_ids[5000], 'the replacement avatar is read')
check(count(log, ' NEW id=') >= 40 and count(log, ' GONE id=') >= 40, 'new and vanished objects are logged (' .. count(log, ' NEW id=') .. ' / ' .. count(log, ' GONE id=') .. ')')
check(S.crashed == nil, 'nothing crashed')

-- ===========================================================================================================
print('== scenario 8: the first units of a kind that get asked about are bodies')
S = H.new{ dir = OUT .. '/bodies', addon = ADDON }
S.script = function(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s:new_world(true)
    -- the unit list is in this order: one walker (it is what shows the kind moves), then two bodies, then more
    -- walkers. Once the kind is known to move, the first units asked about their state machine are the bodies.
    s.live = {}
    local function walker(i) s.live[i] = s:unit(BUG_B, i * 3, 15 + i, 0, { sm = true, state = { 1, 0, 0, 0 }, vx = 0.8, vy = 0.3 }) end
    walker(1)
    for i = 1, 2 do s:unit(BUG_B, 5 + i, 20, 0, { sm = false }) end
    for i = 2, 6 do walker(i) end
  end
  if s.in_mission then
    wander(s, 1 / 60)
    if s.t >= 20 and not s.dd then s.dd = true; s.live[3].sm = false end
  end
end
S:run(35)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
sum = S:read('bfv_probe_summary.txt')
check(first(log, 'KIND kind=' .. BUG_B .. ' mover=true sm=true'), 'a kind has a state machine although the first units asked about were bodies')
check(count(log, ' UNIT why=sm%->none kind=' .. BUG_B) == 1, 'the death of a living unit of that kind is logged')
check(count(log, ' UNIT ') == 1, 'bodies are not logged as deaths (' .. count(log, ' UNIT ') .. ' UNIT lines)')
check(sum and sum:find('bodies%-skipped=[1-9]'), 'the summary counts the bodies it did not follow')
check(count(log, ' ERR ') == 0 and S.crashed == nil, 'no errors, no crash')

-- ===========================================================================================================
print('== scenario 9: death states (seeded, learned, taken back), noise kinds and the follow quotas')
local WARRIOR, HUNTER, BROOD, PART, BLOB = '09872e66d1276e1f', 'a478d36a62a861f4', '583ecde0d7718126', '40ae90fff236865b', 'bbbb000000000001'
S = H.new{ dir = OUT .. '/death', addon = ADDON }
S.script = function(s)
  local t = s.t
  if not s.started and t >= 2 then
    s.started = true
    s:new_world(true)
    s.w, s.h, s.b = {}, {}, {}
    -- warriors (death state 26,0,0,35 is seeded); w[2] stands right ahead of the camera (at 0,-30 looking along +y)
    for i = 1, 6 do s.w[i] = s:unit(WARRIOR, i * 5 - 15, 20 + i, 0, { sm = true, state = { 12, 0, 0, 19 }, vx = 0.5, vy = 0.2 }) end
    s.w[2].x, s.w[2].y, s.w[2].vx, s.w[2].vy = 0, 15, 0.0001, 0.0001
    for i = 1, 4 do s.h[i] = s:unit(HUNTER, i * 6 - 12, 25, 0, { sm = true, state = { 2, 0, 32, 1 }, vx = 0.4, vy = 0.2 }) end
    for i = 1, 6 do s.b[i] = s:unit(BROOD, i * 4 - 12, 30, 0, { sm = true, state = { 6, 0, 0, 0 }, vx = 0.3, vy = 0.2 }) end
    for i = 1, 60 do s:unit(PART, (i % 20) - 10, 10 + (i % 15), 0, { vx = 0.5, vy = 0.5 }) end           -- no state machine, ignored kind
    for i = 1, 60 do s:unit(BLOB, (i % 30) - 15, 5 + (i % 20), 0, { vx = 0.5, vy = 0.5 }) end            -- no state machine, not ignored
  end
  if not s.in_mission then return end
  for _, u in ipairs(s.units) do                       -- everything wanders, with or without a state machine
    if u.vx and not u.removed and not u.frozen then u.x, u.y = u.x + u.vx / 60, u.y + u.vy / 60 end
  end
  s.mouse.left = (t >= 20 and t < 21.2)
  local function at(sec, key, fn) if t >= sec and not s[key] then s[key] = true; fn() end end
  at(20.5, 'a1', function() s.w[2].state = { 26, 0, 0, 35 } end)          -- on the crosshair, while firing
  at(25.6, 'a2', function() s.w[2].sm = false end)                         -- 5.1 s later the machine goes
  at(22.0, 'b1', function() s.w[5].state = { 26, 0, 0, 35 } end)          -- off the crosshair, no shot
  at(23.0, 'c1', function() s.h[1].state = { 0, 0, 0, 1 } end)            -- a hunter passes through a death state ...
  at(24.2, 'c2', function() s.h[1].state = { 2, 0, 32, 1 } end)           -- ... and comes back
  at(26.0, 'd1', function() s.b[1].state = { 20, 3, 0, 7 } end)           -- brood: the death state is not in the seeds
  at(31.0, 'd2', function() s.b[1].sm = false end)
  at(27.0, 'd3', function() s.b[2].state = { 20, 3, 0, 7 } end)
  at(32.0, 'd4', function() s.b[2].sm = false end)                         -- the second time: learned
  at(34.0, 'd5', function() s.b[3].state = { 20, 3, 0, 7 } end)           -- the third unit is noticed when it enters the state
end
S:run(45)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
sum = S:read('bfv_probe_summary.txt')
local d1 = first(log, ' DEATH id=%d+ kind=' .. WARRIOR .. ' st=26,0,0,35 src=seed ')
check(d1 ~= nil, 'an enemy entering its seeded death state is logged as a DEATH at that moment')
check(d1 and (num(d1, 'cone') or 9) < 1 and (num(d1, 'ray') or 9) < 1 and (d1:find('fire=held') or d1:find('fire=[%d%.]+s ago')), 'the DEATH says the crosshair was on it a moment ago (cone, ray) and when the last shot was: ' .. tostring(d1 and d1:match('cone=.*$')))
local d2
for _, line in ipairs(log) do if line:find(' DEATH id=%d+ kind=' .. WARRIOR) and line:find('cone=%- ray=%-') then d2 = line end end
check(d2 ~= nil, 'a death off the crosshair says so (cone=- ray=-)')
local u1 = first(log, ' UNIT why=sm%->none kind=' .. WARRIOR .. ' .*dying=5%.%d ')
check(u1 ~= nil, 'the state machine going away is logged about 5 s after the DEATH (dying=5.x)')
check(first(log, ' DEATH cancel id=%d+ kind=' .. HUNTER .. ' was=0,0,0,1 now=2,0,32,1 after=1%.%d'), 'a unit that leaves the death state again is logged as a cancel')
check(first(log, ' DEATH learned kind=' .. BROOD .. ' st=20,3,0,7'), 'a death state not in the seeds is learned from the second state machine that went away in it')
check(first(log, ' DEATH id=%d+ kind=' .. BROOD .. ' st=20,3,0,7 src=learned'), 'and used for the next unit that enters it')
check(count(log, ' UNIT .*kind=' .. PART) == 0 and count(log, 'KIND kind=' .. PART) == 0, 'a kind on the ignore list is never followed')
check(sum and sum:find(PART .. '[^\n]*part'), 'the summary shows it as ignored')
local nosm = sum and tonumber(sum:match('%((%d+) without a state machine%)'))
check(nosm and nosm <= 24 and nosm > 0, 'units without a state machine stay within their quota (' .. tostring(nosm) .. ')')
check(count(log, ' STATE id=') >= 1, 'state changes of the unit under the crosshair are logged while firing')
check(sum and sum:find('## death states', 1, true) and sum:find(WARRIOR .. '%s+%d+%s+%d+%s+%d+%s+%d+%s+[%d%.]+%s+26,0,0,35%(seed%)'), 'the summary lists the death states with how long after them the machines went away')
check(count(log, ' ERR ') == 0 and S.crashed == nil, 'no errors, no crash')

-- ===========================================================================================================
print("== scenario 10: another player's objects are read only when asked for")
local function others_script(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s.other_peers = true
    s:new_world(true)
    populate(s)
    s.objects[7001] = { owner = 3, fields = { [1] = 'host-name', [2] = 5 } }          -- the other player's avatar
    s.objects[7002] = { owner = 3, fields = { [1] = 'host-name', [2] = 6 } }
  end
  if s.in_mission then wander(s, 1 / 60) end
end
S = H.new{ dir = OUT .. '/others_off', addon = ADDON }
S.script = others_script
S:run(20)
check((S.foreign_reads or 0) == 0 and not (S.batched_ids or {})[7001], "the other player's objects are not read by default")
S = H.new{ dir = OUT .. '/others_on', addon = ADDON, options = { remote = true } }
S.script = others_script
S:run(20)
S:save_logs()
log = S.logs.bfv_probe or {}
check((S.batched_ids or {})[7001] and (S.batched_ids or {})[7002], "with the row on they are read")
check(first(log, ' SESSION peer=number host=me %(number%) peers=2 other_peers=1'), 'the session line counts the peers')
check(S.crashed == nil, 'nothing crashed')
-- a client: the enemies belong to the host, the lookups still give their ids, the objects are not read
S = H.new{ dir = OUT .. '/client', addon = ADDON, customize = function(s) s.host_is_me = false end }
S.script = function(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s.other_peers = true
    s:new_world(true)
    populate(s)
    for i = 1, 12 do s.objects[1000 + i].owner = 3 end                                 -- the enemies are the host's
  end
  if s.in_mission then wander(s, 1 / 60); s.mouse.left = (s.t >= 20 and s.t < 21.2) end
end
S:run(30)
S:save_logs()
log = S.logs.bfv_probe or {}
check(first(log, ' SESSION peer=number host=someone else '), 'a client is told apart from a host')
check(first(log, ' LINK unit#%d+ kind=%x+ has object 10%d%d, which is not in my list %(not read%)'), "an enemy's object that is not mine is found but not read")
check((S.foreign_reads or 0) == 0, 'no foreign object was read')

-- ===========================================================================================================
print('== scenario 11: equal texts get equal stand-ins; a noisy field of a shared layout is muted for all of it')
S = H.new{ dir = OUT .. '/groups', addon = ADDON }
S.script = function(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s:new_world(true)
    for i = 1, 30 do s.objects[500 + i] = { owner = 7, fields = { [1] = 'same-text', [2] = i, [3] = 100, [4] = 'unique-' .. i } } end
    s.objects[600] = { owner = 7, fields = { [1] = 'same-text' } }
  end
  if not s.in_mission then return end
  for i = 1, 30 do
    local o = s.objects[500 + i]
    o.fields[2] = s.t * (i % 7 + 1)                                   -- field 2 changes all the time: noise
    if s.t >= 10 and s.t < 10.5 and i == 5 then o.fields[3] = 40 end  -- field 3 changes once, in one object
  end
end
S:run(20)
S:save_logs()
log = S.logs.bfv_probe or {}
local sig1 = first(log, ' OBJSIG sig=%d+ first_object=501 ')
check(sig1 and sig1:find('1=str#1:9') and sig1:find('4=str#%d+:%d+'), 'the first text seen is str#1, with its length')
local sig2 = first(log, ' OBJSIG sig=%d+ first_object=600 ')
check(sig2 and sig2:find('1=str#1:9'), 'the same text in another object has the same stand-in')
check(first(log, ' OBJSIG sig=%d+ field 2 muted: '), 'a field that changes in most reads of a layout is muted for the layout')
check(count(log, ' GRP id=5%d%d sig=%d+ | 2:') <= 6, 'before it is muted it costs only a few lines (' .. count(log, ' GRP id=5%d%d sig=%d+ | 2:') .. ')')
check(first(log, ' GRP id=505 sig=%d+ | 3: 100 %-> 40'), 'a rare change in one object of the layout still shows (hit points 100 -> 40)')
check(count(log, ' GRP id=5%d%d sig=%d+ | 3:') == 1, '... exactly once')
check(count(log, ' ERR ') == 0 and S.crashed == nil, 'no errors, no crash')

-- ===========================================================================================================
print('== scenario 12: a game object check that gets no answer is not "gone"; the log budget keeps room for what matters')
S = H.new{ dir = OUT .. '/noanswer', addon = ADDON, customize = function(s)
  s.engine.GameSession.game_object_exists = function() error('skipped') end        -- the loader refusing the call after a crash
end }
S.script = host_script
S:run(20)
S:save_logs()
log = S.logs.bfv_probe or {}
check(count(log, ' GONE ') == 0 and count(log, ' NEW ') == 0, 'no object is reported gone or new when the existence check gives no answer')
check(count(log, ' ERR ') == 0 and S.crashed == nil, 'no errors, no crash')

-- a small budget: the same mission with LOG_CAP = 6000
do
  local f = assert(io.open(ADDON, 'r')); local src = f:read('*a'); f:close()
  local small, n = src:gsub('local LOG_CAP      = 900000', 'local LOG_CAP      = 6000')
  assert(n == 1, 'LOG_CAP line not found')
  os.execute('mkdir -p "' .. OUT .. '"')
  local path = OUT .. '/probe_small_budget.lua'
  local out = assert(io.open(path, 'w')); out:write(small); out:close()
  S = H.new{ dir = OUT .. '/budget', addon = path }
  S.script = function(s)
    host_script(s)
    if s.in_mission then
      -- the enemies' hit points go down all the time, and the player shoots and marks
      local k = math.floor(s.t * 4)
      if k ~= s.lastk then
        s.lastk = k
        for id = 200, 899 do if (id + k) % 11 == 0 then s.objects[id].fields[1] = s.objects[id].fields[1] + 1 end end
      end
      s.mouse.left = (math.floor(s.t) % 4 == 0)
      if s.t > 25 and not s.mk then s.mk = true; s.binds.mark_hit.fire = true end
    end
  end
  S:run(30)
  S:shutdown()
  S:save_logs()
  log = S.logs.bfv_probe or {}
  local bytes = 0
  for _, line in ipairs(log) do bytes = bytes + #line + 1 end
  local late_marks = count(log, ' MARK HIT #1 ')
  local sumf = S:read('bfv_probe_summary.txt')
  local last_aim, last_aimobj
  for i, line in ipairs(log) do
    if line:find(' AIM n=', 1, true) then last_aim = i end
    if line:find(' AIMOBJ ', 1, true) then last_aimobj = i end
  end
  check(sumf and sumf:find('lines dropped by tag caps: .*AIM=%d+'), 'a low-value tag (AIM) stops at 65% of the budget, and the summary says how many lines it lost')
  check(last_aim and last_aimobj and last_aim < last_aimobj, 'a high-value tag (AIMOBJ) is still written after the low-value ones stopped')
  check(late_marks == 1 and first(log, ' SUM scans='), 'MARK and SUM lines are written after the low-value tags stopped')
  check(bytes < 6000 + 4000, 'the log stays near its budget (' .. bytes .. ' bytes for 6000)')
  check(S.crashed == nil and count(log, ' ERR ') == 0, 'no errors, no crash')
end

print(string.format('\n%d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
