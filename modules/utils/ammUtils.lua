local object = require("modules/classes/spawn/object")
local amm = {}

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

local function convertProp(prop)
    local scale = loadstring("return " .. prop.scale, "")()
    local area = "base\\amm_props\\entity\\ambient_area_light"
    local point = "base\\amm_props\\entity\\ambient_point_light"
    local spot = "base\\amm_props\\entity\\ambient_spot_light"

    if scale.x ~= 100 or scale.y ~= 100 or scale.z ~= 100 then

    elseif prop.template_path:match(area) or prop.template_path:match(point) or prop.template_path:match(spot) then

    else

    end

    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
    spawnable:loadSpawnData({
        spawnData = object.path,
        app = object.app
    }, ToVector4(object.pos), ToEulerAngles(object.rot))

    local newObject = require("modules/classes/spawn/object"):new(savedUI)
    newObject.name = object.name
    newObject.headerOpen = object.headerOpen
    newObject.loadRange = object.loadRange
    newObject.autoLoad = object.autoLoad
    newObject.spawnable = spawnable

    if getState then
        return newObject:getState()
    else
        return newObject
    end
end

function amm.importPreset(data, savedUI)
    local root = gr:new(savedUI)
    root.name = data.file_name:gsub(".json", "")

    local props = gr:new(savedUI)
    props.parent = root
    props.name = "Props"

    local lights = gr:new(savedUI)
    lights.parent = root
    lights.name = "Lights"

    local meshes = gr:new(savedUI)
    meshes.parent = root
    meshes.name = "Meshes"

    for _, prop in pairs(data.props) do
        local location = loadstring("return " .. prop.pos, "")()
        local pos = Vector4.new(location.x, location.y, location.z, 0)
        local rot = EulerAngles.new(location.roll, location.pitch, location.yaw)

        local spawnData = {
            path = prop.template_path,
            app = prop.app,
            name = prop.name,
            pos = pos,
            rot = rot,
            headerOpen = false,
            loadRange = 100,
            autoLoad = false
        }

        local object = savedUI.convertObject(spawnData, false)
        if prop.template_path:match(area) or prop.template_path:match(point) or prop.template_path:match(spot) then
            local lightData = getAMMLightByID(data.lights, prop.uid)

            spawnData.color = loadstring("return " .. lightData.color, "")()
            spawnData.color = {spawnData.color[1], spawnData.color[2], spawnData.color[3]}
            spawnData.intensity = lightData.intensity
            local angles = loadstring("return " .. lightData.angles, "")()
            spawnData.innerAngle = angles.inner
            spawnData.outerAngle = angles.outer
            spawnData.radius = lightData.radius

            if prop.template_path:match(area) then
                spawnData.lightType = 2
            elseif prop.template_path:match(point) then
                spawnData.lightType = 0
            else
                spawnData.lightType = 1
            end

            local light = require("modules/classes/spawn/light/light"):new()
            light:loadSpawnData(spawnData, spawnData.pos, spawnData.pos)
            object.spawnable = light
            object.parent = lights
            table.insert(lights.childs, object)
        else
            object.parent = props
            table.insert(props.childs, object)
        end
    end

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