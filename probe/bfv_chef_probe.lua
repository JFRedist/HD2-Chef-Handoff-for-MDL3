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
-- helpers (the loader's crash guard). The one stage that has ended the game for other mods, reading OTHER players'
-- network game objects, is OFF until you switch it on in the F9 menu.
--
-- 0.2.0, after the first real run (see docs/probe-run-1.md): enemies are noticed dying 5 s earlier (the animation
-- state they sit in for their last 5 s), the crosshair is followed with the ray test until a unit dies, every game
-- object of mine is looked at (0.1.0 saw only the 40 oldest) and the unit under the crosshair is tied to its game object.
local chef = ...
if type(chef) ~= 'table' then return end

local VERSION = '0.2.0'
local M = { version = VERSION }

if chef.own_log then chef.own_log('bfv_probe') end   -- first thing: from here chef.log writes bfv_probe.log

-- ---------------------------------------------------------------------------------------------------------------------
-- settings of the probe itself
-- ---------------------------------------------------------------------------------------------------------------------
local RUNTIME_KIND = '46cab355bd8d4d37'   -- runtime-built units: the loader says never to ask them where they are
local RADIUS       = 100                  -- metres around the camera in which units are followed
local TRACK_MAX    = 120                  -- most units with an animation state machine followed at once
local TRACK_NOSM   = 24                   -- most units without one (parts, projectiles): they must not take the places of the others
local SCAN_EVERY   = 3                    -- seconds between scans of the world's unit list
local SCAN_FAST    = 1.2                  -- ... for the first scans of a world, while unit kinds are being sorted out
local SCAN_BUDGET  = 250                  -- units looked at per frame while a scan runs
local SAMPLE_CYCLE = 0.15                 -- seconds for one pass over the followed units
local OBJ_PERIOD   = 0.20                 -- seconds between samples of the game objects that have a field layout of their own
local OBJ_TRACK    = 16                   -- most of those followed
local OBJ_LIMIT    = 3000                 -- most game objects of mine known at once
local OBJ_NARROW   = 40                   -- ... with the "all objects" row off: only the oldest ones, as 0.1.0 did
local DESCRIBE_MAX = 6                    -- game objects looked at for the first time per frame
local SWEEP_IDLE   = 5                    -- game objects of the shared layouts read per frame
local SWEEP_BUSY   = 14                   -- ... while the fire button is held and for 3 s after a mark
local LINK_PERIOD  = 0.25                 -- seconds between looks at the units under the crosshair
local LINK_NEAR    = 3                    -- most units under the crosshair looked up at a time
local LINK_CENSUS  = 80                   -- most other units looked up per world (one per half second)
local LOG_CAP      = 900000               -- bytes of bfv_probe.log written per launch (the loader restarts a file at 1 MB)
local TAG_CAP      = { UNIT = 800, STATE = 800, DEATH = 1000, OBJ = 1500, GRP = 1500, AIMOBJ = 1000, AIM = 600,
                       FIRE = 1500, KIND = 500, OBJSIG = 200, NEW = 400, GONE = 400, SIGKIND = 150, IGNORE = 60,
                       LINK = 300 }

-- Kinds that are never followed. Run 1 (0.1.0): these three made 667 of the 844 UNIT lines. Two are parts that come and
-- go with every enemy (no state machine), one is a short-lived unit (1.6 s) flying around the player.
local IGNORE = { ['40ae90fff236865b'] = 'part', ['d40f23a128bd988d'] = 'part', ['620769fb47f74906'] = 'short' }

-- The animation state (four numbers, as animation_get_state gives them) an enemy sits in for its last 5 s: run 1 showed
-- the unit entering it 5.0 s before its state machine went away. Seeds for the kinds run 1 saw; other kinds are learned
-- (a state held for 3.5 s or more when the machine went away, twice). A hunter's last number differs (1, 3 or 5), and
-- 0,0,0,1 was also seen before the last state, so a DEATH can be taken back: it is logged as DEATH cancel.
local DEATH_SEED = {
  ['09872e66d1276e1f'] = { '26,0,0,35' },
  ['a1f37bf2a40fbde4'] = { '26,0,0,35' },
  ['c14e0e887e7d2106'] = { '18,29,1,0', '18,18,1,0' },
  ['a478d36a62a861f4'] = { '0,0,0,1', '0,0,0,3', '0,0,0,5' },
  ['d522fd4748d443a5'] = { '24,1,36,1', '24,2,36,1' },
  ['1a7fcdff98c664b0'] = { '12,0,15,30' },
}

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
-- Tags that stop at 65% of the log budget, so a long mission cannot use it all up before the lines that matter most (DEATH,
-- UNIT, AIMOBJ, MARK) are written.
local LOW_TAGS = { GRP = true, OBJ = true, STATE = true, AIM = true, FIRE = true, NEW = true, GONE = true, OBJSIG = true }

local function emit(tag, text, always)
  local cap = TAG_CAP[tag]
  local n = (tag_lines[tag] or 0) + 1
  if cap and n > cap and not always then
    tag_dropped[tag] = (tag_dropped[tag] or 0) + 1
    return
  end
  if capped and not always then return end
  if LOW_TAGS[tag] and logged > 0.65 * LOG_CAP and not always then
    tag_dropped[tag] = (tag_dropped[tag] or 0) + 1
    return
  end
  tag_lines[tag] = n
  local line = string.format('t=%.2f %s %s', chef.time(), tag, text)
  if #line > 1600 then line = line:sub(1, 1600) .. '...' end
  logged = logged + #line + 1
  if logged > LOG_CAP and not always then
    capped = true
    chef.log('%s', string.format('t=%.2f CAP the log budget is used up; from here only MARK, SUM and error lines are written', chef.time()))
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

-- Text in a game object (a name, an id) is not logged, but where two objects hold the same text the log shows it:
-- str#3:16 is the third different text seen, 16 characters long.
local PSEUDO, pseudo_n = {}, 0
local function pseudo(v)
  local p = PSEUDO[v]
  if not p then
    if pseudo_n >= 600 then return 'str#?:' .. #v end
    pseudo_n = pseudo_n + 1
    p = 'str#' .. pseudo_n .. ':' .. #v
    PSEUDO[v] = p
  end
  return p
end

-- one field value as comparable data: numbers, booleans and texts as they are; a vector as a short text that starts
-- with a control character (so it cannot be taken for a text of the game)
local function raw(v)
  local t = type(v)
  if t == 'number' then
    if v ~= v then return '\1nan' end
    return v
  elseif t == 'boolean' or t == 'string' then
    return v
  elseif t == 'userdata' then
    local x, y, z = chef.call('Vector3.to_elements', v)
    if type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
      return string.format('\1vec(%.4g,%.4g,%.4g)', x, y, z)
    end
    return '\1userdata'
  end
  return '\1{' .. t .. '}'
end

-- two raw values the log would show alike (numbers: to about five digits)
local function same(a, b)
  if a == b then return true end
  if type(a) == 'number' and type(b) == 'number' then
    local d = a - b
    if d < 0 then d = -d end
    local m = a < 0 and -a or a
    return d <= 1e-5 * (m > 1 and m or 1)
  end
  return false
end

-- a raw value as text for the log
local function show(v)
  local t = type(v)
  if t == 'number' then
    if v == math.floor(v) and v > -1e15 and v < 1e15 then return string.format('%.0f', v) end
    return string.format('%.5g', v)
  elseif t == 'string' then
    if v:byte(1) == 1 then return v:sub(2) end
    return pseudo(v)
  end
  return tostring(v)
end

-- a game object's fields as path -> raw value: a field that is a table is opened one level (its entries as field.entry)
local keystr = setmetatable({}, { __index = function(t, k) local text = tostring(k); t[k] = text; return text end })
local function flatten(fields, out)
  local n = 0
  for k, v in pairs(fields) do
    n = n + 1
    if n > 200 then break end
    if type(v) == 'table' then
      local m = 0
      for k2, v2 in pairs(v) do
        m = m + 1
        if m > 64 then break end
        out[keystr[k] .. '.' .. keystr[k2]] = raw(v2)
      end
    else
      out[keystr[k]] = raw(v)
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
local A = { next = 0, samples = 0, hits = 0 }              -- the aim ray tests (see aim_step)
local cam = nil                                        -- {x,y,z,fx,fy,fz} copied each frame

local cfg = { units = true, player = true, wide = true, aim = true, link = true, remote = false, hud = true }

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

-- (chef.capabilities is a read-only proxy: pairs() over it gives nothing, so ask chef.has for each name)
local CAP_NAMES = { 'after_startup', 'settings', 'share', 'events', 'require', 'bind', 'menu', 'shims', 'dev', 'logs',
                    'own_log', 'units', 'spawn', 'timers', 'budget', 'session', 'settings_file', 'shapes',
                    'sprite_sheets', 'notify', 'typed', 'key_labels', 'save_table', 'mods', 'health', 'index',
                    'joining', 'ray_box', 'mouse_hold', 'players_event', 'hang_watchdog', 'option_buttons',
                    'option_colors', 'option_headings', 'menu_state', 'mod_stopped_event', 'bind_combos',
                    'option_folds' }

local function banner()
  L('BANNER', 'probe=%s loader=%s %s api=%s date=%s', VERSION, tostring(chef.loader), tostring(chef.loader_version),
    tostring(chef.api), os.date('%Y-%m-%d %H:%M:%S'))
  if chef.has then
    local caps = {}
    for _, name in ipairs(CAP_NAMES) do caps[#caps + 1] = name .. '=' .. (has(name) and '1' or '0') end
    L('CAPS', '%s', table.concat(caps, ' '))
  else
    L('CAPS', 'chef.has does not exist: a loader older than 1.0.1')
  end
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
local KINDS = {}
local TOT = { scans = 0, spawned = 0, deaths = 0, gone = 0, kinds = 0, bodies = 0, dying = 0, late = 0, cancels = 0, learned = 0 }
local U
local recent_deaths = {}                                -- the last DEATH events: { t, id, kind }
local function units_reset()
  for _, K in pairs(KINDS) do K.n, K.probe, K.probe_n, K.moved_check = 0, {}, 0, false end
  U = { kinds = KINDS, tracked = {}, tracked_n = 0, tracked_nosm = 0, order = {}, cursor = 1, scan = nil, next_scan = 0,
        scans = 0, seq = 0, spawned = 0, deaths = 0, gone = 0, dead = {}, dead_n = 0 }
  recent_deaths = {}
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
          deaths = 0, gone = 0, first = now, logged = false, ignore = IGNORE[k], short = 0, term = {}, sigs = {},
          dying = 0, cancels = 0, late = 0, lag_n = 0, lag_sum = 0 }
    if DEATH_SEED[k] then
      K.death = {}
      for _, st in ipairs(DEATH_SEED[k]) do K.death[st] = 'seed' end
    end
    U.kinds[k] = K
    TOT.kinds = TOT.kinds + 1
  end
  return K
end

local function ago(t) return t and string.format('%.2f', now - t) or '-' end

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
  if K and why == 'sm->none' then
    -- the state held when the machine went away is the kind's death state, if it was held for most of 5 s: seen twice, learned
    if r.dying and r.death_t then
      K.lag_n, K.lag_sum = K.lag_n + 1, K.lag_sum + (now - r.death_t)
    elseif r.st and r.st_t and not (K.death and K.death[r.st]) then
      local held = now - r.st_t
      if held >= 3.5 and held <= 8 then
        K.term[r.st] = (K.term[r.st] or 0) + 1
        if K.term[r.st] >= 2 then
          K.death = K.death or {}
          K.death[r.st] = 'learned'
          TOT.learned = TOT.learned + 1
          L('DEATH', 'learned kind=%s st=%s (held %.1f s when the state machine went away, seen %d times)', r.kind, r.st, held, K.term[r.st])
        end
      end
    end
  end
  -- a kind whose units keep vanishing within seconds and never had a state machine is noise
  if K and why == 'alive->false' and now - r.born < 3 and K.sm ~= true then
    K.short = K.short + 1
    if K.short >= 8 and not K.ignore then
      K.ignore = 'auto'
      L('IGNORE', 'kind=%s is not followed from now on: %d units gone within 3 s of being followed, none with a state machine', r.kind, K.short)
    end
  end
  -- the states the unit was in, each with the seconds before this event at which it entered them
  local hist = {}
  for i = 1, #r.hist do hist[i] = string.format('%.1f:%s', r.hist[i][1] - now, r.hist[i][2]) end
  L('UNIT', 'why=%s kind=%s id=%d age=%.1f d=%s ang=%s st=%s hist=[%s] fire=%s tier=%s dying=%s cone=%s ray=%s obj=%s', why, r.kind, r.id,
    now - r.born, r.d and string.format('%.1f', r.d) or '-', r.ang and string.format('%.1f', r.ang) or '-',
    tostring(r.st), table.concat(hist, '|'), since_fire(), tier_of(r.kind),
    r.dying and (r.death_t and string.format('%.1f', now - r.death_t) or 'late') or '-', ago(r.cone_t), ago(r.aim_t), tostring(r.objid or '-'))
end

-- An enemy enters its death state: the kill, about five seconds before its state machine goes away. The game object of
-- the unit is read once more by the link stage (set below), and the log says how long ago the crosshair was on it.
local link_on_death
local function death_event(r, st)
  local K = U.kinds[r.kind]
  r.dying, r.death_t = true, now
  K.dying, TOT.dying = K.dying + 1, TOT.dying + 1
  recent_deaths[#recent_deaths + 1] = { t = now, id = r.id, kind = r.kind }
  if #recent_deaths > 6 then table.remove(recent_deaths, 1) end
  L('DEATH', 'id=%d kind=%s st=%s src=%s d=%s ang=%s age=%.1f cone=%s ray=%s fire=%s tier=%s obj=%s', r.id, r.kind, st,
    tostring(K.death[st]), r.d and string.format('%.1f', r.d) or '-', r.ang and string.format('%.1f', r.ang) or '-',
    now - r.born, ago(r.cone_t), ago(r.aim_t), since_fire(), tier_of(r.kind), tostring(r.objid or '-'))
  if link_on_death then safe('link', link_on_death, r) end      -- (its own stage: an error there must not stop the units stage)
end

-- the animation state of a followed unit changed (old is nil for the first state seen)
local function state_changed(r, old, new)
  local K = U.kinds[r.kind]
  local death = K and K.death
  if old == nil then
    if death and death[new] then
      r.dying = true                           -- on its way out when first seen: no time to give
      K.late, TOT.late = K.late + 1, TOT.late + 1
      L('DEATH', 'late id=%d kind=%s st=%s (in its death state when first seen)', r.id, r.kind, new)
    end
    return
  end
  if death and death[new] and not r.dying then
    death_event(r, new)
  elseif r.dying and not (death and death[new]) then
    r.dying = false                            -- taken back: it left the state before the state machine went away
    K.cancels, TOT.cancels = K.cancels + 1, TOT.cancels + 1
    L('DEATH', 'cancel id=%d kind=%s was=%s now=%s after=%s', r.id, r.kind, tostring(old), tostring(new), ago(r.death_t))
    r.death_t = nil
  end
  -- the state changes of the unit under the crosshair while I shoot: hit reactions would show here
  if r.ang and r.ang < 12 and r.d and r.d < 120 and (fire_down or (last_fire_up and now - last_fire_up < 4)) then
    L('STATE', 'id=%d kind=%s %s -> %s ang=%.1f d=%.1f fire=%s', r.id, r.kind:sub(1, 8), tostring(old), tostring(new), r.ang, r.d, since_fire())
  end
end

local function track(u, k, x, y, z)
  if U.tracked[u] or U.dead[u] then return end
  U.seq = U.seq + 1
  local d, ang = aim_of(x, y, z)
  local K = U.kinds[k]
  local r = { unit = u, kind = k, id = U.seq, born = now, x = x, y = y, z = z, d = d, ang = ang, alive = true,
              sm = nil, st = nil, st_t = nil, hist = {}, done = false, nosm = (K ~= nil and K.sm == false) }
  U.tracked[u] = r
  U.tracked_n = U.tracked_n + 1
  if r.nosm then U.tracked_nosm = U.tracked_nosm + 1 end
  U.order[#U.order + 1] = r
  U.spawned, TOT.spawned = U.spawned + 1, TOT.spawned + 1
end

local function untrack(r)
  if U.tracked[r.unit] then
    U.tracked[r.unit] = nil
    U.tracked_n = U.tracked_n - 1
    if r.nosm then U.tracked_nosm = U.tracked_nosm - 1 end
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
      if K.ignore then
        -- counted, nothing else asked of it
      elseif K.mover == nil then
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
        if K.checks >= 5 and K.mover == nil then
          K.mover, K.static_seen, K.probe, K.probe_n, K.recheck_at = false, true, {}, 0, now + 20
        end
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
      local c = S.cand[i]
      local K = U.kinds[c[2]]
      if K and K.sm == false then
        if U.tracked_nosm < TRACK_NOSM then track(c[1], c[2], c[3], c[4], c[5]) end
      elseif U.tracked_n - U.tracked_nosm < TRACK_MAX then
        track(c[1], c[2], c[3], c[4], c[5])
      end
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
      state_changed(r, r.st, st)
      r.st_t = now
    end
  end
  r.st = st
  local x, y, z = chef.unit_position(u)
  if x then
    r.x, r.y, r.z = x, y, z
    r.d, r.ang = aim_of(x, y, z)
    if r.ang and r.ang < 6 and r.d and r.d < 150 then r.cone_t = now end
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
-- stage 2: game objects (the network objects of the session). Everything that is synchronised has one: the players,
-- the enemies (a host owns every one of them), projectiles, the mission timer ... Each is a numbered list of fields.
-- Mine (GameSession.objects_owned_by) are all looked at, not just the oldest 40 as 0.1.0 did: an object whose field
-- layout nobody else shares (the mission timer, a player ...) is followed one by one (OBJ lines); objects that share a
-- layout (enemies ...) are read round robin, and a field that changes in a tenth of the reads of its layout (or in 5 of
-- the first 6) is noise and muted for the layout (GRP lines). The numbered layouts (OBJSIG lines) and their changing fields go to the summary.
-- ---------------------------------------------------------------------------------------------------------------------
local SIGS = {}                    -- field layout text -> the layout (kept across worlds; its members are not)
local OT = { census = 0, described = 0, samples = 0, changes = 0, gone = 0, new = 0, sigs = 0, owned_max = 0 }
local O
local function objects_reset()
  for _, G in pairs(SIGS) do G.n = 0 end
  O = { next = 0, next_census = 0, by_id = {}, order = {}, cursor = 1, pending = {}, pend_i = 1, queued = {}, singles = {},
        force = false, busy_until = 0, settled = false, owned_n = nil, session_logged = false, shown = 0, foreign = {} }
end
objects_reset()

local function signature_of(f)
  local keys = {}
  for _, k in ipairs(sorted_keys(f, 160)) do keys[#keys + 1] = tostring(k) .. ':' .. type(f[k]):sub(1, 1) end
  return #keys .. '|' .. table.concat(keys, ',')
end

local function fields_text(flat)
  local parts, n = {}, 0
  local keys = sorted_keys(flat)
  for _, p in ipairs(keys) do
    n = n + 1
    if n > 48 then parts[#parts + 1] = '+' .. (#keys - 48) .. ' more'; break end
    parts[#parts + 1] = p .. '=' .. show(flat[p])
  end
  return table.concat(parts, ' ')
end

local function session_handles()
  local s = C('Network.game_session')
  local peer = C('Network.peer_id')
  if s == nil or peer == nil then return nil end
  return s, peer
end

local function object_gone(rec)
  if rec.gone then return end
  rec.gone = true
  OT.gone = OT.gone + 1
  local G = rec.G
  if G then
    G.n, G.gone = G.n - 1, G.gone + 1
    if O.settled then L('GONE', 'id=%s sig=%d age=%.1f', tostring(rec.id), G.id, now - rec.first) end
  end
end

-- the layout of an object (numbered in the order they are met)
local function note_sig(f, id, foreign)
  local sig = signature_of(f)
  local G = SIGS[sig]
  if not G then
    OT.sigs = OT.sigs + 1
    G = { id = OT.sigs, n = 0, total = 0, gone = 0, example = id, samples = 0, reads = 0, chg = {}, gchg = {}, muted = {},
          lines = {}, kinds = {} }
    SIGS[sig] = G
    L('OBJSIG', 'sig=%d first_object=%s%s fields=%d | %s', G.id, tostring(id), foreign and ' foreign=true' or '',
      #sorted_keys(f, 160), fields_text(flatten(f, {})))
  end
  return G
end

-- an object not looked at before: exists, fields, layout
local function describe(s, id)
  local rec = { id = id, first = now, chg = {}, muted = {}, samples = 0 }
  O.by_id[id] = rec
  OT.described = OT.described + 1
  local there = C('GameSession.game_object_exists', s, id)
  if there == false then rec.gone = true; return end
  if there ~= true then rec.bad = true; return end            -- (a refusal is not an answer; never asked again)
  local f = C('GameSession.game_object_field_batched', s, id, {})
  if type(f) ~= 'table' then rec.bad = true; return end       -- never asked again
  local G = note_sig(f, id, O.foreign[id])
  G.n, G.total = G.n + 1, G.total + 1
  rec.G, rec.prev = G, flatten(f, {})
  O.order[#O.order + 1] = rec
  if O.settled then
    OT.new = OT.new + 1
    L('NEW', 'id=%s sig=%d', tostring(id), G.id)
  end
end

local function describe_some(s)
  local n = 0
  while n < DESCRIBE_MAX do
    local id = O.pending[O.pend_i]
    if id == nil then
      O.pending, O.pend_i = {}, 1
      if not O.settled and O.census_logged then
        O.settled = true
        local count = 0
        for _ in pairs(O.by_id) do count = count + 1 end
        L('OBJ', 'all %d game objects looked at once: %d field layouts so far', count, OT.sigs)
      end
      break
    end
    O.pend_i = O.pend_i + 1
    O.queued[id] = nil
    if not O.by_id[id] then describe(s, id); n = n + 1 end
  end
end

-- the list of my objects, about once a second: new ones wait to be described, gone ones are noted, and the objects with
-- a layout of their own (two members or fewer) are picked to be followed one by one
local function census(s, peer)
  local owned = C('GameSession.objects_owned_by', s, peer)
  if type(owned) ~= 'table' then
    if once('owned_failed') then L('OBJ', 'GameSession.objects_owned_by gave no list (%s)', type(owned)) end
    return
  end
  local ids = {}
  for _, id in pairs(owned) do
    if type(id) == 'number' then ids[#ids + 1] = id end
    if #ids >= OBJ_LIMIT then break end
  end
  -- other players' objects (a client sees the enemies there): only when asked for, it has ended the game for other mods
  if cfg.remote and #ids < OBJ_LIMIT then
    local others = C('GameSession.other_peers', s)
    if type(others) == 'table' then
      local nothers = 0
      for _, p in pairs(others) do
        nothers = nothers + 1
        if nothers > 4 then break end
        local theirs = C('GameSession.objects_owned_by', s, p)
        if type(theirs) == 'table' then
          for _, id in pairs(theirs) do
            if type(id) == 'number' and #ids < OBJ_LIMIT then ids[#ids + 1] = id; O.foreign[id] = true end
          end
        end
      end
    end
  end
  table.sort(ids)
  OT.census = OT.census + 1
  O.owned_n = #ids
  if #ids > OT.owned_max then OT.owned_max = #ids end
  if not O.census_logged then
    O.census_logged = true
    L('OBJ', 'game objects listed: %d (peer known, session ok)', #ids)
  end
  local seen = {}
  for _, id in ipairs(ids) do seen[id] = true end
  for id, rec in pairs(O.by_id) do
    if not seen[id] then
      object_gone(rec)
      O.by_id[id] = nil
    end
  end
  for i, id in ipairs(ids) do
    if (cfg.wide or i <= OBJ_NARROW) and not O.by_id[id] and not O.queued[id] then
      O.pending[#O.pending + 1] = id
      O.queued[id] = true
    end
  end
  -- the objects with a layout of their own: the oldest and the newest ones (a player's own objects are made late)
  local singles = {}
  for _, rec in pairs(O.by_id) do
    rec.fast = false
    if rec.G and not rec.gone and rec.G.n <= 2 then singles[#singles + 1] = rec end
  end
  table.sort(singles, function(a, b) return a.id < b.id end)
  local pick, n = {}, #singles
  if n <= OBJ_TRACK then
    pick = singles
  else
    local half = math.floor(OBJ_TRACK / 2)
    for i = 1, half do pick[#pick + 1] = singles[i] end
    for i = n - (OBJ_TRACK - half) + 1, n do pick[#pick + 1] = singles[i] end
  end
  for _, rec in ipairs(pick) do rec.fast = true end
  O.singles = pick
end

-- One object read again; the fields that changed since its last read go to the log under tag. per_object: a field that
-- changes in most reads of this object is muted for it (the objects followed one by one); else the layout's other
-- members count too and a field muted is muted for the layout.
local function sample_rec(tag, s, rec, extra, per_object)
  local there = C('GameSession.game_object_exists', s, rec.id)
  if there == false then
    object_gone(rec)
    return false
  end
  if there ~= true then return false end                   -- (a refusal is not an answer)
  local f = C('GameSession.game_object_field_batched', s, rec.id, {})
  if type(f) ~= 'table' then return false end
  local flat = flatten(f, {})
  local prev, G = rec.prev, rec.G
  rec.prev = flat
  rec.samples = rec.samples + 1
  OT.samples, G.reads = OT.samples + 1, G.reads + 1
  if not prev then return true end
  if not per_object then G.samples = G.samples + 1 end
  local changed
  for p, v in pairs(flat) do
    if not same(prev[p], v) then
      G.chg[p] = (G.chg[p] or 0) + 1
      local muted
      if per_object then
        local c = (rec.chg[p] or 0) + 1
        rec.chg[p] = c
        if c >= 12 and c > 0.35 * rec.samples and not rec.muted[p] then
          rec.muted[p] = true
          L(tag, 'id=%s %s muted (changes in most reads)', tostring(rec.id), p)
        end
        muted = rec.muted[p]
      else
        G.gchg[p] = (G.gchg[p] or 0) + 1
        -- noise is told from a rare change early: 5 changes in the first 6 reads of a layout, or in a tenth of the first 40
        if not G.muted[p] and ((G.samples >= 6 and G.gchg[p] >= 5) or (G.samples >= 40 and G.gchg[p] > 0.10 * G.samples)
                               or (G.lines[p] or 0) >= 150) then
          G.muted[p] = true
          L('OBJSIG', 'sig=%d field %s muted: %d changes in %d reads', G.id, p, G.gchg[p], G.samples)
        end
        muted = G.muted[p]
      end
      if not muted then
        changed = changed or {}
        changed[#changed + 1] = p
        G.lines[p] = (G.lines[p] or 0) + 1
      end
    end
  end
  if changed then
    table.sort(changed)
    local parts = {}
    for i = 1, math.min(#changed, 12) do
      local p = changed[i]
      parts[i] = p .. ': ' .. show(prev[p]) .. ' -> ' .. show(flat[p])
    end
    if #changed > 12 then parts[#parts + 1] = '+' .. (#changed - 12) .. ' more' end
    L(tag, 'id=%s sig=%d%s | %s', tostring(rec.id), G.id, extra or '', table.concat(parts, ' ; '))
    OT.changes = OT.changes + 1
  end
  return true
end

-- the objects that share a layout, round robin: a few per frame, more while I fire and for 3 s after a mark
local function sweep(s)
  local order = O.order
  local budget = (fire_down or now < O.busy_until) and SWEEP_BUSY or SWEEP_IDLE
  local cursor, done, looked, n = O.cursor, 0, 0, #order
  while done < budget and looked < n do
    if cursor > #order then cursor = 1 end
    local rec = order[cursor]
    if rec == nil then break end
    looked = looked + 1
    if rec.gone then
      table.remove(order, cursor)
    elseif rec.fast or (rec.aimed_until and now < rec.aimed_until) then
      cursor = cursor + 1                              -- read one by one, not here
    else
      sample_rec('GRP', s, rec, nil, false)
      done = done + 1
      cursor = cursor + 1
    end
  end
  O.cursor = cursor
end

local function count_pairs(t)
  local n = 0
  if type(t) == 'table' then for _ in pairs(t) do n = n + 1 end end
  return n
end

local function player_step()
  local s, peer = session_handles()
  if not s then return end
  if not O.session_logged then
    O.session_logged = true
    local host = C('GameSession.game_session_host', s)
    local who = 'unknown'
    if host == true then who = 'me' elseif host == false then who = 'someone else' elseif host ~= nil then who = (host == peer) and 'me' or 'someone else' end
    L('SESSION', 'peer=%s host=%s (%s) peers=%d other_peers=%d | chef: is_host=%s players=%s', type(peer), who, type(host),
      count_pairs(C('GameSession.peers', s)), count_pairs(C('GameSession.other_peers', s)),
      tostring(chef.is_host and chef.is_host()), tostring(chef.players and chef.players()))
  end
  if now >= O.next_census then
    O.next_census = now + 1.0
    census(s, peer)
  end
  describe_some(s)
  if now >= O.next or O.force then
    O.next, O.force = now + OBJ_PERIOD, false
    for _, rec in ipairs(O.singles) do
      if not rec.gone then sample_rec('OBJ', s, rec, nil, true) end
    end
  end
  if cfg.wide then sweep(s) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- stage 3: the unit under the crosshair and its game object. GameSession.unit_synchronizer and the UnitSynchronizer
-- lookups only read. The object of a unit I aim at is read four times a second while I fire, and once when the unit
-- enters its death state; one other unit every half second is looked up as well, to learn which object layout belongs to
-- which kind of unit. An object that is not mine is not read unless the "other players' objects" row is on.
-- ---------------------------------------------------------------------------------------------------------------------
local LK = { next = 0, next_census = 0, lookups = 0, found = 0, none = 0, foreign = 0, census_n = 0, sync = nil, sync_at = -100, pairs = {} }

local function link_reset()
  LK.census_n, LK.sync, LK.sync_at = 0, nil, -100
end

local function ensure_sync(s)
  if not LK.sync or now - LK.sync_at > 5 then
    LK.sync, LK.sync_at = C('GameSession.unit_synchronizer', s), now
    if LK.sync == nil and once('sync_failed') then L('LINK', 'GameSession.unit_synchronizer gave nothing') end
  end
  return LK.sync ~= nil
end

-- the game object of a followed unit: the id the synchronizer gives, the layout it has, the layout <-> kind note
local function link_unit(s, r)
  r.link_tries = (r.link_tries or 0) + 1
  if r.link_tries >= 3 then r.objid = false end        -- give up after three tries (set again below on success)
  if not chef.unit_alive(r.unit) then return end
  LK.lookups = LK.lookups + 1
  local id = C('UnitSynchronizer.unit_to_game_object_id', LK.sync, r.unit)
  if type(id) ~= 'number' then
    LK.none = LK.none + 1
    if LK.none <= 5 then L('LINK', 'no object for unit#%d kind=%s (%s)', r.id, r.kind:sub(1, 8), type(id)) end
    return
  end
  r.objid = id
  LK.found = LK.found + 1
  local rec = O.by_id[id]
  if rec and rec.G then
    r.objrec = rec
    local G = rec.G
    local K = U.kinds[r.kind]
    G.kinds[r.kind] = (G.kinds[r.kind] or 0) + 1
    if K then K.sigs[G.id] = (K.sigs[G.id] or 0) + 1 end
    local key = G.id .. '|' .. r.kind
    if not LK.pairs[key] then
      LK.pairs[key] = true
      L('SIGKIND', 'sig=%d kind=%s tier=%s object=%s', G.id, r.kind, tier_of(r.kind), tostring(id))
    end
  else
    LK.foreign = LK.foreign + 1
    if LK.foreign <= 5 then L('LINK', 'unit#%d kind=%s has object %s, which is not in my list (not read)', r.id, r.kind:sub(1, 8), tostring(id)) end
  end
end

local function follow_object(s, r)
  local rec = r.objrec
  if not rec or not rec.G or rec.gone then return end
  rec.aimed_until = now + 1.0
  if not rec.shown then
    rec.shown = true
    if O.shown < 60 then
      O.shown = O.shown + 1
      L('AIMOBJ', 'first look id=%s sig=%d unit#%d kind=%s | %s', tostring(rec.id), rec.G.id, r.id, r.kind:sub(1, 8),
        fields_text(rec.prev or {}))
    end
  end
  sample_rec('AIMOBJ', s, rec, string.format(' unit#%d kind=%s', r.id, r.kind:sub(1, 8)), true)
end

link_on_death = function(r)
  if not cfg.link then return end
  local s = session_handles()
  if not s or not ensure_sync(s) then return end
  if r.objid == nil then link_unit(s, r) end
  local rec = r.objrec
  if rec and rec.G and not rec.gone then
    sample_rec('AIMOBJ', s, rec, string.format(' death unit#%d kind=%s', r.id, r.kind:sub(1, 8)), true)
  end
end

local function link_step()
  if not (cfg.link and cam) then return end
  if now < LK.next then return end
  LK.next = now + LINK_PERIOD
  local s = session_handles()
  if not s or not ensure_sync(s) then return end
  -- the units under the crosshair: hit by the aim ray lately, or within 3 degrees
  local aiming = fire_down or (last_fire_up and now - last_fire_up < 2.0) or now < O.busy_until
  local c = {}
  for _, r in pairs(U.tracked) do
    if r.alive and not r.done and ((r.aim_t and now - r.aim_t < 0.6) or (r.ang and r.ang < 3 and r.d and r.d < 120)) then
      c[#c + 1] = r
    end
  end
  table.sort(c, function(a, b) return (a.ang or 99) < (b.ang or 99) end)
  for i = 1, math.min(#c, LINK_NEAR) do
    local r = c[i]
    if r.objid == nil then link_unit(s, r) end
    if aiming and r.objid then follow_object(s, r) end
  end
  -- one other unit every half second, the nearest not looked up yet
  if now >= LK.next_census and LK.census_n < LINK_CENSUS then
    LK.next_census = now + 0.5
    local best
    for _, r in pairs(U.tracked) do
      if r.alive and not r.done and r.objid == nil and r.sm == true and r.d and (not best or r.d < best.d) then best = r end
    end
    if best then
      LK.census_n = LK.census_n + 1
      link_unit(s, best)
    end
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
    parts[i] = string.format('%s#%d d=%.1f ang=%s alive=%s sm=%s st=%s%s', r.kind:sub(1, 8), r.id, r.d,
      r.ang and string.format('%.1f', r.ang) or '-', tostring(r.alive), tostring(r.sm), tostring(r.st), r.dying and ' DYING' or '')
  end
  return table.concat(parts, ' ; ')
end

local function mark(what)
  marks[what] = marks[what] + 1
  local deaths = {}
  for _, d in ipairs(recent_deaths) do
    if now - d.t <= 6 then deaths[#deaths + 1] = string.format('%s#%d:%.1fs', d.kind:sub(1, 8), d.id, now - d.t) end
  end
  emit('MARK', string.format('%s #%d fire=%s followed=%d deaths6s=[%s] near=[%s]', what:upper(), marks[what], since_fire(),
    U.tracked_n, table.concat(deaths, ' '), nearest_text(6)), true)
  O.force = true
  O.busy_until = now + 3
  if chef.notify then chef.notify('PROBE MARK ' .. what:upper() .. ' ' .. marks[what], 1.2, 255, 230, 90) end
end

local function input_step()
  local down = chef.mouse_down('left') == true
  if down and not fire_down then
    fire_down, fire_since, last_fire_down = true, now, now
    A.next = 0                                      -- (a tap lasts a tenth of a second: test the ray at once, at the moment of the shot)
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

-- aim: while the fire button is held (and for 1.5 s after), which followed units does the camera's ray go through (a box
-- test). A unit that is dying is left out: its body would keep the ray for the next target.
local function aim_step()
  if not (cfg.aim and cam and has('ray_box')) then return end
  if not (fire_down or (last_fire_up and now - last_fire_up < 1.5)) then return end
  if now < A.next then return end
  A.next = now + 0.12
  local from = { x = cam.x, y = cam.y, z = cam.z }
  local dir = { x = cam.fx, y = cam.fy, z = cam.fz }
  local c = {}
  for _, r in pairs(U.tracked) do
    if r.alive and not r.done and not r.dying and r.ang and r.ang < 10 and r.d and r.d < 160 then c[#c + 1] = r end
  end
  table.sort(c, function(a, b) return a.ang < b.ang end)
  local hits = {}
  for i = 1, math.min(#c, 6) do
    local r = c[i]
    local dist = chef.ray_box(from, dir, r.unit)
    if type(dist) == 'number' then
      r.aim_t, r.aim_dist = now, dist
      hits[#hits + 1] = string.format('%s#%d:%.1fm@%.1f', r.kind:sub(1, 8), r.id, dist, r.ang)
    end
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
  lines[#lines + 1] = string.format('units (all worlds): scans=%d kinds=%d spawned=%d lost-state-machine/alive-false=%d gone=%d bodies-skipped=%d | followed now=%d (%d without a state machine)',
    TOT.scans, TOT.kinds, TOT.spawned, TOT.deaths, TOT.gone, TOT.bodies, U.tracked_n, U.tracked_nosm)
  lines[#lines + 1] = string.format('death states: DEATH events=%d late=%d cancelled=%d learned=%d', TOT.dying, TOT.late, TOT.cancels, TOT.learned)
  lines[#lines + 1] = string.format('game objects (all worlds): lists=%d looked at first=%d layouts=%d reads=%d changes logged=%d gone=%d new=%d | listed now=%s most=%d',
    OT.census, OT.described, OT.sigs, OT.samples, OT.changes, OT.gone, OT.new, tostring(O.owned_n), OT.owned_max)
  lines[#lines + 1] = string.format('link: lookups=%d found=%d no-object=%d not-mine=%d | aim ray tests=%d with-hits=%d', LK.lookups, LK.found, LK.none, LK.foreign, A.samples, A.hits)
  lines[#lines + 1] = string.format('input: clicks=%d marks kill=%d hit=%d other=%d', clicks, marks.kill, marks.hit, marks.other)
  lines[#lines + 1] = string.format('rows: units=%s player=%s wide=%s aim=%s link=%s remote=%s', tostring(cfg.units), tostring(cfg.player),
    tostring(cfg.wide), tostring(cfg.aim), tostring(cfg.link), tostring(cfg.remote))
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
  lines[#lines + 1] = '## death states: kind  DEATH-events  cancelled  late  state-machine-lost-after-DEATH(n, mean seconds)  states(source)'
  local dk = {}
  for k, K in pairs(KINDS) do if K.death then dk[#dk + 1] = k end end
  table.sort(dk, function(a, b) return KINDS[a].dying > KINDS[b].dying end)
  for _, k in ipairs(dk) do
    local K = KINDS[k]
    local sts = {}
    for _, st in ipairs(sorted_keys(K.death)) do sts[#sts + 1] = st .. '(' .. K.death[st] .. ')' end
    lines[#lines + 1] = string.format('%s %5d %5d %5d  %4d %6s  %s', k, K.dying, K.cancels, K.late, K.lag_n,
      K.lag_n > 0 and string.format('%.2f', K.lag_sum / K.lag_n) or '-', table.concat(sts, ' '))
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## unit kinds seen: kind  last-count  max-count  mover  has-state-machine  deaths  gone  tier  ignored  object-layouts(sig:count)'
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
    -- 'false*': found not to move, being looked at again right now (idle units may start walking)
    local moves = (K.mover == nil and K.static_seen) and 'false*' or tostring(K.mover)
    local sg = {}
    for _, id in ipairs(sorted_keys(K.sigs)) do sg[#sg + 1] = id .. ':' .. K.sigs[id] end
    lines[#lines + 1] = string.format('%s %5d %5d  %-6s %-5s  %4d %4d  %-6s %-7s %s', kinds[i], K.n or 0, K.max, moves, tostring(K.sm), K.deaths, K.gone,
      tier_of(kinds[i]), K.ignore and tostring(K.ignore) or '-', table.concat(sg, ' '))
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = '## game object layouts: sig  members-now  ever  gone  reads  | fields that changed (count; m = muted)  | unit kinds tied to it (count)'
  local sigs = {}
  for _, G in pairs(SIGS) do sigs[#sigs + 1] = G end
  table.sort(sigs, function(a, b) return a.id < b.id end)
  for i = 1, math.min(#sigs, 120) do
    local G = sigs[i]
    local fields = {}
    for p, c in pairs(G.chg) do fields[#fields + 1] = { p, c } end
    table.sort(fields, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local ft = {}
    for j = 1, math.min(#fields, 10) do ft[j] = fields[j][1] .. ':' .. fields[j][2] .. (G.muted[fields[j][1]] and 'm' or '') end
    local kt = {}
    for _, k in ipairs(sorted_keys(G.kinds)) do kt[#kt + 1] = k:sub(1, 8) .. ':' .. G.kinds[k] end
    lines[#lines + 1] = string.format('sig=%d %4d %5d %4d %6d | %s | %s', G.id, G.n, G.total, G.gone, G.reads,
      #ft > 0 and table.concat(ft, ' ') or '-', #kt > 0 and table.concat(kt, ' ') or '-')
  end
  write_file('bfv_probe_summary.txt', lines)
  emit('SUM', string.format('scans=%d kinds=%d followed=%d deaths=%d dying=%d gone=%d objs=%s layouts=%d reads=%d changes=%d links=%d/%d clicks=%d marks=%d/%d/%d log=%dB',
    TOT.scans, TOT.kinds, U.tracked_n, TOT.deaths, TOT.dying, TOT.gone, tostring(O.owned_n), OT.sigs, OT.samples, OT.changes, LK.found, LK.lookups,
    clicks, marks.kill, marks.hit, marks.other, logged), true)
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
  toggle('units', 'Units: census and deaths', true, 'Follow moving units near you; log when they enter their death state, die or vanish.', 'What to record')
  toggle('player', 'My game objects: field changes', true, 'Log the network objects you own when a field changes.')
  toggle('wide', 'All of my game objects, not just the oldest 40', true, 'Reads every game object you own (a host owns all enemies) a few per frame. Reading only; light on the CPU.')
  toggle('aim', 'Aim ray tests while firing', true, 'While the left mouse button is held, log which followed units the camera ray goes through.')
  toggle('link', 'Unit under the crosshair <-> its game object', true, 'Looks up the game object of the unit you aim at (lookups only) and reads it while you fire. Objects of other players are not read.')
  toggle('remote', "Other players' game objects (MAY END THE GAME)", false, "Also reads objects owned by other players. That has ended the game for other mods, the loader then skips the call. Keep it off unless asked.")
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
  link_reset()
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
  safe('aim', aim_step)
  safe('link', link_step)
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
  local text = string.format('BFV PROBE %s  FOLLOWED %d  DEATHS %d  OBJECTS %s  LINKS %d  MARKS %d  LOG %dK%s', VERSION, U.tracked_n, TOT.dying,
    tostring(O.owned_n or '-'), LK.found, marks.kill + marks.hit + marks.other, math.floor(logged / 1024), capped and ' FULL' or '')
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
