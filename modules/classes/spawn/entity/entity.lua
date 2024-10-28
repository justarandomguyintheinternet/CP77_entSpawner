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
    o.typeInfo = {}
    o.enumInfo = {}

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

-- Instance Data (Mess)

function entity:getSortedKeys(tbl)
    local keys = {}
    local max = 0

    for key, _ in pairs(tbl) do
        max = math.max(max, ImGui.CalcTextSize(tostring(key)))
        table.insert(keys, key)
    end

    table.sort(keys, function (a, b)
        return string.lower(tostring(a)) < string.lower(tostring(b))
    end)

    return keys, max
end

function entity:getDerivedClasses(base)
    local classes = { base }

    for _, derived in pairs(Reflection.GetDerivedClasses(base)) do
        if derived:GetName().value ~= base then
            for _, class in pairs(self:getDerivedClasses(derived:GetName().value)) do
                table.insert(classes, class)
            end
        end
    end

    return classes
end

---Hell (Attempt to get the type of the data at the specified path)
---@param componentID number
---@param path table
---@param key string
---@return table { typeName: string, isEnum: boolean, propType: CName }
function entity:getPropTypeInfo(componentID, path, key)
    -- Step one up, so we can get class of parent, then use that to get property type
    local parentPath = utils.deepcopy(path)
    table.remove(parentPath, #parentPath)

    local value = utils.getNestedValue(self.defaultComponentData[componentID], parentPath)
    if not value then -- Might be a custom array entry, only present in instanceDataChanges
        value = utils.getNestedValue(self.instanceDataChanges[componentID], parentPath)
    end

    -- Handle or array entry
    if not value["$type"] then
        if value["HandleId"] then
            -- Step one further up, to get the class of the parent of the handle (Could also step down and retrieve type there)
            table.remove(parentPath, #parentPath)
        end
        if type(key) == "number" then -- Is array entry
            if value["HandleId"] then
                -- Type of handle, by stepping down
                return { typeName = value["Data"]["$type"], isEnum = false, propType = nil}
            else
                -- If its not a handle, parentPath will be prop which exists on default data (value ~= nil), but the actual array entry does only exist in instanceDataChanges
                if not value[key] then
                    value = utils.getNestedValue(self.instanceDataChanges[componentID], parentPath)
                end
                return { typeName = value[key]["$type"], isEnum = false, propType = nil}
            end
        end
    end

    value = utils.getNestedValue(self.defaultComponentData[componentID], parentPath) -- Re-Fetch, in case it was a handle and we changed the path
    if not value then -- Array entry, only present in instanceDataChanges
        value = utils.getNestedValue(self.instanceDataChanges[componentID], parentPath)
    end

    local fullPath = table.concat(path, "/")
    if not self.typeInfo[fullPath] then
        local propType = Reflection.GetClass(value["$type"]):GetProperty(key):GetType()
        local propEnum = propType:IsEnum()
        local propTypeName = propType:GetName().value

        self.typeInfo[fullPath] = { typeName = propTypeName, isEnum = propEnum, propType = propType }
    end

    return self.typeInfo[fullPath]
end

function entity:updatePropValue(componentID, path, value)
    if not self.instanceDataChanges[componentID] then
        self.instanceDataChanges[componentID] = {}
    end
    if not self.instanceDataChanges[componentID][path[1]] then
        self.instanceDataChanges[componentID][path[1]] = utils.deepcopy(self.defaultComponentData[componentID][path[1]])
    end

    utils.setNestedValue(self.instanceDataChanges[componentID], path, value)
    if utils.deepcompare(self.defaultComponentData[componentID][path[1]], self.instanceDataChanges[componentID][path[1]], false) then
        self.instanceDataChanges[componentID][path[1]] = nil
        if utils.tableLength(self.instanceDataChanges[componentID]) == 0 then
            self.instanceDataChanges[componentID] = nil
        end
    end

    self:respawn()
end

function entity:drawStringProp(componentID, key, data, path, type, width, max)
    ImGui.Text(key)
    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(key) + max)
    ImGui.SetNextItemWidth(width * style.viewSize)
    local value, changed = ImGui.InputText("##" .. componentID .. table.concat(path), data, 100)
    style.tooltip(type)
    self:drawResetProp(componentID, path)
    if changed then
        history.addAction(history.getElementChange(self.object))
        self:updatePropValue(componentID, path, value)
    end
end

function entity:drawNumericProp(componentID, key, data, path, type, isFloat, hasText, format)
    if hasText then
        ImGui.Text(key)
        ImGui.SameLine()
    end
    ImGui.SetNextItemWidth(100 * style.viewSize)
    local value, changed
    if isFloat then
        value, changed = ImGui.InputFloat("##" .. componentID .. table.concat(path), data, 0.05, 0.1, format)
    else
        value, changed = ImGui.InputInt("##" .. componentID .. table.concat(path), data, 1, 10, format)
    end
    style.tooltip(type)
    self:drawResetProp(componentID, path)

    if changed then
        history.addAction(history.getElementChange(self.object))
        self:updatePropValue(componentID, path, value)
    end
end

function entity:drawResetProp(componentID, path)
    local modified = self.instanceDataChanges[componentID] ~= nil and utils.getNestedValue(self.instanceDataChanges[componentID], path) ~= nil

    if ImGui.BeginPopupContextItem("##resetComponentProperty" .. componentID .. table.concat(path), ImGuiPopupFlags.MouseButtonRight) then
        local isArray = type(path[#path]) == "number"

        -- Might be array of handles, so check one path index up (.../->index<-/Data)
        if not isArray and #path > 1 then
            isArray = type(path[#path - 1]) == "number"
            path = utils.deepcopy(path)
            table.remove(path, #path)
        end
        local text = isArray and "Remove" or "Reset"

        if ImGui.MenuItem(text) and modified then
            history.addAction(history.getElementChange(self.object))
            if not isArray then
                self:updatePropValue(componentID, path, utils.deepcopy(utils.getNestedValue(self.defaultComponentData[componentID], path)))
            else
                self:updatePropValue(componentID, path, nil)
            end
        end
        ImGui.EndPopup()
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

function entity:drawAddArrayEntry(prop, componentID, path, data)
    if prop and prop:IsArray() then
        ImGui.Button("+")
        if ImGui.BeginPopupContextItem("##" .. componentID .. table.concat(path), ImGuiPopupFlags.MouseButtonLeft) then
            local base = prop:GetInnerType()
            local isHandle = base:GetMetaType() == ERTTIType.Handle
            if isHandle then base = base:GetInnerType() end

            if base:GetMetaType() ~= ERTTIType.Class then
                ImGui.Text("Type not yet supported")
            else
                for _, class in pairs(self:getDerivedClasses(base:GetName().value)) do
                    if ImGui.MenuItem(class) then
                        local newPath = utils.deepcopy(path)
                        table.insert(newPath, #data + 1)
                        if isHandle then
                            self:updatePropValue(componentID, newPath, { HandleId = "0", Data = red.redDataToJSON(NewObject(class)) })
                        else
                            self:updatePropValue(componentID, newPath, red.redDataToJSON(NewObject(class)))
                        end
                    end
                end
            end
            ImGui.EndPopup()
        end
    end
end

---Draw either a class by iterating over each property, or specical cases like DepotPath, CName etc.
---@param componentID number
---@param key string
---@param data any
---@param path table Path to the data, from the root of the component
---@param max number Maximum width of a label text
function entity:drawTableProp(componentID, key, data, path, max, modified)
    -- Step one down, to avoid handle structure, gets really fucking ugly later
    if data.HandleId then
        table.insert(path, "Data")
        self:drawInstanceDataProperty(componentID, key, data.Data, path, max)
        return
    end

    local info = self:getPropTypeInfo(componentID, path, key)

    style.pushStyleColor(modified, ImGuiCol.Text, style.regularColor)
    if data["DepotPath"] then
        table.insert(path, "DepotPath")
        table.insert(path, "$value")
        self:drawStringProp(componentID, key, data["DepotPath"]["$value"], path, "Resource", 300, max)
        style.popStyleColor(modified)
        return
    elseif info.typeName == "FixedPoint" then
        table.insert(path, "Bits")

        ImGui.Text(key)
        ImGui.SameLine()
        ImGui.SetNextItemWidth(100 * style.viewSize)
        local value, changed = ImGui.InputFloat("##" .. componentID .. table.concat(path), data["Bits"] / 131072, 0, 0, "%.2f")
        if changed then
            history.addAction(history.getElementChange(self.object))
            self:updatePropValue(componentID, path, value * 131072)
        end
        self:drawResetProp(componentID, path)
        style.popStyleColor(modified)
        return
    elseif info.typeName == "TweakDBID" or info.typeName == "CName" or info.typeName == "NodeRef" then
        table.insert(path, "$value")
        self:drawStringProp(componentID, key, data["$value"], path, info.typeName, 150, max)
        style.popStyleColor(modified)
        return
    end

    local name = info.typeName .. " | " .. key

    local open = false
    if ImGui.TreeNodeEx(name, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawResetProp(componentID, path)
        open = true
        style.popStyleColor(modified)

        local keys, max = self:getSortedKeys(data)
        -- Array uses numeric keys
        if info.propType and info.propType:IsArray() then
            keys = {}
            for key, _ in pairs(data) do table.insert(keys, key) end
        end

        for _, propKey in pairs(keys) do
            local entry = data[propKey]
            local propPath = utils.deepcopy(path)
            table.insert(propPath, propKey)
            self:drawInstanceDataProperty(componentID, propKey, entry, propPath, max)
        end

        self:drawAddArrayEntry(info.propType, componentID, path, data)

        ImGui.TreePop()
    end
    if not open then
        self:drawResetProp(componentID, path)
        style.popStyleColor(modified)
    end
end

---@private
---@param componentID number
---@param key string Key of data within the parent
---@param data table
---@param path table Path to the data, from the root of the component
---@param max number Maximum width of a text
function entity:drawInstanceDataProperty(componentID, key, data, path, max)
    if key == "$type" or key == "$storage" or key == "Flags" then return end

    local modified = false
    if self.instanceDataChanges[componentID] and self.instanceDataChanges[componentID][path[1]] then
        if not utils.deepcompare(data, utils.getNestedValue(self.defaultComponentData[componentID], path), false) then
            modified = true
        end
    end

    if type(data) == "table" then
        self:drawTableProp(componentID, key, data, path, max, modified)
    else
        style.pushStyleColor(modified, ImGuiCol.Text, style.regularColor)

        local info = self:getPropTypeInfo(componentID, path, key)

        ImGui.Text(key)
        ImGui.SameLine()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(key) + max)

        if info.typeName == "Bool" then
            local value, changed = ImGui.Checkbox("##" .. componentID .. table.concat(path), data == 1 and true or false)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value and 1 or 0)
            end
        elseif info.typeName == "Float" then
            ImGui.SetNextItemWidth(100 * style.viewSize)
            local value, changed = ImGui.InputFloat("##" .. componentID .. table.concat(path), data, 0, 0, "%.2f")
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value)
            end
        elseif info.typeName == "Uint64" or info.typeName == "CRUID" or info.typeName == "String" then
            ImGui.SetNextItemWidth(100 * style.viewSize)

            local value, changed = ImGui.InputText("##" .. componentID .. table.concat(path), data, 100)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value)
            end
        elseif string.match(info.typeName, "int") or string.match(info.typeName, "Int") then
            ImGui.SetNextItemWidth(100 * style.viewSize)

            local value, changed = ImGui.InputInt("##" .. componentID .. table.concat(path), data, 0)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, value)
            end
        elseif info.isEnum then
            if not self.enumInfo[info.typeName] then
                self.enumInfo[info.typeName] = utils.enumTable(info.typeName)
            end
            local values = self.enumInfo[info.typeName]

            ImGui.SetNextItemWidth(100 * style.viewSize)
            local value, changed = ImGui.Combo("##" .. componentID .. table.concat(path), utils.indexValue(values, data) - 1, values, #values)
            if changed then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, values[value + 1])
            end
        else
            ImGui.Text(key .. " " .. info.typeName)
        end

        style.tooltip(info.typeName)
        self:drawResetProp(componentID, path)
        style.popStyleColor(modified)
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
            style.popStyleColor(not self.instanceDataChanges[key])

            local keys, max = self:getSortedKeys(component)
            for _, propKey in pairs(keys) do
                local entry = component[propKey]
                local modified = self.instanceDataChanges[key] and self.instanceDataChanges[key][propKey]
                if modified then entry = self.instanceDataChanges[key][propKey] end

                style.pushStyleColor(true, ImGuiCol.Text, style.mutedColor)
                self:drawInstanceDataProperty(key, propKey, entry, { propKey }, max)

                style.popStyleColor(true)
            end
            ImGui.TreePop()
        end
        if not expanded then
            self:drawResetComponent(key)
            style.popStyleColor(not self.instanceDataChanges[key])
        end
    end
end

return entity