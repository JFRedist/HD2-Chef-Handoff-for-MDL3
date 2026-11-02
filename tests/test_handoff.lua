-- Runs handoff/chef_handoff.lua in a small fake game and checks what it does and, as important, what it leaves alone.
--   lua5.1 tests/test_handoff.lua            (from the repository root)
-- The real Chef is exercised by tests/handoff_sim.sh; this one is the quick check of the addon's own logic.
local WINDOWS = package.config:sub(1, 1) == '\\'  -- (os.execute runs cmd there, not sh)
local ADDON = os.getenv('HANDOFF_ADDON') or 'handoff/chef_handoff.lua'
local OUT = os.getenv('HANDOFF_TEST_OUT') or (WINDOWS and (os.getenv('TEMP') or '.') .. '\\bfv_handoff_test' or '/tmp/bfv_handoff_test')
local CORE = 'mods/chef_shared_loader/core_1'
local NULL = WINDOWS and 'NUL' or '/dev/null'

-- an empty folder; on Windows also the addon's folder in it (the backslashes it glues on make real folders there, and
-- io.open makes none: elsewhere they are part of a file's name)
local function fresh(dir, sub)
  if WINDOWS then
    local d = dir:gsub('/', '\\')
    os.execute('if exist "' .. d .. '" rmdir /s /q "' .. d .. '"')
    os.execute('mkdir "' .. d .. (sub and '\\' .. sub or '') .. '"')
  else
    os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
  end
end

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
  fresh(dir, 'A\\Arrowhead\\Helldivers2')
  local base = dir .. '/A'                 -- APPDATA; the folder names are glued on with backslashes, as on Windows: on this
                                           -- machine the files come out as 'A\Arrowhead\Helldivers2\<name>' inside dir
  local G = { calls = {}, updates = 0, last_args = nil, required = {}, t = 0, order = {}, record = false, cpu = 0 }
  local env = {}
  for _, name in ipairs({ 'rawget', 'rawset', 'type', 'pcall', 'tostring', 'tonumber', 'ipairs', 'pairs', 'select', 'error',
                          'string', 'table', 'math' }) do env[name] = _G[name] end
  env._G = env
  env.os = { getenv = function(k) if k == 'APPDATA' then return base end end, date = os.date }
  local real_open = io.open
  env.io = { open = function(path, mode)
    if opts.guard_on_io then                        -- a loader that puts its own callbacks back when they are gone, and runs
      if env.render == nil then env.render = G.game_render end           -- that check whenever a mod opens a file
      if env.shutdown == nil then env.shutdown = G.game_shutdown end
    end
    local rel = type(path) == 'string' and path:match('^data/(.*)$')
    if rel then                                     -- the game's patch files: a folder of fixtures, or none
      G.data_first = G.data_first or G.t
      if opts.data == false or not opts.data then return nil, 'no such file' end
      return real_open(opts.data .. '/data/' .. rel, mode)
    end
    return real_open(path, mode)
  end }
  if opts.io_error then env.io.open = function() error('boom') end end
  env.os.clock = opts.fake_cpu and function() return G.cpu end or os.clock
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
      G.chef_saw = {}
      for _, k in ipairs({ 'init', 'update', 'render', 'shutdown' }) do G.chef_saw[k] = env[k] ~= nil end
      local before = env.update
      if opts.core_sees_through then before = G.sneak end         -- (as if it had found the chain anyway: the test hands it over)
      env.ChefSharedLoader = newproxy(true)                       -- (read-only and not a table, like the real one)
      getmetatable(env.ChefSharedLoader).__index = { version = '1.4.1', api = 3 }
      -- like Chef: its own callbacks, and the update that was set before it started kept and called after its own (the addon
      -- takes the game's callbacks off the globals while Chef loads, so there is none to keep)
      if not opts.core_no_callbacks then
        env.update = function(dt, ...)
          G.chef_updates = (G.chef_updates or 0) + 1
          if G.record then G.order[#G.order + 1] = 'chef update' end
          if opts.chef_update_error then error('chef boom') end
          if before then return before(dt, ...) end
        end
        env.init = function() if G.record then G.order[#G.order + 1] = 'chef init' end end
        env.render = function() if G.record then G.order[#G.order + 1] = 'chef render' end end
        env.shutdown = function() if G.record then G.order[#G.order + 1] = 'chef shutdown' end end
      else
        env.update, env.init, env.render, env.shutdown = nil, nil, nil, nil     -- (a core that installs nothing of its own)
      end
      return true
    end
    error('module not found: ' .. tostring(name))
  end
  if opts.update ~= false then
    env.update = function(dt, a, b)
      G.updates = G.updates + 1; G.last_args = { dt, a, b }
      if G.record then G.order[#G.order + 1] = 'game update' end
      if G.burn then G.cpu = G.cpu + G.burn; G.burn = nil end          -- (a call that takes a while, on a fake CPU clock)
      return 'ret'
    end
    if opts.callbacks ~= false then
      env.init = function() G.game_inits = (G.game_inits or 0) + 1; if G.record then G.order[#G.order + 1] = 'game init' end end
      env.render = function() G.renders = (G.renders or 0) + 1; if G.record then G.order[#G.order + 1] = 'game render' end end
      env.shutdown = function() G.shutdowns = (G.shutdowns or 0) + 1; if G.record then G.order[#G.order + 1] = 'game shutdown' end end
      G.game_render, G.game_shutdown = env.render, env.shutdown
    end
  end
  if opts.debug then env.debug = opts.debug end
  if opts.full_env then                              -- what the real game's Lua has besides
    env.debug = { getinfo = debug.getinfo, gethook = function() return nil end }
    env.getmetatable, env.getfenv = getmetatable, getfenv
  end
  if opts.mt then setmetatable(env, opts.mt) end
  if opts.sticky then                                -- a key that taking off (rawset to nil) does not clear
    env.rawset = function(t, k, v) if t == env and k == opts.sticky and v == nil then return t end return rawset(t, k, v) end
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

-- MDL3's sandbox, as the real run of 0.2.2 showed it (tests/fixtures/handoff/mdl3_boot_h.lua is the same for Chef's simulator):
-- the game's globals GT hold MDL3's own update, render and shutdown (MDL3's update calls each addon's own update, its shutdown each
-- addon's shutdown). The addon runs in a proxy P: its _G is P; update and shutdown are its own (taking update off puts MDL3's
-- stand-in back, taking shutdown off does nothing), init is its own and unset, everything else is GT's; getfenv(0) is GT.
-- Chef's core (the fake one) reads its globals from GT, as require gives a chunk the running thread's globals.
local function sandbox_game(opts)
  opts = opts or {}
  local dir = OUT .. '/' .. opts.name
  fresh(dir, 'A\\Arrowhead\\Helldivers2')
  local base = dir .. '/A'
  local G = { t = 0, order = {}, record = false, mdl3_updates = 0, required = {} }
  local GT = {}
  for _, name in ipairs({ 'rawget', 'rawset', 'type', 'pcall', 'tostring', 'tonumber', 'ipairs', 'pairs', 'select', 'error',
                          'string', 'table', 'math', 'getmetatable' }) do GT[name] = _G[name] end
  GT._G = GT
  GT.os = { getenv = function(k) if k == 'APPDATA' then return base end end, date = os.date, clock = os.clock }
  GT.io = { open = function(path, mode)
    if type(path) == 'string' and path:match('^data/') then return nil, 'no such file' end
    return io.open(path, mode)
  end }
  GT.package = { loaded = {} }
  GT.debug = { getinfo = debug.getinfo, gethook = function() return nil end }
  GT.stingray = { Application = { can_get = function(kind, name) return kind == 'lua' and name == CORE end } }
  GT.CowboyBingusModLoader = { modules = {} }
  local SLOT = { init = true, update = true, shutdown = true }
  local function default_update() end
  local function default_shutdown() G.addon_shutdowns = (G.addon_shutdowns or 0) + 1 end
  local slots = { update = default_update, shutdown = default_shutdown }
  local P = {}
  local get, put
  local function sb_rawget(t, k) if t == P then return get(k) end return rawget(t, k) end
  local function sb_rawset(t, k, v) if t == P then put(k, v); return t end return rawset(t, k, v) end
  local fake_gt = opts.gt_without_stingray and {} or GT
  local function sb_getfenv(x) if x == 0 then return fake_gt end return getfenv(x) end
  get = function(k)
    if k == '_G' then return P end
    if k == 'rawget' then return sb_rawget end
    if k == 'rawset' then return sb_rawset end
    if k == 'getfenv' then return sb_getfenv end
    if SLOT[k] then return slots[k] end
    return rawget(GT, k)
  end
  put = function(k, v)
    if k == 'update' then slots.update = v or default_update
    elseif k == 'shutdown' then if v ~= nil then slots.shutdown = v end
    elseif k == 'init' then slots.init = v
    else rawset(GT, k, v) end
  end
  setmetatable(P, { __index = function(_, k) return get(k) end, __newindex = function(_, k, v) put(k, v) end })
  GT.update = function(dt)
    G.mdl3_updates = G.mdl3_updates + 1
    G.mdl3_inside_chef = G.mdl3_inside_chef or G.in_chef
    if G.record then G.order[#G.order + 1] = 'mdl3 update' end
    slots.update(dt)
  end
  GT.render = function() if G.record then G.order[#G.order + 1] = 'mdl3 render' end end
  GT.shutdown = function()
    if G.record then G.order[#G.order + 1] = 'mdl3 shutdown' end
    G.mdl3_shutdowns = (G.mdl3_shutdowns or 0) + 1
    slots.shutdown()
  end
  G.mdl3 = { update = GT.update, render = GT.render, shutdown = GT.shutdown }
  if opts.gt_newindex then                 -- a guard on the game's table that takes callbacks set on missing keys for itself
    G.swallowed = {}
    setmetatable(GT, { __newindex = function(t, k, v)
      if k == 'init' or k == 'update' or k == 'render' or k == 'shutdown' then G.swallowed[k] = v else rawset(t, k, v) end
    end })
  end
  GT.require = function(name)
    G.required[#G.required + 1] = name
    if opts.require_error then error('core failed: boom') end
    if name ~= CORE then error('module not found: ' .. tostring(name)) end
    G.note = rawget(GT, 'ChefSharedLoaderHandoff')
    G.chef_saw = {}
    local kept = {}
    for _, k in ipairs({ 'init', 'update', 'render', 'shutdown' }) do G.chef_saw[k] = rawget(GT, k) ~= nil; kept[k] = rawget(GT, k) end
    G.kept = kept
    GT.ChefSharedLoader = newproxy(true)
    getmetatable(GT.ChefSharedLoader).__index = { version = '1.5.1', api = 1 }
    GT.init = function() end
    GT.update = function(dt)                 -- like Chef: its own, then the callbacks it kept, as a boot script's
      G.in_chef = true
      if G.record then G.order[#G.order + 1] = 'chef update' end
      if kept.update then kept.update(dt) end
      G.in_chef = false
    end
    GT.render = function() if G.record then G.order[#G.order + 1] = 'chef render' end; if kept.render then kept.render() end end
    GT.shutdown = function() if G.record then G.order[#G.order + 1] = 'chef shutdown' end; if kept.shutdown then kept.shutdown() end end
    return true
  end
  local chunk = assert(loadfile(ADDON))
  setfenv(chunk, P)
  G.module = chunk()
  G.GT, G.P, G.slots = GT, P, slots
  G.hook = slots.update
  G.path = function(name) return base .. '\\Arrowhead\\Helldivers2\\' .. name end
  function G.frames(seconds, dt)
    dt = dt or 1 / 60
    for _ = 1, math.floor(seconds / dt + 0.5) do G.t = G.t + dt; GT.update(dt) end
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
check(G.updates - before == 120 and (G.chef_updates or 0) >= 100, 'after the hand-off the chain goes on behind Chef\'s update (' .. G.updates - before .. ')')
check(#G.required == 1, 'no second hand-off')
check(lines(log) < 24, 'the log stays short (' .. lines(log) .. ' lines)')

print('== the game\'s callbacks stay out of Chef\'s hands and run behind its own')
G = game{ name = 'callbacks' }
G.frames(5)
local chain = G.env.update
G.frames(2)
check(G.chef_saw and not (G.chef_saw.init or G.chef_saw.update or G.chef_saw.render or G.chef_saw.shutdown),
  'while Chef loads it finds no init, update, render or shutdown to keep: they were taken off the globals')
check(type(G.env.update) == 'function' and G.env.update ~= chain, 'afterwards update is a new function: Chef\'s own, with the chain behind it')
G.record, G.order = true, {}
G.env.update(1 / 60); G.env.render(); G.env.shutdown()
check(table.concat(G.order, ',') == 'chef update,game update,chef render,game render,chef shutdown,game shutdown',
  'update, render and shutdown run Chef\'s first, then the game\'s chain (' .. table.concat(G.order, ',') .. ')')
G.order = {}
G.env.init()
check(table.concat(G.order, ',') == 'chef init' and (G.game_inits or 0) == 0, 'init is Chef\'s own; the game\'s init, called long ago, is not called again')
check((read(G.path('chef_handoff.log')) or ''):find('run behind Chef', 1, true), 'the log says the callbacks run behind Chef\'s own')

print('== a loader that puts its callbacks back whenever a mod opens a file (a guess at what Chef 1.5.1 found in the game)')
G = game{ name = 'guard_io', guard_on_io = true }
G.frames(7)
check(G.module.state == 'chef started', 'the hand-off happens')
check(G.chef_saw and not (G.chef_saw.init or G.chef_saw.update or G.chef_saw.render or G.chef_saw.shutdown),
  'Chef still finds none of the callbacks: nothing opens a file between taking them off and require')
local glog = read(G.path('chef_handoff.log')) or ''
check(not glog:find('still on the globals', 1, true), 'and nothing was left on the globals')
G.record, G.order = true, {}
G.env.update(1 / 60); G.env.render(); G.env.shutdown()
check(table.concat(G.order, ',') == 'chef update,game update,chef render,game render,chef shutdown,game shutdown',
  'the order afterwards is the usual one (' .. table.concat(G.order, ',') .. ')')

print('== a callback that taking it off does not clear')
G = game{ name = 'sticky', sticky = 'render' }
G.frames(7)
check(G.chef_saw and G.chef_saw.render and not G.chef_saw.update, 'Chef finds that one (and only that one)')
check((read(G.path('chef_handoff.log')) or ''):find('still on the globals right after they were taken off: render', 1, true), 'and the log names it')

print('== how many times the update chain runs a frame once Chef has the game')
G = game{ name = 'count_once' }
G.frames(7)
G.frames(11)
local clog = read(G.path('chef_handoff.log')) or ''
check(clog:find('ran 600 times in the first 600 frames after the hand-off: once a frame', 1, true), 'normally once a frame, and the log says so')
G = game{ name = 'count_twice', core_sees_through = true }
G.frames(5)
G.sneak = G.env.update                               -- the chain as it is just before the hand-off
G.frames(2)
local u0 = G.updates
G.frames(11)
clog = read(G.path('chef_handoff.log')) or ''
check(clog:find('ran 1200 times in the first 600 frames after the hand-off: TWICE a frame', 1, true), 'if Chef runs the chain as well: twice, and the log says so')
check(G.updates - u0 == 1320, 'which is what happened (' .. (G.updates - u0) .. ' runs in 660 frames)')
G = game{ name = 'count_onupdate', update = false, on_update = true }
for _ = 1, 1200 do G.on_update.fn(1 / 60) end
check(not (read(G.path('chef_handoff.log')) or ''):find('update chain ran', 1, true), 'hooked through on_update there is no chain to count: no line')

print('== what the log tells about the callbacks and the globals')
G = game{ name = 'describe', full_env = true }
G.frames(7)
local dlog = read(G.path('chef_handoff.log')) or ''
check(dlog:find('  the game\'s callbacks: init=0x', 1, true) or dlog:find('  the game\'s callbacks: init=', 1, true), 'at load: the four callbacks')
local before_line = dlog:match('the game\'s callbacks before: ([^\n]+)') or ''
local after_line = dlog:match('the game\'s callbacks after Chef loaded: ([^\n]+)') or ''
check(before_line:find('update=[^ ]+ %[handoff/chef_handoff%.lua:%d+%]') and before_line:find('render=[^ ]+ %[tests/test_handoff%.lua:%d+%]'),
  'before the hand-off: each with where it was defined (update is this addon\'s hook, render the game\'s)')
check(after_line:find('update=[^ ]+ %[tests/test_handoff%.lua:%d+%]') and not after_line:find('taken off', 1, true),
  'after Chef loaded: Chef\'s own, none of them the ones taken off')
check(dlog:find('metatable of _G: none', 1, true) and dlog:find('_G is the global table: no, this addon runs in it: no', 1, true)
  and dlog:find('require: [^ ]+ %[tests/test_handoff%.lua:%d+%]'), 'the globals\' metatable, which table the addon runs in, and where require comes from')
G = game{ name = 'describe_mt', full_env = true, mt = { __newindex = function(t, k, v) rawset(t, k, v) end } }
G.frames(7)
dlog = read(G.path('chef_handoff.log')) or ''
check(dlog:find('metatable of _G: __newindex=[^ ]+ %[tests/test_handoff%.lua:%d+%]') and G.module.state == 'chef started',
  'a guard on the globals (__newindex) is named, and the hand-off still works')
G = game{ name = 'describe_bare' }
G.frames(7)
dlog = read(G.path('chef_handoff.log')) or ''
check(dlog:find('metatable of _G: unknown (no getmetatable here)', 1, true) and dlog:find('the game\'s callbacks after Chef loaded: init=', 1, true),
  'without debug, getmetatable or getfenv it says less, and still says it')
local order_ok = true
local p1, p2, p3 = dlog:find('callbacks before', 1, true), dlog:find('debug hook after', 1, true), dlog:find('after Chef loaded', 1, true)
if not (p1 and p2 and p3 and p1 < p2 and p2 < p3) then order_ok = false end
check(order_ok, 'the lines come in order: before, then after the hand-off')

print('== MDL3\'s sandbox (the real MDL3, as the 0.2.2 log showed it): the callbacks come off the game\'s own table')
G = sandbox_game{ name = 'sandbox' }
check(G.module and G.module.state == 'waiting' and G.hook ~= nil, 'the addon loads in the sandbox and hooks its own update there')
G.frames(7)
check(G.module.state == 'chef started' and #G.required == 1, 'the hand-off happens once')
check(type(G.note) == 'table' and G.note.phase == 'init', 'Chef finds the note on the game\'s table, where it reads its globals')
check(G.chef_saw and not (G.chef_saw.update or G.chef_saw.render or G.chef_saw.shutdown),
  'Chef finds none of MDL3\'s update, render, shutdown there (0.2.2 took them off the sandbox, and Chef found update and shutdown)')
check(G.GT.ChefSharedLoaderHandoff == nil, 'the note is gone afterwards')
check(G.slots.update == G.hook, 'the addon\'s own update in the sandbox is left alone')
G.record, G.order = true, {}
G.GT.update(1 / 60); G.GT.render(); G.GT.shutdown()
check(table.concat(G.order, ',') == 'chef update,mdl3 update,chef render,mdl3 render,chef shutdown,mdl3 shutdown',
  'the game\'s callbacks: Chef\'s first, then MDL3\'s (' .. table.concat(G.order, ',') .. ')')
check(not G.mdl3_inside_chef, 'MDL3\'s update is not called from inside Chef\'s (where Chef 1.5\'s watchdog would time it)')
G.record = false
local u0, n0 = G.mdl3_updates, #G.required
G.frames(11)
check(G.mdl3_updates - u0 == 660 and #G.required == n0, 'MDL3\'s update runs once a frame, and there is no second hand-off')
local slog = read(G.path('chef_handoff.log')) or ''
check(slog:find('the game\'s global table: getfenv(0) (this addon\'s _G is a sandbox of its own, not the global table)', 1, true),
  'the log says which table it used')
check(slog:find('  the game\'s callbacks (its global table): init=nil update=', 1, true)
  and slog:find('the game\'s callbacks before %(its global table%): init=nil update=[^ ]+ %[tests/test_handoff%.lua:%d+%]'),
  'and what was on it, at load and before the hand-off: MDL3\'s own')
check(not slog:find('still on', 1, true) and not slog:find('the one taken off', 1, true), 'all came off, none came back while Chef loaded')
check(slog:find('the game\'s callbacks after Chef loaded (its global table): init=', 1, true), 'and what was on it after Chef loaded')
check(slog:find('metatable of _G: __index=', 1, true) and slog:find('metatable of the global table: none', 1, true), 'it describes both tables')
check(slog:find('ran 600 times in the first 600 frames after the hand-off: once a frame', 1, true), 'the count says once a frame')

G = sandbox_game{ name = 'sandbox_fail', require_error = true }
G.frames(7)
check(G.module.state == 'hand-off failed' and G.GT.update == G.mdl3.update and G.GT.render == G.mdl3.render and G.GT.shutdown == G.mdl3.shutdown,
  'in the sandbox, a core that fails leaves MDL3\'s callbacks on the game\'s table as they were')
G.frames(1)
check(G.mdl3_updates > 0, 'and MDL3 goes on')

G = sandbox_game{ name = 'sandbox_nostingray', gt_without_stingray = true }
G.frames(7)
check(G.module.state == 'chef started' and (read(G.path('chef_handoff.log')) or ''):find('without the engine\'s stingray in it', 1, true),
  'a getfenv(0) that is not the game\'s table (no stingray in it) is not used: the hand-off works as before, and the log says why')

G = sandbox_game{ name = 'sandbox_guard', gt_newindex = true }
G.frames(7)
local glog2 = read(G.path('chef_handoff.log')) or ''
check(glog2:find('guards the keys it does not have: the callbacks are replaced by empty stand-ins', 1, true),
  'a game table that guards its missing keys (__newindex): the log says the callbacks are replaced by stand-ins, not taken off')
check(G.module.state == 'chef started' and next(G.swallowed) == nil, 'Chef\'s own callbacks land on the table (none went to the guard)')
check(G.kept and type(G.kept.update) == 'function' and G.kept.update ~= G.mdl3.update and G.kept.shutdown ~= G.mdl3.shutdown,
  'what Chef keeps are the stand-ins, not MDL3\'s')
G.record, G.order = true, {}
G.GT.update(1 / 60); G.GT.render(); G.GT.shutdown()
check(table.concat(G.order, ',') == 'chef update,mdl3 update,chef render,mdl3 render,chef shutdown,mdl3 shutdown' and not G.mdl3_inside_chef,
  'and the callbacks run Chef\'s first, then MDL3\'s, outside Chef (' .. table.concat(G.order, ',') .. ')')
check(not glog2:find('still on', 1, true), 'nothing was left on the table but the stand-ins')

print('== the core fails to load: the callbacks are put back as they were')
G = game{ name = 'fails_cb', require_error = true }
G.frames(5)
chain = G.env.update
local game_render, game_shutdown, game_init = G.env.render, G.env.shutdown, G.env.init
G.frames(2)
check(G.module.state == 'hand-off failed', 'the hand-off failed')
check(G.env.update == chain and G.env.render == game_render and G.env.shutdown == game_shutdown and G.env.init == game_init,
  'update, render, shutdown and init are the very functions they were before')
check((read(G.path('chef_handoff.log')) or ''):find('put back as they were', 1, true), 'and the log says so')

print('== Chef started but installed no callbacks of its own')
G = game{ name = 'nocb', core_no_callbacks = true }
G.frames(5)
chain = G.env.update
G.frames(2)
check(G.module.state == 'chef started' and G.env.update == chain, 'the game\'s callbacks stay as they were')

print('== Chef\'s own update raising an error does not stop the game\'s chain')
G = game{ name = 'chef_raises', chef_update_error = true }
G.frames(7)
local before_raise = G.updates
G.frames(2)
check(G.updates - before_raise == 120, 'the chain runs every frame (' .. G.updates - before_raise .. ')')
check((read(G.path('chef_handoff.log')) or ''):find('Chef\'s update raised an error', 1, true), 'the log says so')

print('== a slow call of the chain is written to the log (Chef 1.4.1 and 1.5.x would have stopped it)')
G = game{ name = 'slow', fake_cpu = true }
G.frames(7)
G.burn = 1.2
G.frames(1)
G.burn = 3.4
G.frames(1)
local slowlog = read(G.path('chef_handoff.log')) or ''
check(slowlog:find('took 1200 ms of CPU time', 1, true) and slowlog:find('took 3400 ms of CPU time', 1, true), 'a call of 1.2 s and one of 3.4 s each get a line')
local frames_before = G.updates
G.frames(2)
check(G.updates - frames_before == 120, 'and the chain goes on')

print('== the debug hook is written to the log, before and after the hand-off')
G = game{ name = 'hook', debug = { gethook = function() return function() end, '', 1000000 end } }
G.frames(7)
local hooklog = read(G.path('chef_handoff.log')) or ''
check(hooklog:find('debug hook before: function', 1, true) and hooklog:find('debug hook after: function', 1, true) and hooklog:find('count 1000000', 1, true),
  'a hook that is set is described: before and after')
G = game{ name = 'nohook', debug = { gethook = function() return nil end } }
G.frames(7)
check((read(G.path('chef_handoff.log')) or ''):find('debug hook before: none', 1, true), 'no hook: "none"')
G = game{ name = 'nodebug' }
G.frames(7)
check((read(G.path('chef_handoff.log')) or ''):find('unknown (no debug.gethook here)', 1, true) and #G.required == 1,
  'no debug library in the addon\'s world: "unknown", and the hand-off still happens')

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
fresh(FIX)
assert(os.execute('python3 -I tests/fixtures/handoff/make_patches.py "' .. FIX .. '" > ' .. NULL) == 0, 'make_patches.py failed')
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
