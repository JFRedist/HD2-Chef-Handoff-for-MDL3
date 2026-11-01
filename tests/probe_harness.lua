-- A test harness for Chef addons, written from the documented `chef` API (docs/MODDING.md and docs/types/chef.lua in
-- Chef Shared Loader's repository). It is NOT Chef Shared Loader and it is not the game: it is a fake `chef` table, a
-- fake engine and a small scripted world, so that an addon can be run for a few simulated minutes on plain Lua 5.1 and
-- its output checked. It also runs the addon in a locked environment (only the globals the loader gives a mod), so a
-- stray `print`, `require` or `debug` fails here instead of in the game.
--
--   local H = dofile('tests/probe_harness.lua')
--   local sim = H.new{ dir = '/tmp/x', addon = 'probe/bfv_chef_probe.lua' }
--   sim:run(90)
--   sim.logs.bfv_probe   -- the lines the addon wrote with chef.log after chef.own_log('bfv_probe')
local H = {}

local function pack(...) return { n = select('#', ...), ... } end

-- the globals a Chef mod has (its own copies of the libraries; os and io cut down)
local function sandbox_env(S)
  local env = {}
  for _, name in ipairs({ 'assert', 'error', 'ipairs', 'next', 'pairs', 'pcall', 'rawequal', 'rawget', 'rawset', 'select',
                          'setmetatable', 'tonumber', 'tostring', 'type', 'unpack', 'xpcall', 'string', 'table', 'math',
                          'coroutine' }) do
    env[name] = _G[name]
  end
  env.os = { clock = os.clock, time = os.time, date = os.date, difftime = os.difftime, getenv = os.getenv }
  env.io = { open = io.open }
  env._G = env
  env.stingray = S.stingray
  for name, t in pairs(S.stingray) do
    if name:match('^%u') then env[name] = t end             -- Unit, World ... are globals too
  end
  -- a mistyped global should fail the test (in the game it would read as nil)
  setmetatable(env, { __index = function(_, k) error('read of undefined global ' .. tostring(k), 2) end,
                      __newindex = function(t, k, v) rawset(t, k, v) end })
  return env
end

local function make_engine(S)
  local E = {}
  local function stale(u)
    if type(u) ~= 'table' or u.world ~= S.world_id then
      S.crashed = 'a unit from another world was asked something'
      error('CRASH: stale unit')
    end
    if u.removed then
      S.crashed = 'a destroyed unit was asked something'
      error('CRASH: destroyed unit')
    end
  end
  E.World = {
    units = function(_w)
      local list = {}
      for _, u in ipairs(S.units) do if not u.removed then list[#list + 1] = u end end
      return list
    end,
    spawn_unit = function() end,
  }
  E.Unit = {
    alive = function(u) return not u.removed and u.world == S.world_id end,
    has_animation_state_machine = function(u) stale(u); return u.sm == true end,
    animation_get_state = function(u) stale(u); return u.state[1], u.state[2], u.state[3], u.state[4] end,
    world_position = function(u, _n) stale(u); return u.x, u.y, u.z end,
    box = function(u) stale(u); return u end,
    num_meshes = function() return 1 end,
  }
  E.Vector3 = {
    to_elements = function(v)
      local c = S.vectors[v]
      if not c then error('not a vector') end
      return c[1], c[2], c[3]
    end,
  }
  E.Network = {
    game_session = function() return S.in_mission and 'SESSION' or nil end,
    peer_id = function() return 7 end,
  }
  E.GameSession = {
    in_session = function() return true end,
    game_session_host = function() return S.host_is_me ~= false and 7 or 3 end,
    peers = function() return S.other_peers and { 7, 3 } or { 7 } end,
    other_peers = function() return S.other_peers and { 3 } or {} end,
    game_object_owner = function(_, id) return S.objects[id] and S.objects[id].owner end,
    objects_owned_by = function(s, peer)
      if s ~= 'SESSION' then return nil end
      if peer ~= 7 and not (peer == 3 and S.other_peers) then return nil end
      local ids = {}
      for id in pairs(S.objects) do if S.objects[id].owner == peer then ids[#ids + 1] = id end end
      table.sort(ids)
      return ids
    end,
    game_object_exists = function(_, id) return S.objects[id] ~= nil end,
    game_object_field_batched = function(_, id, _t)
      local o = S.objects[id]
      if not o then error('CRASH: object does not exist') end
      if o.owner ~= 7 then S.foreign_reads = (S.foreign_reads or 0) + 1 end
      S.batched_ids = S.batched_ids or {}
      S.batched_ids[id] = (S.batched_ids[id] or 0) + 1
      S.batched_frame = (S.batched_frame or 0) + 1
      local out = {}
      for k, v in pairs(o.fields) do
        if type(v) == 'table' and not S.vectors[v] then
          local c = {}
          for k2, v2 in pairs(v) do c[k2] = v2 end
          out[k] = c
        else
          out[k] = v
        end
      end
      return out
    end,
    unit_synchronizer = function() return 'SYNC' end,
  }
  E.UnitSynchronizer = {
    unit_to_game_object_id = function(sync, u)
      if sync ~= 'SYNC' then return nil end
      stale(u)
      S.lookups = (S.lookups or 0) + 1
      return u.objid
    end,
    game_object_id_to_unit = function() return nil end,
  }
  E.Wwise = { load_bank = function() end, unload_bank = function() end }
  E.WwiseWorld = { trigger_event = function() end, make_auto_source = function() end,
                   set_listener_pose = function() end, get_source_volume = function() end }
  E.Localizer = false                                       -- the loader keeps this one from mods
  E.Math = { ray_box_intersection = function() end }
  E.Application = { build_identifier = function() return 'sim' end }
  return E
end

function H.new(opts)
  local S = { t = 0, frame = 0, world_id = 1, in_mission = false, units = {}, objects = {}, vectors = {},
              logs = {}, log_name = 'chef_loader', refuse_all = false, crashed = nil, draws = 0, notices = {},
              rows = {}, binds = {}, mouse = { left = false }, camera_on = true, sim_seq = 0,
              dir = opts.dir, opts = opts }
  os.execute('rm -rf "' .. S.dir .. '" && mkdir -p "' .. S.dir .. '"')

  -- the engine and what the addon sees of it
  local engine = make_engine(S)
  S.engine = engine
  S.stingray = {}
  for k, v in pairs(engine) do S.stingray[k] = v end

  function S:vec(x, y, z)
    local v = newproxy(true)
    self.vectors[v] = { x, y, z }
    return v
  end

  function S:unit(kind, x, y, z, o)
    self.sim_seq = self.sim_seq + 1
    local u = { id = self.sim_seq, kind = kind, x = x, y = y, z = z, world = self.world_id, sm = false,
                state = {}, removed = false }
    for k, v in pairs(o or {}) do u[k] = v end
    self.units[#self.units + 1] = u
    return u
  end

  -- ---------------------------------------------------------------- the fake chef
  local chef = { loader = 'Chef Shared Loader', loader_version = '1.4.1', api = 3, name = 'mods/jfredist/bfv_chef_probe',
                 options = {}, TOP = 1000, log_directory = S.dir, log_file = S.dir .. '/chef_loader.log' }
  local capmap = { api = 3 }
  local caps = { 'after_startup', 'settings', 'share', 'events', 'require', 'bind', 'menu', 'shims', 'dev', 'logs',
                 'own_log', 'units', 'spawn', 'timers', 'budget', 'session', 'settings_file', 'shapes', 'sprite_sheets',
                 'notify', 'typed', 'key_labels', 'save_table', 'mods', 'health', 'index', 'joining', 'ray_box',
                 'mouse_hold', 'players_event', 'hang_watchdog', 'option_buttons', 'option_colors', 'option_headings',
                 'menu_state', 'mod_stopped_event', 'bind_combos', 'option_folds' }
  for _, c in ipairs(caps) do capmap[c] = true end
  -- like the real loader's: a read-only proxy, so pairs() over it gives nothing (a probe must ask chef.has by name)
  chef.capabilities = setmetatable({}, { __index = capmap, __newindex = function() error('capabilities are read-only') end,
                                         __metatable = 'locked' })
  if opts.old_loader then
    -- loader 1.0.0 style: no chef.has, no events, no own log, no bindings, no menu
    chef.capabilities = nil
  else
    function chef.has(name) return capmap[name] == true end
    function chef.own_log(name) S.log_name = name; S.logs[name] = S.logs[name] or {}; return true end
    function chef.after_startup(fn) S.after_startup = S.after_startup or {}; table.insert(S.after_startup, fn) end
    function chef.on(event, fn) S.listeners = S.listeners or {}; S.listeners[event] = S.listeners[event] or {}
      table.insert(S.listeners[event], fn) end
    function chef.emit(event, ...) for _, fn in ipairs((S.listeners or {})[event] or {}) do fn(...) end end
    function chef.title(text) S.title = text end
    function chef.option(id, spec)
      if spec.heading and not chef.capabilities.option_headings then error('unknown spec field heading') end
      local value = spec.default
      if opts.options and opts.options[id] ~= nil then value = opts.options[id] end      -- a row the test has set beforehand
      S.rows[id] = { spec = spec, value = value }
      return value
    end
    function chef.get(id) return S.rows[id] and S.rows[id].value end
    function chef.set(id, value)
      local row = S.rows[id]
      row.value = value
      for _, fn in ipairs(row.on_change or {}) do fn(value) end
      return value
    end
    function chef.on_change(id, fn)
      local row = S.rows[id]
      row.on_change = row.on_change or {}
      table.insert(row.on_change, fn)
      return true
    end
    function chef.button(id, label, fn, text) S.rows[id] = { spec = { type = 'button', label = label, run = fn, text = text } } end
    function chef.bind(id, key, label)
      local b = { id = id, key = key, label = label, fire = false }
      function b.pressed() local p = b.fire; b.fire = false; return p end
      function b.down() return false end
      function b.key_name() return key end
      S.binds[id] = b
      return b
    end
    function chef.notify(text, seconds) table.insert(S.notices, { text = text, seconds = seconds, t = S.t }) end
    function chef.budget(ms) S.budget = ms; return ms end
  end

  function chef.log(fmt, ...)
    local line = string.format(fmt, ...)
    local list = S.logs[S.log_name]
    if not list then list = {}; S.logs[S.log_name] = list end
    list[#list + 1] = line
  end
  function chef.time() return S.t end
  function chef.world() return S.in_mission and 'WORLD' or nil end
  function chef.world_id() return S.world_id end
  function chef.in_mission() return S.in_mission end
  function chef.camera()
    if not S.camera_on then return nil end
    return S.cam
  end
  function chef.screen() return 2560, 1440 end
  function chef.color(r, g, b, a) return { r, g, b, a or 255 } end
  function chef.text(...) S.draws = S.draws + 1; S.last_text = select(3, ...); return 100 end
  function chef.rect() S.draws = S.draws + 1 end
  function chef.mouse_down(name) return S.mouse[name] == true end
  function chef.key_down() return false end
  function chef.key_pressed() return false end

  local function run_call(name, ...)
    if S.refuse_all then return nil, 'refused by the test' end
    local tname, fname = name:match('^([%w_]+)%.([%w_]+)$')
    local T = tname and engine[tname]
    if T == false then return nil, 'refused: table is off limits' end
    if type(T) ~= 'table' then return nil, 'no table ' .. tostring(tname) end
    local f = T[fname]
    if type(f) ~= 'function' then return nil, 'no function ' .. tostring(name) end
    local r = pack(pcall(f, ...))
    if not r[1] then return nil, tostring(r[2]) end
    return unpack(r, 2, r.n)
  end
  function chef.call(name, ...) return run_call(name, ...) end
  function chef.call_kind(name, _kind, ...) return run_call(name, ...) end

  function chef.unit_kind(u)
    if type(u) ~= 'table' or u.kind == nil then return nil end        -- not a unit at all: the loader answers nil
    if u.world ~= S.world_id then S.crashed = 'unit_kind on a stale handle'; return nil end
    return u.kind
  end
  function chef.unit_alive(u)
    if type(u) ~= 'table' then return false end
    return u.world == S.world_id and not u.removed
  end
  function chef.unit_position(u)
    if not chef.unit_alive(u) then return nil end
    if u.kind == '46cab355bd8d4d37' then S.crashed = 'position of a runtime-built unit'; return nil end
    return u.x, u.y, u.z
  end
  -- a ray against the box of a unit (0.8 x 0.8 x 2 m, its middle 1 m above its position), like the loader's simulator
  function chef.ray_box(from, dir, u)
    if not chef.unit_alive(u) then return nil, 'dead' end
    local lo = { u.x - 0.4, u.y - 0.4, u.z }
    local hi = { u.x + 0.4, u.y + 0.4, u.z + 2 }
    local o = { from.x, from.y, from.z }
    local d = { dir.x, dir.y, dir.z }
    local tmin, tmax = 0, 1e9
    for i = 1, 3 do
      if math.abs(d[i]) < 1e-9 then
        if o[i] < lo[i] or o[i] > hi[i] then return nil end
      else
        local t1, t2 = (lo[i] - o[i]) / d[i], (hi[i] - o[i]) / d[i]
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return nil end
      end
    end
    return tmin
  end

  -- an old loader or a hostile engine can be asked for
  if opts.customize then opts.customize(S, chef) end
  S.chef = chef
  S.cam = { x = 0, y = -30, z = 2, fx = 0, fy = 1, fz = 0, yaw = 0, fov = 0.9 }

  -- ---------------------------------------------------------------- load the addon
  local chunk, err = loadfile(opts.addon)
  assert(chunk, err)
  S.env = sandbox_env(S)
  setfenv(chunk, S.env)
  S.addon = chunk(chef)
  if S.after_startup then for _, fn in ipairs(S.after_startup) do fn() end end

  -- ---------------------------------------------------------------- the clock
  function S:frame_step(dt)
    self.t = self.t + dt
    self.frame = self.frame + 1
    if self.script then self.script(self) end
    local c0 = os.clock()
    self.batched_frame = 0
    if self.addon.update then self.addon.update(dt) end
    if (self.batched_frame or 0) > (self.max_batched_frame or 0) then self.max_batched_frame = self.batched_frame end
    if self.addon.render then self.addon.render() end
    self.cpu = (self.cpu or 0) + (os.clock() - c0)
  end

  function S:run(seconds, fps)
    fps = fps or 60
    local dt = 1 / fps
    local frames = math.floor(seconds * fps + 0.5)
    for _ = 1, frames do self:frame_step(dt) end
  end

  function S:new_world(in_mission)
    self.world_id = self.world_id + 1
    self.in_mission = in_mission
    self.units, self.objects = {}, {}
    if in_mission then
      chef.emit = chef.emit or function() end
      chef.emit('mission_start', self.world_id)
    end
  end

  function S:end_mission()
    local id = self.world_id
    self.in_mission = false
    if chef.emit then chef.emit('mission_end', id) end
  end

  function S:shutdown()
    if self.addon.shutdown then self.addon.shutdown() end
  end

  function S:save_logs()
    for name, lines in pairs(self.logs) do
      local f = assert(io.open(self.dir .. '/' .. name .. '.log', 'w'))
      f:write(table.concat(lines, '\n'), '\n')
      f:close()
    end
  end

  function S:read(name)
    local f = io.open(self.dir .. '/' .. name, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
  end

  function S:grep(log, pattern)
    local out = {}
    for _, line in ipairs(self.logs[log] or {}) do
      if line:find(pattern) then out[#out + 1] = line end
    end
    return out
  end

  return S
end

return H
