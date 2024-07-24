local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local red = require("modules/utils/redConverter")
local amm = {
    importing = false,
    progress = 0,
    total = 0
}

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

    -- Holy mother of clusterfucks
    if pos:Distance(scale) < 100 then
        scale = Vector4.new(100, 100, 100, 0)
    end

    return { pos = pos, rot = rot, scale = scale, path = prop.template_path, app = prop.app, uid = prop.uid, name = prop.name }
end

local lightComponentNames = {
    "Light0275",
    "Light7460",
    "Light5050",
    "Light1783",
    "Light5638",
    "amm_light",
    "Light5520",
    "Light7161",
    "Light0034",
    "Light2702",
    "Light1460",
    "Light6337",
    "Light2103",
    "Light6270",
    "Light5424",
    "Light7002",
    "L_Main",
    "Light6234",
    "LT_Point",
    "LT_Spot",
    "Light6765",
    "Light4716",
    "Light_Main8854",
    "Light_Main",
    "Light",
    "Light_Glow",
    "head_light_left_01",
    "head_light_right_01",
    "Mesh4713",
    "Light_DistantLight"
}

local function getEntityInstanceData(entity, lightData)
    local instanceData = {}

    for _, component in pairs(entity:GetComponents()) do
        if component:IsA("gameLightComponent") and utils.has_value(lightComponentNames, component.name.value) then
            local data = red.redDataToJSON(component)
            local angles = loadstring("return " .. lightData.angles, "")()
            local color = loadstring("return " .. lightData.color, "")()

            data.color.Red = math.floor(color[1] * 255)
            data.color.Green = math.floor(color[2] * 255)
            data.color.Blue = math.floor(color[3] * 255)
            data.color.Alpha = math.floor(color[4] * 255)
            data.intensity = lightData.intensity
            data.innerAngle = angles.inner
            data.outerAngle = angles.outer
            data.radius = lightData.radius

            table.insert(instanceData, data)
        end
    end

    return instanceData
end

local function createGroup(savedUI, name, parent)
    local group = gr:new(savedUI)
    group.parent = parent
    group.headerOpen = false
    group.name = name

    return group
end

function amm.importPreset(data, savedUI, importTasks)
    local meshService = require("modules/utils/tasks"):new()

    local root = createGroup(savedUI, data.file_name:gsub(".json", ""), nil)
    local props = createGroup(savedUI, "Props", root)
    local lights = createGroup(savedUI, "Lights", root)
    local lightNodes = createGroup(savedUI, "Light Nodes", lights)
    local lightCustom = createGroup(savedUI, "Customized Light Props", lights)
    local scaledProps = createGroup(savedUI, "Scaled Props", root)

    for _, prop in pairs(data.props) do
        local propData = extractPropData(prop)

        --- Generate base object for hierarchy
        local o = generateObject(savedUI, propData)

        local isLight = getAMMLightByID(data.lights, propData.uid)
        local isAMMLight = propData.path:match(area) or propData.path:match(point) or propData.path:match(spot)

        if isLight and isAMMLight then
            -- Light Node
            o.spawnable = convertLight(propData, data)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = lightNodes
            table.insert(lightNodes.childs, o)
            amm.progress = amm.progress + 1
        elseif isLight and not isAMMLight then
            -- Generate instance data for custom lights
            meshService:addTask(function ()
                local spawnable = require("modules/classes/spawn/entity/entity"):new()
                spawnable:loadSpawnData({
                    spawnData = propData.path,
                    app = propData.app
                }, propData.pos, propData.rot)
                spawnable:spawn()

                spawnable:onBBoxLoaded(function (entity)
                    spawnable.instanceData = getEntityInstanceData(entity, isLight)

                    local lightObject = generateObject(savedUI, { name = propData.name .. "_light" })
                    lightObject.spawnable = spawnable
                    lightObject.parent = lightCustom
                    table.insert(lightCustom.childs, lightObject)

                    amm.progress = amm.progress + 1
                    print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. #spawnable.instanceData .. " light components.")
                    Game.GetStaticEntitySystem():DespawnEntity(spawnable.entityID)
                    meshService:taskCompleted()
                end)
            end)
        elseif (propData.scale.x ~= 100 or propData.scale.y ~= 100 or propData.scale.z ~= 100) then
            if not Game.GetResourceDepot():ResourceExists(propData.path) then
                print("[AMMImport] Resource for " .. propData.path .. " does not exist, skipping...")
            else
                meshService:addTask(function ()
                    cache.tryGet(propData.path .. "_meshInstanceData")
                    .notFound(function (task)
                        utils.log("Data for", propData.path, "not found, loading...")
                        local spawnable = require("modules/classes/spawn/entity/entity"):new()
                        spawnable:loadSpawnData({
                            spawnData = propData.path,
                            app = propData.app
                        }, Vector4.new(0, 0, 0, 0), propData.rot)
                        spawnable:spawn()

                        spawnable:onBBoxLoaded(function (entity)
                            local instances = {}
                            for _, mesh in pairs(cache.getValue(propData.path .. "_meshes")) do
                                if mesh.scaled then
                                    local data = red.redDataToJSON(entity:FindComponentByName(mesh.name))
                                    table.insert(instances, data)
                                end
                            end

                            cache.addValue(propData.path .. "_meshInstanceData", instances)

                            Game.GetStaticEntitySystem():DespawnEntity(spawnable.entityID)
                            utils.log("Data for", propData.path, "loaded and cached.", propData.uid)
                            task:taskCompleted()
                        end)
                    end)
                    .found(function ()
                        local meshesData = cache.getValue(propData.path .. "_meshInstanceData")
                        for _, mesh in pairs(meshesData) do
                            if propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0 then
                                mesh.chunkMask = "0"
                            else
                                mesh.visualScale.X = propData.scale.x / 100
                                mesh.visualScale.Y = propData.scale.y / 100
                                mesh.visualScale.Z = propData.scale.z / 100
                            end
                        end

                        o.spawnable = convertProp(propData)
                        o.spawnable.instanceData = meshesData
                        o.name = o.spawnable:generateName(propData.name)
                        o.parent = props
                        table.insert(scaledProps.childs, o)

                        print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. #meshesData .. " mesh components.")
                        utils.log("[ammUtils] Task Done For " .. propData.path)
                        utils.log("   ")
                        amm.progress = amm.progress + 1
                        meshService:taskCompleted()
                    end)
                end)
            end
        else
            o.spawnable = convertProp(propData)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = props
            table.insert(props.childs, o)

            amm.progress = amm.progress + 1
        end
    end

    meshService:onFinalize(function ()
        table.insert(root.childs, props)
        table.insert(root.childs, lights)
        table.insert(lights.childs, lightCustom)
        table.insert(lights.childs, lightNodes)
        table.insert(root.childs, scaledProps)

        root.pos = root:getCenter()
        lights.pos = lights:getCenter()
        lightCustom.pos = lightCustom:getCenter()
        lightNodes.pos = lightNodes:getCenter()
        props.pos = props:getCenter()
        scaledProps.pos = scaledProps:getCenter()

        root:save()
        print("[ObjectSpawner] Imported \"" .. data.file_name .. "\" from AMM.")
        -- os.remove("data/AMMImport/" .. data.file_name)

        importTasks:taskCompleted()
    end)

    meshService.taskDelay = 0.05
    meshService:run(true)
end

function amm.importPresets(savedUI)
    local importTasks = require("modules/utils/tasks"):new()
    amm.progress = 0

    for _, file in pairs(dir("data/AMMImport")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            importTasks:addTask(function ()
                local data = config.loadFile("data/AMMImport/" .. file.name)
                amm.importPreset(data, savedUI, importTasks)

                amm.total = amm.total + #data.props
            end)
        end
    end

    importTasks:onFinalize(function ()
        print("[AMMImport] All presets imported.")
        amm.importing = false
    end)

    amm.importing = true
    importTasks:run(true)
end

return amm