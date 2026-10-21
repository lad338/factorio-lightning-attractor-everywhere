-- Computed once at load, not rebuilt on every build/blueprint/death
-- event: prototypes never change at runtime.
--
-- Only includes a name if its "-solar" duplicate prototype actually
-- exists -- `type = "lightning-attractor"` alone isn't enough, since
-- Fulgora's decorative ruin variants match the type filter but have
-- no energy_source and so never got a duplicate from
-- prototypes/entity/solar-duplicates.lua. Checking for the duplicate's
-- existence, rather than re-deriving which originals were skipped and
-- why, stays correct even if that skip logic changes.
local ORIGINAL_NAMES = {}
for name, _ in pairs(prototypes.get_entity_filtered{{filter = "type", type = "lightning-attractor"}}) do
  if prototypes.entity[name .. "-solar"] then
    ORIGINAL_NAMES[name] = true
  end
end

local function original_names()
  return ORIGINAL_NAMES
end

-- The engine refuses to build (or revive a ghost of) a
-- lightning-attractor-type entity on a surface with no
-- lightning_properties at all -- "Cannot be built on a surface
-- without lightning" -- enforced before on_built_entity fires, so it
-- can't be intercepted there. Scripted placement (surface.create_entity)
-- is exempt from this restriction; only a real player's direct click
-- is blocked.
--
-- So every item that places an original is redirected (in
-- solar-duplicates.lua) to place its solar-panel duplicate instead,
-- which is never restricted anywhere. The swap here is symmetric: a
-- duplicate built or revived where the surface actually has lightning
-- is corrected to the real original via script (exempt); an original
-- built or revived where the surface lacks lightning is corrected to
-- the duplicate. `correct_name` returns the name the entity should
-- have, or nil if it's already correct.
local function correct_name(current_name, has_lightning)
  local original = current_name:match("^(.+)%-solar$")
  if original then
    if has_lightning and ORIGINAL_NAMES[original] then
      return original
    end
    return nil
  end
  if ORIGINAL_NAMES[current_name] and not has_lightning then
    return current_name .. "-solar"
  end
  return nil
end

local function maybe_swap(entity)
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  -- No fixed planet (e.g. a space platform) reads the surface
  -- property's own default (0 = "not lightning"), same as any other
  -- non-lightning planet.
  local has_lightning = surface.get_property("lightning-attractor-everywhere-is-lightning") > 0

  if entity.type == "entity-ghost" then
    -- A ghost of either variant can exist on any surface -- only a
    -- real entity's placement/revival is restricted. Swapping the
    -- ghost itself the moment it appears (blueprint paste, undo, the
    -- death-ghost handler below, or a direct force-ghost-build with
    -- the redirected item) means whatever revives it later never hits
    -- the restriction at all.
    local target = correct_name(entity.ghost_name, has_lightning)
    if not target then return end
    local position, direction, force, quality = entity.position, entity.direction, entity.force, entity.quality
    entity.destroy()
    surface.create_entity{
      name = "entity-ghost",
      inner_name = target,
      position = position,
      direction = direction,
      force = force,
      quality = quality,
    }
    return
  end

  local target = correct_name(entity.name, has_lightning)
  if not target then return end
  surface.create_entity{
    name = target,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    quality = entity.quality,
    fast_replace = true,
    spill = false,
  }
end

script.on_event(defines.events.on_built_entity, function(event)
  -- The event's field is `entity`, not `created_entity`.
  maybe_swap(event.entity)
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
  maybe_swap(event.entity)
end)

-- Covers scripted placement too (map editor, other mods' automation,
-- create_entity{raise_built = true}) -- on_built_entity can't be
-- raised through script.raise_event, so script_raised_built is the
-- only way to reach this logic without a real connected player.
script.on_event(defines.events.script_raised_built, function(event)
  maybe_swap(event.entity)
end)

-- Covers a script manually reviving a ghost with raise_revive = true
-- (same event.entity shape as script_raised_built) -- a real
-- construction robot's own revival fires on_robot_built_entity
-- instead, already covered above.
script.on_event(defines.events.script_raised_revive, function(event)
  maybe_swap(event.entity)
end)

-- Rewrites a captured blueprint's entities to their "-solar" duplicate
-- name, so the blueprint is always safely placeable/ghostable on any
-- surface. Blueprint-paste placement is NOT exempt from the engine's
-- lightning-surface restriction (only a mod's own script-driven
-- create_entity calls are) -- a blueprint storing the restricted
-- original name can fail to even create a ghost on a non-lightning
-- surface, regardless of where it was captured. The duplicate reuses
-- the original's own localised_name/icon/placeable_by, so this is
-- invisible in the blueprint UI; maybe_swap (already wired to
-- on_built_entity/on_robot_built_entity/script_raised_built, for both
-- real entities and ghosts) upgrades it to the real original on paste
-- wherever the destination surface actually has lightning.
-- `bp` is a LuaItemStack (blueprint in hand) or a LuaRecord (a
-- blueprint-library entry re-selected rather than freshly captured) --
-- event.stack is nil for the latter case. Both expose
-- get_blueprint_entities/set_blueprint_entities the same way, just
-- under a different validity attribute.
local function rewrite_blueprint_entities(bp)
  if not bp then return end
  if bp.object_name == "LuaItemStack" and not bp.valid_for_read then return end
  if bp.object_name == "LuaRecord" and not bp.valid_for_write then return end
  local entities = bp.get_blueprint_entities()
  if not entities then return end

  local changed = false
  for _, bp_entity in pairs(entities) do
    if original_names()[bp_entity.name] then
      bp_entity.name = bp_entity.name .. "-solar"
      changed = true
    end
  end
  if changed then
    bp.set_blueprint_entities(entities)
  end
end

script.on_event(defines.events.on_player_setup_blueprint, function(event)
  -- Re-selecting a blueprint from the library sets event.record
  -- instead of event.stack.
  rewrite_blueprint_entities(event.stack or event.record)
end)

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  local original = entity.name:match("^(.+)%-solar$")
  if not original then return end
  if not original_names()[original] then return end
  -- Respect the force's own create_ghost_on_entity_death setting --
  -- the duplicate's own create_ghost_on_death = false means vanilla
  -- never does this for us, so this manual replacement has to check
  -- it too.
  if not entity.force.create_ghost_on_entity_death then return end

  -- Create the ghost as the ORIGINAL and let maybe_swap's own
  -- ghost-handling branch correct it to the duplicate if needed
  -- (raise_built = true routes through script_raised_built, which
  -- that branch already listens to).
  entity.surface.create_entity{
    name = "entity-ghost",
    inner_name = original,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    quality = entity.quality,
    raise_built = true,
  }
end)

-- Night output runs in BURSTS: a randomized number of quick,
-- symmetric rise/fall peaks in rapid succession (each falling all the
-- way to 0 between peaks), followed by a sustained, randomized flat-0
-- hold before the next burst. `solar_coefficient_property` is
-- per-surface, shared by every duplicate on that surface -- there's
-- no per-entity lever for a solar-panel's output. The discharge flash
-- runs continuously through each climb and fall, and the real
-- "lightning striking the attractor" animation fires once, exactly
-- when a peak is reached.
local DRIFT_INTERVAL = 30       -- ease/check every 0.5 seconds
local RISE_EASE_FACTOR = 0.5
local FALL_EASE_FACTOR = 0.5
local REACHED_THRESHOLD = 0.02  -- how close to target counts as "arrived" (asymptotic ease never hits it exactly)

-- Vanilla's own "lightning" entity has a fixed energy = 1000MJ -- real
-- strikes never vary in size, only timing. This skew (concentrating
-- most peaks near the floor, rare ones near the ceiling) is this
-- mod's own stylistic choice, not a vanilla-derived figure.
local PEAK_MIN, PEAK_MAX = 5.2, 20.0
local PEAK_SKEW = 3  -- cubing a uniform [0,1) sample concentrates it near 0
local ZERO_LEVEL = 0

local MIN_PEAKS_PER_BURST, MAX_PEAKS_PER_BURST = 1, 5

local function random_peak()
  return PEAK_MIN + (math.random() ^ PEAK_SKEW) * (PEAK_MAX - PEAK_MIN)
end

local function random_peaks_per_burst()
  return math.random(MIN_PEAKS_PER_BURST, MAX_PEAKS_PER_BURST)
end

-- Borrowed from Fulgora's own lightning_properties.lightnings_per_chunk_per_tick
-- (~0.0016667, i.e. a mean interval of 600 ticks per chunk): a
-- constant per-tick strike probability is a Poisson process, whose
-- inter-arrival times are exponentially distributed (memoryless:
-- mostly short gaps, with a long tail of rare long ones). Reused that
-- same ~600-tick figure as the mean for how long the flat-0 hold
-- between bursts lasts.
local MEAN_ZERO_HOLD_TICKS = 600
local MAX_ZERO_HOLD_TICKS = 3600  -- hard cap: the exponential's long tail could otherwise stall a surface for an absurd stretch

local function random_zero_hold_ticks()
  -- Inverse-CDF sampling of an exponential distribution with the
  -- given mean: -mean * ln(1 - u), u ~ Uniform[0, 1).
  return math.min(MAX_ZERO_HOLD_TICKS, -MEAN_ZERO_HOLD_TICKS * math.log(1 - math.random()))
end

local function drift_state(surface)
  storage.night_drift = storage.night_drift or {}
  local state = storage.night_drift[surface.index]
  if not state then
    state = {
      current = 1,
      target = random_peak(),
      attacking = true,
      zero_hold_remaining = 0,
      peaks_remaining = random_peaks_per_burst(),
    }
    storage.night_drift[surface.index] = state
  end
  return state
end

script.on_nth_tick(DRIFT_INTERVAL, function()
  for _, surface in pairs(game.surfaces) do
    local state = drift_state(surface)

    if state.zero_hold_remaining > 0 then
      -- Idle at 0 between bursts -- the property is already at
      -- ZERO_LEVEL from the fall that just finished, so there's
      -- nothing to ease; just count the hold down.
      state.zero_hold_remaining = state.zero_hold_remaining - DRIFT_INTERVAL
      goto continue
    end

    do
      local ease = state.attacking and RISE_EASE_FACTOR or FALL_EASE_FACTOR
      state.current = state.current + (state.target - state.current) * ease
      surface.set_property("lightning-attractor-everywhere-night", state.current)

      -- Flash on every step of both the climb and the fall, not just
      -- the instant a peak is reached, so the animation is visibly
      -- running throughout each build-up and drop; silent only during
      -- the flat-0 hold (the `goto continue` above already skips that
      -- entirely). Darkness-gated since performance_at_day = 0 makes
      -- the output, and so the flash, meaningless during the day
      -- regardless of the coefficient. time_to_live is slightly longer
      -- than the retrigger interval so each new flash overlaps the
      -- tail of the previous one.
      if surface.darkness > 0.5 then
        for _, entity in pairs(surface.find_entities_filtered{type = "solar-panel"}) do
          local original = entity.name:match("^(.+)%-solar$")
          if original and original_names()[original] then
            rendering.draw_animation{
              animation = original .. "-solar-discharge-animation",
              target = entity,
              surface = surface,
              time_to_live = DRIFT_INTERVAL + 10,
              -- draw_animation defaults render_layer to "arrow" (meant
              -- for UI indicators); "light-effect" is the layer meant
              -- for this kind of additive glow.
              render_layer = "light-effect",
            }
          end
        end
      end

      if math.abs(state.target - state.current) < REACHED_THRESHOLD then
        if state.attacking then
          -- Reached a peak -- play the real "lightning striking the
          -- attractor" animation once, on top of the continuous
          -- discharge glow already playing, then fall back to 0.
          -- No runtime existence check for the animation name:
          -- `prototypes.animation` isn't an indexable table at all
          -- (LuaPrototypes has no `animation` attribute), so this
          -- trusts the data-stage nil-guard in solar-duplicates.lua
          -- and the hard space-age dependency instead.
          if surface.darkness > 0.5 then
            for _, entity in pairs(surface.find_entities_filtered{type = "solar-panel"}) do
              local original = entity.name:match("^(.+)%-solar$")
              if original and original_names()[original] then
                rendering.draw_animation{
                  animation = "lightning-attractor-everywhere-strike-animation",
                  target = entity,
                  surface = surface,
                  time_to_live = 60,
                  render_layer = "light-effect",
                }
              end
            end
          end
          state.target = ZERO_LEVEL
          state.attacking = false
        else
          -- Reached 0 -- either a brief dip mid-burst (more peaks
          -- left: climb again right away) or the end of a burst (hold
          -- at 0 for a randomized stretch, then start a new burst with
          -- a new randomized peak count).
          state.peaks_remaining = state.peaks_remaining - 1
          if state.peaks_remaining > 0 then
            state.target = random_peak()
            state.attacking = true
          else
            state.zero_hold_remaining = random_zero_hold_ticks()
            state.peaks_remaining = random_peaks_per_burst()
            state.target = random_peak()
            state.attacking = true
          end
        end
      end
    end

    ::continue::
  end
end)
