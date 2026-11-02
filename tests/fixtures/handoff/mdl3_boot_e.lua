-- Variant E of the stand-in: like B (addons started while the boot runs, plain require first), but keeping NO `modules` entries,
-- only what a plain require leaves in package.loaded: that is all the first real run of the real MDL3 showed Chef ("already started
-- by another loader (started)"). The same stand-in, but it starts its addons while the boot runs (before the game calls init), and it tries every
-- addon it finds with a plain require first, the way a loader that scans the patches for HD2-Addon headers would
-- (the first stand-in Chef addon has `HD2-Requires: chef-shared-loader`, which a loader may or may not honour: this one does not;
-- the second has none and survives the require, like Treasure Radar under the real MDL3).
rawset(_G, 'CowboyBingusModLoader', { version = 21, api = 1, revision = 'stand-in-mdl3', modules = {}, game = { build_identifier = 'sim' },
  open_log = function() return { write = function() end, close = function() end } end })
local function start(name)
  local L = rawget(_G, 'CowboyBingusModLoader')
  local ok, err = pcall(require, name)
  print('[stand-in mdl3] ' .. name .. ' -> ' .. (ok and 'loaded' or ('load failed: ' .. tostring(err))))
end
local updates = 0
function init() print('[stand-in mdl3] init'); INIT_RAN = true end
function update(dt) updates = updates + 1 end
function render() end
function shutdown() print('[stand-in mdl3] shutdown; updates seen: ' .. updates) end
start('mods/jfredist/handoff_standin')
start('mods/jfredist/handoff_standin2')
start('mods/jfredist/chef_handoff')
print('[stand-in mdl3] boot done; init ran yet? ' .. tostring(rawget(_G, 'INIT_RAN')))
