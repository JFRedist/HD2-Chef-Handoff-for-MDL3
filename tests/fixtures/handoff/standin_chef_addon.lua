-- HD2-Addon: mods/jfredist/handoff_standin
-- HD2-Requires: chef-shared-loader >= 1.0.0
-- A stand-in for a mod made for Chef (HUDdle, say), for tests/handoff_sim.sh: it logs that it started, draws a rectangle
-- every frame and counts its frames. It needs the `chef` table, so it can only run under Chef.
local chef = ...
if type(chef) ~= 'table' then return end
local frames = 0
local M = { version = '0.0.1' }
chef.log('stand-in addon started on %s %s', tostring(chef.loader), tostring(chef.loader_version))
function M.update(dt) frames = frames + 1 end
function M.render()
  if not chef.in_mission() then return end
  chef.rect(100, 100, 50, 20, chef.color(255, 200, 0, 255), 900)
end
function M.shutdown() chef.log('stand-in addon: %d frames', frames) end
return M
