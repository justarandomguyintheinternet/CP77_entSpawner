local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")
local red = require("modules/utils/redConverter")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

---Class for base entity handling
---@class entity : spawnable
---@field public apps table
---@field public appIndex integer
---@field private bBoxCallback function
---@field public bBox table {min: Vector4, max: Vector4}
---@field public instanceDataChanges table Changes to the default data, regardless of app (Matched by ID)
---@field public defaultComponentData table Default data for each component, regardless of whether it was changed. Keeps up to date with app changes
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"
    o.icon = IconGlyphs.AlphaEBoxOutline

    o.apps = {}
    o.appIndex = 0
    o.bBoxCallback = nil
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }

    o.instanceDataChanges = {}
    o.defaultComponentData = {}

    o.uk10 = 1056

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
    self.defaultComponentData = {}

    for _, component in pairs(entity:GetComponents()) do
        local ignore = false

        if component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent") then
            ignore = ResRef.FromHash(component.mesh.hash):ToString():match("base\\spawner") or ResRef.FromHash(component.mesh.hash):ToString():match("base\\amm_props\\mesh\\invis_")
        end
        if not ignore then
            self.defaultComponentData[tostring(CRUIDToHash(component.id)):gsub("ULL", "")] = red.redDataToJSON(component)
        end

        for key, data in pairs(utils.deepcopy(self.instanceDataChanges)) do
            if key == tostring(CRUIDToHash(component.id)):gsub("ULL", "") then
                assembleInstanceData(data, utils.deepcopy(self.defaultComponentData[key]))
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

        visualizer.updateScale(entity, self:getVisualizerSize(), "arrows")

        if self.bBoxCallback then
            self.bBoxCallback(entity)
        end
    end)
end

function entity:save()
    local data = spawnable.save(self)
    data.instanceDataChanges = utils.deepcopy(self.instanceDataChanges)

    local default = {}
    for key, _ in pairs(self.instanceDataChanges) do
        default[key] = utils.deepcopy(self.defaultComponentData[key])
    end
    data.defaultComponentData = default

    return data
end

function entity:onBBoxLoaded(callback)
    self.bBoxCallback = callback
end

function entity:getSize()
    return { x = self.bBox.max.x - self.bBox.min.x, y = self.bBox.max.y - self.bBox.min.y, z = self.bBox.max.z - self.bBox.min.z }
end

function entity:getVisualizerSize()
    local size = self:getSize()

    local max = math.min(math.max(size.x, size.y, size.z, 1) * 0.5, 3.5)
    return { x = max, y = max, z = max }
end

function entity:drawResetProp(componentID, path)
    local modified = self.instanceDataChanges[componentID] ~= nil and utils.getNestedValue(self.instanceDataChanges[componentID], path) ~= nil

    if ImGui.BeginPopupContextItem("##resetComponentProperty" .. componentID .. path[1] .. path[#path], ImGuiPopupFlags.MouseButtonRight) then
        if ImGui.MenuItem("Reset") and modified then
            history.addAction(history.getElementChange(self.object))
            if #path == 1 or (#path == 2 and self.instanceDataChanges[componentID][path[1]]["HandleId"] ~= nil) then -- Get rid of changes
                self.instanceDataChanges[componentID][path[1]] = nil
                if utils.tableLength(self.instanceDataChanges[componentID]) == 0 then
                    self.instanceDataChanges[componentID] = nil
                end
            else
                utils.setNestedValue(self.instanceDataChanges[componentID], path, utils.deepcopy(utils.getNestedValue(self.defaultComponentData[componentID], path)))
            end
            self:respawn()
        end
        ImGui.EndPopup()
    end
end

function entity:updatePropValue(componentID, path, value)
    if not self.instanceDataChanges[componentID] then
        self.instanceDataChanges[componentID] = {}
    end
    if not self.instanceDataChanges[componentID][path[1]] then
        self.instanceDataChanges[componentID][path[1]] = utils.deepcopy(self.defaultComponentData[componentID][path[1]])
    end
    utils.setNestedValue(self.instanceDataChanges[componentID], path, value)
    -- TODO: If value is the same as default, remove it from instanceDataChanges
    self:respawn()
end

---@private
function entity:drawInstanceDataProperty(componentID, key, data, path)
    local dataType = type(data)

    if dataType == "table" then
        if utils.tableLength(data) == 0 then
            ImGui.Text(key .. " Empty Array")
            return
        end
        if data.HandleId then
            local dataPath = utils.deepcopy(path)
            table.insert(dataPath, "Data")
            self:drawInstanceDataProperty(componentID, key, data.Data, dataPath)
            return
        end

        local dataType = data["$type"]
        if not dataType then
            if data["DepotPath"] then
                dataType = "Resource"
            else
                dataType = "Unknown"
            end
        end

        local name = dataType .. " | " .. key

        local open = false
        if ImGui.TreeNodeEx(name, ImGuiTreeNodeFlags.SpanFullWidth) then
            self:drawResetProp(componentID, path)
            open = true
            for _, propKey in pairs(self:getSortedKeys(data)) do
                local entry = data[propKey]
                local propPath = utils.deepcopy(path)
                table.insert(propPath, propKey)
                self:drawInstanceDataProperty(componentID, propKey, entry, propPath)
            end
            ImGui.TreePop()
        end
        if not open then self:drawResetProp(componentID, path) end
    else
        -- TODO: Clean all of this up, make it more modular, make it easy to have bespoke editing of e.g. worldposition / color, make use of drag inputs
    -- if type(data) == "number" then
    --     local value, changed = ImGui.InputInt(key, data)
    --     if changed then
    --         history.addAction(history.getElementChange(self.object))
    --         self:updatePropValue(componentID, path, value)
    --     end
    --     self:drawResetProp(componentID, path)
    -- elseif type(data) == "string" then
    --     ImGui.Text(key .. tostring(data))
    --     self:drawResetProp(componentID, path)
    -- elseif type(data) == "boolean" then
        if key == "$type" or key == "$storage" or key == "Flags" then return end
        if key == "$value" then
            ImGui.Text(key .. " " .. data)
            self:drawResetProp(componentID, path)
            return
        end

        local parentPath = utils.deepcopy(path)
        table.remove(parentPath, #parentPath)
        local dataType = Reflection.GetClass(utils.getNestedValue(self.defaultComponentData[componentID], parentPath)["$type"]):GetProperty(key):GetType():GetName().value

        if dataType == "Bool" then
            ImGui.Text(key)
            ImGui.SameLine()
            local value, changed = ImGui.Checkbox("##" .. key .. componentID .. path[1], data == 1 and true or false)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value and 1 or 0)
            end
        elseif dataType == "Float" then
            ImGui.Text(key)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            local value, changed = ImGui.InputFloat("##" .. key .. componentID .. path[1], data)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value)
            end
        else
            ImGui.Text(key .. " " .. dataType)
        end
        self:drawResetProp(componentID, path)
    end
end

function entity:drawResetComponent(id)
    if ImGui.BeginPopupContextItem("##resetComponent" .. id, ImGuiPopupFlags.MouseButtonRight) then
        if ImGui.MenuItem("Reset") and self.instanceDataChanges[id] then
            history.addAction(history.getElementChange(self.object))
            self.instanceDataChanges[id] = nil
            self:respawn()
        end
        ImGui.EndPopup()
    end
end

function entity:drawInstanceData()
    for key, component in pairs(self.defaultComponentData) do
        local name = component["$type"] .. " | " .. component.name["$value"]
        style.pushStyleColor(not self.instanceDataChanges[key], ImGuiCol.Text, style.mutedColor)

        local expanded = false
        if ImGui.TreeNodeEx(name, ImGuiTreeNodeFlags.SpanFullWidth) then
            expanded = true
            self:drawResetComponent(key)

            for _, propKey in pairs(self:getSortedKeys(component)) do
                local entry = component[propKey]
                local modified = self.instanceDataChanges[key] and self.instanceDataChanges[key][propKey]
                if modified then entry = self.instanceDataChanges[key][propKey] end

                style.pushStyleColor(not modified, ImGuiCol.Text, style.mutedColor)
                self:drawInstanceDataProperty(key, propKey, entry, { propKey })

                style.popStyleColor(not modified)
            end
            ImGui.TreePop()
        end
        if not expanded then
            self:drawResetComponent(key)
        end

        style.popStyleColor(not self.instanceDataChanges[key])
    end
end

function entity:getSortedKeys(tbl)
    local order = {"$type", "id", "name"}
    local keys = {}

    for key, _ in pairs(tbl) do
        table.insert(keys, key)
    end

    table.sort(keys, function (a, b)
        local aIndex = utils.indexValue(order, a)
        local bIndex = utils.indexValue(order, b)

        if aIndex ~= -1 and bIndex ~= -1 then
            return aIndex < bIndex
        end

        if aIndex ~= -1 then
            return true
        end

        if bIndex ~= -1 then
            return false
        end

        return string.lower(a) < string.lower(b)
    end)

    return keys
end

function entity:draw()
    spawnable.draw(self)

    style.pushGreyedOut(#self.apps == 0 or not self:isSpawned())

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    local index, changed = style.trackedCombo(self.object, "##app", self.appIndex, list, 110)
    if changed and #self.apps > 0 and self:isSpawned() then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        self.defaultComponentData = {}

        if entity then
            self:respawn()
        end
    end
    style.popGreyedOut(#self.apps == 0 or not self:isSpawned())
end

function entity:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    table.insert(properties, {
        id = self.node .. "instanceData",
        name = "Entity Instance Data",
        defaultHeader = false,
        draw = function()
            self:drawInstanceData()
        end
    })
    return properties
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

        for _, data in pairs(utils.deepcopy(self.defaultComponentData)) do
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