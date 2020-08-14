local noise = require("noise")
local tne = noise.to_noise_expression
local functions = require("functions")
local fnp = require("fractured-noise-programs")

local resources = data.raw['resource']
local rawResourceData = require("prototypes.raw-resource-data")

local radius = noise.var("fw_distance")
local scaledRadius = (radius / functions.size)
local aux = 1 - noise.var("fractured-world-aux")

local startingAreaRadius = noise.var("fw_default_size")
local starting_factor =
    noise.delimit_procedure(noise.clamp(-noise.min(radius, 0) * math.huge, 0, 1))
local startingPatchScaleFactor = noise.min(startingAreaRadius / 128, 1)
local startingPatchDefaultRadius = 15 * startingPatchScaleFactor

local currentResourceData = {}

for k, v in pairs(rawResourceData) do
    if mods[k] then
        for ore, oreData in pairs(v) do
            if resources[ore] and resources[ore].autoplace then
                currentResourceData[ore] = oreData
            end
        end
    end
end

local starting_patches = resource_autoplace__patch_metasets.starting.patch_set_indexes
local regular_patches = resource_autoplace__patch_metasets.regular.patch_set_indexes

-- pick up any ores not in the raw dataset and give them a default
for ore, index in pairs(regular_patches) do
    if resources[ore] and resources[ore].autoplace and not currentResourceData[ore] then
        currentResourceData[ore] = {density = 8}
    end
end

--[[
    1. See if ore has infinite in the name, and is infinite
    2. Check if there's another ore with the same name minus the infinite bit
    3. If so, wipe out the infinite ore from the list, tag it in the parent resource
    4. Check if the ore is in the starting area, if so, add a flag
    5. This flag will later be used to tell which "slice" of the starting island to place the ore
]]
local infiniteOreData = {}
local doInfiniteOres = settings.startup["fractured-world-enable-infinite-parenting"].value
local startingOreCount = 0
for ore, oreData in pairs(currentResourceData) do
    local isInfinite = doInfiniteOres and resources[ore].infinite and
                           string.find(ore, "^infinite%-") and true or false
    if isInfinite then
        local parentOreName = string.sub(ore, 10)
        if resources[parentOreName] then
            infiniteOreData[ore] = {
                parentOreName = parentOreName
            }
            currentResourceData[ore] = nil
            currentResourceData[parentOreName].has_infinite_version = true
        end
    end
    if starting_patches[ore] then
        startingOreCount = startingOreCount + 1
        currentResourceData[ore].starting_patch = startingOreCount
    end
end
--[[
generate locations for starting ores
divide circle into n slices
for each slice, generate a point from 0-0.5 of the slice angle,
    0.25 to 0.75 the "total" distance to the edge
]]

local rotationFactor = functions.slider_to_scale("control-setting:map-rotation:size:multiplier") *
                           math.pi / 2

local sliceSize = 2 * math.pi / startingOreCount
local startingPoints = {}
for i = 1, startingOreCount do
    local random = functions.get_random_point(i, i, startingAreaRadius)
    local radius = (random.y) / 3 + startingAreaRadius / 6
    local angle = random.x / startingAreaRadius * sliceSize / 2 + i * sliceSize + rotationFactor
    local point_x = radius * noise.cos(angle)
    local point_y = radius * noise.sin(angle)
    startingPoints[i] = {x = point_x, y = point_y}
end

--[[
default settings: approx 64 islands/km2
we want at most 1/16 of the islands to have ore by default
sum up spots/km2 for current ores, if over 4, multiply richness by #ores/4
get weighted sum of ore spots/km2 * frequency,
]]
local oreCount = 0

-- startLevel, endLevel: what aux values to place this ore at
for ore, oreData in pairs(currentResourceData) do
    local control_setting = noise.get_control_setting(ore)
    local frequency_multiplier = control_setting.frequency_multiplier or 1
    local base_frequency = oreData.frequency or 2.5
    local thisFrequency = frequency_multiplier * base_frequency
    oreData.startLevel = oreCount
    oreCount = oreCount + thisFrequency
    oreData.endLevel = oreCount
    local randmin = oreData.randmin or 0.25
    local randmax = oreData.randmax or 2
    oreData.variance = randmax - randmin
    oreData.randmin = randmin
    oreData.starting_radius_multiplier = 1 + ((oreData.starting_radius or 1) - 1) *
                                             tne(starting_factor)
end

local overallFrequency = settings.startup["fractured-world-overall-resource-frequency"].value
local maxPatchesPerKm2 = overallFrequency * 64
local oreCountMultiplier = noise.delimit_procedure(noise.max(1, oreCount / maxPatchesPerKm2))

-- scale startLevel and endLevel so that the desired overall frequency of islands have ore
for ore, oreData in pairs(currentResourceData) do
    oreData.startLevel = tne(oreData.startLevel) / (oreCountMultiplier) * overallFrequency
    oreData.endLevel = tne(oreData.endLevel) / (oreCountMultiplier) * overallFrequency
end

local function get_infinite_probability(ore)
    local parentOreName = infiniteOreData[ore].parentOreName
    local parentOreData = currentResourceData[parentOreName]
    local parentProbability = data.raw["noise-expression"]["fractured-world-" .. parentOreName ..
                                  "-probability"].expression

    local minRadius = 1 / 8
    local maxRadius = 1 / 2
    local get_radius = functions.make_interpolation(parentOreData.startLevel, minRadius,
                                                    parentOreData.endLevel, maxRadius)

    local thisRadius = get_radius(aux)
    data:extend{
        {
            type = "noise-expression",
            name = "fractured-world-" .. ore .. "radial-multiplier",
            expression = noise.max(thisRadius - scaledRadius, 0)
        }
    }
    -- if the island is dry, *or* if it has biters on it, place the infinite ore
    local moistureFactor = noise.max(noise.less_than(noise.var("moisture"), tne(0.5)),
                                     noise.var("fractured-world-biter-islands"))
    local sizeMultiplier = noise.get_control_setting(ore).size_multiplier
    local randomness = noise.clamp(noise.var("fw-scaling-noise"), 1, 10)
    local probabilities = {
        tne(10), parentProbability, moistureFactor,
        noise.var("fractured-world-" .. ore .. "radial-multiplier"),
        sizeMultiplier, randomness
    }
    return functions.multiply_probabilities(probabilities)
end

local function get_infinite_richness(ore)

    local oreData = currentResourceData[infiniteOreData[ore].parentOreName]
    local addRich = oreData.addRich or 0
    local postMult = oreData.postMult or 1
    local minimumRichness = oreData.minRich or 0
    local settings = noise.get_control_setting(ore)
    local variance = (aux - oreData.startLevel) / (oreData.endLevel - oreData.startLevel) *
                         oreData.variance + (oreData.randmin)

    local factors = {
        oreData.density,
        770 * noise.var("distance") + 1000000,
        settings.richness_multiplier,
        1 / noise.max(oreData.randProb or 1, 1),
        oreCountMultiplier, variance,
        1 / tne(fnp.landDensity),
        noise.max(noise.var("fractured-world-" .. ore .. "radial-multiplier"), 1),
        tne(10)
    }
    return noise.max((functions.multiply_probabilities(factors) + addRich) * postMult,
                     minimumRichness)
end

local function get_probability(ore)
    local oreData = currentResourceData[ore]

    local settings = noise.get_control_setting(ore)
    local randProb = oreData.randProb or 1
    local aboveMinimum = noise.max(0, aux - oreData.startLevel)
    local belowMaximum = noise.max(0, oreData.endLevel - aux)
    local probability_expression = noise.clamp(aboveMinimum * belowMaximum * math.huge, 0, 1)
    probability_expression = probability_expression * (tne(1) - starting_factor)
    if oreData.starting_patch then
        local startingPatchRadius = startingPatchDefaultRadius * settings.size_multiplier ^ 0.5 *
                                        oreData.starting_radius_multiplier
        local startingPoint = startingPoints[oreData.starting_patch]
        local point_x = startingPoint.x
        local point_y = startingPoint.y
        local x = noise.var("x")
        local y = noise.var("y")
        local distanceFromPoint = functions.distance(point_x - x, point_y - y)
        -- TODO: add variation to starting ores based on "starting patch radius"
        probability_expression = probability_expression +
                                     noise.less_than(distanceFromPoint, startingPatchRadius +
                                                         (noise.var("fw-small-noise") / 25))
    end

    if randProb < 1 then
        -- Adjustment so there isn't a ridiculous number of patches on an island
        randProb = randProb / 4
        probability_expression = probability_expression * tne {
            type = "function-application",
            function_name = "random-penalty",
            arguments = {
                source = tne(1),
                x = noise.var("x"),
                y = noise.var("y"),
                amplitude = tne(1 / randProb) -- put random_probability points with probability < 0
            }
        }
    end
    return noise.clamp(probability_expression, -1, 1)
end

local function get_richness(ore)
    -- Get params for calculations
    local oreData = currentResourceData[ore]
    local addRich = oreData.addRich or 0
    local postMult = oreData.postMult or 1
    local minimumRichness = oreData.minRich or 0
    local randProb = oreData.randProb
    if randProb then randProb = randProb / 4 end
    local settings = noise.get_control_setting(ore)

    local variance = (aux - oreData.startLevel) / (oreData.endLevel - oreData.startLevel) *
                         oreData.variance + (oreData.randmin)
    local factors = {
        oreData.density or 8,
        770 * noise.var("distance") + 1000000,
        settings.richness_multiplier,
        settings.size_multiplier,
        1 / noise.max(oreData.randProb or 1, 1),
        oreCountMultiplier, variance,
        1 / tne(fnp.landDensity),
        noise.max(1 / startingPatchScaleFactor, 1),
        noise.clamp(noise.absolute_value(noise.var("fw-small-noise") / 25 + 2), 0.5, 2),
        1 / oreData.starting_radius_multiplier
    }
    local richness_expression = noise.max((functions.multiply_probabilities(factors) + addRich) *
                                              postMult, minimumRichness)

    return richness_expression
end

return {
    get_probability = get_probability,
    get_richness = get_richness,
    currentResourceData = currentResourceData,
    get_infinite_probability = get_infinite_probability,
    get_infinite_richness = get_infinite_richness,
    infiniteOreData = infiniteOreData
}
