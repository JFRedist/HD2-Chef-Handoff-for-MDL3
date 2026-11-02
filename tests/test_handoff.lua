-- Runs handoff/chef_handoff.lua in a small fake game and checks what it does and, as important, what it leaves alone.
--   lua5.1 tests/test_handoff.lua            (from the repository root)
-- The real Chef is exercised by tests/handoff_sim.sh; this one is the quick check of the addon's own logic.
local ADDON = os.getenv('HANDOFF_ADDON') or 'handoff/chef_handoff.lua'
local OUT = os.getenv('HANDOFF_TEST_OUT') or '/tmp/bfv_handoff_test'
local CORE = 'mods/chef_shared_loader/core_1'

local checks, failures = 0, 0
local function slurp(path) local f = io.open(path, 'r'); if not f then return nil end; local t = f:read('*a'); f:close(); return t end
local VER = (slurp(ADDON) or ''):match("local VERSION = '([^']+)'") or '?'
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
  local G = { calls = {}, updates = 0, last_args = nil, required = {}, t = 0 }
  local env = {}
  for _, name in ipairs({ 'rawget', 'rawset', 'type', 'pcall', 'tostring', 'tonumber', 'ipairs', 'pairs', 'select', 'error',
                          'string', 'table', 'math' }) do env[name] = _G[name] end
  env._G = env
  env.os = { getenv = function(k) if k == 'APPDATA' then return base end end, date = os.date }
  local real_open = io.open
  env.io = { open = function(path, mode)
    local rel = type(path) == 'string' and path:match('^data/(.*)$')
    if rel then                                     -- the game's patch files: a folder of fixtures, or none
      G.data_first = G.data_first or G.t
      if opts.data == false or not opts.data then return nil, 'no such file' end
      return real_open(opts.data .. '/data/' .. rel, mode)
    end
    return real_open(path, mode)
  end }
  if opts.io_error then env.io.open = function() error('boom') end end
  env.os.clock = os.clock
  env.package = { loaded = opts.loaded or {} }
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
    G.required_at = G.t
    if opts.require_error then error('core failed: boom') end
    if name == CORE then
      G.note = env.ChefSharedLoaderHandoff
      G.loaded_at_require = {}
      for k, v in pairs(env.package.loaded) do G.loaded_at_require[k] = v end
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
  if opts.modules then env.CowboyBingusModLoader = { modules = opts.modules } end
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
    for _ = 1, math.floor(seconds / dt + 0.5) do G.t = G.t + dt; G.ret = env.update(dt, 'a', 'b') end
  end
  return G
end

print('== the normal case: Chef installed, MDL3 above it')
local G = game{ name = 'normal' }
check(type(G.module) == 'table' and G.module.version == VER, 'the addon returns its module table')
check(G.module.state == 'waiting', 'it hooks the game\'s update global and waits')
G.frames(5)
check(#G.required == 0, 'nothing is handed off in the first 5 seconds (the game, MDL3 and its addons settle first)')
check(G.updates == 300, 'the original update runs every frame meanwhile (' .. G.updates .. ')')
check(G.last_args[1] == 1 / 60 and G.last_args[2] == 'a' and G.last_args[3] == 'b', 'with its arguments passed through')
G.frames(2)
check(#G.required == 1 and G.required[1] == CORE, 'then Chef\'s core is required, once')
check(type(G.note) == 'table' and G.note.phase == 'init' and G.note.from == 'MDL3 chef_handoff ' .. VER,
  'with the note Chef\'s documentation asks for: phase init, and who is handing off')
check(G.env.ChefSharedLoaderHandoff == nil, 'the note is gone afterwards')
check(G.module.state == 'chef started', 'the state says Chef started')
local log = read(G.path('chef_handoff.log'))
check(log and log:find('Chef Shared Loader 1.4.1 started (api 3)', 1, true), 'the log says so, with the version read from Chef\'s read-only global')
check(log and log:find('CowboyBingusModLoader = nil', 1, true) and log:find('MDL3 = nil', 1, true), 'the log lists the loader tables it found (none in this fake game)')
check((read(G.path('chef_handoff_state.txt')) or ''):sub(1, #VER + 3) == 'ok ' .. VER, 'the state file says ok')
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
G = game{ name = 'crashed', mark = 'attempt ' .. VER .. '\n' }
G.frames(8)
check(#G.required == 0 and G.module.state == 'skipped after a crash', 'the hand-off is not tried again')
check((read(G.path('chef_handoff.log')) or ''):find('Delete that file', 1, true), 'the log says how to try again')
G = game{ name = 'crashed_ok', mark = 'ok ' .. VER .. '\n' }
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

print('== Chef addons that MDL3 has already "started" (Treasure Radar in the first real run)')
local FIX = OUT .. '/fixtures'
os.execute('rm -rf "' .. FIX .. '" && mkdir -p "' .. FIX .. '"')
assert(os.execute('python3 -I tests/fixtures/handoff/make_patches.py "' .. FIX .. '" > /dev/null') == 0, 'make_patches.py failed')
local ALL = { 'radar_like', 'probe_like', 'mdl3_like', 'late_chef', 'huge_chef', 'filler_0', 'garbage_chef', 'comment_mention' }
local function marked()
  local t = {}
  for _, n in ipairs(ALL) do t['mods/test/' .. n] = true end
  t['mods/jfredist/chef_handoff'] = true
  return t
end
G = game{ name = 'release', data = FIX, loaded = marked() }
G.frames(8)
local at = G.loaded_at_require or {}
check(#G.required == 1, 'the hand-off still happens')
check(at['mods/test/radar_like'] == nil, 'a Chef addon without an HD2-Requires line (`local chef = ...`) is taken off package.loaded before Chef is asked to start')
check(at['mods/test/probe_like'] == nil, 'one with the HD2-Requires: chef-shared-loader line is too')
check(at['mods/test/late_chef'] == nil, 'one whose `local chef = ...` comes after a long comment (still in the first 16 KB) is too')
check(at['mods/test/mdl3_like'] == true, 'an addon made for MDL3 (no chef in it) stays')
check(at['mods/test/huge_chef'] == true, 'a Lua resource over 4 MB is never read (the BF5 build is 6 MB): it stays')
check(at['mods/test/filler_0'] == true, 'a patch with thousands of entries (built game data) is skipped: its addons stay')
check(at['mods/test/garbage_chef'] == true, 'a file that has a patch\'s layout but not its magic number is not read')
local rlog = read(G.path('chef_handoff.log')) or ''
check(at['mods/test/comment_mention'] == true, 'an addon that only mentions chef in comments is not taken for a Chef addon')
check(at['mods/jfredist/chef_handoff'] == true, 'the hand-off addon itself (whose text talks about chef) is never taken for one')
check(rlog:find('patch files read: 4 (6 addons, 3 made for Chef, 0 read errors)', 1, true), 'the log says what was read: 4 patch files, 6 addons, 3 of them made for Chef')
check(rlog:find('made for Chef: mods/test/late_chef mods/test/probe_like mods/test/radar_like', 1, true), 'and which')
check(rlog:find('taken off package.loaded, so that Chef starts them: mods/test/late_chef mods/test/probe_like mods/test/radar_like', 1, true), 'and which were taken off the list')

G = game{ name = 'modules', data = FIX, loaded = marked(),
          modules = { ['mods/test/radar_like'] = 'loaded', ['mods/test/probe_like'] = 'loading', ['mods/test/mdl3_like'] = 'loaded',
                      ['mods/x/other'] = 'load failed: boom' } }
G.frames(8)
local mods = G.env.CowboyBingusModLoader.modules
check(mods['mods/test/radar_like'] == 'load failed: made for Chef Shared Loader' and mods['mods/test/probe_like'] == 'load failed: made for Chef Shared Loader',
  'in a Bingus-style loader\'s modules table the Chef addons ("loaded", "loading") are marked as not running')
check(mods['mods/test/mdl3_like'] == 'loaded' and mods['mods/x/other'] == 'load failed: boom', 'and nothing else in it is touched')
rlog = read(G.path('chef_handoff.log')) or ''
check(rlog:find("marked as not running in the loader's modules table: mods/test/probe_like mods/test/radar_like", 1, true), 'the log says which')
check(rlog:find('(CowboyBingusModLoader.modules: 4 entries)', 1, true) and rlog:find('mods/test/mdl3_like=loaded', 1, true), 'and what the table held before')

check(G.data_first and G.data_first >= 4.9 and G.data_first <= 5.3 and G.required_at >= 5.9,
  'the patch files are read a second before the hand-off (read at ' .. string.format('%.1f', G.data_first or -1) .. ' s, hand-off at ' .. string.format('%.1f', G.required_at or -1) .. ' s), not in the same frame')

local placeholder = newproxy(true)
G = game{ name = 'placeholder', data = FIX, loaded = { ['mods/test/radar_like'] = placeholder } }
G.frames(8)
check((G.loaded_at_require or {})['mods/test/radar_like'] == placeholder, 'require\'s own placeholder (a userdata: a failed require) is left alone; Chef starts that mod anyway')

G = game{ name = 'nodata', loaded = { ['mods/chef/treasure_radar'] = true, ['mods/rosensterner/minimal_hud'] = true, ['mods/codex/hd2_data_hub'] = true } }
G.frames(8)
at = G.loaded_at_require or {}
check(#G.required == 1 and at['mods/chef/treasure_radar'] == nil and at['mods/rosensterner/minimal_hud'] == nil and at['mods/codex/hd2_data_hub'] == true,
  'when the patch files cannot be read, a built-in list (Treasure Radar, HUDdle) is used, and an MDL3 addon stays')
check((read(G.path('chef_handoff.log')) or ''):find('using the built-in list', 1, true), 'the log says so')

G = game{ name = 'ioerror', io_error = true, loaded = { ['mods/chef/treasure_radar'] = true } }
G.frames(8)
check(#G.required == 1 and G.module.state == 'chef started', 'file reads that raise errors do not stop the hand-off')

G = game{ name = 'notinstalled_loaded', data = FIX, chef_installed = false, loaded = marked() }
G.frames(8)
local untouched = true
for _, n in ipairs(ALL) do if G.env.package.loaded['mods/test/' .. n] ~= true then untouched = false end end
check(untouched, 'with no Chef to hand off to, package.loaded is not touched')
G = game{ name = 'running_loaded', data = FIX, chef_running = true, loaded = marked() }
G.frames(8)
untouched = true
for _, n in ipairs(ALL) do if G.env.package.loaded['mods/test/' .. n] ~= true then untouched = false end end
check(untouched, 'with Chef running already, package.loaded is not touched')

print('== no folder to write to')
G = game{ name = 'nofolder' }
G.env.os.getenv = function() return nil end
G.frames(8)
check(#G.required == 1, 'without APPDATA the hand-off still happens (it just has nowhere to log)')

print(string.format('\n%d checks, %d failed', checks, failures))
os.exit(failures == 0 and 0 or 1)
