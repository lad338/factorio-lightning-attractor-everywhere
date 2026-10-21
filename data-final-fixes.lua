-- Runs after every mod's own data.lua, so every planet (vanilla or
-- modded) and every lightning-attractor-type entity is registered by
-- now -- the earliest point this scan can be done correctly.
--
-- "Which planets have lightning" is carried to the control stage via a
-- surface-property (surface_properties is a plain mutable field on
-- PlanetPrototype, readable at runtime through
-- LuaSurface.get_property()) -- NOT a setting's default_value:
-- data.raw["string-setting"] does not exist during the data stage
-- (settings and data prototypes are built in separate stages/tables),
-- so that approach fails outright, not just silently.
for name, planet in pairs(data.raw["planet"] or {}) do
  if planet.lightning_properties then
    planet.surface_properties = planet.surface_properties or {}
    planet.surface_properties["lightning-attractor-everywhere-is-lightning"] = 1
  end
end

-- "Every lightning-attractor-type entity" needs no cross-stage carrier
-- at all -- control.lua gets this live, every time, via
-- prototypes.get_entity_filtered{{filter = "type", type =
-- "lightning-attractor"}}, so there's nothing to precompute here beyond
-- the restriction below.

-- Gravity-only restriction (keeps these off zero-gravity space
-- platforms); there is no restriction to remove today -- vanilla
-- lightning-rod/lightning-collector have no surface_conditions at all.
for name, entity in pairs(data.raw["lightning-attractor"] or {}) do
  entity.surface_conditions = entity.surface_conditions or {}
  table.insert(entity.surface_conditions, {property = "gravity", min = 1})
  -- Matches the solar-panel duplicate's own fast_replaceable_group
  -- (prototypes/entity/solar-duplicates.lua) so control.lua's
  -- fast_replace swap works in both directions.
  entity.fast_replaceable_group = name .. "-lightning-attractor-everywhere"
end

-- Solar-panel duplicates are generated here, not in data.lua: another
-- mod's own lightning-attractor-type entity may not exist yet during
-- OUR data.lua (mod load order isn't guaranteed to put us last) --
-- generating duplicates too early would silently skip it, leaving it
-- gravity-restricted and fast-replaceable (both set above, which don't
-- depend on load order) but with no "-solar" target to swap to. This
-- file runs after every mod's own data.lua, so every lightning-attractor
-- entity -- vanilla or modded -- is guaranteed to exist by now.
require("prototypes.entity.solar-duplicates")
