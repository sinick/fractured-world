local fw_settings = {
    {
        type = "int-setting",
        name = "fractured-world-default-cell-size",
        setting_type = "startup",
        default_value = 128,
        minimum_value = 0
    }, {
        type = "double-setting",
        name = "fractured-world-overall-resource-frequency",
        setting_type = "startup",
        default_value = 0.02,
        minimum_value = 0,
        maximum_value = 1
    }, {
        type = "bool-setting",
        name = "fractured-world-enable-infinite-parenting",
        setting_type = "startup",
        default_value = true
    }, {
        type = "bool-setting",
        name = "fractured-world-use-quick-startup",
        setting_type = "startup",
        default_value = false
    }, {
        type = "string-setting",
        name = "fractured-world-quick-startup-preset",
        setting_type = "startup",
        default_value = "default",
        allowed_values = fractured_world.allowed_presets
    }
}
local n = 0
for _, setting in pairs(fw_settings) do
    setting.order = tostring(n)
    n = n + 1
end
data:extend(fw_settings)
