-- HD2-Addon: mods/jfredist/chef_handoff
-- Chef hand-off for MDL3: starts Chef Shared Loader from inside another mod loader.
--
-- The game runs one `boot`: the one in the highest patch. With MDL3 above Chef Shared Loader the game runs MDL3's
-- boot, and Chef, and every mod made for it (HUDdle, Treasure Radar ...), never starts. Chef's documentation ("For
-- other loaders") says how a loader hands the game to it: set the note `ChefSharedLoaderHandoff` and `require` its core.
-- This addon does that from MDL3's side, once the game is running (a few seconds in), so both loaders work:
-- MDL3 keeps the mods made for it, Chef starts the mods made for Chef. It touches nothing else. Without Chef installed
-- it does nothing; if Chef is running already it does nothing. It writes chef_handoff.log (the last launch's is kept as
-- chef_handoff.previous.log) and one tiny state file in %APPDATA%\Arrowhead\Helldivers2, the folder Chef and MDL3 use.
--
-- One more thing, found in the first real run: MDL3 starts EVERY addon with an HD2-Addon header, Chef's too, with
-- nothing to run on. A Chef mod that survives that (Treasure Radar) is then "started by another loader" as far as Chef
-- can tell (package.loaded has it), so Chef skips it and it never runs. Before the hand-off this addon reads the headers
-- of the Lua resources in the game's patch files (the way Chef does), finds the addons made for Chef (the ones that take
-- their helpers from the chunk's argument, or ask for Chef in a header line) and takes them off package.loaded (and off
-- the loader's own list, when it has one), so that Chef starts them properly. The mods made for Rat's Shared Loader (which
-- Chef runs as a boot script) lose what MDL3's start of them left in package.loaded, so that Rat starts them.
--
-- And one more, found with Chef 1.5 (and true of 1.4 as well): the callbacks the game has (init, update, render, shutdown: MDL3's
-- and its mods' chains) are kept by Chef when it is handed the game, and it runs them itself after its own, as "a boot script's".
-- From 1.4.0, when the watchdog came, it does that under its hang watchdog: a call that runs on for over 3 s counts as a hang
-- and the chain is switched off, MDL3 with it. So Chef is not given them: they are taken off the game's global table while Chef loads and put back behind Chef's own (Chef's
-- first, then MDL3's, which the game calls as before). The game's global table, not this addon's _G: MDL3 runs every addon in a
-- sandbox of its own (the real run of 0.2.2 showed it), where update and shutdown are the addon's own. 0.2.1 and 0.2.2 took the
-- callbacks off that sandbox, so Chef 1.5.1 in the game still found MDL3's own update and shutdown, and ran MDL3's update under its
-- watchdog. The log says which table was used, what was on it before and after, and whether the update chain then runs once a
-- frame or twice (Chef running it too).
--
-- The Chef side is the documented one (Chef Shared Loader by Th3chef, docs/MODDING.md, "For other loaders": "Everything
-- here is free to copy into your loader as it is"). Nothing of Chef's code is in this file.
local VERSION = '0.2.6'
local CORE = 'mods/chef_shared_loader/core_1'    -- Chef's core, a Lua resource without an HD2- header: no loader starts it as a mod
local DELAY = 6.0                                -- seconds of game time (the frames' dt added up) before the hand-off
local KEY = '__CHEF_HANDOFF_ADDON'
local KEYS = { 'init', 'update', 'render', 'shutdown' }   -- the game's callbacks
local STATE, LOG, PREV_LOG = 'chef_handoff_state.txt', 'chef_handoff.log', 'chef_handoff.previous.log'

local sr = rawget(_G, 'stingray')
local clock = 0
-- CPU time, when there is a clock for it (not every loader gives its mods os, or os.clock)
local has_cpu = type(os) == 'table' and type(os.clock) == 'function'
local cpu = has_cpu and os.clock or function() return 0 end

-- ---------------------------------------------------------------------------------------------------------------------
-- files: the log and the state mark
-- ---------------------------------------------------------------------------------------------------------------------
local function folder()
  local ok, base = pcall(function() return type(os) == 'table' and type(os.getenv) == 'function' and os.getenv('APPDATA') end)
  if not ok or type(base) ~= 'string' or base == '' then return nil end
  return base .. '\\Arrowhead\\Helldivers2\\'
end

-- true, or false and why not
local function write_file(name, mode, text)
  local dir = folder()
  if not dir then return false, 'no APPDATA folder' end
  if type(io) ~= 'table' or type(io.open) ~= 'function' then return false, 'no io.open' end
  local ok, f, err = pcall(io.open, dir .. name, mode)
  if not ok then return false, tostring(f) end
  if not f then return false, tostring(err) end
  local okw, w, werr = pcall(f.write, f, text)
  pcall(f.close, f)
  if not okw then return false, tostring(w) end
  if not w then return false, tostring(werr) end
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

-- (never raises: it is called after require too, where nothing may stop the mark and the callbacks from being put right)
local logged = 0
local function log(fmt, ...)
  if logged > 60 then return end                 -- a few lines a launch: this is not a place for floods
  logged = logged + 1
  local ok, text = pcall(string.format, fmt, ...)
  if not ok then text = tostring(fmt) end
  pcall(function()
    local stamp = '?'
    pcall(function() stamp = os.date('%H:%M:%S') end)
    write_file(LOG, 'a', string.format('%s %6.1f s | %s\n', tostring(stamp), clock, tostring(text)))
  end)
end

-- a value as text, whatever it is (an error object, Chef's read-only global ...)
local function str(v)
  local ok, s = pcall(tostring, v)
  if ok and type(s) == 'string' then return s end
  return '(' .. type(v) .. ')'
end

local same = rawget(_G, 'rawequal')              -- (not every loader gives its mods the whole base library)
if type(same) ~= 'function' then same = function(a, b) return a == b end end

-- The game's own global table: the one the game reads init, update, render and shutdown from, and the one Chef's core gets as its
-- globals when it is required (the running thread's globals: getfenv(0)). Under MDL3 3.0.0-dev.29 an addon runs in a sandbox of
-- its own, as the real run of 0.2.2 showed: its _G is not that table, and update and shutdown there are the addon's own, which MDL3
-- calls from its own. The callbacks Chef keeps are the ones on the game's table, so that is where they are taken off. It is used
-- only when it holds the engine's stingray table; anywhere else this addon's _G is the global table and is used, as before.
-- Returns the table, a rawget and a rawset for it (its own: a sandbox may give its addons others), and what it is, for the log.
local function game_globals()
  local gf = rawget(_G, 'getfenv')
  if type(gf) ~= 'function' then return _G, rawget, rawset, 'this addon\'s _G (no getfenv here)' end
  local ok, g = pcall(gf, 0)
  if not ok or type(g) ~= 'table' then return _G, rawget, rawset, 'this addon\'s _G (getfenv(0) gave no table)' end
  if same(g, _G) then return _G, rawget, rawset, 'this addon\'s _G (it is the global table)' end
  local okr, st = pcall(rawget, g, 'stingray')
  if not okr or type(st) ~= 'table' then
    return _G, rawget, rawset, 'this addon\'s _G (getfenv(0) is another table, without the engine\'s stingray in it)'
  end
  local rg, rs = rawget(g, 'rawget'), rawget(g, 'rawset')
  if type(rg) ~= 'function' or type(rs) ~= 'function' then rg, rs = rawget, rawset end
  return g, rg, rs, 'getfenv(0) (this addon\'s _G is a sandbox of its own, not the global table)'
end

-- One copy per Lua state. The mark of it is kept on the game's own global table, put there with that table's own rawset, not on
-- this addon's _G: a loader that starts the addon again (a reload) gives it a new _G, and under MDL3 3.0.0-dev.43 a rawset on _G
-- is MDL3's own, which puts the value on the game's table and takes it off again when MDL3 stops the addon (0.2.5 kept it there:
-- a copy started again found nothing and started the log afresh). A second load in the same _G is the same copy. A copy started
-- again in another _G while the first one still waits for its hand-off takes over (the first one may not be called any more);
-- once the first one has done its part, the new one does nothing.
local GT0, RG0, RS0 = game_globals()
local okx, existing = pcall(RG0, GT0, KEY)
if not okx or type(existing) ~= 'table' then existing = nil end
if existing and (same(existing.env, _G) or existing.state ~= 'waiting') then
  if not same(existing.env, _G) then
    log('chef_handoff %s loaded again, in another _G (a loader started it again): the first copy has done its part (%s), so this one does nothing',
      VERSION, str(existing.state))
  end
  return existing
end
local M = { version = VERSION, state = 'loaded', env = _G }
if existing then existing.state = 'replaced' end
if not pcall(RS0, GT0, KEY, M) then pcall(rawset, _G, KEY, M) end

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

-- a function as the log shows it: its address (the same function has the same one all launch) and where it was defined
local function where(f)
  local d = rawget(_G, 'debug')
  if type(d) ~= 'table' or type(d.getinfo) ~= 'function' then return '' end
  local ok, info = pcall(d.getinfo, f, 'S')
  if not ok or type(info) ~= 'table' then return '' end
  if info.what == 'C' then return ' [C]' end
  local src = tostring(info.short_src or info.source or '?')
  if #src > 60 then src = '...' .. src:sub(-57) end
  return string.format(' [%s:%s]', src, tostring(info.linedefined or '?'))
end

local function fn_text(f)
  if type(f) ~= 'function' then return f == nil and 'nil' or type(f) end
  local ok, s = pcall(tostring, f)
  return (ok and type(s) == 'string' and (s:gsub('^function:%s*', '')) or 'function') .. where(f)
end

-- the four callbacks as they are on a table now (this addon's _G unless T, RG are given); taken: a table of the ones taken off,
-- to mark them where they are back
local function callbacks_text(taken, T, RG)
  T, RG = T or _G, RG or rawget
  local parts = {}
  for _, k in ipairs(KEYS) do
    local f = RG(T, k)
    local t = fn_text(f)
    if taken and f ~= nil and same(f, taken[k]) then t = t .. ' (the one taken off)' end
    parts[#parts + 1] = k .. '=' .. t
  end
  return table.concat(parts, ' ')
end

-- the globals' table and require as this addon sees them: a loader that guards the callbacks, or loads a module its own
-- way, shows here
local function mt_text(t)
  local gm = rawget(_G, 'getmetatable')
  if type(gm) ~= 'function' then return 'unknown (no getmetatable here)' end
  local ok, mt = pcall(gm, t)
  if not ok then return 'getmetatable failed' end
  if mt == nil then return 'none' end
  if type(mt) ~= 'table' then return 'protected (' .. type(mt) .. ')' end
  local fields = {}
  for _, name in ipairs({ '__index', '__newindex', '__metatable' }) do
    local v = rawget(mt, name)
    if v ~= nil then fields[#fields + 1] = name .. '=' .. (type(v) == 'function' and fn_text(v) or type(v)) end
  end
  return #fields > 0 and table.concat(fields, ' ') or 'a table, no __index or __newindex'
end

local function env_text()
  local parts = {}
  parts[#parts + 1] = 'metatable of _G: ' .. mt_text(_G)
  local gf = rawget(_G, 'getfenv')
  if type(gf) == 'function' then
    local ok0, g0 = pcall(gf, 0)
    local okc, gc = pcall(gf, where)                 -- (a function of this file: its environment is this addon's)
    if ok0 then
      parts[#parts + 1] = string.format('_G is the global table: %s, this addon runs in it: %s',
        same(g0, _G) and 'yes' or 'no', okc and (same(g0, gc) and 'yes' or 'no') or '?')
      if type(g0) == 'table' and not same(g0, _G) then parts[#parts + 1] = 'metatable of the global table: ' .. mt_text(g0) end
    end
  end
  parts[#parts + 1] = 'require: ' .. fn_text(rawget(_G, 'require'))
  local pk = rawget(_G, 'package')
  local loaders = type(pk) == 'table' and rawget(pk, 'loaders') or nil
  if type(loaders) == 'table' then
    local l = {}
    for i = 1, 8 do
      if loaders[i] == nil then break end
      l[#l + 1] = fn_text(loaders[i])
    end
    parts[#parts + 1] = string.format('package.loaders: %s', #l > 0 and table.concat(l, ', ') or 'none')
  end
  return table.concat(parts, '; ')
end

if existing then
  log('chef_handoff %s loaded again, in another _G, while the first copy was still waiting for its hand-off (a loader started it again): this copy takes over',
    VERSION)
else
  -- A new launch starts its log afresh. The last launch's is kept as chef_handoff.previous.log: it tells a launch that went on
  -- past its hand-off from one that ended in it (see the state mark, below), and it is the one to send when that launch went wrong.
  -- Not when Chef is running already: no hand-off comes then, and this may be a copy Chef started as one of its own mods (Chef
  -- on top, or a loader that handed off before starting its addons), which Chef lets read only the logs it wrote itself.
  local okc, chef_now = pcall(function() return RG0(GT0, 'ChefSharedLoader') or _G.ChefSharedLoader end)
  if not (okc and chef_now ~= nil) then
    local old = read_file(LOG)
    if type(old) == 'string' and old ~= '' then write_file(PREV_LOG, 'w', old) end
  end
  write_file(LOG, 'w', '')
  log('chef_handoff %s loaded; the game\'s update is a %s', VERSION, type(rawget(_G, 'update')))
  for _, name in ipairs({ 'CowboyBingusModLoader', 'HD2ModLoader', 'MDL3', 'MDL', 'HD2Data', 'ModOptionsMenu', 'ChefSharedLoader' }) do
    log('  %s = %s', name, describe(name))
  end
  log('  the game\'s callbacks: %s', callbacks_text())
  local GT, RG = game_globals()
  if GT ~= _G then log('  the game\'s callbacks (its global table): %s', callbacks_text(nil, GT, RG)) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Chef's addons that MDL3 has already "started"
-- ---------------------------------------------------------------------------------------------------------------------
-- The game's patch files (data/9ba626afa44a3aa3.patch_N): a 72-byte header (0xF0000011, the type count, the entry count),
-- 32-byte type rows, 80-byte entries (id, type, offset ... u64, then the size as u32 at byte 56). A Lua resource is
-- 8 bytes (length, 2) and then its text. The first 16 KB of each Lua resource under 4 MB are read, only in patches of 4096
-- entries or fewer (a mod's own patch is a few; bigger ones are built game data). An addon that does not show in them that
-- it is made for Chef is read to its end: `local chef = ...` can come late (NarrowHUD 1.0.6 has 220 KB of data before it).
local LUA_TYPE = '\226\023\209\044\250\141\078\161'           -- a14e8dfa2cd117e2 as 8 bytes, little endian
local FALLBACK = { 'mods/chef/treasure_radar', 'mods/rosensterner/minimal_hud' }   -- when the patch files cannot be read
local HEAD = 16384                                             -- bytes of each Lua resource read first
local LOCAL_CHEF = '\nlocal%s+chef%s*=%s*%.%.%.'               -- `local chef = ...` as code at the start of a line

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

-- A mod made for Rat's Shared Loader: `-- @loader rat` among the comment lines the file starts with, in its first 4096 bytes,
-- and no other `@loader` line there (the rule Rat's Shared Loader and Chef go by)
local function rat_mark(src)
  local head, at, marked = src:sub(1, 4096), 1, false
  while true do
    local line, nxt = head:match('^(%-%-[^\n]*)\n()', at)
    if not line then return marked end
    if line:find('^%-%- @loader%s') or line == '-- @loader' then
      if not line:find('^%-%- @loader%s+rat%s*$') then return false end
      marked = true
    end
    at = nxt
  end
end

-- one patch file: fills `made` with the addons made for Chef and `rats` with those made for Rat's Shared Loader; returns false
-- when there is no such file
local function scan_patch(n, made, stats, rats)
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
          local data = f:read(math.min(len, HEAD))
          local src = data and data:sub(9) or ''
          if src:sub(1, 3) == '\239\187\191' then src = src:sub(4) end                  -- a BOM
          local name = src:match('^%-%- HD2%-Addon:%s*([%w_%-/]+)')
          if name then
            stats.addons = stats.addons + 1
            if name ~= 'mods/jfredist/chef_handoff' then
              -- (`local chef = ...` as code, not mentioned in a comment; or the header line asking for Chef, which is among the
              -- first lines, so it is looked for in the first 16 KB only)
              local chef_mod = src:find(LOCAL_CHEF) or src:find('\n%-%- HD2%-Requires:%s*chef%-shared%-loader')
              if not chef_mod and #data < len then
                local rest = f:read(len - #data)
                if rest then
                  stats.deep = stats.deep + 1
                  -- (with the last line of the first 16 KB in front, for a `local chef = ...` that the 16 KB mark cuts in two)
                  chef_mod = ((src:match('\n[^\n]*$') or '') .. rest):find(LOCAL_CHEF)
                end
              end
              if chef_mod then made[name] = true end
              if rat_mark(src) then rats[name] = true end
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

-- every patch file, within a time budget; returns the sets of names (Chef's, Rat's), and what it saw. The numbers are read
-- until 8 in a row are missing (0.2.4 stopped at patch_400, and a player with 529 patch files had Chef mods above it)
local function scan_chef_addons()
  local made, stats, rats = {}, { files = 0, addons = 0, errors = 0, deep = 0 }, {}
  if type(io) ~= 'table' or type(io.open) ~= 'function' then return made, stats, 'no io.open', rats end
  local t0 = cpu()
  local misses, n = 0, 0
  while misses < 8 do
    if scan_patch(n, made, stats, rats) then misses = 0 else misses = misses + 1 end
    if has_cpu and cpu() - t0 > 0.5 then return made, stats, 'stopped after 0.5 s, at patch_' .. n, rats end
    n = n + 1
  end
  stats.ms = has_cpu and math.floor((cpu() - t0) * 1000 + 0.5) or 0
  return made, stats, nil, rats
end

-- The reading of the patch files is done a second before the hand-off, so that the two do not land in one frame.
local scanned = nil
local function prepare_scan()
  if scanned then return end
  local okp, made, stats, note, rats = pcall(scan_chef_addons)
  if not okp then made, stats, note, rats = {}, { files = 0, addons = 0, errors = 0 }, tostring(made), {} end
  scanned = { made = made, stats = stats, note = note, rats = rats or {} }
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
  log('patch files read: %d (%d addons, %d made for Chef, %d read errors)%s%s%s', stats.files, stats.addons, #names, stats.errors,
    stats.ms and (' in ' .. stats.ms .. ' ms') or '',
    (stats.deep or 0) > 0 and ('; ' .. stats.deep .. ' addon(s) read past the first 16 KB') or '', note and ('; ' .. note) or '')
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
  -- Mods made for Rat's Shared Loader (HD2 Transmog ...): MDL3 starts them too, with no Rat, and leaves an entry in
  -- package.loaded: require's own placeholder when the mod failed, or Rat's "not started" mark (a table with a shared_loader
  -- field) that the HD2 Lua Runtime's core returns when it finds no Rat. Chef runs Rat's Shared Loader as one of its boot
  -- scripts after the hand-off, and that loader starts its mods with require: a placeholder made it skip the mod as started
  -- elsewhere (0.2.4 with Transmog 1.1.2), and the mark came straight back from require, so the runtime never ran under it and
  -- Transmog found no `hd2rt` (the first build of 0.2.5). Both are taken off; a value a mod left after it really ran stays.
  -- MDL3 also puts a loader of its own for each of them in package.preload, which require asks before the game's resources:
  -- it hands back what MDL3's start gave (the mark, or the mod's error again), so with package.loaded cleared the mods still
  -- never ran under Rat (the second build: Transmog's error carried MDL3's own traceback, the core "loaded" in a millisecond).
  -- That loader is taken off too, so that require loads the mod's own resource; the log says where it was defined.
  local rat_names, cleared, unhooked = {}, {}, {}
  for name in pairs(scanned.rats) do rat_names[#rat_names + 1] = name end
  if #rat_names > 0 then
    table.sort(rat_names)
    local preload = pk.preload
    for _, name in ipairs(rat_names) do
      local v = loaded[name]
      if type(v) == 'userdata' or (type(v) == 'table' and rawget(v, 'shared_loader') ~= nil) then
        loaded[name] = nil
        cleared[#cleared + 1] = name
      end
      local p = type(preload) == 'table' and preload[name] or nil
      if p ~= nil then
        preload[name] = nil
        unhooked[#unhooked + 1] = name .. ' (' .. fn_text(p) .. ')'
      end
    end
    log('made for Rat\'s Shared Loader: %s; what MDL3\'s start of them left (require\'s placeholder, Rat\'s "not started" mark) '
      .. 'taken off, so that it starts them: %s', table.concat(rat_names, ' '), #cleared > 0 and table.concat(cleared, ' ') or '(none had one)')
    log('their loaders in package.preload taken off, so that require loads their own code: %s',
      #unhooked > 0 and table.concat(unhooked, ', ') or '(none had one)')
  end
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

-- ---------------------------------------------------------------------------------------------------------------------
-- the game's callbacks: kept away from Chef, put back behind Chef's own
-- ---------------------------------------------------------------------------------------------------------------------
local SLOW = 0.5                                     -- seconds of CPU time in one call of the chain worth a line in the log
local COUNT_FRAMES = 600                             -- frames after the hand-off over which the update chain's runs are counted

-- Empty stand-ins, used instead of taking the callbacks off when the game's table guards the keys it does not have (a __newindex,
-- or a metatable it hides): Chef sets its own callbacks with plain assignments, and on a missing key such a guard could send them
-- elsewhere. With a stand-in on each key the assignments land on the table; Chef keeps the stand-ins, which do nothing.
local STANDIN = {}
for _, k in ipairs(KEYS) do STANDIN[k] = function() end end

-- does the table guard new keys? (a __newindex, or a metatable that hides itself)
local function guards_new_keys(T)
  local gm = rawget(_G, 'getmetatable')
  if type(gm) ~= 'function' then return false end
  local ok, mt = pcall(gm, T)
  if not ok then return true end
  if mt == nil then return false end
  if type(mt) ~= 'table' then return true end
  return rawget(mt, '__newindex') ~= nil
end

-- takes the callbacks off the game's global table T (RG, RS: its rawget and rawset), or puts a stand-in on each of the four keys
-- (standins; on the empty ones too, so that every callback Chef sets lands on the table): what was there goes into saved, one by
-- one (so that a failure half-way still knows what to put back), and saved is returned
local function stash_callbacks(T, RG, RS, standins, saved)
  for _, k in ipairs(KEYS) do
    local f = RG(T, k)
    if type(f) == 'function' then saved[k] = f end
    if standins then RS(T, k, STANDIN[k]) elseif type(f) == 'function' then RS(T, k, nil) end
  end
  return saved
end

local slow_lines = 0
local function note_slow(key, took)
  if slow_lines >= 5 then return end
  slow_lines = slow_lines + 1
  log('one call of the game\'s %s chain (MDL3 and its mods) took %d ms of CPU time', key, math.floor(took * 1000 + 0.5))
end

local function finish(key, t0, ...)
  local took = cpu() - t0
  if took > SLOW then note_slow(key, took) end
  return ...
end

-- How many times the game's update chain runs a frame once Chef has the game. This addon's own hook (below) is called by that
-- chain (a link of it, or under MDL3 one of the addon updates MDL3's update calls), so it is counted however the chain is called:
-- once a frame is from behind Chef's update (below), as it should be; twice means Chef runs the chain as well, which it does only
-- if it kept it (its log's "running the callbacks ... set before it started me").
M.chain_runs = 0
local chain_base, chef_updates = 0, 0
local function count_frame(...)
  chef_updates = chef_updates + 1
  if chef_updates == COUNT_FRAMES then
    local runs = M.chain_runs - chain_base
    local verdict
    if runs == 0 then
      verdict = 'this addon\'s hook is not in the chain: cannot tell'
    elseif runs <= COUNT_FRAMES * 1.1 then
      verdict = 'once a frame: Chef does not run it itself'
    elseif runs >= COUNT_FRAMES * 1.9 and runs <= COUNT_FRAMES * 2.1 then
      verdict = 'TWICE a frame: Chef runs it as well (it kept it)'
    else
      verdict = 'neither once nor twice a frame'
    end
    log('the game\'s update chain ran %d times in the first %d frames after the hand-off: %s', runs, COUNT_FRAMES, verdict)
  end
  return ...
end

-- Chef's own callback first, then the chain that was there before, as Chef's runs the callbacks it keeps, but outside Chef's watchdog
local function behind(chef_fn, old, key)
  local errors = 0
  local count = key == 'update'
  return function(...)
    local ok, err = pcall(chef_fn, ...)
    if not ok then
      errors = errors + 1
      if errors <= 3 then log('Chef\'s %s raised an error: %s', key, tostring(err)) end
    end
    if count then return count_frame(finish(key, cpu(), old(...))) end
    return finish(key, cpu(), old(...))
  end
end

-- put the callbacks back on T: behind Chef's own when Chef started, as they were when it did not. (init: the game called MDL3's
-- long ago and does not call it again, Chef's own stays.)
local function restore_callbacks(T, RG, RS, saved, chef_started)
  local kept, back = {}, {}
  for _, k in ipairs(KEYS) do
    local old = saved[k]
    local now = RG(T, k)
    local standin = now == STANDIN[k]                   -- (Chef did not set one of its own there)
    if standin then now = nil end
    if old == nil then
      if standin then RS(T, k, nil) end                 -- (a stand-in on a key that had nothing, and Chef set nothing there)
    elseif chef_started and k == 'init' then
      if standin then RS(T, k, old) end                 -- (no stand-in is left behind; the game does not call init again)
    elseif chef_started and type(now) == 'function' then
      RS(T, k, behind(now, old, k))
      kept[#kept + 1] = k
    else
      RS(T, k, old)
      back[#back + 1] = k
    end
  end
  if #kept > 0 then log('the game\'s %s now run behind Chef\'s own (Chef\'s first, then the game\'s)', table.concat(kept, ', ')) end
  if #back > 0 then log('put back as they were: %s', table.concat(back, ', ')) end
end

-- is a debug hook set on this thread? (Chef's hang watchdog and a loader's own budget both use one; the log says which it is)
local function hook_state()
  local d = rawget(_G, 'debug')
  if type(d) ~= 'table' or type(d.gethook) ~= 'function' then return 'unknown (no debug.gethook here)' end
  local ok, h, m, c = pcall(d.gethook)
  if not ok then return 'unknown (debug.gethook failed)' end
  if h == nil then return 'none' end
  return string.format('%s (mask "%s", count %s)', tostring(h), tostring(m or ''), tostring(c or 0))
end

-- what f gives, or what went wrong, as text (for log lines that must not raise)
local function safe(f, ...)
  local ok, v = pcall(f, ...)
  if ok then return v end
  return 'could not tell: ' .. str(v)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the state mark
-- ---------------------------------------------------------------------------------------------------------------------
-- chef_handoff_state.txt says "attempt <version> <time>" while Chef loads, then "ok <version>" or "failed <version>". A launch
-- that finds "attempt" there takes the last one for one that ended in the hand-off (the game closed or crashed while Chef loaded)
-- and does not hand off, so that a crash in Chef's load does not come back at every launch.
-- 0.2.5 wrote "ok" only once the callbacks were back and the log lines written, and a player on Chef Shared Loader 1.5.3 and MDL3
-- 3.0.0-dev.43 found "attempt" left after every launch that worked (issue #4): every launch after it skipped the hand-off. So the
-- mark is written as soon as require is back, before anything else, and read back; one that did not land is written again on
-- the next frames. The log's line right after require names the attempt by its time, and the next launch, which finds "attempt"
-- with that time, reads the last launch's log (chef_handoff.previous.log): with that line in it, that launch went on past its
-- hand-off and the hand-off goes ahead. A mark left by another version of this addon gets one more try too.
local function back_key(stamp) return 'back from require (attempt ' .. tostring(stamp or '?') .. ')' end

local function launch_stamp()
  local ok, s = pcall(function() return os.date('%Y-%m-%dT%H:%M:%S') end)
  if ok and type(s) == 'string' and s:find('^%d%d%d%d%-%d%d%-%d%dT') then return s end
  return nil
end

-- writes the mark and reads it back: true, or false and why not
local function put_mark(text)
  local ok, why = write_file(STATE, 'w', text)
  if not ok then return false, why end
  local back = read_file(STATE)
  if type(back) ~= 'string' or (back:gsub('%s+$', '')) ~= (text:gsub('%s+$', '')) then
    return false, 'it reads back as ' .. (type(back) == 'string' and string.format('%q', back:sub(1, 40)) or 'nothing')
  end
  return true
end

local function settle(started)
  local ok, why = put_mark((started and 'ok ' or 'failed ') .. VERSION .. '\n')
  if ok then M.mark_done = true end
  return ok, why
end

-- Chef's global, on the game's table or (where there is no other) on this addon's _G
local function chef_global(GT, RG)
  local ok, v = pcall(RG, GT, 'ChefSharedLoader')
  if ok and v ~= nil then return v end
  ok, v = pcall(rawget, _G, 'ChefSharedLoader')
  if ok then return v end
  return nil
end

-- On the frames after a hand-off whose mark did not land (a write that failed, or an error that cut the hand-off short after the
-- "attempt"): written again every 30 frames, 20 times, as the frame finds it ("ok" if Chef is running).
local late = { wait = 0, tries = 0 }
local function settle_late()
  if late.wait > 0 then late.wait = late.wait - 1 return end
  late.tries = late.tries + 1
  local GT, RG = game_globals()
  local running = chef_global(GT, RG) ~= nil
  local ok, why = settle(running)
  if ok then
    log('chef_handoff_state.txt written on a later frame (try %d): %s', late.tries,
      running and 'ok (Chef is running)' or 'failed (Chef is not running)')
  elseif late.tries >= 20 then
    M.mark_done = true                           -- (no more tries)
    log('chef_handoff_state.txt could not be written in %d tries (%s): it still says "attempt". The next launch reads this log ' ..
      '(as chef_handoff.previous.log) to tell that this one went on', late.tries, str(why))
  else
    late.wait = 30
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- the hand-off
-- ---------------------------------------------------------------------------------------------------------------------
local function handoff()
  local GT, RG, RS, which = game_globals()
  local running = chef_global(GT, RG)
  if running ~= nil then
    M.state = 'chef already running'
    log('Chef Shared Loader is running already (version %s): nothing to do', str(field(running, 'version')))
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
    log('Chef Shared Loader is not installed (can_get(\'lua\', \'%s\') = %s): nothing to do', CORE, str(okc and has or has))
    return
  end
  -- A launch that ended during an earlier hand-off left its mark: do not try again until the mark is deleted (unless the last
  -- launch's log shows that the hand-off it names came back, or the mark is another version's).
  local mark = read_file(STATE)
  if type(mark) == 'string' and mark:find('^attempt') then
    local shown = (mark:gsub('%s+$', ''))
    local mver, mstamp = mark:match('^attempt%s+(%S+)%s*(%S*)')
    local prev = read_file(PREV_LOG)
    if mstamp and mstamp ~= '' and type(prev) == 'string' and prev:find(back_key(mstamp), 1, true) then
      log('chef_handoff_state.txt says "%s", but %s says that hand-off came back from require: that launch went on (the mark ' ..
        'after it did not land). Handing off.', shown, PREV_LOG)
    elseif mver and mver ~= VERSION then
      log('chef_handoff_state.txt says "%s": the last launch ended during a hand-off by chef_handoff %s. This is %s: trying once ' ..
        'more (if this launch ends in the hand-off too, the next one does not try).', shown, mver, VERSION)
    else
      M.state = 'skipped after a crash'
      log('the last launch ended during the hand-off (chef_handoff_state.txt says "%s"): not trying again. Delete that file to try once more.',
        shown)
      return
    end
  end
  local okr, errr = pcall(release_chef_addons)
  if not okr then log('could not look for Chef addons already started by MDL3: %s', str(errr)) end
  local sandboxed = GT ~= _G
  local where_cb = sandboxed and ' (its global table)' or ''
  log('handing off: require(\'%s\') with the note { from = ..., phase = \'init\' } (the game has called init long ago)', CORE)
  log('the game\'s global table: %s', which)
  log('debug hook before: %s', safe(hook_state))
  log('around the globals: %s', safe(env_text))
  log('the game\'s callbacks before%s: %s', where_cb, safe(callbacks_text, nil, GT, RG))
  local standins = guards_new_keys(GT)
  if standins then
    log('the game\'s global table guards the keys it does not have: the callbacks are replaced by empty stand-ins while Chef loads, not taken off (Chef keeps the stand-ins)')
  end
  local stamp = launch_stamp()
  write_file(STATE, 'w', 'attempt ' .. VERSION .. (stamp and (' ' .. stamp) or '') .. '\n')
  M.attempted, late.wait = true, 1               -- (from the next frame on, a mark that did not land is written again)
  -- From here until Chef has read the globals nothing runs but rawset and require: no log line, no file (whatever put a callback
  -- back on the game's table in that time would show it to Chef). The callbacks come off the game's own table, where Chef's core
  -- reads them, not off this addon's _G: under MDL3 that is a sandbox of its own (0.2.1 and 0.2.2 took them off the sandbox, and
  -- Chef 1.5.1 in the game still found MDL3's update and shutdown).
  local saved, still = {}, {}
  local oks, errs = pcall(function()
    stash_callbacks(GT, RG, RS, standins, saved)
    for _, k in ipairs(KEYS) do
      local v = RG(GT, k)
      if standins and v ~= STANDIN[k] or not standins and v ~= nil and saved[k] ~= nil then still[#still + 1] = k end
    end
    RS(GT, 'ChefSharedLoaderHandoff', { from = 'MDL3 chef_handoff ' .. VERSION, phase = 'init' })
  end)
  if not oks then
    for _, k in ipairs(KEYS) do
      local okg, v = pcall(RG, GT, k)
      if saved[k] ~= nil or (okg and v ~= nil and v == STANDIN[k]) then pcall(RS, GT, k, saved[k]) end
    end
    pcall(RS, GT, 'ChefSharedLoaderHandoff', nil)
    M.state = 'hand-off failed'
    pcall(settle, false)
    log('taking the game\'s callbacks off failed (%s): they are back as they were, and Chef is not handed the game', str(errs))
    return
  end
  local ok, err = pcall(require, CORE)
  -- From here on each step is protected or cannot raise: the mark is written and the callbacks go back whatever happens.
  local okn, errn = pcall(RS, GT, 'ChefSharedLoaderHandoff', nil)
  local chef = chef_global(GT, RG)
  local started = ok and chef ~= nil
  local okm, wrote, why = pcall(settle, started)
  M.state = started and 'chef started' or 'hand-off failed'
  if started then
    log('%s: Chef Shared Loader %s started (api %s). Its own log is chef_loader.log.', back_key(stamp),
      str(field(chef, 'version')), str(field(chef, 'api')))
  else
    log('%s: the hand-off did not start Chef (require %s: %s; ChefSharedLoader = %s)', back_key(stamp), str(ok), str(err), str(chef))
  end
  if not (okm and wrote) then
    late.wait = 30
    log('chef_handoff_state.txt could not be written (%s): trying again on the next frames', str(okm and why or wrote))
  end
  if not okn then log('taking the note off the game\'s global table failed: %s', str(errn)) end
  if #still > 0 then
    local on = sandboxed and 'the game\'s global table' or 'the globals'
    if standins then log('not replaced by the stand-ins on %s: %s', on, table.concat(still, ', '))
    else log('still on %s right after they were taken off: %s', on, table.concat(still, ', ')) end
  end
  log('debug hook after: %s', safe(hook_state))
  log('the game\'s callbacks after Chef loaded%s: %s', where_cb, safe(callbacks_text, saved, GT, RG))
  chain_base = M.chain_runs
  local okb, errb = pcall(restore_callbacks, GT, RG, RS, saved, started)
  if not okb then
    log('putting the callbacks back failed: %s', str(errb))
    for _, k in ipairs(KEYS) do
      local okg, v = pcall(RG, GT, k)
      if not okg or v == nil or v == STANDIN[k] then pcall(RS, GT, k, saved[k]) end
    end
  end
end

-- the first frames after the delay
local function tick()
  if clock >= DELAY - 1 and not scanned then
    local ok, err = pcall(prepare_scan)
    if not ok then scanned = { made = {}, stats = { files = 0, addons = 0, errors = 1 }, note = str(err), rats = {} } end
  end
  if clock < DELAY then return end
  M.state = 'handing off'
  local ok, err = pcall(handoff)
  if not ok then
    M.state = 'error'
    log('error in the hand-off: %s', str(err))
  end
end

-- every frame: the clock (game time, the frames' dt added up; one huge dt, a loading hitch, counts as one frame), the hand-off
-- once it is due, and a mark that did not land
local function frame(dt)
  clock = clock + ((type(dt) == 'number' and dt > 0 and dt < 1) and dt or 1 / 60)
  if M.state == 'waiting' then tick() end
  if M.attempted and not M.mark_done then pcall(settle_late) end
end

-- hooked the way the BF5 MDL3 build hooks: chain the game's update global. At the hand-off the chain is taken off the global
-- while Chef loads and put back behind Chef's own update (see stash_callbacks, restore_callbacks), so the chain goes on.
local prev = rawget(_G, 'update')
if type(prev) == 'function' then
  M.state = 'waiting'
  rawset(_G, 'update', function(dt, ...)
    M.chain_runs = M.chain_runs + 1
    frame(dt)
    return prev(dt, ...)
  end)
else
  local L = rawget(_G, 'CowboyBingusModLoader')
  if type(L) == 'table' and type(L.on_update) == 'function' then
    M.state = 'waiting'
    pcall(L.on_update, 'chef_handoff', function(dt) frame(dt) end)
    log('no update global: hooked through CowboyBingusModLoader.on_update')
  else
    M.state = 'no hook'
    log('no update global and no on_update: cannot run the hand-off')
  end
end

return M
