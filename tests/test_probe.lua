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
    S.objects[1000 + i] = { owner = 3, fields = { [1] = 100, [2] = 0 } }
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
print('== scenario 1: a mission with fire, kills, marks, a new mission world and the risky stage')
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
  if t >= 40 and not s.eon then s.eon = true; s.chef.set('enemyobj', true) end
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
check(S.rows.units and S.rows.player and S.rows.aim and S.rows.enemyobj and S.rows.hud, 'the menu rows exist')
check(S.rows.enemyobj.spec.default == false, 'the risky stage is off by default')
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
check(hulk and hulk:find('hist=%[%-[%d%.]+:5,0,0,0|%-[%d%.]+:12,0,0,0%]') and hulk:find('tier=heavy$'), 'the hulk death keeps its state history 5 -> 12, in seconds before the event, and its tier')

check(count(log, ' OBJSIG sig=') >= 3, 'game object field layouts are described (' .. count(log, ' OBJSIG sig=') .. ' signatures)')
check(not table.concat(log, '\n'):find('rifle', 1, true) and first(log, '2=str%(5%)'), 'text values of game objects are not written to the log, only their length')
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

check(count(log, ' EOBJ enemy object stage is on') == 1, 'the risky stage announces itself once when switched on')
check(count(log, ' EOBJ follow id=1%d%d%d') >= 1, 'it follows enemy objects found through the unit synchronizer')
check(first(log, ' EOBJ id=1%d%d%d sig=%?.*| 1: 100 %-> 60'), 'an enemy object health change 100 -> 60 is logged')
check(count(log, ' EOBJ ') < 200, 'the risky stage logs a bounded amount')

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
check(count(log, ' UNIT ') <= 1500, 'UNIT lines stay within their cap (' .. count(log, ' UNIT ') .. ')')
check(count(log, ' UNIT ') >= 1400, 'the cap is reached in this flood, so the test exercises it')
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
S = H.new{ dir = OUT .. '/host', addon = ADDON }
S.script = function(s)
  if not s.started and s.t >= 2 then
    s.started = true
    s:new_world(true)
    populate(s)
    for id = 200, 899 do s.objects[id] = { owner = 7, fields = { [1] = id, [2] = 0, [3] = id % 7 } } end   -- 700 more
  end
  if s.in_mission then wander(s, 1 / 60) end
end
S:run(30)
S:shutdown()
S:save_logs()
log = S.logs.bfv_probe or {}
check(distinct(S.batched_ids) <= 40, 'with the risky stage off, at most 40 of my objects are ever read (' .. distinct(S.batched_ids) .. ')')
check(first(log, ' OBJ owned objects: 7%d%d '), 'the owned count is still reported (' .. tostring((first(log, ' OBJ owned objects'))) .. ')')
check(S.batched_ids[100] and S.batched_ids[101] and S.batched_ids[102], 'the lowest ids, which are the player objects, are among them')
-- short-lived objects come and go (50 of them over 25 s), then the avatar is replaced: the limit of 40 counts objects
-- that still exist, not every object ever looked at, so the new avatar is still read
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
check(distinct(S.batched_ids) > 60, 'more than 40 objects are read over a mission when they do not exist at the same time (' .. distinct(S.batched_ids) .. ')')
check(S.batched_ids and S.batched_ids[5000], 'the replacement avatar is read')

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

print(string.format('\n%d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
