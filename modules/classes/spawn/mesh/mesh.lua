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

local colliderShapes = { "Box", "Capsule", "Sphere" }

---Class for worldMeshNode
---@class mesh : spawnable
---@field public apps table
---@field public appIndex integer
---@field public scale {x: number, y: number, z: number}
---@field protected occluderType integer
---@field protected occluderTypes table
---@field protected hasOccluder boolean|table
---@field protected windImpulseEnabled boolean
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
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Appearance", "Collider", "Occluder", "Enable Wind Impulse" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
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
        occluderType = self.occluderTypes[self.occluderType + 1],
        windImpulseEnabled = self.windImpulseEnabled and 1 or 0
    }

    return data
end

return mesh