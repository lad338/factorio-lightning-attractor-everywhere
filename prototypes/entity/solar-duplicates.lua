-- For each lightning-attractor-type entity, build a solar-panel
-- duplicate: same footprint/energy_source, output only at night via
-- performance_at_night, immune to planet solar strength via
-- solar_coefficient_property pointing at our own surface property
-- (not vanilla's "solar-power") -- see the design doc for why this
-- needs no scripting at all. Graphics reuse the original's own
-- chargable_graphics.picture directly: it's already a plain
-- {layers = {sprite, shadow}} table, the exact shape solar-panel's
-- own `picture` field expects.
for name, original in pairs(data.raw["lightning-attractor"]) do
  -- Fulgora's decorative ruin variants (fulgoran-ruin-attractor,
  -- simulacruis-fulgoran-ruin-attractor) match the type filter but
  -- have no energy_source, so a solar-panel duplicate (which requires
  -- one) is meaningless for them -- and deepcopying a nil
  -- energy_source below would crash the data stage.
  if not original.energy_source then goto continue end
  -- Defensive against a third-party mod's own lightning-attractor-type
  -- entity not following vanilla's exact shape: efficiency, minable,
  -- and chargable_graphics (with a .picture/.discharge_animation.layers)
  -- are all optional on the base prototype, even though both vanilla
  -- originals set all of them. Skip rather than crash the whole data
  -- stage over one malformed entity.
  if not original.minable then goto continue end
  if not original.efficiency or original.efficiency == 0 then goto continue end
  local chargable = original.chargable_graphics
  if not (chargable and chargable.picture and chargable.discharge_animation and chargable.discharge_animation.layers) then goto continue end

  -- production_kw is tuned against a real measured baseline, not
  -- derived from efficiency: vanilla's own solar-panel on Nauvis
  -- averages 4.6655 kW/tile over a full day/night cycle.
  -- lightning-rod (1 tile) targets 2x that per-tile rate;
  -- lightning-collector targets 4.5x the rod's own total (not its
  -- 4-tile footprint scaled the same way, which would be 8x). Both
  -- figures below already divide out solar_coefficient_property's
  -- own averaging effect (1.01861 kW of real output per kW of
  -- nameplate, measured the same way), so a third-party mod's own
  -- lightning-attractor entity -- with no equivalent explicit target --
  -- falls back to the old efficiency-ratio scaling off the rod's own
  -- baseline instead.
  local ROD_PRODUCTION_KW = 9.16
  local COLLECTOR_RATIO_OVER_ROD = 4.5
  local production_kw = name == "lightning-collector"
    and ROD_PRODUCTION_KW * COLLECTOR_RATIO_OVER_ROD
    or ROD_PRODUCTION_KW * (original.efficiency / 0.2)

  data:extend({
    {
      type = "solar-panel",
      name = name .. "-solar",
      -- Reuses the original's own existing locale entry so the swap
      -- stays invisible in tooltips too -- this mod has no locale/
      -- folder of its own.
      localised_name = {"entity-name." .. name},
      localised_description = {"entity-description." .. name},
      icon = original.icon,
      icon_size = original.icon_size,
      icons = original.icons,
      flags = table.deepcopy(original.flags),
      minable = {mining_time = original.minable.mining_time, result = original.minable.result},
      fast_replaceable_group = name .. "-lightning-attractor-everywhere",
      max_health = original.max_health,
      corpse = original.corpse,
      dying_explosion = original.dying_explosion,
      resistances = table.deepcopy(original.resistances),
      collision_box = original.collision_box,
      selection_box = original.selection_box,
      drawing_box_vertical_extension = original.drawing_box_vertical_extension,
      -- NOT table.deepcopy(original.energy_source): a lightning-attractor's
      -- own energy_source is tuned for absorbing one bursty strike at
      -- a time (usage_priority = "primary-output", a large
      -- buffer/drain) and silently produces zero power if copied onto
      -- a solar-panel. Needs a fresh source matching vanilla
      -- solar-panel's own usage_priority = "solar".
      energy_source = {type = "electric", usage_priority = "solar"},
      picture = table.deepcopy(chargable.picture),
      performance_at_day = 0,
      performance_at_night = 1,
      production = production_kw .. "kW",
      solar_coefficient_property = "lightning-attractor-everywhere-night",
      create_ghost_on_death = false,
      -- placeable_by (not a separate placeholder item) governs
      -- create_blueprint capture, Q-pipette, and ghost-revival's
      -- required item. An entity with no items_to_place_this/placeable_by
      -- link at all is silently excluded from blueprint capture, and
      -- pointing this at the ORIGINAL's own item means the player/bot
      -- always gets handed a real, obtainable item rather than an
      -- invented one they could never otherwise get.
      placeable_by = {item = original.minable.result, count = 1},
    },
  })

  data:extend({
    {
      type = "animation",
      name = name .. "-solar-discharge-animation",
      layers = table.deepcopy(chargable.discharge_animation.layers),
    },
  })

  -- Redirect every item that places the original to place the
  -- duplicate instead. The engine blocks a real player's direct click
  -- from placing a lightning-attractor-type entity on a planet
  -- without lightning_properties, but exempts scripted placement
  -- (surface.create_entity) -- so the item's own place_result can
  -- never safely be the original. The duplicate (solar-panel type)
  -- has no such restriction anywhere, so it's always safe as the
  -- item's direct target; control.lua's swap logic corrects it to the
  -- real original via script when the surface actually has lightning.
  -- The item's displayed name is unaffected either way, since
  -- place_result's own name comes from the target entity's
  -- localised_name, which the duplicate already reuses from the
  -- original above.
  for _, item in pairs(data.raw["item"] or {}) do
    if item.place_result == name then
      item.place_result = name .. "-solar"
    end
  end

  -- Without this, the original becomes un-ghostable entirely, not
  -- merely un-revivable: an entity needs at least one real
  -- items_to_place_this/placeable_by link to be ghost-creatable at
  -- all, and the redirect above just removed its only one. This is
  -- what a blueprint paste of the ORIGINAL (which the blueprint
  -- rewrite always stores, regardless of where it was captured) would
  -- hit immediately. Pointing it at the same real item the duplicate
  -- already uses restores that link without reintroducing the item's
  -- own place_result.
  original.placeable_by = {item = original.minable.result, count = 1}

  ::continue::
end

-- Shared across every duplicate (registered once, not per-original):
-- vanilla's own "lightning actually striking an attractor" animation.
-- This lives on the `lightning` entity's own graphics_set
-- (graphics_set.attractor_hit_animation) as a plain 36-frame sprite
-- animation, not on the attractor itself -- unlike the rest of
-- graphics_set (cloud_background, ground_streamers,
-- shader_configuration, etc.), which is a procedurally-rendered
-- effect with no reusable Animation prototype behind it. Registering
-- this as our own standalone animation lets control.lua play the real
-- "bolt visibly hitting the attractor" visual exactly when a peak
-- lands.
local lightning_entity = data.raw["lightning"] and data.raw["lightning"]["lightning"]
local hit_animation = lightning_entity and lightning_entity.graphics_set
  and lightning_entity.graphics_set.attractor_hit_animation
if hit_animation then
  data:extend({
    {
      type = "animation",
      name = "lightning-attractor-everywhere-strike-animation",
      layers = {table.deepcopy(hit_animation)},
    },
  })
end
