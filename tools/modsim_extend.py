#!/usr/bin/env python3
"""Extends a COPY of Chef Shared Loader's simulator script (tools/modsim/modsim.lua) with a fake battlefield modelled
on what the probe saw in a real mission (first run, 2026-11-01). The simulator's own mission has 2,000 units that never
move and no game objects, so the probe's tracking would sit idle.

  python3 -I tools/modsim_extend.py <the copy's tools/modsim/modsim.lua>

Never point it at the original in a Chef checkout: make a scratch copy first (tests/chef_sim.sh does).

What the real log showed, and what this reproduces (marked SEEN); what is guessed is marked GUESS:
  SEEN   enemy kinds and their death states: warrior 09872e66.. (26,0,0,35), scavenger c14e0e88.. (18,29,1,0), hunter
         a478d36a.. (0,0,0,5), hive guard a1f37bf2.. (26,0,0,35), charger 1a7fcdff.. (12,0,15,30)
  SEEN   a unit enters its death state at the kill and keeps its state machine for 5.0 s more
  SEEN   every enemy has two sub-units without a state machine (40ae90ff.., d40f23a1..) that go with it
  SEEN   short-lived units (620769fb.., 1.6 s) near the player; the player's own parts move near the camera
  SEEN   units removed in a living state far away (despawn) and near (blown apart)
  SEEN   the game is hosted by this player: about 340 game objects are owned, in groups of one layout
         (a timer object, static objects, many enemy-like objects of a few layouts)
  GUESS  an enemy's game object has its hit points in field 22; the player's weapon has its ammo in field 3
  GUESS  UnitSynchronizer.unit_to_game_object_id(sync, unit) and game_object_id_to_unit(sync, id)
  GUESS  GameSession.objects_owned_by(session, peer) for the second player ('b2', with --join): two objects 9001, 9002
The scripted mission (the camera is at 0,0,10 looking along 0.6,0.8,0; the mission starts at 40 s):
  60..66 s  four enemies on the aim line are shot once each and die 0.4 s later; four off the aim line die with no shot
  70..71 s  a hive guard on the aim line takes four shots (600 hit points, 160 each)
  72 s, 73 s  two enemies are blown apart (removed alive); 75 s two far ones despawn
  80..81 s  a charger on the aim line takes three shots (1200 hit points, 450 each)
  60..90 s  twenty short-lived units fly around the player
  85 s      four more warriors (and their game objects) arrive"""
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    src = f.read()


def once(old, new):
    global src
    assert src.count(old) == 1, 'anchor not found exactly once (is this a modsim.lua of a different version?): ' + old[:60]
    src = src.replace(old, new)


# 1. data and helpers, before make_mission() runs
once("local function make_mission()",
     r"""-- ======================================================= BFV probe test battlefield (scratch copy only)
local OBJ, OBJ_IDS = {}, {}                 -- game objects this (host) game owns
local REMOTE_IDS = { 9001, 9002 }            -- objects of the second player (joins with --join)
local SYNC_UNIT = {}                        -- game object id -> its unit
local function vec(x, y, z) return { x = x, y = y, z = z } end
local function obj(id, fields)
  if not OBJ[id] then OBJ_IDS[#OBJ_IDS + 1] = id end
  OBJ[id] = { fields = fields }
end
local function drop_obj(id)
  OBJ[id] = nil
  for i, x in ipairs(OBJ_IDS) do if x == id then table.remove(OBJ_IDS, i) break end end
end
local ATT_A, ATT_B, PROJ = '40ae90fff236865b', 'd40f23a128bd988d', '620769fb47f74906'
local KINDS = {          -- kind, living states, death state, hit points
  warrior   = { '09872e66d1276e1f', { { 12, 0, 0, 19 }, { 4, 0, 0, 19 } }, { 26, 0, 0, 35 }, 150 },
  scavenger = { 'c14e0e887e7d2106', { { 10, 18, 0, 0 }, { 2, 18, 0, 0 } }, { 18, 29, 1, 0 }, 50 },
  hunter    = { 'a478d36a62a861f4', { { 2, 0, 32, 1 }, { 8, 0, 32, 1 } }, { 0, 0, 0, 5 }, 100 },
  guard     = { 'a1f37bf2a40fbde4', { { 12, 0, 0, 19 }, { 10, 0, 0, 19 } }, { 26, 0, 0, 35 }, 600 },
  charger   = { '1a7fcdff98c664b0', { { 10, 0, 15, 30 } }, { 12, 0, 15, 30 }, 1200 },
  brood     = { '583ecde0d7718126', { { 6, 0, 0, 0 }, { 3, 0, 0, 0 } }, { 20, 3, 0, 7 }, 80 },   -- not in the probe's seeds
}
local EXTRA = { warrior = { [24] = 0, [26] = false }, scavenger = {}, hunter = { [21] = 0 }, guard = { [24] = true, [27] = 0 },
                charger = { [26] = true }, brood = { [24] = 5 } }
local SPARK = 'f00dfeed00000001'              -- a short-lived kind the probe does not know (it should stop following it)
local next_obj = 1000
local function layout(name, x, y, z, hp)       -- GUESS: field 22 is the hit points
  local f = { [1] = 0, [2] = vec(x, y, z), [3] = vec(0, 0, 0), [4] = false, [6] = 0, [7] = false, [8] = 32767,
              [9] = 'owner-' .. name, [10] = 1, [11] = 80, [12] = 0, [13] = 'id-' .. name, [16] = 2, [17] = 0, [18] = 0,
              [19] = false, [20] = 32767, [22] = hp, [23] = 12345, [25] = 1 }
  for k, v in pairs(EXTRA[name]) do f[k] = v end
  return f
end
local function add_unit(m, u)
  m.units[#m.units + 1] = u
  m.movers[#m.movers + 1] = u
  return u
end
-- an enemy: its body (state machine) and the two sub-units that go with it, and its game object
local function add_enemy(m, name, x, y, z, vx, vy, plan)
  local K = KINDS[name]
  local id = next_obj; next_obj = next_obj + 1
  local b = unit(K[1], x, y, z, { sm = true, state = K[2][1], vx = vx, vy = vy, objid = id, kname = name, plan = plan or {} })
  add_unit(m, b)
  b.parts = { add_unit(m, unit(ATT_A, x, y, z, { parent = b })), add_unit(m, unit(ATT_B, x, y, z, { parent = b })) }
  obj(id, layout(name, x, y, z, K[4]))
  SYNC_UNIT[id] = b
  m.enemies[#m.enemies + 1] = b
  return b
end
local function remove_unit(m, u)
  u.alive = false
  for i, x in ipairs(m.units) do if x == u then table.remove(m.units, i) break end end
end
local function remove_enemy(m, b)
  for _, p in ipairs(b.parts) do remove_unit(m, p) end
  remove_unit(m, b)
  drop_obj(b.objid)
  SYNC_UNIT[b.objid] = nil
end
local AIM_DIR, AIM_PERP = { 0.6, 0.8 }, { -0.8, 0.6 }
local function on_axis(d) return AIM_DIR[1] * d, AIM_DIR[2] * d, 9 end          -- at the camera's height: the aim target
local function off_axis(d, deg)
  local a = math.rad(deg)
  return d * (math.cos(a) * AIM_DIR[1] + math.sin(a) * AIM_PERP[1]), d * (math.cos(a) * AIM_DIR[2] + math.sin(a) * AIM_PERP[2]), 0
end
local function shots(list) for _, ts in ipairs(list) do CLICK[#CLICK + 1] = { 'left', ts } end end

local function make_mission()""")

# 2. the mission world: enemies, parts, objects (CLICK exists by now: modsim.py's settings come first)
once("  filler(m.units, 2000, 30)\n  return m\nend",
     r"""  filler(m.units, 2000, 30)
  m.movers, m.enemies, m.later = {}, {}, {}
  -- the player's own parts, moving about the camera
  for i, kind in ipairs({ '1c8764d62e12925a', 'a9936cbe561e8180', 'dbb6c961c59fadc1', '619795f79ceda1b3', '006e44327bb953fe' }) do
    add_unit(m, unit(kind, 0.5 * i, 0.5, 8 + i * 0.1, { sm = (i % 2 == 0), state = { i, 0, 1, 0 }, wob = i }))
  end
  -- on the aim line, shot once each; dies 0.4 s after the shot
  for _, e in ipairs({ { 'warrior', 30, 60.0 }, { 'scavenger', 45, 62.0 }, { 'hunter', 60, 64.0 }, { 'scavenger', 25, 66.0 } }) do
    local x, y, z = on_axis(e[2])
    add_enemy(m, e[1], x, y, z, 0.001, 0.001, { hits = { e[3] }, dmg = 1000, die = e[3] + 0.4 })
    shots({ e[3] })
  end
  -- off the aim line: killed by someone else (no shot)
  for i, e in ipairs({ { 'warrior', 30, 40, 61.0 }, { 'scavenger', 40, -35, 63.0 }, { 'hunter', 35, 60, 65.0 }, { 'guard', 50, -50, 67.0 } }) do
    local x, y, z = off_axis(e[2], e[3])
    add_enemy(m, e[1], x, y, z, 0.2, 0.1, { die = e[4] })
  end
  -- a hive guard on the aim line that takes four shots, a charger that takes three
  do
    local x, y, z = on_axis(50)
    add_enemy(m, 'guard', x, y, z, 0.001, 0.001, { hits = { 70.0, 70.4, 70.8, 71.2 }, dmg = 160, die = 71.6 })
    shots({ 70.0, 70.4, 70.8, 71.2 })
    x, y, z = on_axis(60)
    add_enemy(m, 'charger', x, y, z, 0.12, 0.16, { hits = { 80.0, 80.5, 81.0 }, dmg = 450, die = 81.4 })
    shots({ 80.0, 80.5, 81.0 })
  end
  -- SEEN: 0,0,0,1 is the hunter's death state but was also met before the last state: it passes through it and comes back
  do
    local x, y, z = off_axis(40, -60)
    add_enemy(m, 'hunter', x, y, z, 0.4, 0.2, { flick = { at = 68.0, len = 1.2, back = { 8, 0, 32, 1 } } })
  end
  -- a kind the probe has to learn the death state of: three die, the third one after the machine of the first went away
  for i, at in ipairs({ 84.0, 86.0, 93.0 }) do
    local x, y, z = off_axis(30 + i * 3, 50 - i * 20)
    add_enemy(m, 'brood', x, y, z, 0.4, 0.3, { die = at })
  end
  for i = 1, 3 do                                    -- (and some that live on, so the kind moves)
    local x, y, z = off_axis(50 + i * 5, 30 + i * 10)
    add_enemy(m, 'brood', x, y, z, 0.5, 0.2, {})
  end
  -- blown apart (removed alive), and despawned far away
  do
    local x, y, z = off_axis(35, 20)
    add_enemy(m, 'scavenger', x, y, z, 0.3, 0.2, { destroy = 72.0 })
    x, y, z = off_axis(30, -25)
    add_enemy(m, 'warrior', x, y, z, 0.3, 0.2, { destroy = 73.0 })
    x, y, z = off_axis(140, 10)
    add_enemy(m, 'guard', x, y, z, 0.3, 0.2, { destroy = 75.0 })
    x, y, z = off_axis(145, -10)
    add_enemy(m, 'scavenger', x, y, z, 0.3, 0.2, { destroy = 75.0 })
  end
  -- twenty wanderers that never die: they make every kind a mover
  local names = { 'warrior', 'scavenger', 'hunter', 'guard', 'scavenger' }
  for i = 1, 20 do
    local x, y, z = off_axis(25 + (i * 7) % 60, ((i * 37) % 160) - 80)
    add_enemy(m, names[(i % #names) + 1], x, y, z, 0.5 + (i % 3) * 0.4, 0.3, {})
  end
  -- short-lived units flying around the player (SEEN: 620769fb.., 1.6 s)
  for i = 1, 20 do
    m.later[#m.later + 1] = { at = 60 + i * 1.5, kind = PROJ, x = 3 + (i % 5) * 2, y = 3 + (i % 4) * 2, z = 9, life = 1.6 }
  end
  -- GUESS: another short-lived kind. A few live long enough to be known as movers, then sixty come and go within 1.6 s
  for i = 1, 4 do
    m.later[#m.later + 1] = { at = 41 + i * 0.5, kind = SPARK, x = 6 + i, y = 5, z = 9, life = 45 }
  end
  for i = 1, 60 do
    m.later[#m.later + 1] = { at = 50 + i * 0.5, kind = SPARK, x = 4 + (i % 3), y = 4 + (i % 4), z = 9, life = 1.6 }
  end
  -- the game objects (SEEN: layouts and counts; GUESS: the meaning of the fields marked)
  obj(0, { [1] = true, [2] = 668, [3] = 257, [10] = 1, [11] = 456121928, [12] = 2002245864, [14] = 1, [20] = 4, [21] = 58, [25] = 1 })
  obj(331, { [2] = false, [3] = 4308 })
  obj(337, { [1] = 2400, [6] = 0, [7] = vec(1, 0, 0), [8] = vec(1, 0, 0), [9] = vec(1, 0, 1), [10] = vec(1, 0, 0),
             [11] = vec(1, 0, 0), [12] = vec(1, 0, 0), [13] = 1, [15] = true, [17] = 0, [18] = 0, [19] = 0, [20] = 0, [21] = false, [22] = false })
  obj(338, { [1] = 'player-id-1', [2] = 0, [3] = 0, [4] = 1, [8] = vec(-306.7, -21.9, -2.9), [9] = vec(0, 0, 0.98), [10] = false })
  obj(346, { [1] = 'player-id-2', [2] = 0, [3] = 1, [7] = vec(-252.1, -137.1, -3.8), [8] = vec(0, 0, -0.8), [9] = false })
  obj(359, { [1] = false, [2] = true, [3] = 32, [4] = 32, [5] = 21.744, [6] = 8, [7] = false, [8] = false })   -- GUESS: [3] is the ammo
  -- the player object and its avatar are made late (high ids) like in the game; GUESS: the player's field 3 counts kills
  obj(611, { [1] = 'player-id-1', [2] = 612, [3] = 0, [4] = 0 })
  obj(612, { [1] = vec(0, 0, 10), [2] = 0, [3] = 100, [64] = { [25] = 32767 } })
  for _, id in ipairs(REMOTE_IDS) do OBJ[id] = { fields = { [1] = 'remote-player', [2] = vec(5, 5, 9), [3] = id } } end
  for i = 1, 150 do obj(2000 + i, { [1] = 0, [2] = vec(i, i, 0), [3] = vec(0, 0, 0) }) end                      -- decor-like crowd
  for i = 1, 120 do obj(3000 + i, { [1] = 0, [2] = vec(i, -i, 0), [3] = vec(0, 0, 0), [4] = false, [5] = 0 }) end -- another crowd
  return m
end""")

# 3. state machine calls on units
once("    num_lights = function(u) live(u) return u.lights or 0 end,",
     """    num_lights = function(u) live(u) return u.lights or 0 end,
    has_animation_state_machine = function(u) live(u) return u.sm == true end,
    animation_get_state = function(u) live(u) local s = u.state or {} return s[1], s[2], s[3], s[4] end,""")

# 4. game session reads and the unit synchronizer
once("    synchronizing_peers = function() if JOIN and t >= JOIN and t < JOIN + 3 then return { 'b2' } end return {} end },\n}",
     """    synchronizing_peers = function() if JOIN and t >= JOIN and t < JOIN + 3 then return { 'b2' } end return {} end,
    objects_owned_by = function(s, peer)
      local out = {}
      local src = (peer == 'b2') and REMOTE_IDS or OBJ_IDS
      for i, id in ipairs(src) do out[i] = id end
      return out
    end,
    other_peers = function() if JOIN and t >= JOIN then return { 'b2' } end return {} end,
    game_object_owner = function(s, id) return (id == 9001 or id == 9002) and 'b2' or 'a1' end,
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
  UnitSynchronizer = {
    unit_to_game_object_id = function(sync, u) live(u) return u.objid end,
    game_object_id_to_unit = function(sync, id) local u = SYNC_UNIT[id]; if u and u.alive then return u end end },
}""")

# 5. the script, inside the frame loop
once("  stats.frame_rects = 0\n  update(1 / 60)",
     r"""  do
    local w = main()
    if w.movers then
      -- walkers; sub-units follow their body; the player's parts wobble about the camera
      for _, u in ipairs(w.movers) do
        if u.alive then
          if u.parent then u.pos.x, u.pos.y, u.pos.z = u.parent.pos.x, u.parent.pos.y, u.parent.pos.z
          elseif u.wob then u.pos.x = 0.5 * u.wob + 0.8 * math.sin(t * 2 + u.wob)
          elseif u.vx and not u.dying then u.pos.x = u.pos.x + u.vx / 60; u.pos.y = u.pos.y + u.vy / 60 end
        end
      end
      -- short-lived units
      for i = #w.later, 1, -1 do
        local s = w.later[i]
        if t >= s.at then
          local u = unit(s.kind, s.x, s.y, s.z, { vx = 5, vy = 3, die = t + s.life })
          w.units[#w.units + 1] = u; w.movers[#w.movers + 1] = u
          table.remove(w.later, i)
        end
      end
      for _, u in ipairs(w.movers) do
        if u.alive and u.die and t >= u.die then remove_unit(w, u) end
      end
      -- the scripted enemies
      if w == mission and not next_mission then
        for _, e in ipairs(w.enemies) do
          local p = e.plan
          if e.alive and p then
            for i, th in ipairs(p.hits or {}) do
              if t >= th and not p['h' .. i] then
                p['h' .. i] = true
                local o = OBJ[e.objid]
                if o then o.fields[22] = o.fields[22] - p.dmg end
                if not e.dying and e.kname ~= 'charger' then e.flinch = t + 0.3; e.state_keep = e.state; e.state = { 5, 0, 0, 7 } end   -- GUESS: a hit reaction
                OBJ[359].fields[3] = OBJ[359].fields[3] - 1                      -- GUESS: ammo
              end
            end
            if p.flick and t >= p.flick.at and not p.flicked then p.flicked = t; p.keep = e.state; e.state = { 0, 0, 0, 1 } end
            if p.flicked and not p.flickback and t >= p.flicked + p.flick.len then p.flickback = true; e.state = p.flick.back end
            if p.die and t >= p.die and not e.dying then
              e.dying = true; e.state = KINDS[e.kname][3]; e.gone_at = t + 5.0
              OBJ[611].fields[3] = OBJ[611].fields[3] + (p.hits and 1 or 0)          -- GUESS: the player's kill counter
              if not p.hits and OBJ[e.objid] then OBJ[e.objid].fields[22] = 0 end    -- GUESS: hit points reach 0 for other reasons too
            end
            if e.flinch and t >= e.flinch then e.flinch = nil; if not e.dying then e.state = e.state_keep end end
            if e.alive and OBJ[e.objid] and not e.dying then OBJ[e.objid].fields[2] = vec(e.pos.x, e.pos.y, e.pos.z) end   -- positions follow the unit
            if e.dying and e.sm and t >= e.gone_at then
              e.sm = false
              for _, part in ipairs(e.parts) do remove_unit(w, part) end         -- SEEN: the sub-units go when the state machine does
              drop_obj(e.objid)
            end
            if p.destroy and t >= p.destroy then remove_enemy(w, e); e.plan = nil end
          end
        end
        if t >= 85 and not w.reinforced then                                         -- more enemies (and their objects) arrive
          w.reinforced = true
          for i = 1, 4 do
            local x, y, z = off_axis(40 + i * 3, 20 * i - 50)
            add_enemy(w, 'warrior', x, y, z, 0.3, 0.2, {})
          end
        end
        OBJ[337].fields[1] = 2400 - t                                                -- SEEN: a timer, and counters that tick
        OBJ[337].fields[18] = math.floor(t * 5)
        OBJ[612].fields[1] = vec(t * 0.01, 0, 10)
      end
    end
  end
  stats.frame_rects = 0
  update(1 / 60)""")

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(src)
print('extended', path)
