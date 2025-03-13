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

local componentNames = { "Light0275", "Light7460", "Light5050", "Light1783", "Light5638", "amm_light", "Light5520", "Light7161", "Light0034", "Light2702", "Light1460", "Light6337", "Light2103", "Light6270", "Light5424", "Light7002", "L_Main", "Light6234", "LT_Point", "LT_Spot", "Light6765", "Light4716", "Light_Main8854", "Light_Main", "Light", "Light_Glow", "head_light_left_01", "head_light_right_01", "Mesh4713", "Light_DistantLight" }

---@param spawnUI spawnUI
---@param AMM table
function amm.generateProps(spawnUI, AMM, spawner)
    local props = AMM.API.GetAMMProps()

    local propsService = require("modules/utils/tasks"):new()

    for _, prop in pairs(props) do
        propsService:addTask(function ()
            local new = require("modules/classes/editor/spawnableElement"):new(spawnUI)
            new.spawnable = require("modules/classes/spawn/entity/ammEntity"):new()
            new.spawnable:loadSpawnData({ spawnData = prop.path }, Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0))
            new.name = new.spawnable:generateName(prop.name)

            local name = utils.createFileName(prop.name)
            if name == "" then
                name = "unnamed"
            end

            config.saveFile("data/spawnables/entity/amm/" .. name .. ".json", new:serialize())

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
        spawnUI.loadSpawnData(spawner)
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

local function generateElement(savedUI, data)
    local element = require("modules/classes/editor/spawnableElement"):new(savedUI)
    element.name = data.name

    return element
end

local function generateGroup(savedUI, name, parent)
    local group = require("modules/classes/editor/positionableGroup"):new(savedUI)
    group.name = name

    if parent then
        group:setParent(parent)
    end

    return group
end

local function CRUIDToString(id)
    return tostring(CRUIDToHash(id)):gsub("ULL", "")
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

    local fixedRotation = EulerAngles.new(-90.23202, -65.13491, -90.25572)
    local fixedPosition = Vector4.new(0.061408997, -0.05025482, -0.21749115, 1)
    fixedPosition = propData.rot:ToQuat():Transform(fixedPosition)

    local light = require("modules/classes/spawn/light/light"):new()
    light:loadSpawnData(spawnData, utils.addVector(propData.pos, fixedPosition), utils.addEuler(fixedRotation, propData.rot))

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

local function setInstanceDataMesh(entity, propData, spawnable)
    for _, component in pairs(entity:GetComponents()) do
        local use = entityBuilder.shouldUseMesh(component)
        if use.use and component:IsA("entMeshComponent") and CRUIDToString(component.id) ~= "0" then
            local change = {}
            if propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0 then
                change = { chunkMask = "0" }
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

            spawnable.instanceDataChanges[tostring(CRUIDToHash(component.id)):gsub("ULL", "")] = change
        end
    end
end

local function setInstanceDataLight(entity, lightData, spawnable)
    for _, name in pairs(componentNames) do
        local component = entity:FindComponentByName(name)
        if component and CRUIDToString(component.id) ~= "0" then
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

            spawnable.instanceDataChanges[tostring(CRUIDToHash(component.id)):gsub("ULL", "")] = change
            break -- idek wth AMM is doing, only sets properties for first component
        end
    end
end

local componentWhitelist = {
    "entColliderComponent",
    "gameVisionModeComponent",
    "entLocalizationStringComponent",
    "entMeshComponent",
    "entPhysicalDestructionComponent",
    "gameaudioSoundComponent",
    "gameScanningComponent",
    "StimBroadcasterComponent",
    "gameTargetingComponent",
    "DisassemblableComponent"
}

---@param spawnable entity
---@param entity entEntity
---@return boolean
function amm.canConvertToMesh(spawnable, entity)
    if #spawnable.meshes ~= 1 then
        return false
    end

    if spawnable.meshes[1].collision then
        return false
    end

    if not (entity:IsExactlyA("entEntity") or entity:IsA("gameObject") or entity:IsA("gameItemObject")) then
        return false
    end

    if entity:FindComponentByName("amm_prop_slot1") then
        return true
    end

    for _, component in pairs(entity:GetComponents()) do
        for _, name in pairs(componentWhitelist) do
            if not component:IsA(name) then
                return false
            end
        end
    end

    return true
end

function amm.importPreset(data, spawnedUI, importTasks)
    local meshService = require("modules/utils/tasks"):new()

    local root = generateGroup(spawnedUI, data.file_name:gsub(".json", ""), nil)
    local props = generateGroup(spawnedUI, "Props", root)
    local lights = generateGroup(spawnedUI, "Lights", root)
    local lightNodes = generateGroup(spawnedUI, "Light Nodes", lights)
    local lightCustom = generateGroup(spawnedUI, "Customized Light Props", lights)
    local scaledProps = generateGroup(spawnedUI, "Scaled Props", root)
    local meshes = generateGroup(spawnedUI, "Meshes", root)

    for _, prop in pairs(data.props) do
        local propData = extractPropData(prop)

        --- Generate base object for hierarchy
        local o = generateElement(savedUI, propData)

        local isLight = getAMMLightByID(data.lights, propData.uid)
        local isAMMLight = propData.path:match(area) or propData.path:match(point) or propData.path:match(spot)
        local isScaled = propData.scale.x ~= 100 or propData.scale.y ~= 100 or propData.scale.z ~= 100

        if isLight and isAMMLight then
            -- Light Node
            o.spawnable = convertLight(propData, data)
            o.name = o.spawnable:generateName(propData.name)
            o:setParent(lightNodes)
            amm.progress = amm.progress + 1
        else
            if not Game.GetResourceDepot():ResourceExists(propData.path) then
                print("[AMMImport] Resource for " .. propData.path .. " does not exist, skipping...")
                amm.progress = amm.progress + 1
            else
                meshService:addTask(function ()
                    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
                    spawnable:loadSpawnData({
                        spawnData = propData.path,
                        app = propData.app
                    }, propData.pos, propData.rot)

                    spawnable:onBBoxLoaded(function (entity)
                        local canConvert = amm.canConvertToMesh(spawnable, entity)

                        if isLight then
                            setInstanceDataLight(entity, isLight, spawnable)

                            if not isScaled then
                                o.spawnable = spawnable
                                o.name = o.spawnable:generateName(propData.name .. "_light")
                                o:setParent(lightCustom)
                            end

                            spawnable:loadInstanceData(entity, true)
                            print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. utils.tableLength(spawnable.instanceDataChanges) .. " light components.")
                        end
                        if isScaled and not canConvert then
                            setInstanceDataMesh(entity, propData, spawnable)

                            o.spawnable = spawnable
                            o.name = o.spawnable:generateName(propData.name)
                            o:setParent(scaledProps)

                            o.spawnable:loadInstanceData(entity, true)
                            print("[AMMImport] Imported prop " .. propData.name .. " by generating instanceData for " .. utils.tableLength(spawnable.instanceDataChanges) .. " mesh components.")
                        end
                        if canConvert then
                            local scale = spawnable.meshes[1].originalScale
                            scale.x = scale.x * propData.scale.x / 100
                            scale.y = scale.y * propData.scale.y / 100
                            scale.z = scale.z * propData.scale.z / 100

                            local mesh = require("modules/classes/spawn/mesh/mesh"):new()
                            mesh:loadSpawnData({
                                spawnData = spawnable.meshes[1].path,
                                app = spawnable.meshes[1].app,
                                scale = { x = scale.x, y = scale.y, z = scale.z }
                            }, spawnable.meshes[1].globalPosition, spawnable.meshes[1].globalRotation)

                            o.spawnable = mesh
                            o.name = o.spawnable:generateName(propData.name)
                            o:setParent(meshes)
                            print("[AMMImport] Imported prop " .. propData.name .. " by converting to mesh node.")
                        elseif not isLight and not isScaled then
                            o.spawnable = convertProp(propData)
                            o.name = o.spawnable:generateName(propData.name)
                            o:setParent(props)
                            print("[AMMImport] Imported prop " .. propData.name .. " by converting to entity node.")
                        end

                        Game.GetStaticEntitySystem():DespawnEntity(spawnable.entityID)
                        amm.progress = amm.progress + 1
                        meshService:taskCompleted()
                    end)

                    spawnable:spawn()
                end)
            end
        end
    end

    meshService:onFinalize(function ()
        root:save()
        print("[ObjectSpawner] Imported \"" .. data.file_name .. "\" from AMM.")

        importTasks:taskCompleted()
    end)

    meshService:run(false)
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