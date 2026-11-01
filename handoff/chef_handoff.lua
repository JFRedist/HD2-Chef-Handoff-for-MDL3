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
-- The Chef side is the documented one (Chef Shared Loader by Th3chef, docs/MODDING.md, "For other loaders": "Everything
-- here is free to copy into your loader as it is"). Nothing of Chef's code is in this file.
local VERSION = '0.1.0'
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
