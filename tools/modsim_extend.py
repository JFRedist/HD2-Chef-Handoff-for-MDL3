#!/usr/bin/env python3
"""Extends a COPY of Chef Shared Loader's simulator script (tools/modsim/modsim.lua) with enough of a fake battlefield
for the probe: walking enemies that have animation state machines, scripted deaths, and a few network game objects.

  python3 -I tools/modsim_extend.py <the copy's tools/modsim/modsim.lua>

Chef's own simulator has a mission with 2,000 units that never move and no game objects, so the probe's whole tracking
path would sit idle. With this, the probe runs on the REAL Chef Shared Loader (its sandbox, its unit helpers, its
crash model) over a world where things happen. Never point it at the original in a Chef checkout: make a scratch copy
first (tests/chef_sim.sh does).

What it adds to the simulated mission (camera at 0,0,10 looking along 0.6,0.8,0):
  10 bugs of kind aaaa000000000001, 3 'chargers' (1a7fcdff98c664b0, a heavy in the MDL3 build's tier table),
  2 squadmates (dddd000000000001), and one bug straight ahead at 40 m and the camera's height (the aim target),
  each with a state machine; and the game objects 100 (the player: field 3 counts kills), 101 (the avatar, moving
  every frame), 102, and one object (field 1: health) per bug.
Script (normal scenario): t=60 the target enters state 7, t=60.5 its state machine goes away and the player's kill
counter becomes 1, t=61 every enemy object's health becomes 40, t=65 a bug is destroyed, t=70 a charger enters state
12, t=72 its state machine goes away."""
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    src = f.read()


def once(old, new):
    global src
    assert src.count(old) == 1, 'anchor not found exactly once (is this a modsim.lua of a different version?): ' + old[:60]
    src = src.replace(old, new)


# 1. movers in the mission world
once("  filler(m.units, 2000, 30)\n  return m\nend",
     """  filler(m.units, 2000, 30)
  m.movers = {}
  local function mover(kind, x, y, z, vx, vy, extra)
    local u = unit(kind, x, y, z, { sm = true, state = { 1, 0, 0, 0 }, vx = vx, vy = vy })
    for k, v in pairs(extra or {}) do u[k] = v end
    m.units[#m.units + 1] = u
    m.movers[#m.movers + 1] = u
    return u
  end
  for i = 1, 10 do mover('aaaa000000000001', (7 * i) % 40 - 10, 5 + (9 * i) % 50, 0, 0.5, 0.3, { objid = 2000 + i }) end
  for i = 1, 3 do mover('1a7fcdff98c664b0', 20 + i * 4, 30 + i * 3, 0, 0.3, 0.2, { objid = 2100 + i }) end
  for i = 1, 2 do mover('dddd000000000001', -5 + i, -10, 0, 0.2, 0.2) end
  m.target = mover('aaaa000000000001', 24, 32, 9, 0.0001, 0.0001, { objid = 2200 })
  return m
end""")

# 2. network game objects and the scripted state, defined before the engine tables
once("local overlay = { t = 0, levels = 0, units = {} }",
     """local OBJ = {
  [100] = { fields = { [1] = 1, [2] = 42, [3] = 0, [4] = 0, [5] = 0, [6] = false } },
  [101] = { fields = { [1] = { x = 0, y = 0, z = 0 }, [2] = 0, [3] = 100, [64] = { [25] = 32767 } } },
  [102] = { fields = { [1] = 30, [2] = 'rifle' } },
}
for i = 1, 10 do OBJ[2000 + i] = { fields = { [1] = 100, [2] = 0 } } end
for i = 1, 3 do OBJ[2100 + i] = { fields = { [1] = 100, [2] = 0 } } end
OBJ[2200] = { fields = { [1] = 100, [2] = 0 } }
local sc = {}
local overlay = { t = 0, levels = 0, units = {} }""")

# 3. state machine calls on units
once("    num_lights = function(u) live(u) return u.lights or 0 end,",
     """    num_lights = function(u) live(u) return u.lights or 0 end,
    has_animation_state_machine = function(u) live(u) return u.sm == true end,
    animation_get_state = function(u) live(u) local s = u.state or {} return s[1], s[2], s[3], s[4] end,""")

# 4. game session reads and the unit synchronizer (the signature of unit_to_game_object_id is a guess)
once("    synchronizing_peers = function() if JOIN and t >= JOIN and t < JOIN + 3 then return { 'b2' } end return {} end },\n}",
     """    synchronizing_peers = function() if JOIN and t >= JOIN and t < JOIN + 3 then return { 'b2' } end return {} end,
    objects_owned_by = function(s, peer) return { 100, 101, 102 } end,
    game_object_exists = function(s, id) return OBJ[id] ~= nil end,
    game_object_field_batched = function(s, id, tbl)
      local o = OBJ[id]
      if not o then error('no such game object') end
      local out = {}
      for k, v in pairs(o.fields) do
        if type(v) == 'table' then local c = {} for k2, v2 in pairs(v) do c[k2] = v2 end out[k] = c else out[k] = v end
      end
      return out
    end,
    unit_synchronizer = function(s) return { sync = 1 } end },
  UnitSynchronizer = { unit_to_game_object_id = function(sync, u) live(u) return u.objid end },
}""")

# 5. the script, inside the frame loop
once("  stats.frame_rects = 0\n  update(1 / 60)",
     """  do
    local w = main()
    if w.movers then
      for _, u in ipairs(w.movers) do
        if u.alive and u.sm then u.pos.x = u.pos.x + u.vx / 60; u.pos.y = u.pos.y + u.vy / 60 end
      end
      OBJ[101].fields[1] = { x = t, y = 0, z = 0 }
      OBJ[101].fields[2] = t
      if w == mission and not next_mission then
        if t >= 60.0 and not sc.a then sc.a = true; w.target.state = { 7, 0, 0, 0 } end
        if t >= 60.5 and not sc.b then sc.b = true; w.target.sm = false; OBJ[100].fields[3] = 1 end
        if t >= 61 and not sc.c then sc.c = true; for id, o in pairs(OBJ) do if id >= 2000 then o.fields[1] = 40 end end end
        if t >= 65 and not sc.d then
          sc.d = true
          local b = w.movers[3]
          b.alive = false
          for i, x in ipairs(w.units) do if x == b then table.remove(w.units, i) break end end
        end
        if t >= 70 and not sc.e then sc.e = true; w.movers[11].state = { 12, 0, 0, 0 } end
        if t >= 72 and not sc.f then sc.f = true; w.movers[11].sm = false end
      end
    end
  end
  stats.frame_rects = 0
  update(1 / 60)""")

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(src)
print('extended', path)
