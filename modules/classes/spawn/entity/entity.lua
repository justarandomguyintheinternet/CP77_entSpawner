local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")
local red = require("modules/utils/redConverter")

---Class for base entity handling
---@class entity : spawnable
---@field public apps table
---@field public appIndex integer
---@field private bBoxCallback function
---@field public bBox table {min: Vector4, max: Vector4}
---@field public instanceData table Default data for each changed component, on a per app basis
---@field public instanceDataChanges table Changes to the default data, regardless of app (Matched by ID)
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.apps = {}
    o.appIndex = 0
    o.bBoxCallback = nil
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }

    o.instanceData = {}
    o.instanceDataChanges = {}

    setmetatable(o, { __index = self })
   	return o
end

function entity:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    self.apps = cache.getValue(self.spawnData .. "_apps")
    if not self.apps then
        self.apps = {}
        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end
        end)
        cache.addValue(self.spawnData .. "_apps", self.apps)
    end

    self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
end

local function assembleInstanceData(instanceDataPart, instanceData)
    for key, data in pairs(instanceDataPart) do
        instanceData[key] = data
    end
end

function entity:loadInstanceData(entity)
    for _, component in pairs(entity:GetComponents()) do
        for key, data in pairs(utils.deepcopy(self.instanceDataChanges)) do
            if key == tostring(CRUIDToHash(component.id)):gsub("ULL", "") then

                local defaultData = nil

                for _, entry in pairs(self.instanceData) do
                    if entry.id == key then
                        defaultData = entry
                        break
                    end
                end

                if not defaultData then
                    defaultData = red.redDataToJSON(component)
                    table.insert(self.instanceData, defaultData)
                end

                assembleInstanceData(data, defaultData)
                red.JSONToRedData(data, component)
            end
        end
    end
end

function entity:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    self:loadInstanceData(entity)

    cache.tryGet(self.spawnData .. "_bBox", self.spawnData .. "_meshes")
    .notFound(function (task)
        builder.getEntityBBox(entity, function (data)
            local meshes = {}
            for _, mesh in pairs(data.meshes) do
                table.insert(meshes, { app = mesh.app, path = mesh.path, pos = utils.fromVector(mesh.pos), rot = utils.fromEuler(mesh.rot), name = mesh.name, scaled = mesh.hasScale })
            end

            cache.addValue(self.spawnData .. "_bBox", { min = utils.fromVector(data.bBox.min), max = utils.fromVector(data.bBox.max) })
            cache.addValue(self.spawnData .. "_meshes", meshes)
            print("[Entity] Loaded and cached BBOX for entity " .. self.spawnData .. " with " .. #meshes .. " meshes.")

            task:taskCompleted()
        end)
    end)
    .found(function ()
        utils.log("[Entity] BBOX for entity " .. self.spawnData .. " found.")
        local box = cache.getValue(self.spawnData .. "_bBox")
        self.bBox.min = ToVector4(box.min)
        self.bBox.max = ToVector4(box.max)

        visualizer.updateScale(entity, self:getVisualScale(), "arrows")

        if self.bBoxCallback then
            self.bBoxCallback(entity)
        end
    end)
end

function entity:save()
    local data = spawnable.save(self)
    data.instanceData = self.instanceData
    data.instanceDataChanges = self.instanceDataChanges

    return data
end

function entity:onBBoxLoaded(callback)
    self.bBoxCallback = callback
end

function entity:getVisualScale()
    local x = self.bBox.max.x - self.bBox.min.x
    local y = self.bBox.max.y - self.bBox.min.y
    local z = self.bBox.max.z - self.bBox.min.z

    local max = math.min(math.max(x, y, z, 1) * 0.5, 3.5)
    return { x = max, y = max, z = max }
end

function entity:getExtraHeight()
    return 4 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 1
end

function entity:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    style.pushGreyedOut(#self.apps == 0 or not self:isSpawned())

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    ImGui.SetNextItemWidth(150)
    local index, changed = ImGui.Combo("##app", self.appIndex, list, #list)
    if changed and #self.apps > 0 and self:isSpawned() then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        self.instanceData = {}

        if entity then
            self:respawn()
        end
    end
    style.popGreyedOut(#self.apps == 0 or not self:isSpawned())
end

local function copyAndPrepareData(data, index)
	local orig_type = type(data)
    local copy

    if orig_type == 'table' then
        copy = {}
        for origin_key, origin_value in next, data, nil do
            local keyCopy = copyAndPrepareData(origin_key, index)
            local valueCopy = copyAndPrepareData(origin_value, index)

            if keyCopy == "HandleId" then
                valueCopy = tostring(index[1])
                index[1] = index[1] + 1
            end

            copy[keyCopy] = valueCopy
        end
        setmetatable(copy, copyAndPrepareData(getmetatable(data), index))
    else
        copy = data
    end
    return copy
end

--exEntitySpawner.Spawn("base\\worlds\\03_night_city\\sectors\\se1\\loc_q103_ghost_town\\interior_wall_lamp_a_3_q103.ent", GetPlayer():GetWorldTransform())

function entity:export(index, length)
    local data = spawnable.export(self)

    if utils.tableLength(self.instanceDataChanges) > 0 then
        local dict = {}

        local i = 0
        for key, _ in pairs(self.instanceDataChanges) do
            dict[tostring(i)] = key
            i = i + 1
        end

        local combinedData = {}

        for _, data in pairs(utils.deepcopy(self.instanceData)) do
            if self.instanceDataChanges[data.id] then
                assembleInstanceData(self.instanceDataChanges[data.id], data)
                table.insert(combinedData, data)
            end
        end

        local baseHandle = length + 10 + index * 25 -- 10 offset to last handle of nodeData, 25 handleIDs per entity for instance data

        data.data.instanceData = {
            ["HandleId"] = tostring(baseHandle), -- 10 offset to last handle of nodeData, 25 handleIDs per entity for instance data
            ["Data"] = {
                ["$type"] = "entEntityInstanceData",
                ["buffer"] = {
                    ["BufferId"] = tostring(FNV1a64("Entity" .. tostring(self.position.x * self.position.y) .. math.random(1, 10000000))):gsub("ULL", ""),
                    ["Type"] = "WolvenKit.RED4.Archive.Buffer.RedPackage, WolvenKit.RED4, Version=8.14.1.0, Culture=neutral, PublicKeyToken=null",
                    ["Data"] = {
                        ["Version"] = 4,
                        ["Sections"] = 6,
                        ["CruidIndex"] = -1,
                        ["CruidDict"] = dict,
                        ["Chunks"] = copyAndPrepareData(combinedData, { baseHandle + 1 })
                    }
                }
            }
        }
    end

    return data
end

return entity