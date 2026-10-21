-- Entry point for the data stage.
data:extend({
  {
    type = "surface-property",
    name = "lightning-attractor-everywhere-night",
    default_value = 1,
  },
  -- Cross-stage signal for "is this planet lightning-capable" (see
  -- data-final-fixes.lua): data.raw["string-setting"] does not exist
  -- during the data stage, so a planet-prototype field mutated here and
  -- read back at runtime via LuaSurface.get_property() is the real
  -- channel -- not a hidden setting's default_value.
  {
    type = "surface-property",
    name = "lightning-attractor-everywhere-is-lightning",
    default_value = 0,
  },
})
