-- Variant H of the stand-in: MDL3's sandbox, as the hand-off 0.2.2's log showed it in the real game (2026-11-02, MDL3 3.0.0-dev.29,
-- Chef 1.5.1). What that log showed, and what this stand-in does:
--   * an addon runs in an environment of its own: its _G is not the global table (getfenv(0) is), and has MDL3's __index and
--     __newindex;
--   * update and shutdown are the addon's own: MDL3 calls each addon's from the game's update and shutdown (MDL.log: "It has no
--     shutdown of its own"). Taking the addon's update off puts MDL3's stand-in for it back, taking its shutdown off does nothing
--     (the log: "still on the globals right after they were taken off: update, shutdown"); init is the addon's own too, and unset;
--   * everything else, render included, is the game's global table;
--   * the game's update, render and shutdown are MDL3's own, in that table: that is where Chef's core finds them when it is required.
-- MDL3's update has one SLOW call, as in F (3.6 s of CPU time at the 900th frame, after the hand-off): Chef from 1.5.0 stops a
-- chain it runs itself. With the hand-off 0.2.2 Chef keeps MDL3's update and shutdown ("running the callbacks ... (2)", as in the
-- game) and its watchdog switches MDL3 off at that call.
local GT = _G
rawset(GT, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3-sandbox', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local real_rawget, real_rawset = rawget, rawset
local SLOT = { init = true, update = true, shutdown = true }
local addons = {}
local function default_update() end
local function default_shutdown() end

local function sandbox()
  local slots = { update = default_update, shutdown = default_shutdown }
  local P = {}
  local get, put
  local function sb_rawget(t, k) if t == P then return get(k) end return real_rawget(t, k) end
  local function sb_rawset(t, k, v) if t == P then put(k, v); return t end return real_rawset(t, k, v) end
  get = function(k)
    if k == '_G' then return P end
    if k == 'rawget' then return sb_rawget end
    if k == 'rawset' then return sb_rawset end
    if SLOT[k] then return slots[k] end
    return real_rawget(GT, k)
  end
  put = function(k, v)
    if k == 'update' then slots.update = v or default_update        -- taken off: MDL3's stand-in for it comes back
    elseif k == 'shutdown' then if v ~= nil then slots.shutdown = v end   -- taken off: nothing happens
    elseif k == 'init' then slots.init = v
    else real_rawset(GT, k, v) end                                    -- the rest is the game's
  end
  setmetatable(P, { __index = function(_, k) return get(k) end, __newindex = function(_, k, v) put(k, v) end })
  return P, slots
end

local function start(name)
  local P, slots = sandbox()
  local chunk = package.loaders[2](name)                -- (the simulator's loader for the deployed patches)
  if type(chunk) ~= 'function' then print('[stand-in mdl3] ' .. name .. ' -> not found'); return end
  setfenv(chunk, P)
  local ok, err = pcall(chunk)
  CowboyBingusModLoader.modules[name] = ok and 'managed' or ('load failed (managed): ' .. tostring(err))
  addons[#addons + 1] = { name = name, slots = slots }
  print('[stand-in mdl3] ' .. name .. ' -> ' .. CowboyBingusModLoader.modules[name])
end

local function burn(seconds)
  local t0 = os.clock()
  while os.clock() - t0 < seconds do end
end
local updates, addon_updates = 0, 0
function init() print('[stand-in mdl3] init') end
function update(dt)
  updates = updates + 1
  for _, a in ipairs(addons) do
    addon_updates = addon_updates + 1
    local ok, err = pcall(a.slots.update, dt)
    if not ok then print('[stand-in mdl3] ' .. a.name .. ' update error: ' .. tostring(err)) end
  end
  if updates == 900 then
    burn(3.6)
    print('[stand-in mdl3] the slow update call ended')
  end
end
function render() end
function shutdown()
  for _, a in ipairs(addons) do pcall(a.slots.shutdown) end
  print('[stand-in mdl3] shutdown; updates seen: ' .. updates .. '; addon updates: ' .. addon_updates)
end
start('mods/jfredist/chef_handoff')
print('[stand-in mdl3] boot done')
