-- The same stand-in, but this loader hands off to Chef itself, from its boot (as Chef's documentation asks of loaders
-- that want to host it). The hand-off addon must notice that Chef is running and leave it alone.
local A = rawget(_G, 'stingray') and stingray.Application
rawset(_G, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local updates = 0
function init() print('[stand-in mdl3] init') end
function update(dt) updates = updates + 1 end
function render() end
function shutdown() print('[stand-in mdl3] shutdown; updates seen: ' .. updates) end
if A and A.can_get('lua', 'mods/chef_shared_loader/core_1') and rawget(_G, 'ChefSharedLoader') == nil then
  rawset(_G, 'ChefSharedLoaderHandoff', { from = 'stand-in MDL3 (own hand-off)' })
  require('mods/chef_shared_loader/core_1')
end
local L = rawget(_G, 'CowboyBingusModLoader')
L.modules['mods/jfredist/chef_handoff'] = 'loading'
local ok, err = pcall(require, 'mods/jfredist/chef_handoff')
L.modules['mods/jfredist/chef_handoff'] = ok and 'loaded' or ('load failed: ' .. tostring(err))
print('[stand-in mdl3] chef_handoff -> ' .. L.modules['mods/jfredist/chef_handoff'])
