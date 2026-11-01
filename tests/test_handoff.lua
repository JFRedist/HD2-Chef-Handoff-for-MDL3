-- Runs handoff/chef_handoff.lua in a small fake game and checks what it does and, as important, what it leaves alone.
--   lua5.1 tests/test_handoff.lua            (from the repository root)
-- The real Chef is exercised by tests/handoff_sim.sh; this one is the quick check of the addon's own logic.
local ADDON = os.getenv('HANDOFF_ADDON') or 'handoff/chef_handoff.lua'
local OUT = os.getenv('HANDOFF_TEST_OUT') or '/tmp/bfv_handoff_test'
local CORE = 'mods/chef_shared_loader/core_1'

local checks, failures = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if cond then print('  ok    ' .. msg) else failures = failures + 1; print('  FAIL  ' .. msg) end
end
local function read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end
local function lines(text) local n = 0; for _ in (text or ''):gmatch('[^\n]+') do n = n + 1 end; return n end

-- a fake game: globals, an engine with Application.can_get, a require that knows the core, a folder for APPDATA
local function game(opts)
  opts = opts or {}
  local dir = OUT .. '/' .. opts.name
  os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
  local base = dir .. '/A'                 -- APPDATA; the folder names are glued on with backslashes, as on Windows: on this
                                           -- machine the files come out as 'A\Arrowhead\Helldivers2\<name>' inside dir
  local G = { calls = {}, updates = 0, last_args = nil, required = {} }
  local env = {}
  for _, name in ipairs({ 'rawget', 'rawset', 'type', 'pcall', 'tostring', 'tonumber', 'ipairs', 'pairs', 'select', 'error',
                          'string', 'table', 'math' }) do env[name] = _G[name] end
  env._G = env
  env.os = { getenv = function(k) if k == 'APPDATA' then return base end end, date = os.date }
  env.io = { open = io.open }
  env.stingray = { Application = { can_get = function(kind, name)
    G.calls[#G.calls + 1] = 'can_get ' .. kind .. ' ' .. name
    if opts.can_get_error then error('boom') end
    return kind == 'lua' and name == CORE and opts.chef_installed ~= false
  end } }
  if opts.no_can_get then env.stingray.Application.can_get = nil end
  if opts.no_stingray then env.stingray = nil end
  -- require: the core is a fake Chef core: it takes the note, sets the read-only global, and makes its own update
  env.require = function(name)
    G.required[#G.required + 1] = name
    if opts.require_error then error('core failed: boom') end
    if name == CORE then
      G.note = env.ChefSharedLoaderHandoff
      env.ChefSharedLoaderHandoff = nil
      local before = env.update
      env.ChefSharedLoader = newproxy(true)                       -- (read-only and not a table, like the real one)
      getmetatable(env.ChefSharedLoader).__index = { version = '1.4.1', api = 3 }
      -- like Chef: its own update first, then the callback that was set before it started
      env.update = function(dt, ...) G.chef_updates = (G.chef_updates or 0) + 1; if before then return before(dt, ...) end end
      return true
    end
    error('module not found: ' .. tostring(name))
  end
  if opts.update ~= false then
    env.update = function(dt, a, b) G.updates = G.updates + 1; G.last_args = { dt, a, b }; return 'ret' end
  end
  if opts.on_update then
    env.CowboyBingusModLoader = { on_update = function(id, fn) G.on_update = { id = id, fn = fn } end }
  end
  if opts.chef_running then
    env.ChefSharedLoader = newproxy(true)
    getmetatable(env.ChefSharedLoader).__index = { version = '1.3.9', api = 3 }
  end
  if opts.mark then
    local f = io.open(base .. '\\Arrowhead\\Helldivers2\\chef_handoff_state.txt', 'w')
    f:write(opts.mark); f:close()
  end
  local chunk, err = loadfile(ADDON)
  assert(chunk, err)
  setfenv(chunk, env)
  G.env, G.dir = env, dir
  G.module = chunk()
  G.path = function(name) return base .. '\\Arrowhead\\Helldivers2\\' .. name end
  function G.frames(seconds, dt)
    dt = dt or 1 / 60
    for _ = 1, math.floor(seconds / dt + 0.5) do G.ret = env.update(dt, 'a', 'b') end
  end
  return G
end

print('== the normal case: Chef installed, MDL3 above it')
local G = game{ name = 'normal' }
check(type(G.module) == 'table' and G.module.version == '0.1.0', 'the addon returns its module table')
check(G.module.state == 'waiting', 'it hooks the game\'s update global and waits')
G.frames(5)
check(#G.required == 0, 'nothing is handed off in the first 5 seconds (the game, MDL3 and its addons settle first)')
check(G.updates == 300, 'the original update runs every frame meanwhile (' .. G.updates .. ')')
check(G.last_args[1] == 1 / 60 and G.last_args[2] == 'a' and G.last_args[3] == 'b', 'with its arguments passed through')
G.frames(2)
check(#G.required == 1 and G.required[1] == CORE, 'then Chef\'s core is required, once')
check(type(G.note) == 'table' and G.note.phase == 'init' and G.note.from == 'MDL3 chef_handoff 0.1.0',
  'with the note Chef\'s documentation asks for: phase init, and who is handing off')
check(G.env.ChefSharedLoaderHandoff == nil, 'the note is gone afterwards')
check(G.module.state == 'chef started', 'the state says Chef started')
local log = read(G.path('chef_handoff.log'))
check(log and log:find('Chef Shared Loader 1.4.1 started (api 3)', 1, true), 'the log says so, with the version read from Chef\'s read-only global')
check(log and log:find('CowboyBingusModLoader = nil', 1, true) and log:find('MDL3 = nil', 1, true), 'the log lists the loader tables it found (none in this fake game)')
check((read(G.path('chef_handoff_state.txt')) or ''):find('^ok 0.1.0'), 'the state file says ok')
local before = G.updates
G.frames(2)
check(G.updates - before == 120 and (G.chef_updates or 0) >= 100, 'after the hand-off the chain goes on: Chef\'s update runs and calls the one set before it (' .. G.updates - before .. ')')
check(#G.required == 1, 'no second hand-off')
check(lines(log) < 20, 'the log stays short (' .. lines(log) .. ' lines)')

print('== Chef not installed')
G = game{ name = 'nochef', chef_installed = false }
G.frames(8)
check(#G.required == 0 and G.module.state == 'chef not installed', 'nothing is required; the state says Chef is not installed')
check((read(G.path('chef_handoff.log')) or ''):find('not installed', 1, true), 'the log says so')
check(read(G.path('chef_handoff_state.txt')) == nil, 'no state file is written')
check(G.updates == 480, 'the game\'s update is untouched')

print('== Chef already running (MDL3 handed off itself, or Chef is the top loader)')
G = game{ name = 'running', chef_running = true }
G.frames(8)
check(#G.required == 0 and G.module.state == 'chef already running', 'nothing is done')
check((read(G.path('chef_handoff.log')) or ''):find('running already (version 1.3.9)', 1, true), 'and the log names the version that is running')

print('== the last launch ended during a hand-off')
G = game{ name = 'crashed', mark = 'attempt 0.1.0\n' }
G.frames(8)
check(#G.required == 0 and G.module.state == 'skipped after a crash', 'the hand-off is not tried again')
check((read(G.path('chef_handoff.log')) or ''):find('Delete that file', 1, true), 'the log says how to try again')
G = game{ name = 'crashed_ok', mark = 'ok 0.1.0\n' }
G.frames(8)
check(#G.required == 1, 'an "ok" mark from the last launch does not stop it')

print('== the core fails to load')
G = game{ name = 'fails', require_error = true }
G.frames(8)
check(G.module.state == 'hand-off failed', 'the state says it failed')
check((read(G.path('chef_handoff_state.txt')) or ''):find('^failed'), 'the state file says failed (not "attempt": the next launch tries again)')
check(G.env.ChefSharedLoaderHandoff == nil, 'the note is cleared')
check(G.updates == 480, 'the game\'s update chain is not broken')
check((read(G.path('chef_handoff.log')) or ''):find('core failed: boom', 1, true), 'the log has the reason')

print('== odd games')
G = game{ name = 'nocanget', no_can_get = true }
G.frames(8)
check(#G.required == 0 and G.module.state == 'no Application.can_get', 'no Application.can_get: nothing is done, and it says why')
G = game{ name = 'nostingray', no_stingray = true }
G.frames(8)
check(#G.required == 0 and G.module.state == 'no Application.can_get', 'no stingray table at all: the same')
G = game{ name = 'canget_error', can_get_error = true }
G.frames(8)
check(#G.required == 0 and G.updates == 480, 'can_get raising an error does not break the game\'s update (' .. tostring(G.module.state) .. ')')
G = game{ name = 'noupdate', update = false }
check(G.module.state == 'no hook', 'no update global and no on_update: it says it cannot hook')
G = game{ name = 'onupdate', update = false, on_update = true }
check(G.module.state == 'waiting' and G.on_update and G.on_update.id == 'chef_handoff', 'no update global but an on_update: it hooks through that')
for _ = 1, 480 do G.on_update.fn(1 / 60) end
check(#G.required == 1, '... and the hand-off happens from there')
G = game{ name = 'bad_dt' }
for _ = 1, 600 do G.env.update(nil) end
check(#G.required == 1, 'a frame without a usable dt counts as 1/60 s: the hand-off still comes')
G = game{ name = 'huge_dt' }
G.env.update(50)
check(#G.required == 0, 'one huge dt (a loading hitch) does not count as seconds')

print('== loaded twice')
G = game{ name = 'twice' }
local chunk = loadfile(ADDON)
setfenv(chunk, G.env)
local again = chunk()
check(again == G.module, 'the second load returns the first module')
G.frames(8)
check(#G.required == 1 and G.updates == 480, 'and hooked nothing a second time')

print('== no folder to write to')
G = game{ name = 'nofolder' }
G.env.os.getenv = function() return nil end
G.frames(8)
check(#G.required == 1, 'without APPDATA the hand-off still happens (it just has nowhere to log)')

print(string.format('\n%d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
