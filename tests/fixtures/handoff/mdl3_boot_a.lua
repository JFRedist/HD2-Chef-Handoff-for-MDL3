-- A stand-in for another loader's boot (what MDL3's boot really does is not known to this repository; this does what the
-- BF5 MDL3 build expects of its host): the Boot Mod Loader style tables, the game's callbacks, and its addons started
-- with require once the game calls init. It never starts Chef.
rawset(_G, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local function start(name)
  local L = rawget(_G, 'CowboyBingusModLoader')
  L.modules[name] = 'loading'
  local ok, err = pcall(require, name)
  L.modules[name] = ok and 'loaded' or ('load failed: ' .. tostring(err))
  print('[stand-in mdl3] ' .. name .. ' -> ' .. L.modules[name])
end
local updates = 0
function init()
  print('[stand-in mdl3] init')
  start('mods/jfredist/chef_handoff')
end
function update(dt) updates = updates + 1 end
function render() end
function shutdown() print('[stand-in mdl3] shutdown; updates seen: ' .. updates) end
