local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local amm = {}

local area = "base\\amm_props\\entity\\ambient_area_light"
local point = "base\\amm_props\\entity\\ambient_point_light"
local spot = "base\\amm_props\\entity\\ambient_spot_light"

---@param spawnUI spawnUI
---@param AMM table
function amm.generateProps(spawnUI, AMM)
    local props = AMM.API.GetAMMProps()

    for _, prop in pairs(props) do
        local new = object:new(spawnUI)
        new.spawnable = require("modules/classes/spawn/entity/ammEntity"):new()
        new.spawnable:loadSpawnData({ spawnData = prop.path }, Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0))
        new.name = new.spawnable:generateName(prop.name)

        config.saveFile("data/spawnables/entity/amm/" .. prop.name .. ".json", new:getState())
    end

    spawnUI.loadSpawnData(spawnUI.spawner)
end

local function getAMMLightByID(lights, id)
    for _, light in pairs(lights) do
        if light.uid == id then
            return light
        end
    end
end

local function generateObject(savedUI, data)
    local newObject = require("modules/classes/spawn/object"):new(savedUI)
    newObject.name = data.name
    newObject.headerOpen = false
    newObject.loadRange = 100
    newObject.autoLoad = false

    return newObject
end

local function convertLight(propData, data)
    local lightData = getAMMLightByID(data.lights, propData.uid)

    local spawnData = {}
    spawnData.color = loadstring("return " .. lightData.color, "")()
    spawnData.color = {spawnData.color[1], spawnData.color[2], spawnData.color[3]}
    spawnData.intensity = lightData.intensity
    local angles = loadstring("return " .. lightData.angles, "")()
    spawnData.innerAngle = angles.inner
    spawnData.outerAngle = angles.outer
    spawnData.radius = lightData.radius

    if propData.path:match(area) then
        spawnData.lightType = 2
    elseif propData.path:match(point) then
        spawnData.lightType = 0
    else
        spawnData.lightType = 1
    end

    local light = require("modules/classes/spawn/light/light"):new()
    light:loadSpawnData(spawnData, propData.pos, propData.rot)

    return light
end

local function convertProp(propData)
    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
    spawnable:loadSpawnData({
        spawnData = propData.path,
        app = propData.app
    }, propData.pos, propData.rot)

    return spawnable
end

local function extractPropData(prop)
    local location = loadstring("return " .. prop.pos, "")()
    local scale = loadstring("return " .. prop.scale, "")()
    local pos = Vector4.new(location.x, location.y, location.z, 0)
    local rot = EulerAngles.new(location.roll, location.pitch, location.yaw)
    if scale == nil then
        scale = Vector4.new(100, 100, 100, 0)
    else
        scale = Vector4.new(scale.x, scale.y, scale.z, 0)
    end

    return { pos = pos, rot = rot, scale = scale, path = prop.template_path, app = prop.app, uid = prop.uid, name = prop.name }
end

function amm.importPreset(data, savedUI)
    local meshService = require("modules/utils/tasks"):new()

    local root = gr:new(savedUI)
    root.name = data.file_name:gsub(".json", "")

    local props = gr:new(savedUI)
    props.parent = root
    props.headerOpen = false
    props.name = "Props"

    local lights = gr:new(savedUI)
    lights.parent = root
    lights.headerOpen = false
    lights.name = "Lights"

    local meshes = gr:new(savedUI)
    meshes.parent = root
    meshes.headerOpen = false
    meshes.name = "Meshes"

    for _, prop in pairs(data.props) do
        local propData = extractPropData(prop)

        --- Generate base object for hierarchy
        local o = generateObject(savedUI, propData)
        if propData.path:match(area) or propData.path:match(point) or propData.path:match(spot) then
            o.spawnable = convertLight(propData, data)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = lights
            table.insert(lights.childs, o)
        elseif propData.scale.x ~= 100 or propData.scale.y ~= 100 or propData.scale.z ~= 100 then
            meshService:addTask(function ()
                utils.log("Executing task for " .. propData.path .. " Cached: " .. tostring((cache.getValue(propData.path .. "_bBox") and cache.getValue(propData.path .. "_meshes"))))

                cache.tryGet(propData.path .. "_bBox", propData.path .. "_meshes")
                .notFound(function (task)
                    utils.log("Data for", propData.path, "not found, loading...")
                    local spawnable = require("modules/classes/spawn/entity/entity"):new()
                    spawnable:loadSpawnData({
                        spawnData = propData.path,
                        app = propData.app
                    }, Vector4.new(0, 0, 0, 0), propData.rot)
                    spawnable:spawn()

                    spawnable:onBBoxLoaded(function ()
                        spawnable:despawn()
                        utils.log("Data for", propData.path, "loaded and cached.", propData.uid)
                        task:taskCompleted()
                    end)
                end)
                .found(function ()
                    local meshesData = cache.getValue(propData.path .. "_meshes")
                    for _, mesh in pairs(meshesData) do
                        utils.log("Creating spawnable for mesh " .. mesh.path .. " for prop " .. propData.path, prop.pos, ToVector4(mesh.pos))

                        local m = require("modules/classes/spawn/mesh/mesh"):new()
                        m:loadSpawnData({
                            scale = { x = propData.scale.x / 100, y = propData.scale.y / 100, z = propData.scale.z / 100 },
                            spawnData = mesh.path,
                            app = mesh.app
                        }, utils.addVector(propData.pos, ToVector4(mesh.pos)), utils.addEuler(propData.rot, ToEulerAngles(mesh.rot)))

                        local meshObject = generateObject(savedUI, { name = propData.name })
                        meshObject.spawnable = m
                        meshObject.parent = meshes
                        table.insert(meshes.childs, meshObject)
                    end

                    utils.log("[ammUtils] Task Done For " .. propData.path)
                    print("[AMMImport] Imported prop " .. propData.name .. " by converting it to " .. #meshesData .. " meshes.")
                    utils.log("   ")
                    meshService:taskCompleted()
                end)
            end)
        else
            o.spawnable = convertProp(propData)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = props
            table.insert(props.childs, o)
        end
    end

    meshService:onFinalize(function ()
        table.insert(root.childs, props)
        table.insert(root.childs, lights)
        table.insert(root.childs, meshes)
        root.pos = root:getCenter()
        lights.pos = lights:getCenter()
        props.pos = props:getCenter()
        meshes.pos = meshes:getCenter()

        root:save()
        print("[ObjectSpawner] Imported \"" .. data.file_name .. "\" from AMM.")
        os.remove("data/AMMImport/" .. data.file_name)
    end)

    meshService.taskDelay = 0.05
    meshService:run(true)
end

function amm.importPresets(savedUI)
    for _, file in pairs(dir("data/AMMImport")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/AMMImport/" .. file.name)
            amm.importPreset(data, savedUI)
        end
    end
end

return amm