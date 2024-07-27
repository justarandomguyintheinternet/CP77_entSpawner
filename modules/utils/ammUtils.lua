local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local red = require("modules/utils/redConverter")
local entityBuilder = require("modules/utils/entityBuilder")

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

    local propsService = require("modules/utils/tasks"):new()

    for _, prop in pairs(props) do
        propsService:addTask(function ()
            local new = object:new(spawnUI)
            new.spawnable = require("modules/classes/spawn/entity/ammEntity"):new()
            new.spawnable:loadSpawnData({ spawnData = prop.path }, Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0))
            new.name = new.spawnable:generateName(prop.name)

            local name = utils.createFileName(prop.name)
            if name == "" then
                name = "unnamed"
            end

            config.saveFile("data/spawnables/entity/amm/" .. name .. ".json", new:getState())

            amm.progress = amm.progress + 1
            propsService:taskCompleted()
        end)
    end

    amm.importing = true
    amm.total = #props
    amm.progress = 0

    propsService.taskDelay = 0.01
    propsService:run(true)

    propsService:onFinalize(function ()
        spawnUI.loadSpawnData(spawnUI.spawner)
        amm.importing = false
    end)
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

local function setInstanceDataMesh(entity, propData, spawnable)
    for _, component in pairs(entity:GetComponents()) do
        if entityBuilder.shouldUseMesh(component) and component:IsA("entMeshComponent") then
            local default = red.redDataToJSON(entity:FindComponentByName(component.name))
            table.insert(spawnable.instanceData, default)

            local change = {}
            if propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0 then
                change = {chunkMask = "0"}
            else
                change = {
                    visualScale = {
                        ["$type"] = "Vector3",
                        X = propData.scale.x / 100,
                        Y = propData.scale.y / 100,
                        Z = propData.scale.z / 100
                    }
                }
            end

            spawnable.instanceDataChanges[tostring(CRUIDToHash(entity:FindComponentByName(component.name).id)):gsub("ULL", "")] = change
        end
    end
end

local function setInstanceDataLight(entity, lightData, spawnable)
    for _, component in pairs(entity:GetComponents()) do
        if component:IsA("gameLightComponent") and utils.has_value(lightComponentNames, component.name.value) then
            local data = red.redDataToJSON(component)
            local angles = loadstring("return " .. lightData.angles, "")()
            local color = loadstring("return " .. lightData.color, "")()

            local change = {
                color = {
                    ["$type"] = "Color",
                    Red = math.floor(color[1] * 255),
                    Green = math.floor(color[2] * 255),
                    Blue = math.floor(color[3] * 255),
                    Alpha = math.floor(color[4] * 255)
                },
                intensity = lightData.intensity,
                innerAngle = angles.inner,
                outerAngle = angles.outer,
                radius = lightData.radius
            }

            table.insert(spawnable.instanceData, data)
            spawnable.instanceDataChanges[tostring(CRUIDToHash(component.id)):gsub("ULL", "")] = change
        end
    end
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
        local isScaled = propData.scale.x ~= 100 or propData.scale.y ~= 100 or propData.scale.z ~= 100

        if isLight and isAMMLight then
            -- Light Node
            o.spawnable = convertLight(propData, data)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = lightNodes
            table.insert(lightNodes.childs, o)
            amm.progress = amm.progress + 1
        elseif (isLight and not isAMMLight) or isScaled then
            if not Game.GetResourceDepot():ResourceExists(propData.path) then
                print("[AMMImport] Resource for " .. propData.path .. " does not exist, skipping...")
            else
                meshService:addTask(function ()
                    local spawnable = require("modules/classes/spawn/entity/entity"):new()
                    spawnable:loadSpawnData({
                        spawnData = propData.path,
                        app = propData.app
                    }, propData.pos, propData.rot)
                    spawnable:spawn()

                    spawnable:onBBoxLoaded(function (entity)
                        if isLight then
                            setInstanceDataLight(entity, isLight, spawnable)

                            if not isScaled then
                                o.spawnable = spawnable
                                o.parent = lightCustom
                                o.name = o.spawnable:generateName(propData.name .. "_light")
                                table.insert(lightCustom.childs, o)
                            end

                            print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. #spawnable.instanceData .. " light components.")
                        end
                        if isScaled then
                            setInstanceDataMesh(entity, propData, spawnable)

                            o.spawnable = spawnable
                            o.name = o.spawnable:generateName(propData.name)
                            o.parent = scaledProps
                            table.insert(scaledProps.childs, o)

                            print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. utils.tableLength(spawnable.instanceDataChanges) .. " mesh components.")
                        end

                        Game.GetStaticEntitySystem():DespawnEntity(spawnable.entityID)
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