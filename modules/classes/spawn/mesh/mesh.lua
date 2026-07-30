local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local cache = require("modules/utils/cache")
local visualizer = require("modules/utils/visualizer")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")
local Cron = require("modules/utils/Cron")
local preview = require("modules/utils/previewUtils")
local settings = require("modules/utils/settings")

local colliderShapes = { "Box", "Capsule", "Sphere" }

local conversionTargets = {
    { modulePath = "mesh/mesh", label = IconGlyphs.CubeOutline .. " Static Mesh", plural = "static meshes" },
    { modulePath = "mesh/rotatingMesh", label = IconGlyphs.FormatRotate90 .. " Rotating Mesh", plural = "rotating meshes" },
    { modulePath = "mesh/clothMesh", label = IconGlyphs.ReceiptOutline .. " Cloth Mesh", plural = "cloth meshes" },
    { modulePath = "physics/dynamicMesh", label = IconGlyphs.CubeSend .. " Dynamic Mesh", plural = "dynamic meshes" }
}
local lossyConversionPairs = {
    ["mesh/rotatingMesh>mesh/mesh"] = true,
    ["mesh/rotatingMesh>mesh/clothMesh"] = true,
    ["mesh/rotatingMesh>physics/dynamicMesh"] = true,
    ["mesh/clothMesh>mesh/mesh"] = true,
    ["mesh/clothMesh>mesh/rotatingMesh"] = true,
    ["mesh/clothMesh>physics/dynamicMesh"] = true,
    ["physics/dynamicMesh>mesh/mesh"] = true,
    ["physics/dynamicMesh>mesh/rotatingMesh"] = true,
    ["physics/dynamicMesh>mesh/clothMesh"] = true
}

---Class for worldMeshNode
---@class mesh : spawnable
---@field public apps table
---@field public appIndex integer
---@field public scale {x: number, y: number, z: number}
---@field protected occluderType integer
---@field protected occluderTypes table
---@field protected hasOccluder boolean|table
---@field protected windImpulseEnabled boolean
---@field protected forceAutoHideDistance number
---@field protected castLocalShadows integer
---@field protected castRayTracedGlobalShadows integer
---@field protected castRayTracedLocalShadows integer
---@field protected castShadows integer
---@field protected shadowCastingModeEnum table
---@field protected shadowHeaderState boolean
---@field protected maxShadowPropertiesWidth number?
---@field public bBox table {min: Vector4, max: Vector4}
---@field public colliderShape integer
---@field public hideGenerate boolean
---@field private bBoxLoaded boolean
---@field private assetStartTime number
---@field protected maxPropertyWidth number?
local mesh = setmetatable({}, { __index = spawnable })

function mesh:new()
	local o = spawnable.new(self)

    o.spawnListType = "list"
    o.dataType = "Static Mesh"
    o.spawnDataPath = "data/spawnables/mesh/all/"
    o.modulePath = "mesh/mesh"
    o.node = "worldMeshNode"
    o.description = "Places a static mesh, from a given .mesh file. This will not have any collision, but has an option to generate a fitting collider"
    o.icon = IconGlyphs.CubeOutline

    o.apps = {}
    o.appIndex = 0
    o.scale = { x = 1, y = 1, z = 1 }

    o.occluderType = 0
    o.occluderTypes = utils.enumTable("visWorldOccluderType")
    o.hasOccluder = false
    o.windImpulseEnabled = true
    o.forceAutoHideDistance = 0

    o.castLocalShadows = 0
    o.castRayTracedGlobalShadows = 0
    o.castRayTracedLocalShadows = 0
    o.castShadows = 0
    o.shadowCastingModeEnum = utils.enumTable("shadowsShadowCastingMode")
    o.shadowHeaderState = false
    o.maxShadowPropertiesWidth = nil

    o.bBox = { min = Vector4.new(-0.5, -0.5, -0.5, 0), max = Vector4.new( 0.5, 0.5, 0.5, 0) }
    o.bBoxLoaded = false

    o.colliderShape = 0
    o.hideGenerate = false
    o.maxPropertyWidth = nil
    o.convertTarget = 0

    o.assetPreviewType = "backdrop"
    o.assetPreviewDelay = 0.1
    o.assetStartTime = 0

    o.uk10 = 1040

    setmetatable(o, { __index = self })
   	return o
end

function mesh:loadSpawnData(data, position, rotation)
    spawnable.loadSpawnData(self, data, position, rotation)

    cache.tryGet(self.spawnData .. "_apps", self.spawnData .. "_bBox_max", self.spawnData .. "_bBox_min", self.spawnData .. "_occluder")
    .notFound(function (task)
        self.bBox.max = Vector4.new(0.5, 0.5, 0.5, 0) -- Temp values, so that onAssemble//updateScale can work
        self.bBox.min = Vector4.new(-0.5, -0.5, -0.5, 0)
        self.apps = {}

        builder.registerLoadResource(self.spawnData, function (resource)
            for _, appearance in ipairs(resource.appearances) do
                table.insert(self.apps, appearance.name.value)
            end

            self.bBox.min = resource.boundingBox.Min
            self.bBox.max = resource.boundingBox.Max
            visualizer.updateScale(entity, self:getArrowSize(), "arrows")

            local occluder = false
            for _, param in pairs(resource.parameters) do
                if param:IsA("meshMeshParamOccluderData") then
                    occluder = true
                    break
                end
            end

            -- Save to cache
            cache.addValue(self.spawnData .. "_apps", self.apps)
            cache.addValue(self.spawnData .. "_bBox_max", utils.fromVector(self.bBox.max))
            cache.addValue(self.spawnData .. "_bBox_min", utils.fromVector(self.bBox.min))
            cache.addValue(self.spawnData .. "_occluder", occluder)

            task:taskCompleted()

            if self:isSpawned() and self.isAssetPreview then
                self:assetPreviewSetPosition()
            end
        end)
    end)
    .found(function ()
        self.apps = cache.getValue(self.spawnData .. "_apps")
        self.bBox.max = cache.getValue(self.spawnData .. "_bBox_max")
        self.bBox.min = cache.getValue(self.spawnData .. "_bBox_min")
        self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)
        self.hasOccluder = cache.getValue(self.spawnData .. "_occluder")
        self.bBoxLoaded = true
    end)
end

function mesh:onAssemble(entity)
    spawnable.onAssemble(self, entity)
    local component = entMeshComponent.new()
    component.name = "mesh"
    component.mesh = ResRef.FromString(self.spawnData)
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.meshAppearance = self.app
    component.castLocalShadows = Enum.new("shadowsShadowCastingMode", self.castLocalShadows)
    component.castRayTracedGlobalShadows = Enum.new("shadowsShadowCastingMode", self.castRayTracedGlobalShadows)
    component.castRayTracedLocalShadows = Enum.new("shadowsShadowCastingMode", self.castRayTracedLocalShadows)
    component.castShadows = Enum.new("shadowsShadowCastingMode", self.castShadows)

    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")

    self:assetPreviewAssemble(entity)
end

function mesh:getAssetPreviewTextAnchor()
    local pos = preview.getTopLeft(0.8)
    return utils.addVector(self.position, self.rotation:ToQuat():Transform(Vector4.new(pos, 0, pos, 0)))
end

function mesh:getAssetPreviewPosition()
    -- Scale mesh to fit
    local mesh = self:getEntity():FindComponentByName("mesh")
    local extents = { self.bBox.max.x - self.bBox.min.x, self.bBox.max.y - self.bBox.min.y, self.bBox.max.z - self.bBox.min.z }
    local factor = 0.275 / math.max(table.unpack(extents))

    self.scale = { x = factor, y = factor, z = factor }
    mesh.visualScale = Vector3.new(factor, factor, factor)

    -- Calculate rotation and cycle app
    local rotation = (((Cron.time - self.assetStartTime) % 4) / 4) * 360
    local app = math.floor((((Cron.time - self.assetStartTime) % (#self.apps)) / (#self.apps)) * #self.apps)
    if app ~= self.appIndex then
        self.appIndex = app
        self.app = self.apps[self.appIndex + 1] or "default"
        mesh.meshAppearance = CName.new(self.app)
        mesh:LoadAppearance()
    end

    mesh:SetLocalOrientation(EulerAngles.new(0, 7.5, rotation):ToQuat())

    -- Adjust for offcenter bbox, and adjust for rotation
    local diff = utils.subVector(self.position, self:getCenter())
    diff = self.rotation:ToQuat():TransformInverse(diff)
    diff = Vector4.RotateAxis(diff, Vector4.new(0, 0, 1, 0), Deg2Rad(rotation))

    -- Adjust for x offset in editor mode
    local position, forward = spawnable.getAssetPreviewPosition(self, 0.75)
    diff = utils.addVector(diff, utils.multVector(forward, 0.275))

    if extents[3] < math.max(table.unpack(extents)) * 0.1 then
        diff.z = diff.z - 0.075
    end

    mesh:SetLocalPosition(diff)

    preview.elements["previewFirstLine"]:SetText("Appearance: " .. self.app)
    preview.elements["previewSecondLine"]:SetText(("Size: X=%.2fm Y=%.2fm Z=%.2fm"):format(extents[1], extents[2], extents[3]))

    return position
end

function mesh:assetPreviewAssemble(entity)
    if not self.isAssetPreview then return end

    local size = preview.getBackplaneSize(0.8)
    local component = entMeshComponent.new()
    component.name = "backdrop"
    component.mesh = ResRef.FromString("base\\spawner\\base_grid.w2mesh")
    component.visualScale = Vector3.new(size, size, size)
    component.renderingPlane = ERenderingPlane.RPl_Weapon
    component:SetLocalOrientation(EulerAngles.new(0, 90, 180):ToQuat())
    entity:AddComponent(component)
    preview.addLight(entity, 7.55, 0.75, 1)

    local lightBlocker = entMeshComponent.new()
    lightBlocker.name = "lightBlocker"
    lightBlocker.mesh = ResRef.FromString("engine\\meshes\\editor\\sphere.w2mesh")
    lightBlocker.visualScale = Vector3.new(1.65, 1.65, 1.65)
    lightBlocker:SetLocalPosition(Vector4.new(0, 0.75, 0, 0))
    entity:AddComponent(lightBlocker)

    preview.addLight(entity, 7.55, 0.75, 1)

    local mesh = entity:FindComponentByName("mesh")
    mesh.renderingPlane = ERenderingPlane.RPl_Weapon

    preview.elements["previewFirstLine"]:SetVisible(true)
    preview.elements["previewSecondLine"]:SetVisible(true)
    self.assetStartTime = Cron.time
end

function mesh:spawn()
    local mesh = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = mesh
end

function mesh:save()
    local data = spawnable.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.castLocalShadows = self.castLocalShadows
    data.castRayTracedGlobalShadows = self.castRayTracedGlobalShadows
    data.castRayTracedLocalShadows = self.castRayTracedLocalShadows
    data.castShadows = self.castShadows
    data.occluderType = self.occluderType
    data.windImpulseEnabled = self.windImpulseEnabled
    data.forceAutoHideDistance = self.forceAutoHideDistance

    return data
end

---@protected
function mesh:updateScale()
    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("mesh")
    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)

    component:Toggle(false)
    component:Toggle(true)

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    self:setOutline(self.outline)
end

---@protected
function mesh:updateShadowSettings(changed)
    if not changed then return end

    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("mesh")
    component.castLocalShadows = Enum.new("shadowsShadowCastingMode", self.castLocalShadows)
    component.castRayTracedGlobalShadows = Enum.new("shadowsShadowCastingMode", self.castRayTracedGlobalShadows)
    component.castRayTracedLocalShadows = Enum.new("shadowsShadowCastingMode", self.castRayTracedLocalShadows)
    component.castShadows = Enum.new("shadowsShadowCastingMode", self.castShadows)

    component:Toggle(false)
    component:Toggle(true)
end

function mesh:getSize()
    return { x = (self.bBox.max.x - self.bBox.min.x) * math.abs(self.scale.x), y = (self.bBox.max.y - self.bBox.min.y) * math.abs(self.scale.y), z = (self.bBox.max.z - self.bBox.min.z) * math.abs(self.scale.z) }
end

function mesh:getBBox()
    return {
        min = { x = self.bBox.min.x * math.abs(self.scale.x), y = self.bBox.min.y * math.abs(self.scale.y), z = self.bBox.min.z * math.abs(self.scale.z) },
        max = { x = self.bBox.max.x * math.abs(self.scale.x), y = self.bBox.max.y * math.abs(self.scale.y), z = self.bBox.max.z * math.abs(self.scale.z) }
    }
end

function mesh:getCenter()
    local size = self:getSize()
    local offset = Vector4.new(
        (self.bBox.min.x * self.scale.x) + size.x / 2,
        (self.bBox.min.y * self.scale.y) + size.y / 2,
        (self.bBox.min.z * self.scale.z) + size.z / 2,
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

function mesh:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local scaleFactor = intersection.getResourcePathScalingFactor(self.spawnData, self:getSize())

    local scaledBBox = {
        min = {  x = self.bBox.min.x * math.abs(self.scale.x) * scaleFactor.x, y = self.bBox.min.y * math.abs(self.scale.y) * scaleFactor.y, z = self.bBox.min.z * math.abs(self.scale.z) * scaleFactor.z },
        max = {  x = self.bBox.max.x * math.abs(self.scale.x) * scaleFactor.x, y = self.bBox.max.y * math.abs(self.scale.y) * scaleFactor.y, z = self.bBox.max.z * math.abs(self.scale.z) * scaleFactor.z }
    }
    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)

    local unscaledHit
    if result.hit then
        unscaledHit = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, intersection.unscaleBBox(self.spawnData, self:getSize(), scaledBBox))
    end

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = unscaledHit and unscaledHit.position or result.position,
        collisionType = "bbox",
        distance = result.distance,
        bBox = scaledBBox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

function mesh:draw()
    spawnable.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Appearance", "Collider", "Occluder", "Enable Wind Impulse", "Force Auto-Hide Distance" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.pushGreyedOut(#self.apps == 0)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    style.mutedText("Appearance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local index, changed = style.trackedCombo(self.object, "##app", self.appIndex, list, 160)
    style.tooltip("Select the mesh appearance")
    if changed and #self.apps > 0 then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1] or "default"

        local entity = self:getEntity()

        if entity then
            entity:FindComponentByName("mesh").meshAppearance = CName.new(self.app)
            entity:FindComponentByName("mesh"):LoadAppearance()

            self:setOutline(self.outline)
        end
    end
    style.popGreyedOut(#self.apps == 0)

    if not self.hideGenerate then
        style.mutedText("Collider")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        ImGui.SetNextItemWidth(110 * style.viewSize)
        self.colliderShape, changed = ImGui.Combo("##colliderShape", self.colliderShape, colliderShapes, #colliderShapes)

        ImGui.SameLine()

        if ImGui.Button("Generate") then
            self:generateCollider()
        end
    end

    if self.hasOccluder then
        style.mutedText("Occluder")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.occluderType, _ = style.trackedCombo(self.object, "##occluderType", self.occluderType, self.occluderTypes, 110)
    end

    style.mutedText("Enable Wind Impulse")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.windImpulseEnabled, _ = style.trackedCheckbox(self.object, "##windImpulseEnabled", self.windImpulseEnabled)
    style.tooltip("Enable wind impulse for this mesh, not previewed.")

    style.mutedText("Force Auto-Hide Distance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.forceAutoHideDistance = style.trackedDragFloat(self.object, "##forceAutoHideDistance", self.forceAutoHideDistance, 1, 0, 99999, "%.1f", 110)
    style.tooltip("Overrides the mesh node's auto-hide distance. 0 keeps the engine default; very large values can increase rendering cost.")

    self.shadowHeaderState = ImGui.TreeNodeEx("Shadow Settings")

    if self.shadowHeaderState then
        if not self.maxShadowPropertiesWidth then
            self.maxShadowPropertiesWidth = utils.getTextMaxWidth({ "Cast Local Shadows", "Cast RT Global Shadows", "Cast RT Local Shadows", "Cast Shadows" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Cast Local Shadows")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.castLocalShadows, changed = style.trackedCombo(self.object, "##castLocalShadows", self.castLocalShadows, self.shadowCastingModeEnum)
        self:updateShadowSettings(changed)

        style.mutedText("Cast RT Global Shadows")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.castRayTracedGlobalShadows, changed = style.trackedCombo(self.object, "##castRayTracedGlobalShadows", self.castRayTracedGlobalShadows, self.shadowCastingModeEnum)
        self:updateShadowSettings(changed)

        style.mutedText("Cast RT Local Shadows")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.castRayTracedLocalShadows, changed = style.trackedCombo(self.object, "##castRayTracedLocalShadows", self.castRayTracedLocalShadows, self.shadowCastingModeEnum)
        self:updateShadowSettings(changed)

        style.mutedText("Cast Shadows")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.castShadows, changed = style.trackedCombo(self.object, "##castShadows", self.castShadows, self.shadowCastingModeEnum)
        self:updateShadowSettings(changed)

        ImGui.TreePop()
    end
    
    if self.node == "worldMeshNode" then
        self:drawConversionSelector("##meshConverterType", "Lossy Conversion##meshSingle")
    end
end

function mesh:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
end

---@param targetModulePath string
---@return boolean
function mesh:isMeshConversionAllowed(targetModulePath)
    if targetModulePath == self.modulePath then
        return false
    end

    if targetModulePath == "mesh/clothMesh" then
        return cache.isSpawnDataInSet(self.spawnData, "cloth")
    end

    if targetModulePath == "physics/dynamicMesh" then
        return cache.isSpawnDataInSet(self.spawnData, "dynamic")
    end

    return true
end

---@return table, table
function mesh:getConversionTargets()
    local options = {}
    local actions = {}

    for _, target in ipairs(conversionTargets) do
        if self:isMeshConversionAllowed(target.modulePath) then
            table.insert(options, target.label)
            table.insert(actions, target.modulePath)
        end
    end

    return options, actions
end

---@param targetModulePath string
---@return boolean
function mesh:isLossyConversion(targetModulePath)
    return lossyConversionPairs[self.modulePath .. ">" .. targetModulePath] == true
end

---@param fromModulePath string
---@param targetModulePath string
---@return boolean
function mesh:isLossyConversionFrom(fromModulePath, targetModulePath)
    return lossyConversionPairs[fromModulePath .. ">" .. targetModulePath] == true
end

---@param targetModulePath string
---@param skipHistory boolean?
function mesh:convertToModule(targetModulePath, skipHistory)
    if not targetModulePath then return end

    if not skipHistory then
        history.addAction(history.getElementChange(self.object))
    end
    self.convertTarget = 0
    self:convertSpawnableTo(targetModulePath)
end

---@param comboId string?
---@param popupId string?
function mesh:drawConversionSelector(comboId, popupId)
    local options, actions = self:getConversionTargets()
    if #options == 0 then return end

    comboId = comboId or "##meshConverterType"
    popupId = popupId or "Lossy Conversion##meshConversion"

    style.mutedText("Convert to")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.convertTarget = math.max(0, math.min(self.convertTarget, #options - 1))
    self.convertTarget, _ = style.trackedCombo(self.object, comboId, self.convertTarget, options, 150)
    style.tooltip("Select the mesh type to convert into")

    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth + 150 * style.viewSize + ImGui.GetStyle().ItemSpacing.x)
    style.pushButtonNoBG(false)
    if ImGui.Button("Convert") then
        local target = actions[self.convertTarget + 1]
        if target and self:isLossyConversion(target) and not settings.skipLossyConversionWarning then
            ImGui.OpenPopup(popupId)
        else
            self:convertToModule(target)
        end
    end

    if ImGui.BeginPopupModal(popupId, true, ImGuiWindowFlags.AlwaysAutoResize) then
        style.mutedText("Warning")
        ImGui.Text("This conversion is lossy.")
        ImGui.Text("Type-specific properties will be removed.")
        ImGui.Text("Do you want to continue?")
        ImGui.Dummy(0, 8 * style.viewSize)
        local skipWarning, changed = ImGui.Checkbox("Do not ask again", settings.skipLossyConversionWarning)
        if changed then
            settings.skipLossyConversionWarning = skipWarning
            settings.save()
        end
        ImGui.Dummy(0, 8 * style.viewSize)

        if ImGui.Button("Convert") then
            local target = actions[self.convertTarget + 1]
            self:convertToModule(target)
            ImGui.CloseCurrentPopup()
        end

        ImGui.SameLine()
        if ImGui.Button("Cancel") then
            ImGui.CloseCurrentPopup()
        end

        ImGui.EndPopup()
    end
end

function mesh:convertToStaticMesh()
    self:convertToModule("mesh/mesh")
end

function mesh:convertToClothMesh()
    self:convertToModule("mesh/clothMesh")
end

function mesh:convertToDynamicMesh()
    self:convertToModule("physics/dynamicMesh")
end

function mesh:convertToRotatingMesh()
    self:convertToModule("mesh/rotatingMesh")
end

function mesh:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["meshVisibility"] = {
        name = "Mesh Visibility",
        id = "meshVisibility",
        data = {
            forceAutoHideDistance = 0,
            maxPropertyWidth = nil
        },
        draw = function(element, entries)
            local visibilityData = element.groupOperationData["meshVisibility"]
            if not visibilityData.maxPropertyWidth then
                visibilityData.maxPropertyWidth = utils.getTextMaxWidth({ "Force Auto-Hide Distance" }) + ImGui.GetStyle().ItemSpacing.x * 2 + ImGui.GetCursorPosX()
            end

            style.mutedText("Force Auto-Hide Distance")
            ImGui.SameLine()
            ImGui.SetCursorPosX(visibilityData.maxPropertyWidth)
            ImGui.SetNextItemWidth(110 * style.viewSize)
            visibilityData.forceAutoHideDistance, _ = ImGui.DragFloat("##groupForceAutoHideDistance", visibilityData.forceAutoHideDistance, 1, 0, 99999, "%.1f")
            style.tooltip("0 keeps the engine default; very large values can increase rendering cost.")
            ImGui.SameLine()
            if ImGui.Button("Apply##groupForceAutoHideDistance") then
                history.addAction(history.getMultiSelectChange(entries))

                local nApplied = 0
                for _, entry in ipairs(entries) do
                    if entry.spawnable and entry.spawnable.forceAutoHideDistance ~= nil then
                        entry.spawnable.forceAutoHideDistance = visibilityData.forceAutoHideDistance
                        nApplied = nApplied + 1
                    end
                end

                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Set force auto-hide distance for %s mesh nodes", nApplied)))
            end
        end,
        entries = { self.object }
    }

    properties["meshConverter"] = {
        name = "Mesh Conversion",
        id = "meshConverter",
        data = {
            fromIndex = 0,
            toIndex = 0,
            pendingFromModulePath = nil,
            pendingTargetModulePath = nil
        },
        draw = function(element, entries)
            local converterData = element.groupOperationData["meshConverter"]
            local availableFromTypes = {}
            local availableFromCounts = {}
            local targetDefsByPath = {}
            for _, target in ipairs(conversionTargets) do
                targetDefsByPath[target.modulePath] = target
            end

            for _, target in ipairs(conversionTargets) do
                availableFromCounts[target.modulePath] = 0
            end

            for _, entry in ipairs(entries) do
                local spawnableEntry = entry.spawnable
                if spawnableEntry and availableFromCounts[spawnableEntry.modulePath] ~= nil then
                    availableFromCounts[spawnableEntry.modulePath] = availableFromCounts[spawnableEntry.modulePath] + 1
                end
            end

            for _, target in ipairs(conversionTargets) do
                if availableFromCounts[target.modulePath] and availableFromCounts[target.modulePath] > 0 then
                    table.insert(availableFromTypes, target.modulePath)
                end
            end

            if #availableFromTypes == 0 then return end

            converterData.fromIndex = math.max(0, math.min(converterData.fromIndex, #availableFromTypes - 1))
            local fromOptions = {}
            for _, modulePath in ipairs(availableFromTypes) do
                table.insert(fromOptions, targetDefsByPath[modulePath].label)
            end

            local lineStartX = ImGui.GetCursorPosX()
            local relationLabelX = lineStartX + ImGui.CalcTextSize("Convert") + 4
            local allLabelWidth = ImGui.CalcTextSize("all")
            local toLabelWidth = ImGui.CalcTextSize("to")
            local relationWidth = math.max(allLabelWidth, toLabelWidth) + ImGui.GetStyle().ItemSpacing.x
            local selectorX = relationLabelX + relationWidth
            local selectorWidth = 165 * style.viewSize

            style.mutedText("Convert")
            ImGui.SameLine()
            ImGui.SetCursorPosX(relationLabelX)
            style.mutedText("all")
            ImGui.SameLine()
            ImGui.SetCursorPosX(selectorX)
            ImGui.SetNextItemWidth(selectorWidth)
            local fromIndex, fromChanged = ImGui.Combo("##groupMeshConvertFrom", converterData.fromIndex, fromOptions, #fromOptions)
            if fromChanged then
                converterData.fromIndex = fromIndex
                converterData.toIndex = 0
            end

            local fromModulePath = availableFromTypes[converterData.fromIndex + 1]
            local toOptions = {}
            local toModulePaths = {}

            for _, target in ipairs(conversionTargets) do
                if target.modulePath ~= fromModulePath then
                    local hasConvertibleEntry = false
                    for _, entry in ipairs(entries) do
                        local spawnableEntry = entry.spawnable
                        if spawnableEntry and spawnableEntry.modulePath == fromModulePath and spawnableEntry:isMeshConversionAllowed(target.modulePath) then
                            hasConvertibleEntry = true
                            break
                        end
                    end

                    if hasConvertibleEntry then
                        table.insert(toOptions, target.label)
                        table.insert(toModulePaths, target.modulePath)
                    end
                end
            end

            if #toOptions == 0 then
                return
            end

            ImGui.SetCursorPosX(relationLabelX)
            style.mutedText("to")
            ImGui.SameLine()
            ImGui.SetCursorPosX(selectorX)
            ImGui.SetNextItemWidth(selectorWidth)
            converterData.toIndex = math.max(0, math.min(converterData.toIndex, #toOptions - 1))
            converterData.toIndex, _ = ImGui.Combo("##groupMeshConvertTo", converterData.toIndex, toOptions, #toOptions)
            local targetModulePath = toModulePaths[converterData.toIndex + 1]

            local function applyGroupConversion(sourceModulePath, targetPath)
                history.addAction(history.getMultiSelectChange(entries))

                local nApplied = 0
                for _, entry in ipairs(entries) do
                    local spawnableEntry = entry.spawnable
                    if spawnableEntry and spawnableEntry.modulePath == sourceModulePath and spawnableEntry:isMeshConversionAllowed(targetPath) then
                        spawnableEntry:convertToModule(targetPath, true)
                        nApplied = nApplied + 1
                    end
                end

                local sourcePlural = targetDefsByPath[sourceModulePath] and targetDefsByPath[sourceModulePath].plural or "mesh entries"
                local targetPlural = targetDefsByPath[targetPath] and targetDefsByPath[targetPath].plural or "mesh entries"
                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Converted %s %s to %s", nApplied, sourcePlural, targetPlural)))
            end

            ImGui.SameLine()
            if ImGui.Button("Convert") then
                if self:isLossyConversionFrom(fromModulePath, targetModulePath) and not settings.skipLossyConversionWarning then
                    converterData.pendingFromModulePath = fromModulePath
                    converterData.pendingTargetModulePath = targetModulePath
                    ImGui.OpenPopup("Lossy Conversion##groupMeshConverter")
                else
                    applyGroupConversion(fromModulePath, targetModulePath)
                end
            end
            style.tooltip("Convert selected mesh subtype entries to the selected target type")

            if ImGui.BeginPopupModal("Lossy Conversion##groupMeshConverter", true, ImGuiWindowFlags.AlwaysAutoResize) then
                local pendingFromModulePath = converterData.pendingFromModulePath
                local pendingTargetModulePath = converterData.pendingTargetModulePath
                local nPending = 0

                if pendingFromModulePath and pendingTargetModulePath then
                    for _, entry in ipairs(entries) do
                        local spawnableEntry = entry.spawnable
                        if spawnableEntry and spawnableEntry.modulePath == pendingFromModulePath and spawnableEntry:isMeshConversionAllowed(pendingTargetModulePath) then
                            nPending = nPending + 1
                        end
                    end
                end

                style.mutedText("Warning")
                ImGui.Text("This conversion is lossy.")
                ImGui.Text("Type-specific properties will be removed.")
                ImGui.Text(string.format("Affected entries: %d", nPending))
                ImGui.Text("Do you want to continue?")
                ImGui.Dummy(0, 8 * style.viewSize)
                local skipWarning, changed = ImGui.Checkbox("Do not ask again", settings.skipLossyConversionWarning)
                if changed then
                    settings.skipLossyConversionWarning = skipWarning
                    settings.save()
                end
                ImGui.Dummy(0, 8 * style.viewSize)

                if ImGui.Button("Convert") then
                    if pendingFromModulePath and pendingTargetModulePath then
                        applyGroupConversion(pendingFromModulePath, pendingTargetModulePath)
                    end
                    converterData.pendingFromModulePath = nil
                    converterData.pendingTargetModulePath = nil
                    ImGui.CloseCurrentPopup()
                end

                ImGui.SameLine()
                if ImGui.Button("Cancel") then
                    converterData.pendingFromModulePath = nil
                    converterData.pendingTargetModulePath = nil
                    ImGui.CloseCurrentPopup()
                end

                ImGui.EndPopup()
            end
        end,
        entries = { self.object }
    }

    if self.hideGenerate then return properties end

    properties["mesh"] = {
		name = "Static Mesh",
        id = "mesh",
		data = {
            shape = 0
        },
		draw = function(element, entries)
            style.mutedText("Collider Shape")
            ImGui.SameLine()
            ImGui.SetNextItemWidth(110 * style.viewSize)
            element.groupOperationData["mesh"].shape, _ = ImGui.Combo("##colliderShape", element.groupOperationData["mesh"].shape, colliderShapes, #colliderShapes)

            ImGui.SameLine()

            if ImGui.Button("Generate") then
                history.addAction(history.getMultiSelectChange(entries))
                local nApplied = 0

                for _, entry in ipairs(entries) do
                    if entry.spawnable.node == self.node then
                        entry.spawnable.colliderShape = element.groupOperationData["mesh"].shape
                        entry.spawnable:generateCollider()
                        nApplied = nApplied + 1
                    end
                end

                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Generated colliders for %s nodes", nApplied)))
            end
            style.tooltip("Generate Colliders for all selected meshes.")
        end,
		entries = { self.object }
	}

    return properties
end

---@protected
function mesh:generateCollider()
    local group = require("modules/classes/editor/positionableGroup"):new(self.object.sUI)
    group.name = self.object.name .. "_grouped"
    group:setParent(self.object.parent, utils.indexValue(self.object.parent.childs, self.object) + 1)
    local insertGroup = history.getInsert({ group })

    local collider = require("modules/classes/spawn/collision/collider"):new()

    local x = (self.bBox.max.x - self.bBox.min.x) * self.scale.x
    local y = (self.bBox.max.y - self.bBox.min.y) * self.scale.y
    local z = (self.bBox.max.z - self.bBox.min.z) * self.scale.z

    local pos = Vector4.new(self.position.x, self.position.y, self.position.z, 0)
    local rotation = EulerAngles.new(self.rotation.roll, self.rotation.pitch, self.rotation.yaw)

    local offset = Vector4.new((self.bBox.min.x * self.scale.x) + x / 2, (self.bBox.min.y * self.scale.y) + y / 2, (self.bBox.min.z * self.scale.z) + z / 2, 0)
    offset = self.rotation:ToQuat():Transform(offset)
    pos = Game['OperatorAdd;Vector4Vector4;Vector4'](pos, offset)

    local radius = math.max(x, y) / 2
    local height = z - radius * 2
    if self.colliderShape == 1 then
        if x > z or y > z then
            radius = z / 2
            height = math.max(x, y) - radius * 2
            rotation.roll = rotation.roll + 90

            if y > x then
                rotation.yaw = rotation.yaw + 90
            end
        end
    end

    local data = {
        extents = { x = x / 2, y = y / 2, z = z / 2 },
        radius = radius,
        height = height,
        shape = self.colliderShape
    }

    collider:loadSpawnData(data, pos, rotation)

    local colliderElement = require("modules/classes/editor/spawnableElement"):new(self.object.sUI)
    colliderElement:load({
        name = self.object.name .. "_collider",
        spawnable = collider:save(),
        modulePath = "modules/classes/editor/spawnableElement"
    })
    colliderElement:setParent(group)
    local insertCollider = history.getInsert({ colliderElement })

    local remove = history.getRemove({ self.object })
    self.object:setParent(group)
    local insert = history.getInsert({ self.object })
    local move = history.getMove(remove, insert)

    history.addAction({
        undo = function ()
            move.undo()
            insertCollider.undo()
            insertGroup.undo()
        end,
        redo = function ()
            insertGroup.redo()
            history.spawnedUI.cachePaths()
            insertCollider.redo()
            move.redo()
        end
    })

    self.object.headerOpen = false
end

function mesh:export()
    local app = self.app
    if app == "" then
        app = "default"
    end

    local data = spawnable.export(self)
    data.type = "worldMeshNode"
    data.scale = self.scale
    data.data = {
        mesh = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            },
        },
        meshAppearance = {
            ["$storage"] = "string",
            ["$value"] = app
        },
        castLocalShadows = self.shadowCastingModeEnum[self.castLocalShadows + 1],
        castRayTracedGlobalShadows = self.shadowCastingModeEnum[self.castRayTracedGlobalShadows + 1],
        castRayTracedLocalShadows = self.shadowCastingModeEnum[self.castRayTracedLocalShadows + 1],
        castShadows = self.shadowCastingModeEnum[self.castShadows + 1],
        forceAutoHideDistance = self.forceAutoHideDistance,
        occluderType = self.occluderTypes[self.occluderType + 1],
        windImpulseEnabled = self.windImpulseEnabled and 1 or 0
    }

    return data
end

return mesh
