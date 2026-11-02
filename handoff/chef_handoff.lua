-- HD2-Addon: mods/jfredist/chef_handoff
-- Chef hand-off for MDL3: starts Chef Shared Loader from inside another mod loader.
--
-- The game runs one `boot`: the one in the highest patch. With MDL3 above Chef Shared Loader the game runs MDL3's
-- boot, and Chef, and every mod made for it (HUDdle, Treasure Radar ...), never starts. Chef's documentation ("For
-- other loaders") says how a loader hands the game to it: set the note `ChefSharedLoaderHandoff` and `require` its core.
-- This addon does that from MDL3's side, once the game is running (a few seconds in), so both loaders work:
-- MDL3 keeps the mods made for it, Chef starts the mods made for Chef. It touches nothing else. Without Chef installed
-- it does nothing; if Chef is running already it does nothing. It writes chef_handoff.log (and one tiny state file) in
-- %APPDATA%\Arrowhead\Helldivers2, the folder Chef and MDL3 use.
--
-- One more thing, found in the first real run: MDL3 starts EVERY addon with an HD2-Addon header, Chef's too, with
-- nothing to run on. A Chef mod that survives that (Treasure Radar) is then "started by another loader" as far as Chef
-- can tell (package.loaded has it), so Chef skips it and it never runs. Before the hand-off this addon reads the headers
-- of the Lua resources in the game's patch files (the way Chef does), finds the addons made for Chef (the ones that take
-- their helpers from the chunk's argument, or ask for Chef in a header line) and takes them off package.loaded (and off
-- the loader's own list, when it has one), so that Chef starts them properly.
--
-- The Chef side is the documented one (Chef Shared Loader by Th3chef, docs/MODDING.md, "For other loaders": "Everything
-- here is free to copy into your loader as it is"). Nothing of Chef's code is in this file.
local VERSION = '0.2.0'
local CORE = 'mods/chef_shared_loader/core_1'    -- Chef's core, a Lua resource without an HD2- header: no loader starts it as a mod
local DELAY = 6.0                                -- seconds of game time (the frames' dt added up) before the hand-off
local KEY = '__CHEF_HANDOFF_ADDON'

-- one copy per Lua state (a loader that starts addons twice, a reload ...)
local existing = rawget(_G, KEY)
if type(existing) == 'table' then return existing end
local M = { version = VERSION, state = 'loaded' }
rawset(_G, KEY, M)

local sr = rawget(_G, 'stingray')
local clock = 0

-- ---------------------------------------------------------------------------------------------------------------------
-- files: the log and the state mark
-- ---------------------------------------------------------------------------------------------------------------------
local function folder()
  local ok, base = pcall(function() return type(os) == 'table' and type(os.getenv) == 'function' and os.getenv('APPDATA') end)
  if not ok or type(base) ~= 'string' or base == '' then return nil end
  return base .. '\\Arrowhead\\Helldivers2\\'
end

local function write_file(name, mode, text)
  local dir = folder()
  if not dir or type(io) ~= 'table' or type(io.open) ~= 'function' then return false end
  local ok, f = pcall(io.open, dir .. name, mode)
  if not ok or not f then return false end
  pcall(f.write, f, text)
  pcall(f.close, f)
  return true
end

local function read_file(name)
  local dir = folder()
  if not dir or type(io) ~= 'table' or type(io.open) ~= 'function' then return nil end
  local ok, f = pcall(io.open, dir .. name, 'r')
  if not ok or not f then return nil end
  local ok2, text = pcall(f.read, f, '*a')
  pcall(f.close, f)
  return ok2 and text or nil
end

local logged = 0
local function log(fmt, ...)
  if logged > 60 then return end                 -- a few lines a launch: this is not a place for floods
  logged = logged + 1
  local ok, text = pcall(string.format, fmt, ...)
  if not ok then text = tostring(fmt) end
  local stamp = '?'
  pcall(function() stamp = os.date('%H:%M:%S') end)
  write_file('chef_handoff.log', 'a', string.format('%s %6.1f s | %s\n', stamp, clock, text))
end

-- ---------------------------------------------------------------------------------------------------------------------
-- what is there when this addon starts (to tell, from the log, how MDL3 starts addons)
-- ---------------------------------------------------------------------------------------------------------------------
local function describe(name)
  local v = rawget(_G, name)
  if v == nil then return 'nil' end
  if type(v) ~= 'table' then return type(v) end
  local keys, n = {}, 0
  for k, x in pairs(v) do
    n = n + 1
    if n <= 24 then keys[#keys + 1] = tostring(k) .. ':' .. type(x):sub(1, 1) end
  end
  table.sort(keys)
  return string.format('table(%d: %s%s)', n, table.concat(keys, ' '), n > 24 and ' ...' or '')
end

-- a new launch starts its log fresh
write_file('chef_handoff.log', 'w', '')
log('chef_handoff %s loaded; the game\'s update is a %s', VERSION, type(rawget(_G, 'update')))
for _, name in ipairs({ 'CowboyBingusModLoader', 'HD2ModLoader', 'MDL3', 'MDL', 'HD2Data', 'ModOptionsMenu', 'ChefSharedLoader' }) do
  log('  %s = %s', name, describe(name))
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Chef's addons that MDL3 has already "started"
-- ---------------------------------------------------------------------------------------------------------------------
-- The game's patch files (data/9ba626afa44a3aa3.patch_N): a 72-byte header (0xF0000011, the type count, the entry count),
-- 32-byte type rows, 80-byte entries (id, type, offset ... u64, then the size as u32 at byte 56). A Lua resource is
-- 8 bytes (length, 2) and then its text. Only the first 16 KB of each Lua resource are read, only in patches of 4096
-- entries or fewer (a mod's own patch is a few; bigger ones are built game data).
local LUA_TYPE = '\226\023\209\044\250\141\078\161'           -- a14e8dfa2cd117e2 as 8 bytes, little endian
local FALLBACK = { 'mods/chef/treasure_radar', 'mods/rosensterner/minimal_hud' }   -- when the patch files cannot be read

local function u32(str, i)
  local a, b, c, d = str:byte(i, i + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function u64(str, i)
  local lo, hi = u32(str, i), u32(str, i + 4)
  if not (lo and hi) then return nil end
  return lo + hi * 4294967296
end

-- one patch file: fills `made` with the addons made for Chef; returns false when there is no such file
local function scan_patch(n, made, stats)
  local f = io.open('data/9ba626afa44a3aa3.patch_' .. n, 'rb')
  if not f then return false end
  local ok, err = pcall(function()
    local head = f:read(72)
    if not head or #head < 72 or u32(head, 1) ~= 4026531857 then return end            -- 0xF0000011
    local ntypes, nentries = u32(head, 5), u32(head, 9)
    if not ntypes or not nentries or ntypes > 64 or nentries > 4096 then return end
    local size = ntypes * 32 + nentries * 80
    local toc = f:read(size)
    if not toc or #toc < size then return end
    stats.files = stats.files + 1
    for i = 0, nentries - 1 do
      local at = 1 + ntypes * 32 + i * 80
      if toc:sub(at + 8, at + 15) == LUA_TYPE then
        local off, len = u64(toc, at + 16), u32(toc, at + 56)
        if off and len and len > 16 and len < 4194304 then
          f:seek('set', off)
          local data = f:read(math.min(len, 16384))
          local src = data and data:sub(9) or ''
          if src:sub(1, 3) == '\239\187\191' then src = src:sub(4) end                  -- a BOM
          local name = src:match('^%-%- HD2%-Addon:%s*([%w_%-/]+)')
          if name then
            stats.addons = stats.addons + 1
            -- (`local chef = ...` as code at the start of a line, not mentioned in a comment; or the header line asking for Chef)
            if name ~= 'mods/jfredist/chef_handoff'
               and (src:find('\nlocal%s+chef%s*=%s*%.%.%.') or src:find('\n%-%- HD2%-Requires:%s*chef%-shared%-loader')) then
              made[name] = true
            end
          end
        end
      end
    end
  end)
  pcall(f.close, f)
  if not ok then stats.errors = stats.errors + 1 end
  return true
end

-- every patch file, within a time budget; returns the set of names, and what it saw
local function scan_chef_addons()
  local made, stats = {}, { files = 0, addons = 0, errors = 0 }
  if type(io) ~= 'table' or type(io.open) ~= 'function' then return made, stats, 'no io.open' end
  local t0 = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or 0
  local misses = 0
  for n = 0, 400 do
    if scan_patch(n, made, stats) then misses = 0 else misses = misses + 1 end
    if misses >= 8 then break end
    if type(os.clock) == 'function' and os.clock() - t0 > 0.5 then return made, stats, 'stopped after 0.5 s' end
  end
  stats.ms = type(os.clock) == 'function' and math.floor((os.clock() - t0) * 1000 + 0.5) or 0
  return made, stats
end

-- The reading of the patch files is done a second before the hand-off, so that the two do not land in one frame.
local scanned = nil
local function prepare_scan()
  if scanned then return end
  local okp, made, stats, note = pcall(scan_chef_addons)
  if not okp then made, stats, note = {}, { files = 0, addons = 0, errors = 0 }, tostring(made) end
  scanned = { made = made, stats = stats, note = note }
end

-- takes the addons made for Chef off package.loaded (they are not running: they were started without Chef)
local function release_chef_addons()
  prepare_scan()
  local made, stats, note = scanned.made, scanned.stats, scanned.note
  local names = {}
  for name in pairs(made) do names[#names + 1] = name end
  if #names == 0 and stats.files == 0 then
    for _, name in ipairs(FALLBACK) do names[#names + 1] = name end                   -- the patch files could not be read
    note = (note and note .. '; ' or '') .. 'the patch files could not be read: using the built-in list'
  end
  table.sort(names)
  log('patch files read: %d (%d addons, %d made for Chef, %d read errors)%s%s', stats.files, stats.addons, #names, stats.errors,
    stats.ms and (' in ' .. stats.ms .. ' ms') or '', note and ('; ' .. note) or '')
  local pk = rawget(_G, 'package')
  local loaded = type(pk) == 'table' and pk.loaded or nil
  if type(loaded) ~= 'table' then log('package.loaded is missing: nothing to take them off') return end
  local freed = {}
  for _, name in ipairs(names) do
    local v = loaded[name]
    -- (require's own placeholder, a userdata, is a require that failed or never finished: Chef starts that mod anyway)
    if v ~= nil and type(v) ~= 'userdata' then
      loaded[name] = nil
      freed[#freed + 1] = name
    end
  end
  -- Bingus-style loaders keep a `modules` table of name -> 'loaded' / 'loading' / 'load failed: ...', and Chef also asks it.
  -- Say what MDL3's holds (for the log), and mark the Chef addons in it as what they are: not running.
  local lines, freed_m = {}, {}
  for _, key in ipairs({ 'CowboyBingusModLoader', 'HD2ModLoader' }) do
    local L = rawget(_G, key)
    local mods = type(L) == 'table' and rawget(L, 'modules') or nil
    if type(mods) == 'table' then
      local count = 0
      for name, st in pairs(mods) do
        count = count + 1
        if count <= 40 then lines[#lines + 1] = tostring(name) .. '=' .. tostring(st):sub(1, 40) end
      end
      for _, name in ipairs(names) do
        local st = rawget(mods, name)
        if st == 'loaded' or st == 'loading' then
          mods[name] = 'load failed: made for Chef Shared Loader'
          freed_m[#freed_m + 1] = name
        end
      end
      lines[#lines + 1] = '(' .. key .. '.modules: ' .. count .. ' entries)'
    end
  end
  if #lines > 0 then
    table.sort(lines)
    log('the loader\'s modules table before: %s', table.concat(lines, ' '))
  end
  if #freed_m > 0 then log('marked as not running in the loader\'s modules table: %s', table.concat(freed_m, ' ')) end
  log('made for Chef: %s', #names > 0 and table.concat(names, ' ') or '(none)')
  log('taken off package.loaded, so that Chef starts them: %s', #freed > 0 and table.concat(freed, ' ') or '(none were on it)')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the hand-off
-- ---------------------------------------------------------------------------------------------------------------------
-- (Chef's global is read-only and may be a proxy rather than a table: just index it)
local function field(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

local function handoff()
  local running = rawget(_G, 'ChefSharedLoader')
  if running ~= nil then
    M.state = 'chef already running'
    log('Chef Shared Loader is running already (version %s): nothing to do', tostring(field(running, 'version')))
    return
  end
  local A = type(sr) == 'table' and sr.Application or nil
  if type(A) ~= 'table' or type(A.can_get) ~= 'function' then
    M.state = 'no Application.can_get'
    log('stingray.Application.can_get is missing: cannot tell whether Chef is installed')
    return
  end
  local okc, has = pcall(A.can_get, 'lua', CORE)
  if not okc or has ~= true then
    M.state = 'chef not installed'
    log('Chef Shared Loader is not installed (can_get(\'lua\', \'%s\') = %s): nothing to do', CORE, tostring(okc and has or has))
    return
  end
  -- A launch that ended during an earlier hand-off left its mark: do not try again until the mark is deleted.
  local mark = read_file('chef_handoff_state.txt')
  if type(mark) == 'string' and mark:find('^attempt') then
    M.state = 'skipped after a crash'
    log('the last launch ended during the hand-off (chef_handoff_state.txt says "%s"): not trying again. Delete that file to try once more.',
      (mark:gsub('%s+$', '')))
    return
  end
  local okr, errr = pcall(release_chef_addons)
  if not okr then log('could not look for Chef addons already started by MDL3: %s', tostring(errr)) end
  write_file('chef_handoff_state.txt', 'w', 'attempt ' .. VERSION .. '\n')
  rawset(_G, 'ChefSharedLoaderHandoff', { from = 'MDL3 chef_handoff ' .. VERSION, phase = 'init' })
  log('handing off: require(\'%s\') with the note { from = ..., phase = \'init\' } (the game has called init long ago)', CORE)
  local ok, err = pcall(require, CORE)
  rawset(_G, 'ChefSharedLoaderHandoff', nil)
  local chef = rawget(_G, 'ChefSharedLoader')
  if ok and chef ~= nil then
    M.state = 'chef started'
    write_file('chef_handoff_state.txt', 'w', 'ok ' .. VERSION .. '\n')
    log('Chef Shared Loader %s started (api %s). Its own log is chef_loader.log.',
      tostring(field(chef, 'version')), tostring(field(chef, 'api')))
  else
    M.state = 'hand-off failed'
    write_file('chef_handoff_state.txt', 'w', 'failed ' .. VERSION .. '\n')
    log('the hand-off did not start Chef (require %s: %s; ChefSharedLoader = %s)', tostring(ok), tostring(err), tostring(chef))
  end
end

-- the first frames after the delay
local function tick(dt)
  clock = clock + ((type(dt) == 'number' and dt > 0 and dt < 1) and dt or 1 / 60)
  if clock >= DELAY - 1 and not scanned then
    local ok, err = pcall(prepare_scan)
    if not ok then scanned = { made = {}, stats = { files = 0, addons = 0, errors = 1 }, note = tostring(err) } end
  end
  if clock < DELAY then return end
  M.state = 'handing off'
  local ok, err = pcall(handoff)
  if not ok then
    M.state = 'error'
    log('error in the hand-off: %s', tostring(err))
  end
end

-- hooked the way the BF5 MDL3 build hooks: chain the game's update global. After the hand-off Chef takes the global
-- over and runs this one as "the callbacks the boot script set before it started me", so the chain goes on.
local prev = rawget(_G, 'update')
if type(prev) == 'function' then
  M.state = 'waiting'
  rawset(_G, 'update', function(dt, ...)
    if M.state == 'waiting' then tick(dt) end
    return prev(dt, ...)
  end)
else
  local L = rawget(_G, 'CowboyBingusModLoader')
  if type(L) == 'table' and type(L.on_update) == 'function' then
    M.state = 'waiting'
    pcall(L.on_update, 'chef_handoff', function(dt) if M.state == 'waiting' then tick(dt) end end)
    log('no update global: hooked through CowboyBingusModLoader.on_update')
  else
    M.state = 'no hook'
    log('no update global and no on_update: cannot run the hand-off')
  end
end

return M
