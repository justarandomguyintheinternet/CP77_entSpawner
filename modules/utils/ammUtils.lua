local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")
local amm = {
    importing = false
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

function amm.importPreset(data, savedUI, importTasks)
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

    local colliders = gr:new(savedUI)
    colliders.parent = root
    colliders.headerOpen = false
    colliders.name = "Colliders"


    for _, prop in pairs(data.props) do
        local propData = extractPropData(prop)

        --- Generate base object for hierarchy
        local o = generateObject(savedUI, propData)

        local isLight = getAMMLightByID(data.lights, propData.uid)
        local isAMMLight = propData.path:match(area) or propData.path:match(point) or propData.path:match(spot)

        if isLight and isAMMLight then
            o.spawnable = convertLight(propData, data)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = lights
            table.insert(lights.childs, o)
        elseif propData.scale.x ~= 100 or propData.scale.y ~= 100 or propData.scale.z ~= 100 then --or (isLight and not isAMMLight)
            if not Game.GetResourceDepot():ResourceExists(propData.path) then
                print("[AMMImport] Resource for " .. propData.path .. " does not exist, skipping...")
            else
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
                            local meshCollisions = cache.getValue(mesh.path .. "_collisions")
                            if ((propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0) and meshCollisions) or (meshCollisions and #meshCollisions > 0) then
                                for _, collision in pairs(meshCollisions) do
                                    local c = require("modules/classes/spawn/collision/collider"):new()

                                    local collisionPos = ToVector4(collision.pos)
                                    if not (propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0) then
                                        collisionPos = Vector4.new(collisionPos.x * propData.scale.x / 100, collisionPos.y * propData.scale.y / 100, collisionPos.z * propData.scale.z / 100, 0)
                                    end

                                    utils.log("Collision position after scaling: " .. collisionPos.x .. " " .. collisionPos.y .. " " .. collisionPos.z)

                                    local localPosition = utils.addVector(ToVector4(mesh.pos), collisionPos)

                                    utils.log("Collision position after adding mesh position: " .. localPosition.x .. " " .. localPosition.y .. " " .. localPosition.z)

                                    localPosition = ToEulerAngles(mesh.rot):ToQuat():Transform(localPosition)
                                    localPosition = propData.rot:ToQuat():Transform(localPosition)
                                    local rot = utils.addEulerRelative(utils.addEulerRelative(propData.rot, ToEulerAngles(mesh.rot)), ToQuaternion(collision.rot):ToEulerAngles())

                                    utils.log("Collision position after rotating: " .. localPosition.x .. " " .. localPosition.y .. " " .. localPosition.z)

                                    local pos = utils.addVector(propData.pos, localPosition)

                                    if not (propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0) then
                                        if collision.extents then
                                            local factor = Vector4.new(propData.scale.x / 100, propData.scale.y / 100, propData.scale.z / 100, 0)
                                            factor = ToQuaternion(collision.rot):Transform(factor) -- Account for rotation of collision when applying scaling
                                            local scale = Vector4.new(collision.extents.x * factor.x, collision.extents.y * factor.y, collision.extents.z * factor.z, 0)

                                            collision.extents = { x = scale.x, y = scale.y, z = scale.z }
                                        end
                                        if collision.radius then
                                            collision.radius = collision.radius * (math.max(propData.scale.x, propData.scale.y) / 100)
                                        end
                                        if collision.height then
                                            collision.height = collision.height * (propData.scale.z / 100)
                                        end
                                        utils.log("Prop is scaled, but not zero, scaling collider accordingly")
                                    end

                                    collision.preset = c:getPresetIndexByName(collision.preset)
                                    collision.material = c:getMaterialIndexByName(collision.material)

                                    c:loadSpawnData(collision, pos, rot)
                                    local collisionObject = generateObject(savedUI, { name = propData.name .. "_collision" })
                                    collisionObject.spawnable = c
                                    collisionObject.parent = colliders
                                    table.insert(colliders.childs, collisionObject)

                                    utils.log("Creating collider for mesh " .. mesh.path .. " for prop " .. propData.path)
                                    utils.log("Is zero-scale: " .. tostring(propData.scale.x == 0 and propData.scale.y == 0 and propData.scale.z == 0))
                                end

                                print("[AMMImport] Created " .. #meshCollisions .. " colliders for the mesh " .. mesh.path .. " for prop " .. propData.path)
                            end

                            if propData.scale.x ~= 0 and propData.scale.y ~= 0 and propData.scale.z ~= 0 then
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

                                print("[AMMImport] Imported prop " .. propData.name .. " by converting it to " .. #meshesData .. " meshes.")
                            end
                        end

                        utils.log("[ammUtils] Task Done For " .. propData.path)
                        utils.log("   ")
                        meshService:taskCompleted()
                    end)
                end)
            end
        else
            o.spawnable = convertProp(propData)
            o.name = o.spawnable:generateName(propData.name)
            o.parent = props
            table.insert(props.childs, o)
        end
    end

-- zero scale:
    -- generate collider based on physics param, ignore scale
-- non 100 non zero scale:
    -- generate collider based on physics param, scale collider

    meshService:onFinalize(function ()
        table.insert(root.childs, props)
        table.insert(root.childs, lights)
        table.insert(root.childs, meshes)
        table.insert(root.childs, colliders)
        root.pos = root:getCenter()
        lights.pos = lights:getCenter()
        props.pos = props:getCenter()
        meshes.pos = meshes:getCenter()
        colliders.pos = colliders:getCenter()

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

    for _, file in pairs(dir("data/AMMImport")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            importTasks:addTask(function ()
                local data = config.loadFile("data/AMMImport/" .. file.name)
                amm.importPreset(data, savedUI, importTasks)
            end)
        end
    end

    importTasks:onFinalize(function ()
        print("[AMMImport] All presets imported.")
        amm.importing = false
    end)

    importTasks:run(true)
    -- amm.importing = true
end

return amm