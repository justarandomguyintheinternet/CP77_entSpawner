local utils = require("modules/utils/utils")
local builder = require("modules/utils/entityBuilder")
local visualizer = require("modules/utils/visualizer")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")
local registry = require("modules/utils/nodeRefRegistry")
local editor = require("modules/utils/editor/editor")
local GameSettings = require("modules/utils/GameSettings")
local preview = require("modules/utils/previewUtils")

---Base class for any object / node that can be spawned
---@class spawnable
---@field public dataType string
---@field public spawnListType string
---@field public spawnListPath string
---@field public modulePath string
---@field public spawnData string
---@field public app string
---@field public position Vector4
---@field public rotation EulerAngles
---@field protected entityID entEntityID
---@field protected entity entEntity?
---@field protected spawned boolean
---@field protected spawning boolean
---@field protected despawning boolean
---@field public primaryRange number
---@field public secondaryRange number
---@field public uk10 integer
---@field public uk11 integer
---@field protected streamingMultiplier number
---@field public isHovered boolean
---@field protected arrowDirection string all|red|green|blue
---@field public object element? The element that is using this spawnable
---@field public node string
---@field public description string
---@field public previewNote string
---@field public icon string
---@field private rotationRelative boolean
---@field protected outline integer
---@field private spawnedAndCachedCallback function[]
---@field protected nodeRef string
---@field public noExport boolean
---@field private worldNodePropertyWidth number
---@field public assetPreviewType string none|backdrop|current_position
---@field public assetPreviewDelay number
---@field public isAssetPreview boolean
---@field private assetPreviewLensDistortion boolean
local spawnable = {}

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.node = "worldEntityNode"
    o.description = ""
    o.previewNote = "---"
    o.icon = ""

    o.spawnData = "base\\spawner\\empty_entity.ent"
    o.app = "default"

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})
    o.entity = nil
    o.spawned = false
    o.spawning = false
    o.despawning = false
    o.spawnedAndCachedCallback = {}
    o.worldNodePropertyWidth = nil

    o.noExport = false
    o.primaryRange = 120
    o.secondaryRange = 100
    o.uk10 = 1024
    o.uk11 = 512
    o.streamingMultiplier = 1
    o.nodeRef = ""

    o.isHovered = false
    o.arrowDirection = "none"
    o.rotationRelative = false
    o.outline = 0

    o.assetPreviewType = "none"
    o.assetPreviewDelay = 0.2
    o.isAssetPreview = false
    o.assetPreviewLensDistortion = false

    o.object = object

    self.__index = self
   	return setmetatable(o, self)
end

function spawnable:onAssemble(entity)
    visualizer.attachArrows(entity, self:getArrowSize(), self.isHovered, self.arrowDirection)
end

function spawnable:onAttached(entity)
    self.spawned = true
    self.spawning = false

    for _, callback in ipairs(self.spawnedAndCachedCallback) do
        callback(entity)
    end

    if self.despawning then
        self.despawning = false
        self:despawn()
    end
end

function spawnable:registerSpawnedAndAttachedCallback(callback)
    table.insert(self.spawnedAndCachedCallback, callback)
end

---Spawns the spawnable if not spawned already, must register a callback for entityAssemble which calls onAssemble
function spawnable:spawn()
    if self:isSpawned() or self.spawning then return end

    local spec = StaticEntitySpec.new()
    spec.templatePath = self.spawnData
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.attached = true
    spec.appearanceName = self.app
    self.entityID = Game.GetStaticEntitySystem():SpawnEntity(spec)
    self.spawning = true

    builder.registerAssembleCallback(self.entityID, function (entity)
        self.entity = entity
        self:onAssemble(entity)
    end)

    builder.registerAttachCallback(self.entityID, function (entity)
        self:onAttached(entity)
    end)
end

---@return boolean
function spawnable:isSpawned()
    return self.spawned
end

function spawnable:despawn()
    local entity = self:getEntity()
    if entity then
        Game.GetStaticEntitySystem():DespawnEntity(self.entityID)
    end
    self.spawned = false
    self.entity = nil

    if self.spawning then
        self.despawning = true
    end
end

function spawnable:respawn()
    self:despawn()
    self:spawn()
end

---Update the position and rotation of the spawnable
function spawnable:update()
    if not self:isSpawned() then return end

    local entity = self:getEntity()

    if not entity then return end

    local transform = entity:GetWorldTransform()
    transform:SetPosition(self.position)
    transform:SetOrientationEuler(self.rotation)
    entity:SetWorldTransform(transform)
end

function spawnable:onParentChanged(newParent) end

function spawnable:onObjectRemoved() end

function spawnable:setOutline(color)
    if not self:isSpawned() then return end

    self.outline = color
    utils.sendOutlineEvent(self:getEntity(), color)
end

---Called when one of the control UI widgets is released
function spawnable:onEdited(edited) end

---@return entEntity?
function spawnable:getEntity()
    return Game.GetStaticEntitySystem():GetEntity(self.entityID) or self.entity
end

--- Generate valid name from given name / path
---@param name string
---@return string newName The generated/sanitized name
function spawnable:generateName(name)
    if string.find(name, "\\") then
        name = name:match("\\[^\\]*$") -- Everything after last \
    end
    name = name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    return utils.createFileName(name)
end

---Return the spawnable data for internal object format saving
---@return table {modulePath, position, rotation, spawnData, dataType, app}
function spawnable:save()
    return {
        modulePath = self.modulePath,
        position = { x = self.position.x, y = self.position.y, z = self.position.z, w = 0 },
        rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw },
        spawnData = self.spawnData,
        dataType = self.dataType,
        app = self.app,
        rotationRelative = self.rotationRelative,
        primaryRange = self.primaryRange,
        secondaryRange = self.secondaryRange,
        uk10 = self.uk10,
        uk11 = self.uk11,
        nodeRef = self.nodeRef
    }
end

function spawnable:draw() end

function spawnable:getProperties()
    local properties =  {}

    table.insert(properties, {
        id = "worldNode",
        name = "World Node",
        defaultHeader = false,
        draw = function()
            if not self.worldNodePropertyWidth then
                self.worldNodePropertyWidth = utils.getTextMaxWidth({ "Node Ref", "Primary Range", "Secondary Range" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
            end

            local entry = self.nodeRef ~= "" and registry.refs[self.object:getRootParent().name] and registry.refs[self.object:getRootParent().name][self.nodeRef]
            local refDuplicate = entry and (entry.path ~= self.object:getPath() or entry.duplicate)

            style.mutedText("Node Ref")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.worldNodePropertyWidth)
            self.nodeRef, _, _ = style.trackedTextField(self.object, "##noderef", self.nodeRef, "$/#foobar", style.getMaxWidth(250) - 30 - (refDuplicate and 25 or 0))
            style.pushButtonNoBG(true)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.ReloadAlert) then
                local generated = registry.generate(self.object)

                if generated ~= self.nodeRef then
                    history.addAction(history.getElementChange(self.object))
                    self.nodeRef = generated
                end
            end
            style.pushButtonNoBG(false)
            style.tooltip("Generate a unique NodeRef for this object")

            if refDuplicate then
                ImGui.SameLine()
                style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
                style.tooltip("NodeRef is already in use elsewhere")
            end

            style.mutedText("Primary Range")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.worldNodePropertyWidth)
            self.primaryRange, _, _ = style.trackedDragFloat(self.object, "##primaryRange", self.primaryRange, 0.1, 0, 9999, "%.2f", 90)
            ImGui.SameLine()
            local distance = utils.distanceVector(self.position, GetPlayer():GetWorldPosition())
            style.styledText(IconGlyphs.AxisArrowInfo, distance > self.primaryRange and 0xFF0000FF or 0xFF00FF00)
            style.tooltip("Distance to player: " .. string.format("%.2f", distance))

            style.mutedText("Secondary Range")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.worldNodePropertyWidth)
            self.secondaryRange, _, _ = style.trackedDragFloat(self.object, "##secondaryRange", self.secondaryRange, 0.1, 0, 9999, "%.2f", 90)
            ImGui.SameLine()
            style.styledText(IconGlyphs.AxisArrowInfo, distance > self.secondaryRange and 0xFF0000FF or 0xFF00FF00)
            style.tooltip("Distance to player: " .. string.format("%.2f", distance))

            if ImGui.Button("Auto-Set") then
                history.addAction(history.getElementChange(self.object))
                local values = self:calculateStreamingValues(self.streamingMultiplier)

                self.primaryRange = values.primary
                self.secondaryRange = values.secondary
            end

            ImGui.SameLine()

            ImGui.SetNextItemWidth(80 * style.viewSize)
            self.streamingMultiplier, _ = ImGui.DragFloat("Multiplier", self.streamingMultiplier, 0.01, 0, 50, "%.2f")
            style.tooltip("Multiplier for streaming values, when using \"Auto-Set\"")
        end
    })

    return properties
end

function spawnable:getGroupedProperties()
    local properties = {}

    properties["streamingProperties"] = {
		name = "World Node",
        id = "worldNode",
		data = {
            multiplier = 1
        },
		draw = function(element, entries)
            if ImGui.Button("Calculate Streaming Distances") then
                history.addAction(history.getMultiSelectChange(entries))

                for _, entry in ipairs(entries) do
                    local values = entry.spawnable:calculateStreamingValues(element.groupOperationData["streamingProperties"].multiplier * entry.spawnable.streamingMultiplier)

                    entry.spawnable.primaryRange = values.primary
                    entry.spawnable.secondaryRange = values.secondary
                end
            end

            ImGui.SameLine()

            ImGui.SetNextItemWidth(80 * style.viewSize)
            element.groupOperationData["streamingProperties"].multiplier, _ = ImGui.DragFloat("Multiplier", element.groupOperationData["streamingProperties"].multiplier, 0.01, 0, 50, "%.2f")
            style.tooltip("Multiplier for streaming values, when using \"Calculate Streaming Distances\"")
		end,
		entries = { self.object }
	}

    return properties
end

---Returns the world position of the top left corner, which shall act as anchor for any HUD text of the asset preview
function spawnable:getAssetPreviewTextAnchor()
    return self.position
end

--Should be called once getAssetPreviewTextAnchor will return the correct position (BBOX loaded)
function spawnable:setAssetPreviewTextPostition()
    local x, y = editor.camera.worldToScreen(self:getAssetPreviewTextAnchor())

    local width, height = GetDisplayResolution()
    local factor = width / 2560
    local rx, ry = (x + 1) * width / 2, (- y + 1) * height / 2

    ry = ry + 20 * factor
    rx = rx + 20 * factor

    preview.elements["previewFirstLine"]:SetTranslation(rx, ry)
    preview.elements["previewSecondLine"]:SetTranslation(rx, ry + 40 * factor)
    preview.elements["previewThirdLine"]:SetTranslation(rx, ry + 80 * factor)
end

---Position where the asset preview should be spawned, the actual entity position
---@protected
---@param distance number?
function spawnable:getAssetPreviewPosition(distance)
    if self.assetPreviewType == "backdrop" then
        return editor.getForward((distance or 1) * (68 / GetPlayer():GetFPPCameraComponent():GetFOV()))
    end
    return self.position
end

--Attach any custom components needed
function spawnable:assetPreviewAssemble(entity)
end

--Assumes entity is fully spawned and BBOX is loaded, set to proper position. Called each frame.
function spawnable:assetPreviewSetPosition()
    self.position = self:getAssetPreviewPosition()
    self:update()
end

---Asset preview can be either not enabled, use the current position, or a backdrop (Must be implemented by the object)
---@param state boolean
function spawnable:assetPreview(state)
    self.isAssetPreview = true
    if self.assetPreviewType == "none" then return end

    if state then
        -- Needed, to avoid text being off due to screen curvature effect
        if self.assetPreviewType == "backdrop" and editor.active then
            self.assetPreviewLensDistortion = GameSettings.Get("/accessibility/interface/LensDistortionOverride")
            GameSettings.Set("/accessibility/interface/LensDistortionOverride", true)
        end
        if self.assetPreviewType == "backdrop" then
            self.position = utils.addVector(GetPlayer():GetWorldPosition(), Vector4.new(0, 0, -50, 0))
        end
        -- Only move into position once bbox is loaded, see first assetPreviewSetPosition call
        self:spawn()
        self:registerSpawnedAndAttachedCallback(function ()
            self:assetPreviewSetPosition()
            self:setAssetPreviewTextPostition()
        end)
    else
        if self.assetPreviewType == "backdrop" then
            preview.elements["previewFirstLine"]:SetVisible(false)
            preview.elements["previewSecondLine"]:SetVisible(false)
            preview.elements["previewThirdLine"]:SetVisible(false)
            if editor.active then GameSettings.Set("/accessibility/interface/LensDistortionOverride", self.assetPreviewLensDistortion) end
        end
        self:despawn()
    end
end

---Gets the actual physical size of the spawnable, usually BBOX
---@return table {x, y, z}
function spawnable:getSize()
    return { x = 1, y = 1, z = 1 }
end

function spawnable:getBBox()
    local size = self:getSize()
    return {
        min = { x = -size.x / 2, y = -size.y / 2, z = -size.z / 2 },
        max = { x = size.x / 2, y = size.y / 2, z = size.z / 2 }
    }
end

function spawnable:getArrowSize()
    local size = self:getSize()
    local max = math.min(math.max(size.x, size.y, size.z, 0.75) * 0.4, 1)
    return { x = max, y = max, z = max }
end

function spawnable:getCenter()
    return self.position
end

function spawnable:calculateIntersection(origin, ray)
    local bbox = self:getBBox()

    if not self:getEntity() then
        return { hit = false }
    end

    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, bbox)

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = result.position, -- Hit result of intersection test with unmodified bbox, for more accurate drop to surface
        collisionType = "bbox",
        distance = result.distance,
        bBox = bbox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

---Calculates the streaming distance values for the spawnable based on getSize()
---@param multiplier number
---@return table {primary, secondary, uk10, uk11}
function spawnable:calculateStreamingValues(multiplier)
    -- TODO: Maybe make the multiplier scale non-linearly, so small things get boosted less than big things
    -- multiplier = math.min(1, math.max(0, falloffRange * math.log(math.max(0, maxAxis + minSize))))
    local scale = self:getSize()

    local primary = math.max(math.max(scale.x, scale.y, scale.z) * multiplier * 60, 25)
    primary = math.min(primary, 200 * self.streamingMultiplier)
    local secondary = primary * 0.8

    return { primary = primary, secondary = secondary, uk10 = self.uk10, uk11 = self.uk11 }
end

---Load data blob, position and rotation for spawning
---@param data table
---@param position Vector4
---@param rotation EulerAngles
function spawnable:loadSpawnData(data, position, rotation)
    for key, value in pairs(data) do
        self[key] = value
    end

    self.position = position
    self.rotation = rotation
    self.rotationRelative = data.rotationRelative or false
    self.primaryRange = data.primaryRange or 100
    self.secondaryRange = data.secondaryRange or 120
    self.uk10 = data.uk10 or self.uk10
    self.uk11 = data.uk11 or self.uk11
end

---Export the spawnable for WScript import, using same structure for `data` as JSON formated node
---@param key integer Index of the object in the group
---@param length integer Amount of objects in the group
---@return table {position, rotation, scale, type, data}
function spawnable:export(key, length)
    return {
        position = utils.fromVector(self.position),
        rotation = utils.fromQuaternion(self.rotation:ToQuat()),
        scale = { x = 1, y = 1, z = 1 },
        primaryRange = self.primaryRange,
        secondaryRange = self.secondaryRange,
        uk10 = self.uk10,
        uk11 = self.uk11,
        nodeRef = self.nodeRef,
        type = "worldEntityNode",
        name = "[" .. self.dataType .. "] " .. self.object.name,
        data = {
            entityTemplate = {
                DepotPath = {
                    ["$type"] = "ResourcePath",
                    ["$storage"] = "string",
                    ["$value"] = self.spawnData
                }
            },
            appearanceName = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = self.app
            }
        }
    }
end

return spawnable