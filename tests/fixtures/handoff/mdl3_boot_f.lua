-- Variant F of the stand-in: like A (addons started once the game calls init), but its update chain has one SLOW call: 3.6 s of
-- CPU time at the 900th frame (15 s in, after the hand-off), the way a loader that does real work in its update can have one long
-- frame. A Chef from 1.5.0 that ran this chain itself, as "a boot script's callbacks", would call that a hang (a call over 3 s) and
-- switch the chain off: MDL3 with it. The hand-off addon must keep the chain out of Chef's hands, so nothing of the kind happens.
rawset(_G, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local function start(name)
  local L = rawget(_G, 'CowboyBingusModLoader')
  L.modules[name] = 'loading'
  local ok, err = pcall(require, name)
  L.modules[name] = ok and 'loaded' or ('load failed: ' .. tostring(err))
  print('[stand-in mdl3] ' .. name .. ' -> ' .. L.modules[name])
end
local function burn(seconds)
  local t0 = os.clock()
  while os.clock() - t0 < seconds do end
end
local updates = 0
function init()
  print('[stand-in mdl3] init')
  start('mods/jfredist/chef_handoff')
end
function update(dt)
  updates = updates + 1
  if updates == 900 then
    burn(3.6)
    print('[stand-in mdl3] the slow update call ended')
  end
end
function render() end
function shutdown() print('[stand-in mdl3] shutdown; updates seen: ' .. updates) end
