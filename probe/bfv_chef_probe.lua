-- HD2-Addon: mods/jfredist/bfv_chef_probe
-- HD2-Requires: chef-shared-loader >= 1.0.0
-- BFV Chef Probe: a read-only research addon for Chef Shared Loader.
--
-- Why it exists: the Battlefield 5 hit/kill feedback mod needs three things that its MDL3 build gets from MDL3's native
-- side: (1) who killed what, (2) when the local player hits an enemy, (3) custom sound. Chef Shared Loader runs plain
-- Lua 5.1 with no ffi and no memory access, so the question is what the game's own Lua API shows. This addon only
-- LOOKS and writes what it sees to files in the loader's folder (%APPDATA%\Arrowhead\Helldivers2):
--
--   bfv_probe.log        the event stream: unit deaths, field changes of game objects, fire/mark/aim events
--   bfv_probe_api.txt    the engine tables and functions this game build gives a Chef mod (audio, health ... included)
--   bfv_probe_summary.txt  counters, the unit kinds seen, and calls the loader refused
--
-- It changes nothing in the game. Every engine call goes through chef.call / chef.call_kind / the chef.unit_*
-- helpers (the loader's crash guard). The one stage that might still end the game, reading enemies' network game
-- objects, is OFF until you switch it on in the F9 menu.
local chef = ...
if type(chef) ~= 'table' then return end

local VERSION = '0.1.0'
local M = { version = VERSION }

if chef.own_log then chef.own_log('bfv_probe') end   -- first thing: from here chef.log writes bfv_probe.log

-- ---------------------------------------------------------------------------------------------------------------------
-- settings of the probe itself
-- ---------------------------------------------------------------------------------------------------------------------
local RUNTIME_KIND = '46cab355bd8d4d37'   -- runtime-built units: the loader says never to ask them where they are
local RADIUS       = 100                  -- metres around the camera in which units are followed
local TRACK_MAX    = 120                  -- most units followed at once
local SCAN_EVERY   = 3                    -- seconds between scans of the world's unit list
local SCAN_FAST    = 1.2                  -- ... for the first scans of a world, while unit kinds are being sorted out
local SCAN_BUDGET  = 250                  -- units looked at per frame while a scan runs
local SAMPLE_CYCLE = 0.15                 -- seconds for one pass over the followed units
local OBJ_PERIOD   = 0.20                 -- seconds between samples of game objects
local OBJ_TRACK    = 8                    -- most of my own game objects followed
local EOBJ_TRACK   = 12                   -- most enemy game objects followed (risky stage)
local LOG_CAP      = 900000               -- bytes of bfv_probe.log written per launch (the loader restarts a file at 1 MB)
local TAG_CAP      = { UNIT = 1500, OBJ = 3000, EOBJ = 2500, AIM = 800, FIRE = 2500, KIND = 700, OBJSIG = 80 }

-- @@BEGIN tiers@@
-- The four feedback tiers of the MDL3 build, 142 unit resource ids (from its HD2_EVENT_TYPE_MAP, by
-- tools/extract_tiers.py: 11 flying, 32 heavy, 60 light, 39 medium). Used only to say which unit kinds seen are already classified.
local TIERS = {
  ['0002ba767df856f3']='light', ['089833d2880d9e06']='light', ['08e6ffc2474287bd']='medium',
  ['09dfb04b2e578bc3']='light', ['09fe0be51a23396c']='medium', ['09fe0be51a2339f8']='medium',
  ['0ab7b92b131c228c']='heavy', ['0adc9f9173ad8e1d']='light', ['10081acef6163ef6']='light',
  ['137988cea16458e2']='heavy', ['137988cea16458f7']='heavy', ['1897bdd32105d2dc']='heavy',
  ['19e18b46ec55d94a']='flying', ['19e18b46ec55d988']='flying', ['1a7fcdff98c664b0']='heavy',
  ['1b5b9ac4f96b36e5']='light', ['1e66ee1f6f7fd00e']='heavy', ['1f0a91729c0004e0']='light',
  ['20b9c7734daead65']='heavy', ['215ce160a17be4cd']='light', ['257d805caa7e0fc4']='light',
  ['282eb766c1ffa600']='flying', ['282eb766c1ffa6a1']='flying', ['2a12104f2853ae16']='light',
  ['30cf04b2ec8c9bd4']='light', ['30f2dee2333f227a']='heavy', ['31bae74d2f064d8d']='heavy',
  ['32541fc4ec7c9cdc']='light', ['32cdeada234fb8df']='heavy', ['34dfd23365472dd8']='light',
  ['34dfd23365472e9e']='light', ['36aa99cce5e60146']='medium', ['3aff5fd7d5450b99']='heavy',
  ['3d0e03e2d574e1ca']='light', ['3e0537d606438fea']='heavy', ['4019623142351cb6']='light',
  ['44458a2c52b002fb']='light', ['453fe22c634eb30f']='heavy', ['4e97fb073bdc7a4b']='light',
  ['51eea86bf6997e4e']='light', ['53d8919d7b8abd67']='heavy', ['54e107dacf6929cb']='light',
  ['57eed0eac346cd9d']='medium', ['58b2b86c11369241']='medium', ['5ca832447445c0ba']='light',
  ['6021e22338333d88']='medium', ['604a794ec45bb820']='medium', ['63df3d07b7424588']='heavy',
  ['64090088502435dd']='light', ['64ba5f030b114ec1']='light', ['662a7907531b45e5']='medium',
  ['67dc32dca4f02d33']='medium', ['6b202392f4ab605e']='heavy', ['6dab2eadf5d8b692']='heavy',
  ['728421351d440ebc']='light', ['72a83e49ced6db3d']='light', ['746a7f3beda32699']='medium',
  ['746a7f3beda32b98']='medium', ['74e2285c01da4f71']='flying', ['74e2285c01da58ac']='flying',
  ['78e1497571012c47']='light', ['7b48cacdbacb3881']='light', ['7ece5304f868f6b3']='light',
  ['82a87ad8d595b2ba']='light', ['856e9710e45e760f']='light', ['883401af2a98a5f6']='light',
  ['8ab62629db3d6ac8']='light', ['8ff0a839830a7692']='light', ['905809a4c28d8a45']='medium',
  ['9076eeed17fcee35']='medium', ['91ebd77931110afc']='medium', ['960b48a421a3faaa']='flying',
  ['9647b00cc3a9d36f']='medium', ['965eae5a51acdd4a']='heavy', ['96ba14c9ebb49ce1']='heavy',
  ['98152772a72f7838']='flying', ['9a8a3aae287b230c']='light', ['9d8827fed763650e']='medium',
  ['9d8827fed7636904']='medium', ['9e2e17f2ccccafdd']='heavy', ['9f57782f00e6ed20']='light',
  ['a05bd1ec67b3ac4c']='heavy', ['a1f37bf2a40fbde4']='light', ['a35207c6f2150806']='light',
  ['a381a11c07d3eb94']='medium', ['a4552f97033392f4']='light', ['a6a68d8af177f3a1']='light',
  ['a71aafd82c6ebc92']='light', ['aab438596f5e8fd9']='light', ['ac60e78435098c9d']='light',
  ['ac60e784350990be']='light', ['ae57fcdb49f74e98']='light', ['ae63e525853d7044']='medium',
  ['af0f9b3a163787a5']='light', ['b056f8fc74ab9d94']='light', ['b2a6fa1e4284c7e6']='light',
  ['b4ed319b39f5457b']='light', ['b5dbc0c240c921ad']='light', ['b92435fbf60f0748']='medium',
  ['bc242702fb46b7e7']='heavy', ['bc242702fb46bd78']='heavy', ['be39e313a1e46bb9']='light',
  ['be743b2faa3a6e26']='medium', ['c626d2bb495a202d']='medium', ['c6449ffd9ea3779c']='heavy',
  ['c9bcccb0a54a82a4']='medium', ['cbb1ba3366009c3a']='medium', ['cbb1ba336600a118']='medium',
  ['cc188f0c80505c6c']='light', ['cc7022fdd172089b']='medium', ['ccae5264acd591b7']='medium',
  ['d1e990baf22d5a52']='medium', ['d37e8d120d2836e3']='heavy', ['d465d9c7f77a07cb']='heavy',
  ['d522fd4748d443a5']='medium', ['d5792f6856b06ba4']='light', ['d63fcbff0851b7af']='heavy',
  ['d8cbc4a807a6d035']='light', ['d9511e9f6bd62e3f']='light', ['da40bb347c7447f2']='medium',
  ['db90077e76fa48ac']='flying', ['db964631be1cf501']='light', ['dcf8e74212fbee3b']='heavy',
  ['dfbacbd977a948dc']='light', ['e0353177f1329573']='medium', ['e44ec9f9b3fe1d2a']='heavy',
  ['e683d2ca5618d74a']='light', ['e8f19a0aa958e46d']='medium', ['eacee39fa017b495']='light',
  ['ef04cb84d097a497']='heavy', ['ef570293245a17c2']='heavy', ['f0b26fa925812d00']='light',
  ['f22d027b37beebaa']='flying', ['f22d027b37bef107']='flying', ['f540ca9d9d4a422e']='medium',
  ['f66d0bad8693779a']='medium', ['f79cd8bb654397df']='medium', ['f8131632aa867107']='medium',
  ['f8b5a81a86d5d4eb']='medium', ['fb9937035d652c43']='light', ['fc8dec78be8ab47d']='medium',
  ['fd5247653c897724']='heavy',
}
-- @@END tiers@@
local function tier_of(kind) return TIERS[kind] or '?' end

-- ---------------------------------------------------------------------------------------------------------------------
-- logging
-- ---------------------------------------------------------------------------------------------------------------------
local logged, capped = 0, false
local tag_lines, tag_dropped = {}, {}

local function emit(tag, text, always)
  local cap = TAG_CAP[tag]
  local n = (tag_lines[tag] or 0) + 1
  if cap and n > cap and not always then
    tag_dropped[tag] = (tag_dropped[tag] or 0) + 1
    return
  end
  if capped and not always then return end
  tag_lines[tag] = n
  local line = string.format('t=%.2f %s %s', chef.time(), tag, text)
  if #line > 1600 then line = line:sub(1, 1600) .. '...' end
  logged = logged + #line + 1
  if logged > LOG_CAP and not always then
    capped = true
    chef.log('%s', string.format('t=%.2f CAP the log budget is used up; only MARK, ERR and SUM lines go on', chef.time()))
    return
  end
  chef.log('%s', line)
end

local function L(tag, fmt, ...)
  local ok, text = pcall(string.format, fmt, ...)
  emit(tag, ok and text or ('(bad format) ' .. tostring(fmt)))
end

-- things worth saying once per launch, not once per world
local said = {}
local function once(key)
  if said[key] then return false end
  said[key] = true
  return true
end

-- Errors per stage. A stage that raises 8 errors within 10 seconds rests for a minute and then tries again; the
-- other stages go on meanwhile. Only the first 5 errors of a stage are written out in full.
local stage_errors, stage_off, stage_recent = {}, {}, {}
local function safe(stage, fn, ...)
  local clock = chef.time()
  if stage_off[stage] and clock < stage_off[stage] then return false end
  local ok, e = pcall(fn, ...)
  if not ok then
    stage_errors[stage] = (stage_errors[stage] or 0) + 1
    if stage_errors[stage] <= 5 then emit('ERR', stage .. ': ' .. tostring(e):sub(1, 300), true) end
    local recent = stage_recent[stage] or {}
    stage_recent[stage] = recent
    recent[#recent + 1] = clock
    while recent[1] and clock - recent[1] > 10 do table.remove(recent, 1) end
    if #recent >= 8 then
      stage_off[stage] = clock + 60
      stage_recent[stage] = {}
      emit('ERR', stage .. ' raised 8 errors in 10 s: resting for 60 s', true)
    end
  end
  return ok
end

-- engine calls through the loader's guard; refusals are counted by reason for the summary. The wrappers hand back
-- exactly the values the call gave (pack2 keeps the count, so trailing nils survive).
local refused = {}
local function pack2(...) return select('#', ...), { ... } end
local function note_refusal(name, r)
  if r[1] == nil and type(r[2]) == 'string' then
    local key = name .. ' -> ' .. r[2]:sub(1, 70)
    refused[key] = (refused[key] or 0) + 1
  end
end
local function C(name, ...)
  local n, r = pack2(chef.call(name, ...))
  note_refusal(name, r)
  return unpack(r, 1, n)
end
local function CK(name, kind, ...)
  local n, r = pack2(chef.call_kind(name, kind, ...))
  note_refusal(name, r)
  return unpack(r, 1, n)
end

local function has(cap) return chef.has ~= nil and chef.has(cap) == true end

-- ---------------------------------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------------------------------
local function dir_join(name)
  local d = chef.log_directory or ''
  local sep = d:find('\\', 1, true) and '\\' or '/'
  return d .. sep .. name
end

local function write_file(name, lines)
  local f, err = io.open(dir_join(name), 'w')
  if not f then
    emit('ERR', 'cannot write ' .. name .. ': ' .. tostring(err), true)
    return false
  end
  f:write(table.concat(lines, '\n'), '\n')
  f:close()
  return true
end

local function sorted_keys(t, limit)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
    if limit and #keys >= limit then break end
  end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb and (ta == 'number' or ta == 'string') then return a < b end
    if ta ~= tb then return ta < tb end
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- one value as short text (numbers keep their precision where it matters, vectors become x,y,z)
local function scalar(v)
  local t = type(v)
  if t == 'number' then
    if v ~= v then return 'nan' end
    if v == math.floor(v) and v > -1e15 and v < 1e15 then return string.format('%.0f', v) end
    return string.format('%.5g', v)
  elseif t == 'boolean' or t == 'nil' then
    return tostring(v)
  elseif t == 'string' then
    return 'str(' .. #v .. ')'                -- the text itself is not logged (a player object may hold a name)
  elseif t == 'table' then
    return '{table}'
  elseif t == 'userdata' then
    local x, y, z = chef.call('Vector3.to_elements', v)
    if type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
      return string.format('vec(%.4g,%.4g,%.4g)', x, y, z)
    end
    return 'userdata'
  end
  return t
end

-- a game object's fields as path -> text: a field that is a table is opened one level (its entries as field.entry)
local function flatten(fields, out)
  local n = 0
  for _, k in ipairs(sorted_keys(fields, 160)) do
    n = n + 1
    local v = fields[k]
    if type(v) == 'table' then
      for _, k2 in ipairs(sorted_keys(v, 64)) do
        out[tostring(k) .. '.' .. tostring(k2)] = scalar(v[k2])
      end
    else
      out[tostring(k)] = scalar(v)
    end
  end
  return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- state shared by the stages
-- ---------------------------------------------------------------------------------------------------------------------
local now = 0
local world_id = nil
local mission_t0 = nil
local fire_down, fire_since, last_fire_down, last_fire_up = false, nil, nil, nil
local clicks = 0
local marks = { kill = 0, hit = 0, other = 0 }
local cam = nil                                        -- {x,y,z,fx,fy,fz} copied each frame

local cfg = { units = true, player = true, aim = true, enemyobj = false, hud = true }

local function since_fire()
  if fire_down then return string.format('held %.2fs', now - (fire_since or now)) end
  if last_fire_up then return string.format('%.2fs ago', now - last_fire_up) end
  return 'never'
end

-- ---------------------------------------------------------------------------------------------------------------------
-- stage 0: banner and the engine API surface (written to bfv_probe_api.txt)
-- ---------------------------------------------------------------------------------------------------------------------
local INTEREST = { 'wwise', 'audio', 'sound', 'music', 'voice', 'speech', 'bank', 'health', 'damage', 'kill', 'death',
                   'dead', 'stat', 'score', 'attack', 'credit', 'weapon', 'shot', 'fire', 'projectile', 'explo',
                   'hit', 'event', 'entity', 'player', 'mission' }
local CANDIDATE_GLOBALS = { 'Wwise', 'WwiseWorld', 'WwiseNode', 'Audio', 'Sound', 'SoundEnvironment', 'Player',
                            'Players', 'PlayerManager', 'Entity', 'EntityManager', 'Health', 'HealthComponent',
                            'Stats', 'Statistics', 'Score', 'Mission', 'MissionManager', 'GameSession', 'Network',
                            'UnitSynchronizer', 'Steam', 'Application', 'World', 'Unit', 'Gui', 'Math', 'Window' }
local api_snapshot = nil

local function snapshot_api()
  local snap = { tables = {}, scalars = {}, blocked = {} }
  local root = rawget(_G, 'stingray')
  if type(root) ~= 'table' then return snap end
  for _, name in ipairs(sorted_keys(root, 2000)) do
    local v = root[name]
    local t = type(v)
    if t == 'table' then
      local fns, other = {}, {}
      for _, k in ipairs(sorted_keys(v, 4000)) do
        local kv = v[k]
        if type(kv) == 'function' then fns[#fns + 1] = tostring(k) else other[#other + 1] = tostring(k) .. ':' .. type(kv) end
      end
      snap.tables[name] = { fns = fns, other = other }
    elseif t == 'boolean' then
      snap.blocked[#snap.blocked + 1] = tostring(name) .. '=' .. tostring(v)
    else
      snap.scalars[#snap.scalars + 1] = tostring(name) .. ':' .. t
    end
  end
  return snap
end

local function wrap_names(prefix, names, lines, width)
  local line = prefix
  for _, n in ipairs(names) do
    if #line + #n + 1 > width then lines[#lines + 1] = line; line = prefix end
    line = line .. ' ' .. n
  end
  if line ~= prefix then lines[#lines + 1] = line end
end

local function dump_api(label)
  local snap = snapshot_api()
  local lines = {}
  lines[#lines + 1] = 'BFV Chef Probe ' .. VERSION .. ' - engine API surface as a Chef mod sees it (' .. label .. ')'
  lines[#lines + 1] = 'date ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' | ' .. tostring(chef.loader) .. ' ' .. tostring(chef.loader_version) .. ' api ' .. tostring(chef.api)
  local n_tables, n_fns = 0, 0
  for _, t in pairs(snap.tables) do n_tables = n_tables + 1; n_fns = n_fns + #t.fns end
  lines[#lines + 1] = string.format('%d engine tables, %d functions in them', n_tables, n_fns)
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## names that may matter (audio, health, damage, kills, stats, events ...): table.function'
  for _, name in ipairs(sorted_keys(snap.tables)) do
    local hits = {}
    local lname = name:lower()
    for _, fn in ipairs(snap.tables[name].fns) do
      local both = lname .. '.' .. fn:lower()
      for _, p in ipairs(INTEREST) do
        if both:find(p, 1, true) then hits[#hits + 1] = fn; break end
      end
    end
    if #hits > 0 then wrap_names(name .. ':', hits, lines, 150) end
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## tables that read as false (the loader keeps them from mods) or are not tables'
  lines[#lines + 1] = table.concat(snap.blocked, ' ')
  lines[#lines + 1] = table.concat(snap.scalars, ' ')
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## named globals as the mod sees them'
  local present = {}
  for _, g in ipairs(CANDIDATE_GLOBALS) do
    local v = rawget(_G, g)
    present[#present + 1] = g .. '=' .. (v == nil and 'nil' or type(v))
  end
  wrap_names('', present, lines, 150)
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## every engine table and its functions'
  for _, name in ipairs(sorted_keys(snap.tables)) do
    local t = snap.tables[name]
    lines[#lines + 1] = string.format('# %s (%d functions%s)', name, #t.fns,
      #t.other > 0 and (', other: ' .. table.concat(t.other, ' ', 1, math.min(#t.other, 12))) or '')
    wrap_names('', t.fns, lines, 150)
  end
  write_file('bfv_probe_api.txt', lines)
  L('API', '%s: %d tables, %d functions written to bfv_probe_api.txt', label, n_tables, n_fns)
  api_snapshot = snap
end

local function banner()
  L('BANNER', 'probe=%s loader=%s %s api=%s date=%s', VERSION, tostring(chef.loader), tostring(chef.loader_version),
    tostring(chef.api), os.date('%Y-%m-%d %H:%M:%S'))
  local caps = {}
  if type(chef.capabilities) == 'table' then
    for _, k in ipairs(sorted_keys(chef.capabilities)) do
      if k ~= 'api' then caps[#caps + 1] = k .. '=' .. (chef.capabilities[k] and '1' or '0') end
    end
  end
  L('CAPS', '%s', table.concat(caps, ' '))
  local w, h = chef.screen()
  local B = rawget(_G, 'CowboyBingusModLoader')
  local build = 'unknown'
  if type(B) == 'table' and type(B.game) == 'table' then build = tostring(B.game.build_identifier) end
  L('ENV', 'screen=%sx%s game_build=%s options=%s', tostring(w), tostring(h), build,
    (chef.options and next(chef.options)) and 'set' or 'none')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- stage 1: units. A scan of the world's unit list finds which unit kinds MOVE (enemies, squadmates, vehicles ...),
-- then the movers around the camera are followed: when they stop being alive, lose their animation state machine
-- or vanish from the world, a UNIT line says so, with the states they were in and where the crosshair was.
-- ---------------------------------------------------------------------------------------------------------------------
-- What kind of unit moves, has a state machine and how often it died is true in every mission, so the kinds table
-- outlives worlds; what is followed (and the per-world counters) starts again with each world.
local KINDS, TOT = {}, { scans = 0, spawned = 0, deaths = 0, gone = 0, kinds = 0, bodies = 0 }
local U
local function units_reset()
  for _, K in pairs(KINDS) do K.n, K.probe, K.probe_n, K.moved_check = 0, {}, 0, false end
  U = { kinds = KINDS, tracked = {}, tracked_n = 0, order = {}, cursor = 1, scan = nil, next_scan = 0,
        scans = 0, seq = 0, spawned = 0, deaths = 0, gone = 0, dead = {}, dead_n = 0 }
end
units_reset()

local function dist3(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- distance and the angle (degrees) between the camera's forward direction and the direction to a point
local function aim_of(x, y, z)
  if not cam then return nil, nil end
  local dx, dy, dz = x - cam.x, y - cam.y, (z + 1.0) - cam.z      -- +1 m: about the chest of a standing unit
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  if d < 0.01 then return d, 0 end
  local fl = math.sqrt(cam.fx * cam.fx + cam.fy * cam.fy + cam.fz * cam.fz)
  if fl < 0.0001 then return d, nil end
  local dot = (dx * cam.fx + dy * cam.fy + dz * cam.fz) / (d * fl)
  if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
  return d, math.deg(math.acos(dot))
end

local function states_text(t, n)
  local parts = {}
  for i = 1, n do parts[i] = tostring(t[i]) end
  return table.concat(parts, ',')
end

local function kind_of(k)
  local K = U.kinds[k]
  if not K then
    K = { n = 0, max = 0, probe = {}, probe_n = 0, checks = 0, rechecks = 0, mover = nil, sm = nil, sm_tries = 0,
          deaths = 0, gone = 0, first = now, logged = false }
    U.kinds[k] = K
    TOT.kinds = TOT.kinds + 1
  end
  return K
end

local function unit_event(r, why)
  if r.done then return end
  r.done = true
  local K = U.kinds[r.kind]
  if why:find('gone', 1, true) then
    U.gone, TOT.gone = U.gone + 1, TOT.gone + 1
    if K then K.gone = K.gone + 1 end
  else
    U.deaths, TOT.deaths = U.deaths + 1, TOT.deaths + 1
    if K then K.deaths = K.deaths + 1 end
  end
  U.dead[r.unit] = true
  U.dead_n = U.dead_n + 1
  -- the states the unit was in, each with the seconds before this event at which it entered them
  local hist = {}
  for i = 1, #r.hist do hist[i] = string.format('%.1f:%s', r.hist[i][1] - now, r.hist[i][2]) end
  L('UNIT', 'why=%s kind=%s id=%d age=%.1f d=%s ang=%s st=%s hist=[%s] fire=%s tier=%s', why, r.kind, r.id,
    now - r.born, r.d and string.format('%.1f', r.d) or '-', r.ang and string.format('%.1f', r.ang) or '-',
    tostring(r.st), table.concat(hist, '|'), since_fire(), tier_of(r.kind))
end

local function track(u, k, x, y, z)
  if U.tracked[u] or U.dead[u] then return end
  U.seq = U.seq + 1
  local d, ang = aim_of(x, y, z)
  local r = { unit = u, kind = k, id = U.seq, born = now, x = x, y = y, z = z, d = d, ang = ang, alive = true,
              sm = nil, st = nil, hist = {}, done = false }
  U.tracked[u] = r
  U.tracked_n = U.tracked_n + 1
  U.order[#U.order + 1] = r
  U.spawned, TOT.spawned = U.spawned + 1, TOT.spawned + 1
end

local function untrack(r)
  if U.tracked[r.unit] then
    U.tracked[r.unit] = nil
    U.tracked_n = U.tracked_n - 1
  end
  r.removed = true
end

local function scan_begin()
  local w = chef.world()
  if not w then return end
  local list, why = C('World.units', w)
  if type(list) ~= 'table' then
    if once('world_units_failed') then L('UNITS', 'World.units gave no list: %s', tostring(why or type(list))) end
    return
  end
  U.scan = { list = list, n = #list, i = 1, counts = {}, cand = {}, present = {}, probe_seen = {}, t0 = now }
end

-- a unit of a kind not yet known to move or not: compare where it is with where it was when first looked at (not
-- with the last scan, so a slow walker adds up)
local function probe_move(K, u, x, y, z)
  local p = K.probe[u]
  if p then
    K.moved_check = true
    if dist3(x, y, z, p[1], p[2], p[3]) > 0.75 then K.mover = true end
  else
    K.probe[u] = { x, y, z }
    K.probe_n = K.probe_n + 1
  end
end

local function scan_step(budget)
  local S = U.scan
  if not S then return end
  local last = math.min(S.n, S.i + budget - 1)
  for i = S.i, last do
    local u = S.list[i]
    -- (the list was made some frames ago: ask whether the unit is still there before asking anything else of it)
    local k = (u ~= nil and chef.unit_alive(u)) and chef.unit_kind(u) or nil
    if k and k ~= RUNTIME_KIND then
      S.counts[k] = (S.counts[k] or 0) + 1
      local K = kind_of(k)
      if K.mover == nil then
        -- not known yet whether this kind moves: watch up to three of its units across scans (the position of every
        -- other unit of the kind is not asked)
        if K.probe[u] or K.probe_n < 3 then
          local x, y, z = chef.unit_position(u)
          if x then
            probe_move(K, u, x, y, z)
            S.probe_seen[u] = true
          end
        end
      elseif K.mover == true then
        -- Does this kind have an animation state machine? One unit that has one settles it. A unit without one may
        -- be a body, so only four such answers make the kind one without.
        if K.sm == nil and K.sm_tries < 8 then
          K.sm_tries = K.sm_tries + 1
          local v = CK('Unit.has_animation_state_machine', k, u)
          if v == true then
            K.sm = true
          elseif v ~= nil then
            K.sm_false = (K.sm_false or 0) + 1
            if K.sm_false >= 4 then K.sm = false end
          end
        end
        S.present[u] = true
        if cam and not U.tracked[u] and not U.dead[u] then
          local x, y, z = chef.unit_position(u)
          if x then
            local d = dist3(x, y, z, cam.x, cam.y, cam.z)
            if d <= RADIUS then S.cand[#S.cand + 1] = { u, k, x, y, z, d } end
          end
        end
      end
    end
  end
  S.i = last + 1
  if S.i > S.n then
    -- the scan is complete
    for k, n in pairs(S.counts) do
      local K = U.kinds[k]
      K.n = n
      if n > K.max then K.max = n end
    end
    for k, K in pairs(U.kinds) do
      if K.mover == nil then
        -- drop probes that were not seen this scan, count a finished check
        for pu in pairs(K.probe) do
          if not S.probe_seen[pu] then K.probe[pu] = nil; K.probe_n = K.probe_n - 1 end
        end
        if K.moved_check then K.checks = K.checks + 1; K.moved_check = false end
        if K.checks >= 5 and K.mover == nil then K.mover = false; K.probe = {}; K.probe_n = 0; K.recheck_at = now + 20 end
      elseif K.mover == false and K.recheck_at and now >= K.recheck_at and K.rechecks < 5 and (K.n or 0) >= 2 then
        -- idle units, or probes that happened to be bodies: look again with fresh units
        K.mover, K.checks, K.rechecks, K.recheck_at = nil, 0, K.rechecks + 1, nil
      end
      -- written once the state machine question has an answer (the first try comes a scan after the move is seen)
      if K.mover == true and not K.logged and (K.sm ~= nil or K.sm_tries >= 8) then
        K.logged = true
        L('KIND', 'kind=%s mover=true sm=%s n=%d tier=%s', k, tostring(K.sm), K.n or 0, tier_of(k))
      end
    end
    -- units followed that are no longer in the world's list
    for u, r in pairs(U.tracked) do
      if not S.present[u] then
        unit_event(r, 'gone')
        untrack(r)
      end
    end
    -- new units to follow: the nearest ones, up to the limit
    table.sort(S.cand, function(a, b) return a[6] < b[6] end)
    for i = 1, #S.cand do
      if U.tracked_n >= TRACK_MAX then break end
      local c = S.cand[i]
      track(c[1], c[2], c[3], c[4], c[5])
    end
    U.scans, TOT.scans = U.scans + 1, TOT.scans + 1
    U.scan = nil
    U.next_scan = now + (U.scans < 5 and SCAN_FAST or SCAN_EVERY)
  end
end

local function sample_unit(r)
  local u = r.unit
  if not chef.unit_alive(u) then
    r.alive = false
    unit_event(r, 'alive->false')
    return
  end
  local K = U.kinds[r.kind]
  local sm = r.sm
  if K and K.sm ~= false then
    local v = CK('Unit.has_animation_state_machine', r.kind, u)
    if v ~= nil then sm = (v == true) end
    if v == true and K.sm ~= true then K.sm = true end
  end
  local st = r.st
  if sm then
    local n, t = pack2(CK('Unit.animation_get_state', r.kind, u))
    if t[1] ~= nil then st = states_text(t, math.min(n, 6)) end
    if st ~= r.st then
      r.hist[#r.hist + 1] = { now, tostring(st) }
      if #r.hist > 4 then table.remove(r.hist, 1) end
    end
  end
  r.st = st
  local x, y, z = chef.unit_position(u)
  if x then
    r.x, r.y, r.z = x, y, z
    r.d, r.ang = aim_of(x, y, z)
  end
  if r.sm == true and sm == false then
    r.sm = sm
    unit_event(r, 'sm->none')
    return
  end
  if r.sm == nil and sm == false and K and K.sm == true then
    -- first seen already without the state machine its kind has: a body from before. Not followed (it would hold
    -- one of the places for good) and not logged as a death.
    r.done = true
    U.dead[u] = true
    U.bodies, TOT.bodies = (U.bodies or 0) + 1, TOT.bodies + 1
    return
  end
  r.sm = sm
end

local function units_step(dt)
  if not cam then return end
  if U.scan then
    scan_step(SCAN_BUDGET)
  elseif now >= U.next_scan then
    scan_begin()
    if U.scan then scan_step(SCAN_BUDGET) else U.next_scan = now + SCAN_EVERY end
  end
  -- one slice of the followed units per frame, so a full pass takes about SAMPLE_CYCLE seconds
  local order = U.order
  local n = #order
  if n == 0 then return end
  local slice = math.max(4, math.ceil(n * math.max(dt, 0.001) / SAMPLE_CYCLE))
  local cursor = U.cursor
  for _ = 1, math.min(slice, n) do
    if cursor > #order then cursor = 1 end
    local r = order[cursor]
    if r == nil then break end
    if r.removed or r.done then
      table.remove(order, cursor)               -- the next unit slid into this index: don't advance
    else
      sample_unit(r)
      if r.done then untrack(r); table.remove(order, cursor) else cursor = cursor + 1 end
    end
  end
  U.cursor = cursor
end

-- ---------------------------------------------------------------------------------------------------------------------
-- stage 2/3: game objects (the network objects of the session). Mine: found through objects_owned_by. Fields are
-- numbered and their values are logged only when they change (a field that changes every sample is muted).
-- The enemy stage looks at other objects the same way and is OFF by default: it may end the game.
-- ---------------------------------------------------------------------------------------------------------------------
local O, E
local function objects_reset()
  O = { next = 0, sigs = {}, sig_n = 0, by_id = {}, count = 0, tracked = {}, force = false, refreshes = 0,
        samples = 0, changes = 0, session_logged = false }
  E = { next = 0, tracked = {}, by_id = {}, samples = 0, changes = 0, mapped = 0, force = false }
end
objects_reset()

local function signature_of(f)
  local keys = {}
  for _, k in ipairs(sorted_keys(f, 160)) do keys[#keys + 1] = tostring(k) .. ':' .. type(f[k]):sub(1, 1) end
  return #keys .. '|' .. table.concat(keys, ',')
end

local function fields_text(f)
  local flat = flatten(f, {})
  local parts, n = {}, 0
  for _, p in ipairs(sorted_keys(flat)) do
    n = n + 1
    if n > 48 then parts[#parts + 1] = '+' .. (#sorted_keys(flat) - 48) .. ' more'; break end
    parts[#parts + 1] = p .. '=' .. flat[p]
  end
  return table.concat(parts, ' ')
end

-- sample one object: log what changed since the last sample. rec = { id, prev, chg, muted, sig }
local function sample_object(tag, s, rec, extra)
  if C('GameSession.game_object_exists', s, rec.id) ~= true then
    if not rec.gone then rec.gone = true; L(tag, 'id=%s gone%s', tostring(rec.id), extra or '') end
    return false
  end
  local f = C('GameSession.game_object_field_batched', s, rec.id, {})
  if type(f) ~= 'table' then return false end
  local flat = flatten(f, {})
  if not rec.prev then
    rec.prev = flat
    return true
  end
  local changed = {}
  for p, v in pairs(flat) do
    if rec.prev[p] ~= v then
      local c = (rec.chg[p] or 0) + 1
      rec.chg[p] = c
      -- a field that changes in more than a third of the samples (a position, a timer) is noise: mute it
      if c >= 12 and c > 0.35 * ((rec.samples or 0) + 1) and not rec.muted[p] then
        rec.muted[p] = true
        L(tag, 'id=%s %s muted (changes in most samples)', tostring(rec.id), p)
      end
      if not rec.muted[p] then changed[#changed + 1] = p end
    end
  end
  table.sort(changed)
  rec.samples = (rec.samples or 0) + 1
  if #changed > 0 then
    local parts = {}
    for i = 1, math.min(#changed, 12) do
      local p = changed[i]
      parts[i] = p .. ': ' .. tostring(rec.prev[p]) .. ' -> ' .. flat[p]
    end
    if #changed > 12 then parts[#parts + 1] = '+' .. (#changed - 12) .. ' more' end
    L(tag, 'id=%s sig=%s%s | %s', tostring(rec.id), tostring(rec.sigid or '?'), extra or '', table.concat(parts, ' ; '))
    O.changes = O.changes + 1
  end
  rec.prev = flat
  return true
end

local function session_handles()
  local s = C('Network.game_session')
  local peer = C('Network.peer_id')
  if s == nil or peer == nil then return nil end
  return s, peer
end

local function player_step()
  if now < O.next and not O.force then return end
  O.next = now + OBJ_PERIOD
  O.force = false
  local s, peer = session_handles()
  if not s then return end
  O.refreshes = O.refreshes + 1
  -- refresh the owned list about once a second and describe objects not seen before
  if O.refreshes % 5 == 1 then
    local owned = C('GameSession.objects_owned_by', s, peer)
    if type(owned) == 'table' then
      -- A host owns every enemy and projectile too. Unless the risky stage is on, only the 40 lowest ids (the ones made
      -- first: the player's own persistent objects) are ever looked into; otherwise up to 8000, 10 new ones a second.
      local limit = cfg.enemyobj and 8000 or 40
      local ids = {}
      for _, id in pairs(owned) do
        if type(id) == 'number' then
          ids[#ids + 1] = id
          if #ids >= 4000 then break end
        end
      end
      O.owned_n = #ids
      table.sort(ids)
      local live = 0                                  -- described objects that still exist (are in the owned list)
      for i = 1, #ids do if O.by_id[ids[i]] then live = live + 1 end end
      local fresh = 0
      for _, id in ipairs(ids) do
        if fresh >= 10 or live >= limit or O.count >= 8000 then break end
        if not O.by_id[id] then
          fresh, live = fresh + 1, live + 1
          local rec = { id = id, prev = nil, chg = {}, muted = {}, first = now }
          O.by_id[id] = rec
          O.count = O.count + 1
          if C('GameSession.game_object_exists', s, id) == true then
            local f = C('GameSession.game_object_field_batched', s, id, {})
            if type(f) == 'table' then
              local sig = signature_of(f)
              local S = O.sigs[sig]
              if not S then
                O.sig_n = O.sig_n + 1
                S = { n = 0, id = O.sig_n, example = id }
                O.sigs[sig] = S
                L('OBJSIG', 'sig=%d first_object=%s fields=%d | %s', S.id, tostring(id), #sorted_keys(f, 160), fields_text(f))
              end
              S.n = S.n + 1
              rec.sig, rec.sigid = sig, S.id
              -- only an object that is alone with its layout will be followed, so only it keeps its values
              if S.n == 1 then rec.prev = flatten(f, {}) end
            end
          end
        end
      end
      if not O.session_logged then
        O.session_logged = true
        L('OBJ', 'owned objects: %d (peer known, session ok)', O.owned_n or 0)
      end
    end
    -- follow objects whose field layout is unique among mine (the player object, its avatar, equipment ...): the
    -- OBJ_TRACK oldest ones
    local unique = {}
    for _, rec in pairs(O.by_id) do
      if rec.sig and O.sigs[rec.sig].n == 1 and not rec.gone then unique[#unique + 1] = rec end
    end
    table.sort(unique, function(a, b) return a.id < b.id end)
    O.tracked = {}
    for i = 1, math.min(#unique, OBJ_TRACK) do O.tracked[i] = unique[i] end
  end
  for _, rec in ipairs(O.tracked) do
    O.samples = O.samples + 1
    sample_object('OBJ', s, rec)
  end
end

-- enemy objects (risky): by the unit synchronizer for followed units, else from the most common field layouts
local function enemyobj_step()
  if not cfg.enemyobj then return end
  if now < E.next and not E.force then return end
  E.next = now + 0.25
  E.force = false
  local s = session_handles()
  if not s then return end
  if once('eobj_on') then
    L('EOBJ', 'enemy object stage is on (it may end the game; the loader skips a call that did it twice in a row)')
  end
  -- refresh the followed set every 2 s
  if not E.refreshed or now - E.refreshed >= 2 then
    E.refreshed = now
    local picked = {}
    local sync = C('GameSession.unit_synchronizer', s)
    if sync ~= nil then
      local near = {}
      for _, r in pairs(U.tracked) do if r.alive and r.d then near[#near + 1] = r end end
      table.sort(near, function(a, b) return a.d < b.d end)
      for i = 1, math.min(#near, EOBJ_TRACK) do
        local r = near[i]
        local id = C('UnitSynchronizer.unit_to_game_object_id', sync, r.unit)
        if type(id) == 'number' then
          E.mapped = E.mapped + 1
          picked[#picked + 1] = { id = id, kind = r.kind }
        end
      end
    elseif once('eobj_sync_failed') then
      L('EOBJ', 'GameSession.unit_synchronizer gave nothing')
    end
    local keep, kept_by_id = {}, {}
    for _, p in ipairs(picked) do
      local rec = E.by_id[p.id]
      if not rec then
        rec = { id = p.id, prev = nil, chg = {}, muted = {}, unitkind = p.kind }
        L('EOBJ', 'follow id=%s unit_kind=%s', tostring(p.id), p.kind)
      end
      kept_by_id[p.id] = rec
      keep[#keep + 1] = rec
    end
    E.tracked, E.by_id = keep, kept_by_id            -- objects no longer followed are forgotten, values and all
  end
  for _, rec in ipairs(E.tracked) do
    E.samples = E.samples + 1
    sample_object('EOBJ', s, rec, ' unit=' .. tostring(rec.unitkind))
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- input: fire and the mark keys
-- ---------------------------------------------------------------------------------------------------------------------
local binds = {}

local function nearest_text(n)
  local list = {}
  for _, r in pairs(U.tracked) do if r.d then list[#list + 1] = r end end
  table.sort(list, function(a, b) return a.d < b.d end)
  local parts = {}
  for i = 1, math.min(n, #list) do
    local r = list[i]
    parts[i] = string.format('%s#%d d=%.1f ang=%s alive=%s sm=%s st=%s', r.kind:sub(1, 8), r.id, r.d,
      r.ang and string.format('%.1f', r.ang) or '-', tostring(r.alive), tostring(r.sm), tostring(r.st))
  end
  return table.concat(parts, ' ; ')
end

local function mark(what)
  marks[what] = marks[what] + 1
  emit('MARK', string.format('%s #%d fire=%s followed=%d near=[%s]', what:upper(), marks[what], since_fire(),
    U.tracked_n, nearest_text(6)), true)
  O.force, E.force = true, true
  if chef.notify then chef.notify('PROBE MARK ' .. what:upper() .. ' ' .. marks[what], 1.2, 255, 230, 90) end
end

local function input_step()
  local down = chef.mouse_down('left') == true
  if down and not fire_down then
    fire_down, fire_since, last_fire_down = true, now, now
    clicks = clicks + 1
    L('FIRE', 'down #%d followed=%d', clicks, U.tracked_n)
  elseif not down and fire_down then
    fire_down, last_fire_up = false, now
    L('FIRE', 'up held=%.2f', now - (fire_since or now))
  end
  for what, b in pairs(binds) do
    if b.pressed() then mark(what) end
  end
end

-- aim: while the fire button is held, which followed units does the camera's ray go through (a box test)
local A = { next = 0, samples = 0, hits = 0 }
local function aim_step()
  if not (cfg.aim and fire_down and cam and has('ray_box')) then return end
  if now < A.next then return end
  A.next = now + 0.12
  local from = { x = cam.x, y = cam.y, z = cam.z }
  local dir = { x = cam.fx, y = cam.fy, z = cam.fz }
  local c = {}
  for _, r in pairs(U.tracked) do
    if r.alive and not r.done and r.ang and r.ang < 10 and r.d and r.d < 160 then c[#c + 1] = r end
  end
  table.sort(c, function(a, b) return a.ang < b.ang end)
  local hits = {}
  for i = 1, math.min(#c, 6) do
    local dist = chef.ray_box(from, dir, c[i].unit)
    if type(dist) == 'number' then hits[#hits + 1] = string.format('%s#%d:%.1fm@%.1f', c[i].kind:sub(1, 8), c[i].id, dist, c[i].ang) end
  end
  A.samples = A.samples + 1
  if #hits > 0 then
    A.hits = A.hits + 1
    L('AIM', 'n=%d %s', #hits, table.concat(hits, ' '))
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- summary (bfv_probe_summary.txt and a SUM line)
-- ---------------------------------------------------------------------------------------------------------------------
local next_summary = 0
local function summary(final)
  local lines = {}
  lines[#lines + 1] = 'BFV Chef Probe ' .. VERSION .. ' summary' .. (final and ' (final)' or '') .. ' at t=' .. string.format('%.1f', now)
  lines[#lines + 1] = string.format('units (all worlds): scans=%d kinds=%d spawned=%d deaths=%d gone=%d bodies-skipped=%d | followed now=%d',
    TOT.scans, TOT.kinds, TOT.spawned, TOT.deaths, TOT.gone, TOT.bodies, U.tracked_n)
  lines[#lines + 1] = string.format('objects: refreshes=%d samples=%d changes=%d signatures=%d owned=%s', O.refreshes, O.samples, O.changes, O.sig_n, tostring(O.owned_n))
  lines[#lines + 1] = string.format('enemy objects: on=%s samples=%d mapped=%d', tostring(cfg.enemyobj), E.samples, E.mapped)
  lines[#lines + 1] = string.format('input: clicks=%d marks kill=%d hit=%d other=%d | aim samples=%d with-hits=%d', clicks, marks.kill, marks.hit, marks.other, A.samples, A.hits)
  lines[#lines + 1] = string.format('log: %d bytes%s', logged, capped and ' (CAP reached)' or '')
  local dropped = {}
  for tag, n in pairs(tag_dropped) do dropped[#dropped + 1] = tag .. '=' .. n end
  table.sort(dropped)
  lines[#lines + 1] = 'lines dropped by tag caps: ' .. (#dropped > 0 and table.concat(dropped, ' ') or 'none')
  local errs = {}
  for st, n in pairs(stage_errors) do errs[#errs + 1] = st .. '=' .. n .. ((stage_off[st] and chef.time() < stage_off[st]) and '(resting)' or '') end
  table.sort(errs)
  lines[#lines + 1] = 'stage errors: ' .. (#errs > 0 and table.concat(errs, ' ') or 'none')
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## calls the loader refused or that gave nothing (count)'
  local rk = sorted_keys(refused)
  for i = 1, math.min(#rk, 40) do lines[#lines + 1] = string.format('%6d  %s', refused[rk[i]], rk[i]) end
  -- how much of what moves is already classified by the MDL3 build's tier table
  local movers, known, tiers_n, unknown = 0, 0, {}, {}
  for k, K in pairs(KINDS) do
    if K.mover == true then
      movers = movers + 1
      if TIERS[k] then known = known + 1; tiers_n[TIERS[k]] = (tiers_n[TIERS[k]] or 0) + 1 else unknown[#unknown + 1] = k end
    end
  end
  table.sort(unknown, function(a, b) return (KINDS[a].max or 0) > (KINDS[b].max or 0) end)
  local tn = {}
  for _, t in ipairs(sorted_keys(tiers_n)) do tn[#tn + 1] = t .. '=' .. tiers_n[t] end
  lines[#lines + 1] = string.format('moving unit kinds: %d, with a tier in the MDL3 build\'s table: %d (%s)', movers, known,
    #tn > 0 and table.concat(tn, ' ') or 'none')
  local un = {}
  for i = 1, math.min(#unknown, 60) do un[i] = string.format('%s(max %d, deaths %d)', unknown[i], KINDS[unknown[i]].max or 0, KINDS[unknown[i]].deaths) end
  lines[#lines + 1] = 'moving kinds WITHOUT a tier: ' .. (#un > 0 and table.concat(un, ' ') or 'none')
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## unit kinds seen: kind  last-count  max-count  mover  has-state-machine  deaths  gone  tier'
  local kinds = {}
  for k in pairs(U.kinds) do kinds[#kinds + 1] = k end
  table.sort(kinds, function(a, b)
    local ka, kb = U.kinds[a], U.kinds[b]
    if (ka.deaths + ka.gone) ~= (kb.deaths + kb.gone) then return (ka.deaths + ka.gone) > (kb.deaths + kb.gone) end
    if ka.max ~= kb.max then return ka.max > kb.max end
    return a < b
  end)
  for i = 1, math.min(#kinds, 400) do
    local K = U.kinds[kinds[i]]
    lines[#lines + 1] = string.format('%s %5d %5d  %-5s %-5s  %4d %4d  %s', kinds[i], K.n or 0, K.max, tostring(K.mover), tostring(K.sm), K.deaths, K.gone, tier_of(kinds[i]))
  end
  write_file('bfv_probe_summary.txt', lines)
  emit('SUM', string.format('scans=%d kinds=%d followed=%d deaths=%d gone=%d obj_samples=%d obj_changes=%d eobj=%d clicks=%d marks=%d/%d/%d log=%dB',
    TOT.scans, TOT.kinds, U.tracked_n, TOT.deaths, TOT.gone, O.samples, O.changes, E.samples, clicks, marks.kill, marks.hit, marks.other, logged), true)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the F9 menu
-- ---------------------------------------------------------------------------------------------------------------------
local function setup_menu()
  if not has('menu') then return end
  chef.title('BFV Chef Probe')
  local function toggle(id, label, default, hint, heading)
    local spec = { type = 'toggle', label = label, default = default }
    if has('option_headings') then spec.hint, spec.heading = hint, heading end   -- loader 1.4.0 and newer
    local v = chef.option(id, spec)
    if v ~= nil then cfg[id] = v == true end
    chef.on_change(id, function(value) cfg[id] = value == true end)
  end
  toggle('units', 'Units: census and deaths', true, 'Follow moving units near you and log when they die or vanish.', 'What to record')
  toggle('player', 'My game objects: field changes', true, 'Log the network objects you own when a field changes.')
  toggle('aim', 'Aim ray tests while firing', true, 'While the left mouse button is held, log which followed units the camera ray goes through.')
  toggle('enemyobj', 'Enemy game objects (MAY END THE GAME)', false, 'Reads other network objects. The loader learns from a crash and skips the call, but keep it off for the first run.')
  toggle('hud', 'Show the status line', true, 'A small line at the top left with the probe counters.')
  if has('option_buttons') then
    chef.button('dump_api', 'Write the API list again', function() safe('api', dump_api, 'asked in the menu') end, 'WRITE')
    chef.button('dump_sum', 'Write the summary file now', function() safe('summary', summary, false) end, 'WRITE')
  end
  if has('bind') then
    local function bind(what, key, label)
      local b = chef.bind('mark_' .. what, key, label)
      if b then binds[what] = b end
    end
    bind('kill', 'f6', 'Mark: I just got a KILL')
    bind('hit', 'f7', 'Mark: I just got a HIT')
    bind('other', 'f8', 'Mark: something else happened')
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- frame hooks
-- ---------------------------------------------------------------------------------------------------------------------
local function new_world(id)
  world_id = id
  units_reset()
  objects_reset()
  mission_t0 = nil
  L('WORLD', 'id=%s in_mission=%s', tostring(id), tostring(chef.in_mission()))
end

function M.update(dt)
  now = chef.time()
  local c = chef.camera()
  if type(c) == 'table' and type(c.x) == 'number' and type(c.y) == 'number' and type(c.z) == 'number'
     and type(c.fx) == 'number' and type(c.fy) == 'number' and type(c.fz) == 'number' then
    cam = cam or {}
    cam.x, cam.y, cam.z, cam.fx, cam.fy, cam.fz = c.x, c.y, c.z, c.fx, c.fy, c.fz
  else
    cam = nil                              -- no camera, or one without a forward direction: nothing is measured from it
  end
  local wid = chef.world_id()
  if wid ~= world_id then safe('world', new_world, wid) end
  if not chef.in_mission() then
    fire_down = false                      -- clicks on the ship's menus are not shots
    return
  end
  safe('input', input_step)
  if not mission_t0 then mission_t0 = now end
  if cfg.units then safe('units', units_step, dt) end
  if cfg.player then safe('player', player_step) end
  if cfg.enemyobj then safe('enemyobj', enemyobj_step) end
  safe('aim', aim_step)
  if now >= next_summary then
    next_summary = now + 30
    safe('summary', summary, false)
  end
end

function M.render()
  if not cfg.hud then return end
  local w, h = chef.screen()
  if not w then return end
  local px = math.max(1, math.floor(h / 720 + 0.5))
  local text = string.format('BFV PROBE %s  FOLLOWED %d  DEATHS %d  MARKS %d  LOG %dK%s', VERSION, U.tracked_n, TOT.deaths,
    marks.kill + marks.hit + marks.other, math.floor(logged / 1024), capped and ' FULL' or '')
  chef.text(12, h - 22 * px, text, px, chef.color(255, 230, 90, 255), chef.TOP + 30)
end

function M.shutdown()
  safe('summary', summary, true)
end

function M.on_stop()
  safe('summary', summary, true)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- start
-- ---------------------------------------------------------------------------------------------------------------------
safe('banner', banner)
safe('menu', setup_menu)
if chef.budget then chef.budget(3) end

if chef.after_startup then
  chef.after_startup(function() safe('api', dump_api, 'at start-up') end)
else
  safe('api', dump_api, 'at start-up')
end

if chef.on then
  chef.on('mission_start', function(id)
    L('MISSION', 'start world=%s', tostring(id))
    safe('api', function()
      -- tables can appear once a mission is up: write the list again if it grew
      local snap = snapshot_api()
      local before = 0
      if api_snapshot then for _ in pairs(api_snapshot.tables) do before = before + 1 end end
      local after = 0
      for _ in pairs(snap.tables) do after = after + 1 end
      if after ~= before then dump_api('after the mission started') end
    end)
  end)

  chef.on('mission_end', function(id)
    L('MISSION', 'end world=%s', tostring(id))
    safe('summary', summary, false)
  end)
end

return M
