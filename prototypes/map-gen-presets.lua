local mgp = data.raw["map-gen-presets"].default
local functions = require("prototypes.functions")
local fne = require("prototypes.fractured-noise-expressions")
local make_cartesian_noise_expressions = fne.make_cartesian_noise_expressions
local make_voronoi_noise_expressions = fne.make_voronoi_noise_expressions

--[[data:extend{
    {
        type = "noise-expression",
        name = "debug",
        expression = noise.var("finite_water_level") * 100
    }
}

mgp["fw-debug"] = {
    order = "h",
    basic_settings = {
        property_expression_names = {
            ["entity:iron-ore:richness"] = "debug",
            ["entity:iron-ore:probability"] = 10,
            elevation = 10
        }
    }
} -- ]]

local count_to_order = functions.count_to_order

local count = 0
local function make_preset(name, args)
    local fracturedControls = args.fracturedControls or {}
    local frequency = (fracturedControls.frequency) or (1 / 6)
    local size = fracturedControls.size or 1
    local mapRotation = args.rotation or {6, 1 / 6}
    local property_expression_names = {}
    if args.cartesian or args.voronoi then
        if args.cartesian then
            make_cartesian_noise_expressions(name, args)
        else
            make_voronoi_noise_expressions(name, args)
        end
        local elevation = "fractured-world-" .. name
        local fw_distance = "fractured-world-point-distance-" .. name
        local fw_value = "fractured-world-value-" .. name
        if args.cartesian then
            fw_value = "fractured-world-cartesian-value"
            fw_distance = "fractured-world-chessboard-distance"
        end
        if not (args.voronoi and args.voronoi.vanillaIslands) then
            property_expression_names = {
                elevation = elevation,
                moisture = "fractured-world-moisture",
                temperature = "fractured-world-temperature",
                aux = "fractured-world-aux",
                fw_value = fw_value,
                fw_distance = fw_distance
            }
        else
            property_expression_names = {
                elevation = elevation,
                fw_value = fw_value,
                fw_distance = fw_distance
            }
        end

    end

    local genericBasicSettings = {
        property_expression_names = property_expression_names,
        cliff_settings = {richness = 0},
        autoplace_controls = {
            ["island-randomness"] = {frequency = frequency, size = size},
            ["map-rotation"] = {frequency = mapRotation[1], size = mapRotation[2]}
        }
    }
    local mgs = args.basic_settings or {}
    mgs = util.merge {genericBasicSettings, mgs}
    if args.fracturedResources ~= false then
        for k, v in pairs(fractured_world.property_expressions.resource) do
            if not mgs.property_expression_names[k] then
                mgs.property_expression_names[k] = v
            end
        end
    end
    if args.fracturedEnemies ~= false then
        for k, v in pairs(fractured_world.property_expressions.enemy) do
            if not mgs.property_expression_names[k] then
                mgs.property_expression_names[k] = v
            end
        end
    end
    if args.mapGrid == true then
        mgs.property_expression_names["tile:lab-dark-1:probability"] = "fractured-world-land-grid"
        mgs.property_expression_names["tile:deepwater-green:probability"] =
            "fractured-world-water-grid"
    end

    mgp["fractured-world-" .. name] = {order = "h-" .. count_to_order(count), basic_settings = mgs}
    count = count + 1
end
for name, args in pairs(fractured_world.preset_data) do make_preset(name, args) end

mgp.default = nil
