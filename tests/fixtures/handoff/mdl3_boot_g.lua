-- Variant G of the stand-in: like E, plus a guess at what Chef 1.5.1 found in the first real run with the hand-off 0.2.1. That run's
-- Chef log said "running the callbacks the boot script ... set before it started me (2)" although the addon had taken all of
-- them off the globals before it required Chef, and 0.2.1 wrote two log lines (two file opens) in between. This loader puts its
-- own render and shutdown back whenever they are gone, and it checks that each time something opens a file. It is a model that
-- gives the same count, not a known fact about MDL3.
rawset(_G, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local function start(name)
  local ok, err = pcall(require, name)
  print('[stand-in mdl3] ' .. name .. ' -> ' .. (ok and 'loaded' or ('load failed: ' .. tostring(err))))
end
local updates, puts = 0, 0
function init() print('[stand-in mdl3] init'); INIT_RAN = true end
function update(dt) updates = updates + 1 end
function render() end
function shutdown() print('[stand-in mdl3] shutdown; updates seen: ' .. updates .. '; callbacks put back: ' .. puts) end
local my_render, my_shutdown = render, shutdown
local real_open = io.open
io.open = function(...)
  if rawget(_G, 'render') == nil then rawset(_G, 'render', my_render); puts = puts + 1 end
  if rawget(_G, 'shutdown') == nil then rawset(_G, 'shutdown', my_shutdown); puts = puts + 1 end
  return real_open(...)
end
start('mods/jfredist/handoff_standin')
start('mods/jfredist/handoff_standin2')
start('mods/jfredist/chef_handoff')
print('[stand-in mdl3] boot done; init ran yet? ' .. tostring(rawget(_G, 'INIT_RAN')))
