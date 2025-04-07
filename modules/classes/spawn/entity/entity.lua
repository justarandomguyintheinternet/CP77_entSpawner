local intersection = require("modules/utils/editor/intersection")
local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")
local red = require("modules/utils/redConverter")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local registry = require("modules/utils/nodeRefRegistry")
local Cron = require("modules/utils/Cron")
local preview = require("modules/utils/previewUtils")

---Class for base entity handling
---@class entity : spawnable
---@field public apps table
---@field public appsLoaded boolean
---@field public appIndex integer
---@field private bBoxCallback function
---@field public bBox table {min: Vector4, max: Vector4}
---@field public bBoxLoaded boolean
---@field public meshes table
---@field public instanceDataChanges table Changes to the default data, regardless of app (Matched by ID)
---@field public defaultComponentData table Default data for each component, regardless of whether it was changed. Keeps up to date with app changes
---@field public deviceClassName string
---@field public propertiesWidth table?
---@field protected assetPreviewTimer number
---@field protected assetPreviewBackplane mesh?
---@field protected instanceDataSearch string
---@field protected psControllerID string
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"
    o.icon = IconGlyphs.AlphaEBoxOutline

    o.apps = {}
    o.appsLoaded = false
    o.appIndex = 0
    o.bBoxCallback = nil
    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }
    o.bBoxLoaded = false
    o.meshes = {}

    o.instanceDataChanges = {}
    o.defaultComponentData = {}
    o.typeInfo = {}
    o.enumInfo = {}
    o.deviceClassName = ""
    o.propertiesMaxWidth = nil
    o.instanceDataSearch = ""
    o.psControllerID = ""

    o.assetPreviewType = "backdrop"
    o.assetPreviewDelay = 0.15
    o.assetPreviewTimer = 0
    o.assetPreviewBackplane = nil
    o.assetPreviewIsCharacter = false

    o.uk10 = 1056

    setmetatable(o, { __index = self })
   	return o
end

function entity:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    cache.tryGet(self.spawnData .. "_apps")
    .notFound(function (task)
        builder.registerLoadResource(self.spawnData, function (resource)
            local apps = {}

            for _, appearance in ipairs(resource.appearances) do
                table.insert(apps, appearance.name.value)
            end
            cache.addValue(self.spawnData .. "_apps", apps)
            task:taskCompleted()
        end)
    end)
    .found(function ()
        self.apps = cache.getValue(self.spawnData .. "_apps")
        self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
        self.appsLoaded = true

        if utils.indexValue(self.apps, self.app) - 1 < 0 then
            self.app = self.apps[1] or "default"
        end

        if self.spawning then
            self:spawn(true)
        end
    end)
end

function entity:spawn(ignoreSpawning)
    if not self.appsLoaded then -- Delay spawning until list of apps is loaded, so we dont spawn with random/default appearance
        self.spawning = true
    else
        spawnable.spawn(self, ignoreSpawning)
    end
end

local function CRUIDToString(id)
    return tostring(CRUIDToHash(id)):gsub("ULL", "")
end

function entity:loadInstanceData(entity, forceLoadDefault)
    -- Only generate upon change
    if not forceLoadDefault then -- Called during assemble
        self.defaultComponentData = {}
        -- Always load default data for PS controllers, as these must be serialized during attachment, to prevent values being set from PS data
        for _, component in pairs(entity:GetComponents()) do
            if component:IsA("gameDeviceComponent") and component.persistentState then
                self.defaultComponentData[CRUIDToString(component.id)] = red.redDataToJSON(component)
                self.psControllerID = CRUIDToString(component.id)
            end
        end

        if utils.tableLength(self.instanceDataChanges) == 0 then
            return
        end
    end

    for key, _ in pairs(self.defaultComponentData) do
        if key ~= self.psControllerID then
            self.defaultComponentData[key] = nil
        end
    end

    -- Gotta go through all components, even such with identicaly IDs, due to AMM props using the same ID for all components
    local components = entity:GetComponents()
    self.defaultComponentData["0"] = red.redDataToJSON(entity)

    for _, component in pairs(components) do
        local ignore = false

        if component:IsA("entMeshComponent") or component:IsA("entSkinnedMeshComponent") then
            ignore = ResRef.FromHash(component.mesh.hash):ToString():match("base\\spawner") or ResRef.FromHash(component.mesh.hash):ToString():match("base\\amm_props\\mesh\\invis_")
        end
        ignore = ignore or CRUIDToString(component.id) == "0"

        if not ignore then
            if not component.name.value:match("amm_prop_slot") and not CRUIDToString(component.id) == self.psControllerID then
                self.defaultComponentData[CRUIDToString(component.id)] = red.redDataToJSON(component)
            elseif not self.defaultComponentData[CRUIDToString(component.id)] then
                self.defaultComponentData[CRUIDToString(component.id)] = red.redDataToJSON(component)
            end

            for key, data in pairs(utils.deepcopy(self.instanceDataChanges)) do
                if key == CRUIDToString(component.id) then
                    red.JSONToRedData(data, component)
                end
            end
        end
    end
end

local function fixInstanceData(data, parent)
    for key, value in pairs(data) do
        if type(value) == "table" then
            if value["$type"] == "ResourcePath" and value["$storage"] and value["$storage"] == "uint64" then
                parent = nil
            elseif value["$type"] == "FixedPoint" and value["Bits"] then
                value["Bits"] = math.floor(value["Bits"])
            elseif value["Flags"] and not value["DepotPath"] then
                data[key] = nil
            elseif value["$type"] == "Color" then
                value.Red = math.min(value.Red, 255)
                value.Green = math.min(value.Green, 255)
                value.Blue = math.min(value.Blue, 255)
                value.Alpha = math.min(value.Alpha, 255)
            end

            if data ~= nil then
                fixInstanceData(value, data)
            end
        end
    end
end

function entity:onAssemble(entRef)
    spawnable.onAssemble(self, entRef)

    for _, component in pairs(self.instanceDataChanges) do
        fixInstanceData(component, {})
    end

    self:loadInstanceData(entRef, false)

    for _, component in pairs(entRef:GetComponents()) do
        if component:IsA("gameDeviceComponent") then
            if self.deviceClassName == "" and component.persistentState then
                self.deviceClassName = component.persistentState:GetClassName().value
            end
        end
    end

    self:assetPreviewAssemble(entRef)
end

function entity:onAttached(entRef)
    spawnable.onAttached(self, entRef)

    Cron.AfterTicks(10, function ()
        local success = pcall(function ()
            entRef:GetTemplatePath()
        end)

        if not success then return end

        builder.getEntityBBox(entRef, function (data)
            utils.log("[Entity] Loaded initial BBOX for entity " .. self.spawnData .. " with " .. #data.meshes .. " meshes.")
            self.bBox = data.bBox
            self.meshes = data.meshes

            visualizer.updateScale(entRef, self:getArrowSize(), "arrows")

            if self.bBoxCallback then
                self.bBoxCallback(entRef)
            end
            self.bBoxLoaded = true

            if self.isAssetPreview then
                self:assetPreviewSetPosition()
                self:setAssetPreviewTextPostition()
            end
        end)
    end)
end

function entity:getAssetPreviewTextAnchor()
    if not self.assetPreviewBackplane then
        return Vector4.new(1, 1, 0, 0)
    end

    local pos = preview.getTopLeft(0.275)
    return utils.addVector(self.assetPreviewBackplane.position, utils.addEulerRelative(self.assetPreviewBackplane.rotation, EulerAngles.new(0, 90, 0)):ToQuat():Transform(Vector4.new(pos, 0, pos, 0)))
end

function entity:getAssetPreviewPosition()
    if self.assetPreviewBackplane and self.assetPreviewBackplane:isSpawned() then
        local meshPosition, _ = spawnable.getAssetPreviewPosition(self, 0.25)
        self.assetPreviewBackplane.position = meshPosition
        self.assetPreviewBackplane:update()
    end

    -- Not yet ready, leave off screen
    if not self.bBoxLoaded or not self:isSpawned() then
        return self.position, Vector4.new(0, 1, 0, 0)
    end

    local size = self:getSize()
    local distance = math.max(size.x, size.y, size.z) * 1.6

    local diff = utils.subVector(self.position, self:getCenter())
    local position, forward = spawnable.getAssetPreviewPosition(self, distance)

    self.assetPreviewTimer = self.assetPreviewTimer + Cron.deltaTime
    if self.assetPreviewTimer > 1.5 then
        self.assetPreviewTimer = 0
        self.appIndex = (self.appIndex + 1) % (#self.apps + 1)
        local new = self.apps[self.appIndex] or "default"
        if new ~= self.app then
            self.app = new
            self.bBoxLoaded = false
            self:respawn()
        end
    end

    self.rotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.rotation:ToQuat(), Quaternion.SetAxisAngle(Vector4.new(0, 0, 1, 0), Deg2Rad(Cron.deltaTime * 50))):ToEulerAngles()

    if size.z < math.max(size.x, size.y, size.z) * 0.1 then
        diff = utils.addVector(diff, self.rotation:ToQuat():Transform(Vector4.new(0, 0, -0.1, 0)))
    end

    preview.elements["previewFirstLine"]:SetText("Appearance: " .. self.app)
    preview.elements["previewSecondLine"]:SetText(("Size: X=%.2fm Y=%.2fm Z=%.2fm"):format(size.x, size.y, size.z))
    position = utils.addVector(position, diff)

    return position, forward
end

function entity:assetPreviewAssemble(entRef)
    if not self.isAssetPreview then return end

    for _, component in pairs(entRef:GetComponents()) do
        if component:IsA("entMeshComponent") then
            component.renderingPlane = ERenderingPlane.RPl_Weapon
        end
        if component:IsA("entPhysicalMeshComponent") or component:IsA("entColliderComponent") then
            component.filterData = physicsFilterData.new()
        end
        if component:IsA("entISkinTargetComponent") or component:IsA("entPhysicalDestructionComponent") then
            component:Toggle(false)

            local mesh = entMeshComponent.new()
            mesh.name = component.name.value .. "_copy"
            mesh.id = component.id
            mesh.mesh = component.mesh
            mesh.meshAppearance = component.meshAppearance
            mesh.renderingPlane = ERenderingPlane.RPl_Weapon
            mesh:SetLocalTransform(component:GetLocalPosition(), component:GetLocalOrientation())
            mesh.parentTransform = component.parentTransform
            entRef:AddComponent(mesh)
        end
    end

    preview.elements["previewFirstLine"]:SetVisible(true)
    preview.elements["previewSecondLine"]:SetVisible(true)
    preview.elements["previewThirdLine"]:SetVisible(true)
    preview.elements["previewFirstLine"]:SetText("Appearance: Loading...")
    preview.elements["previewSecondLine"]:SetText("Size: Loading...")
    preview.elements["previewThirdLine"]:SetText("Experimental preview")
end

function entity:assetPreview(state)
    if self.assetPreviewType == "none" then return end

    spawnable.assetPreview(self, state)

    if state then
        self.assetPreviewBackplane = require("modules/classes/spawn/mesh/mesh"):new()
        local rot = utils.addEulerRelative(self.rotation, EulerAngles.new(0, -90, 0))

        local size = preview.getBackplaneSize(0.275)
        local meshPosition, _ = spawnable.getAssetPreviewPosition(self, 0.25)
        self.assetPreviewBackplane:loadSpawnData({ spawnData = "base\\spawner\\base_grid.w2mesh", scale = { x = size, y = size, z = size } }, meshPosition, rot)
        self.assetPreviewBackplane:spawn()
    else
        if self.assetPreviewBackplane then
            self.assetPreviewBackplane:despawn()
            self.assetPreviewBackplane = nil
        end
    end

    self.spawnedAndCachedCallback = {}
end

function entity:save()
    local data = spawnable.save(self)
    data.instanceDataChanges = utils.deepcopy(self.instanceDataChanges)

    local default = {}
    for key, _ in pairs(self.instanceDataChanges) do
        local wrongData = false
        if key == "0" and self.defaultComponentData["0"] then
            for propKey, _ in pairs(self.instanceDataChanges["0"]) do
                if not self.defaultComponentData["0"][propKey] then
                    wrongData = true
                    break
                end
            end
        end

        if not wrongData then
            default[key] = utils.deepcopy(self.defaultComponentData[key])

            if not self.defaultComponentData[key] then
                data.instanceDataChanges[key] = nil
            end
        else
            print("[entSpawner] Something went wrong with instance data for entity " .. self.object.name .. " had to reset some data...")
            data.instanceDataChanges[key] = nil
        end
    end
    data.defaultComponentData = default
    data.deviceClassName = self.deviceClassName

    return data
end

---Gets called once the entity is spawned and the BBox is cached. Gets passed the entity as param
---@param callback any
function entity:onBBoxLoaded(callback)
    self.bBoxCallback = callback
end

---@param entity entity?
---@return table
function entity:getSize()
    return { x = self.bBox.max.x - self.bBox.min.x, y = self.bBox.max.y - self.bBox.min.y, z = self.bBox.max.z - self.bBox.min.z }
end

function entity:getBBox()
    return self.bBox
end

function entity:getCenter()
    local size = self:getSize()
    local offset = Vector4.new(
        self.bBox.min.x + size.x / 2,
        self.bBox.min.y + size.y / 2,
        self.bBox.min.z + size.z / 2,
        0
    )
    offset = self.rotation:ToQuat():Transform(offset)

    return Vector4.new(
        self.position.x + offset.x,
        self.position.y + offset.y,
        self.position.z + offset.z,
        0
    )
end

function entity:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local hit = nil
    local unscaledHit = nil

    for _, mesh in pairs(self.meshes) do
        local meshPosition = utils.addVector(mesh.position, self.position)
        local meshRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.rotation:ToQuat(), mesh.rotation)

        local result = intersection.getBoxIntersection(origin, ray, meshPosition, meshRotation:ToEulerAngles(), mesh.bbox)

        if result.hit then
            if not hit or result.distance < hit.distance then
                hit = result

                unscaledHit = intersection.getBoxIntersection(origin, ray, meshPosition, meshRotation:ToEulerAngles(), intersection.unscaleBBox(mesh.path, mesh.originalScale, mesh.bbox))
            end
        end
    end

    if not hit then return { hit = false } end

    return {
        hit = hit.hit,
        position = hit.position,
        unscaledHit = unscaledHit and unscaledHit.position or hit.position,
        collisionType = "bbox",
        distance = hit.distance,
        bBox = self.bBox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = hit.normal
    }
end

function entity:draw()
    spawnable.draw(self)

    if not self.propertiesWidth then
        local app, _ = ImGui.CalcTextSize("Appearance")
        local class, _ = ImGui.CalcTextSize("Device Class Name")
        local padding = ImGui.GetCursorPosX() + 2 * ImGui.GetStyle().ItemSpacing.x

        self.propertiesWidth = {
            app = app + padding,
            class = class + padding
        }
    end

    local greyOut = #self.apps == 0 or not self:isSpawned()
    style.pushGreyedOut(greyOut)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    style.mutedText("Appearance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.deviceClassName == "" and self.propertiesWidth.app or self.propertiesWidth.class)
    local index, changed = style.trackedCombo(self.object, "##app", self.appIndex, list, 160)
    if changed and #self.apps > 0 and self:isSpawned() then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        self.defaultComponentData = {}

        if entity then
            self:respawn()
        end
    end
    style.popGreyedOut(greyOut)
    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.ContentCopy) then
        ImGui.SetClipboardText(self.app)
    end
    style.pushButtonNoBG(false)


    if self.deviceClassName ~= "" then
        style.mutedText("Device Class Name")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.propertiesWidth.class)
        ImGui.Text(self.deviceClassName)
        ImGui.SameLine()

        ImGui.PushID("##copyDeviceClassName")
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.ContentCopy) then
            ImGui.SetClipboardText(self.deviceClassName)
        end
        style.pushButtonNoBG(false)
        ImGui.PopID()
    end
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

local function copyAndPrepareData(data)
    for key, value in pairs(data) do
        if key == "HandleId" then
            data[key] = nil
        end
        if type(value) == "table" then
            copyAndPrepareData(value)
        end
    end

    return copy
end

local function assembleInstanceData(default, instanceData)
    instanceData.id = default.id
    instanceData["$type"] = default["$type"]
end

function entity:export(index, length)
    local data = spawnable.export(self)

    if utils.tableLength(self.instanceDataChanges) > 0 then
        local dict = {}

        local i = 0
        if self.instanceDataChanges["0"] then -- Make sure "0" is always first
            dict[tostring(i)] = "0"
            i = i + 1
        end

        for key, _ in pairs(self.instanceDataChanges) do
            if key ~= "0" then
                dict[tostring(i)] = key
                i = i + 1
            end
        end

        local combinedData = {}

        for key, data in pairs(self.defaultComponentData) do
            if self.instanceDataChanges[key] then
                local assembled = utils.deepcopy(self.instanceDataChanges[key])
                assembleInstanceData(data, assembled)
                table.insert(combinedData, assembled)
            end
        end

        copyAndPrepareData(combinedData)

        data.data.instanceData = {
            ["Data"] = {
                ["$type"] = "entEntityInstanceData",
                ["buffer"] = {
                    ["BufferId"] = tostring(FNV1a64("Entity" .. tostring(self.position.x * self.position.y) .. math.random(1, 10000000))):gsub("ULL", ""),
                    ["Type"] = "WolvenKit.RED4.Archive.Buffer.RedPackage, WolvenKit.RED4, Version=8.14.1.0, Culture=neutral, PublicKeyToken=null",
                    ["Data"] = {
                        ["Version"] = 4,
                        ["Sections"] = 6,
                        ["CruidIndex"] = self.instanceDataChanges["0"] and 0 or -1,
                        ["CruidDict"] = dict,
                        ["Chunks"] = combinedData
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

                local typeName = type(value[key]) == "table" and value[key]["$type"] or nil
                local isEnum = false

                if not typeName then -- Is simple type
                    local parentParent = utils.deepcopy(parentPath) -- Grab parent of array, to get type of array
                    table.remove(parentParent, #parentParent)

                    local fullPath = table.concat(path, "/")
                    if not self.typeInfo[fullPath] then
                        local parentData = utils.getNestedValue(self.instanceDataChanges[componentID] or self.defaultComponentData[componentID], parentParent)

                        local parentType = parentData["$type"]
                        local propType = Reflection.GetClass(parentType):GetProperty(parentPath[#parentPath]):GetType():GetInnerType()
                        isEnum = propType:IsEnum()
                        typeName = propType:GetName().value

                        self.typeInfo[fullPath] = { typeName = typeName, isEnum = isEnum, propType = nil }
                    else
                        return self.typeInfo[fullPath]
                    end
                end

                return { typeName = typeName, isEnum = isEnum, propType = nil}
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
    key = tostring(key)

    ImGui.Text(key)
    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(key) + max)
    ImGui.SetNextItemWidth(width * style.viewSize)
    local value, _ = ImGui.InputText("##" .. componentID .. table.concat(path), data, 250)
    style.tooltip(type)
    self:drawResetProp(componentID, path)
    if ImGui.IsItemDeactivatedAfterEdit() then
        history.addAction(history.getElementChange(self.object))
        self:updatePropValue(componentID, path, value)
    end
end

function entity:drawNumericProp(componentID, key, data, path, type, isFloat, hasText, format)
    key = tostring(key)

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

---@param componentID number
---@param path table
---@param typeName table?
function entity:drawResetProp(componentID, path, typeName)
    local modified = self.instanceDataChanges[componentID] ~= nil and utils.getNestedValue(self.instanceDataChanges[componentID], path) ~= nil

    if ImGui.BeginPopupContextItem("##resetComponentProperty" .. componentID .. table.concat(path), ImGuiPopupFlags.MouseButtonRight) then
        if typeName and typeName == "handle:AreaShapeOutline" then
            -- Do this here, before we trim the path
            local outline = utils.getClipboardValue("outline")
            if ImGui.MenuItem("Paste outline" .. (outline and " [" .. #outline.points .. "]" or " [Empty]")) and outline then
                history.addAction(history.getElementChange(self.object))
                self:updatePropValue(componentID, path, {
                    ["$type"] = "AreaShapeOutline",
                    ["height"] = outline.height,
                    ["points"] = outline.points
                })
            end
        end

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
                if base:GetName().value == "Bool" then
                    if ImGui.MenuItem("Bool") then
                        local newPath = utils.deepcopy(path)
                        table.insert(newPath, #data + 1)

                        self:updatePropValue(componentID, newPath, 1)
                    end
                elseif base:GetName().value == "TweakDBID" then
                    if ImGui.MenuItem("TweakDBID (String)") then
                        local newPath = utils.deepcopy(path)
                        table.insert(newPath, #data + 1)

                        self:updatePropValue(componentID, newPath, {
                            ["$type"] = "TweakDBID",
                            ["$storage"] = "string",
                            ["$value"] = ""
                        })
                    end
                else
                    ImGui.Text(string.format("%s not yet supported", base:GetName().value))
                end
            else
                for _, class in pairs(utils.getDerivedClasses(base:GetName().value)) do
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
        local value = ImGui.InputFloat("##" .. componentID .. table.concat(path), data["Bits"] / 131072, 0, 0, "%.2f")
        if ImGui.IsItemDeactivatedAfterEdit() then
            history.addAction(history.getElementChange(self.object))
            self:updatePropValue(componentID, path, math.floor(value * 131072))
        end
        self:drawResetProp(componentID, path)
        style.popStyleColor(modified)
        return
    elseif info.typeName == "TweakDBID" or info.typeName == "CName" then
        table.insert(path, "$value")

        ImGui.Text(tostring(key))
        ImGui.SameLine()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(tostring(key)) + max)
        ImGui.SetNextItemWidth(250 * style.viewSize)
        local value, _ = ImGui.InputText("##" .. componentID .. table.concat(path), data["$value"], 250)
        style.tooltip(info.typeName)
        self:drawResetProp(componentID, path)
        if ImGui.IsItemDeactivatedAfterEdit() then
            data["$storage"] = "string"
            history.addAction(history.getElementChange(self.object))
            self:updatePropValue(componentID, path, value)
        end

        style.popStyleColor(modified)
        return
    elseif info.typeName == "NodeRef" then
        table.insert(path, "$value")

        ImGui.Text(tostring(key))
        ImGui.SameLine()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(key) + max)

        local value, finished = registry.drawNodeRefSelector(style.getMaxWidth(250), data["$value"], self.object, false)
        style.tooltip(info.typeName .. " (String will get converted to hash)")
        self:drawResetProp(componentID, path)
        if finished then
            if string.find(value, "%D") then
                value, _ = value:gsub("#", "")
                value, _ = tostring(FNV1a64(value)):gsub("ULL", "")
            end

            history.addAction(history.getElementChange(self.object))
            self:updatePropValue(componentID, path, value)
        end

        style.popStyleColor(modified)
        return
    elseif info.typeName == "LocalizationString" then
        table.insert(path, "value")
        self:drawStringProp(componentID, key, data["value"], path, info.typeName, 150, max)
        style.popStyleColor(modified)
        return
    end

    local name = info.typeName .. " | " .. key

    local open = false
    if ImGui.TreeNodeEx(name, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawResetProp(componentID, path, info.typeName)
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
        self:drawResetProp(componentID, path, info.typeName)
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

        ImGui.Text(tostring(key))
        ImGui.SameLine()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() - ImGui.CalcTextSize(tostring(key)) + max)

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
        elseif info.typeName == "uint64" or info.typeName == "Uint64" or info.typeName == "CRUID" or info.typeName == "String" then
            ImGui.SetNextItemWidth(100 * style.viewSize)

            local value, changed = ImGui.InputText("##" .. componentID .. table.concat(path), data, 250)
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
    local nDefaultData = utils.tableLength(self.defaultComponentData)
    if nDefaultData <= 1 then
        local entity = self:getEntity()

        if entity then
            if nDefaultData == 0 or (nDefaultData == 1 and self.defaultComponentData[self.psControllerID] ~= nil) then -- Load default data if either not loaded, or only for the PS controller
                self:loadInstanceData(entity, true)
            end
        else
            ImGui.Text("Entity not spawned")
            return
        end
    end

    ImGui.PushItemWidth(200 * style.viewSize)
    self.instanceDataSearch = ImGui.InputTextWithHint('##searchComponent', 'Search for component...', self.instanceDataSearch, 100)
    ImGui.PopItemWidth()

    if self.instanceDataSearch ~= "" then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            self.instanceDataSearch = ""
        end
        style.pushButtonNoBG(false)
    end

    for key, component in pairs(self.defaultComponentData) do
        local name = component["$type"]
        local componentName = (component.name and component.name["$value"] or "Entity")
        name = name .. " | " .. componentName

        if self.instanceDataSearch == "" or (componentName:lower():match(self.instanceDataSearch:lower()) or name:lower():match(self.instanceDataSearch:lower())) ~= nil then
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
end

return entity