-- HD2-Addon: mods/jfredist/handoff_standin2
-- A stand-in for a Chef mod like Treasure Radar (tests/handoff_sim.sh): no `HD2-Requires: chef-shared-loader` line, its helpers
-- from `local chef = ...`, and a load that survives a plain require (nothing is called on `chef` while loading except behind a
-- type() check), so another loader that starts every addon "starts" it with nothing to run on. Chef then takes it for running.
local chef = ...
if type(chef.own_log) == 'function' then chef.own_log('handoff_standin2') end
local frames = 0
local M = { version = '0.0.2' }
function M.update(dt) frames = frames + 1 end
function M.render()
  if not chef.in_mission() then return end
  chef.rect(200, 100, 50, 20, chef.color(0, 200, 255, 255), 900)
end
function M.shutdown() chef.log('stand-in 2: %d frames', frames) end
return M
