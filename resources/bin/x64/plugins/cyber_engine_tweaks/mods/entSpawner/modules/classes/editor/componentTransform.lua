local utils = require("modules/utils/core/utils")
local settings = require("modules/utils/core/settings")
local history = require("modules/utils/project/history")
local editor = require("modules/utils/editor/editor")

local positionable = require("modules/classes/editor/positionable")

---Transform editor for one placed component of a spawned entity, drawn with the regular transform UI.
---
---Position and rotation are in world space, like every other transform in the editor. Scale is the
---component's `visualScale`, and is only shown on components that have one. Edits move the live component
---while a field is dragged, and are written to the entity's instance data once the edit finishes,
---so the entity respawns once per edit instead of once per frame.
---
---Not part of the element tree: history, path and save state resolve to the owning entity element.
---@class componentTransform : positionable
---@field owner spawnableElement
---@field componentID string
---@field position Vector4 World position
---@field rotation EulerAngles World rotation
---@field scale {x: number, y: number, z: number} Visual scale
---@field parentPosition Vector4 World position of the space `localTransform` is relative to
---@field parentOrientation Quaternion World orientation of the space `localTransform` is relative to
---@field editing boolean True from the first change until it is written to the instance data
---@field transformChanged boolean
---@field scaleChanged boolean
local componentTransform = setmetatable({}, { __index = positionable })

---@param owner spawnableElement
---@param componentID string
---@param hasScale boolean Whether the component has a `visualScale`
---@return componentTransform
function componentTransform:new(owner, componentID, hasScale)
    local o = positionable.new(self, owner.sUI)

    o.modulePath = "modules/classes/editor/componentTransform"
    o.owner = owner
    o.parent = owner
    o.id = owner.id
    o.componentID = componentID
    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.hasScale = hasScale == true
    o.scale = { x = 1, y = 1, z = 1 }
    o.parentPosition = Vector4.new(0, 0, 0, 0)
    o.parentOrientation = EulerAngles.new(0, 0, 0):ToQuat()
    o.editing = false
    o.transformChanged = false
    o.scaleChanged = false

    o.class = utils.combine(o.class, { "componentTransform" })

    setmetatable(o, { __index = self })
    return o
end

---@return entIPlacedComponent?
function componentTransform:getComponent()
    return self.owner.spawnable:findPlacedComponent(self.componentID)
end

---The world space a live component's local transform is relative to.
---@param component entIPlacedComponent
---@return Vector4 position
---@return Quaternion orientation
local function getLiveParentSpace(component)
    local localToWorld = component:GetLocalToWorld()
    local worldOrientation = localToWorld:GetRotation():ToQuat()
    local parentOrientation = Quaternion.MulInverse(worldOrientation, component:GetLocalOrientation())
    local parentPosition = utils.subVector(localToWorld:GetTranslation(), parentOrientation:Transform(component:GetLocalPosition()))

    return parentPosition, parentOrientation
end

---The world space a component's stored local transform is relative to, built from the stored
---transforms of the components it is bound to, so an animated parent (a fan's rotor) does not move
---it. A slot binding, or a parent with no stored transform, falls back to the live parent space.
---@param spawnable entity
---@param entity entEntity
---@param component entIPlacedComponent
---@param depth integer
---@return Vector4 position
---@return Quaternion orientation
local function getStoredParentSpace(spawnable, entity, component, depth)
    if depth > 16 then
        return getLiveParentSpace(component)
    end

    -- An unbound component is relative to the element's placement. Nothing is read from the game here:
    -- the entity's transform follows its root when the root animates (a hologram's transform animator).
    local binding = component.parentTransform
    if not binding then
        return spawnable.position, spawnable.rotation:ToQuat()
    end

    local slotName = binding.slotName and binding.slotName.value or "None"
    local bindName = binding.bindName and binding.bindName.value or "None"
    if slotName ~= "None" then
        return getLiveParentSpace(component)
    end
    if bindName == "None" then
        return spawnable.position, spawnable.rotation:ToQuat()
    end

    local parent = entity:FindComponentByName(bindName)
    if not parent or not parent:IsA("entIPlacedComponent") then
        return getLiveParentSpace(component)
    end

    -- The root's stored transform is the placement it was read at, not a local offset. A root the
    -- engine added has no ID.
    local parentID = utils.CRUIDToString(parent.id)
    if not parent.parentTransform and (parentID == "0" or parentID == spawnable:getTransformRootComponentID()) then
        return spawnable.position, spawnable.rotation:ToQuat()
    end

    local parentLocalPosition, parentLocalOrientation = spawnable:getComponentStoredTransform(parentID)
    if not parentLocalPosition then
        return getLiveParentSpace(component)
    end

    local spacePosition, spaceOrientation = getStoredParentSpace(spawnable, entity, parent, depth + 1)

    return utils.addVector(spacePosition, spaceOrientation:Transform(parentLocalPosition)),
        utils.multQuat(spaceOrientation, parentLocalOrientation)
end

---Reads the world transform from the stored local transform and the stored parent chain, so a
---component that animates, or is bound to one that does, holds still in the values and the gizmo.
---@return boolean
function componentTransform:readFromComponent()
    local component = self:getComponent()
    local entity = self.owner.spawnable:getEntity()
    if not component or not entity then return false end

    self.parentPosition, self.parentOrientation = getStoredParentSpace(self.owner.spawnable, entity, component, 0)

    local localPosition = component:GetLocalPosition()
    local localOrientation = component:GetLocalOrientation()
    local storedPosition, storedOrientation = self.owner.spawnable:getComponentStoredTransform(self.componentID)
    if storedPosition then
        localPosition = storedPosition
        localOrientation = storedOrientation
    end

    self.position = utils.addVector(self.parentPosition, self.parentOrientation:Transform(localPosition))
    self.rotation = utils.multQuat(self.parentOrientation, localOrientation):ToEulerAngles()

    if self.hasScale then
        local scale = component.visualScale
        self.scale = { x = scale.x, y = scale.y, z = scale.z }
    end

    return true
end

---@param parentPosition Vector4
---@param parentOrientation Quaternion
---@return Vector4 localPosition
---@return Quaternion localOrientation
function componentTransform:getTransformRelativeTo(parentPosition, parentOrientation)
    local inverseParent = Quaternion.MulInverse(EulerAngles.new(0, 0, 0):ToQuat(), parentOrientation)
    local localPosition = inverseParent:Transform(utils.subVector(self.position, parentPosition))
    local localOrientation = utils.multQuat(inverseParent, self.rotation:ToQuat())

    return localPosition, localOrientation
end

---@return Vector4 localPosition
---@return Quaternion localOrientation
function componentTransform:getLocalTransform()
    return self:getTransformRelativeTo(self.parentPosition, self.parentOrientation)
end

function componentTransform:applyToComponent()
    self.editing = true
    self.transformChanged = true

    local component = self:getComponent()
    if not component then return end

    local localPosition, localOrientation = self:getLocalTransform()
    component:SetLocalPosition(localPosition)
    component:SetLocalOrientation(localOrientation)
end

function componentTransform:applyScaleToComponent()
    self.editing = true
    self.scaleChanged = true

    local component = self:getComponent()
    if not component then return end

    component.visualScale = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
end

function componentTransform:setPosition(position)
    if position.x == self.position.x and position.y == self.position.y and position.z == self.position.z then return end

    self.position = position
    self:applyToComponent()
end

function componentTransform:setPositionDelta(delta)
    self.position = utils.addVector(self.position, delta)
    self:applyToComponent()
end

function componentTransform:getPosition()
    return self.position
end

function componentTransform:setRotation(rotation)
    if self.rotationLocked then return end
    if rotation.roll == self.rotation.roll and rotation.pitch == self.rotation.pitch and rotation.yaw == self.rotation.yaw then return end

    self.rotation = rotation
    self:applyToComponent()
end

function componentTransform:setRotationDelta(delta)
    if delta.roll == 0 and delta.pitch == 0 and delta.yaw == 0 or self.rotationLocked then return end

    if self.rotationRelative then
        self.rotation = utils.addEulerRelative(self.rotation, delta)
    else
        self.rotation = utils.addEuler(self.rotation, delta)
    end
    self:applyToComponent()
end

function componentTransform:getRotation()
    return self.rotation
end

function componentTransform:setScale(scale, finished)
    if not self.hasScale then return end
    if scale.x == self.scale.x and scale.y == self.scale.y and scale.z == self.scale.z then return end

    self.scale = { x = scale.x, y = scale.y, z = scale.z }
    self:applyScaleToComponent()
end

function componentTransform:setScaleDelta(delta, finished)
    if not self.hasScale then return end

    self:addScaleDelta(self.scale, delta)
    self:applyScaleToComponent()
end

function componentTransform:getScale()
    return Vector4.new(self.scale.x, self.scale.y, self.scale.z, 0)
end

function componentTransform:getDirection(direction)
    if direction == "forward" then
        return self.rotation:GetForward()
    elseif direction == "right" then
        return self.rotation:GetRight()
    elseif direction == "up" then
        return self.rotation:GetUp()
    end
end

-- Every component that makes up the gizmo; one missing from an entity is skipped.
local gizmoParts = { "arrows", "rings" }

---Moves the owning entity's gizmo onto this component, or back to the entity with `reset`.
---@param reset boolean?
function componentTransform:placeArrows(reset)
    local entity = self.owner.spawnable:getEntity()
    if not entity then return end

    local arrows = entity:FindComponentByName("arrows")
    if not arrows then return end

    if reset then
        for _, part in ipairs(gizmoParts) do
            local component = entity:FindComponentByName(part)
            if component then
                component:SetLocalPosition(Vector4.new(0, 0, 0, 0))
                component:SetLocalOrientation(EulerAngles.new(0, 0, 0):ToQuat())
            end
        end
        return
    end

    -- Read from the arrows' own binding: `getPlacedParent` can name a different component than the
    -- one they were bound to when added, on an entity with no unbound root at the origin.
    local parentPosition, parentOrientation
    local binding = arrows.parentTransform
    local parent = binding and binding.bindName and entity:FindComponentByName(binding.bindName)
    if parent and parent:IsA("entIPlacedComponent") then
        local parentToWorld = parent:GetLocalToWorld()
        parentPosition = parentToWorld:GetTranslation()
        parentOrientation = parentToWorld:GetRotation():ToQuat()
    else
        parentPosition = entity:GetWorldPosition()
        parentOrientation = entity:GetWorldOrientation()
    end

    local localPosition, localOrientation = self:getTransformRelativeTo(parentPosition, parentOrientation)
    for _, part in ipairs(gizmoParts) do
        local component = entity:FindComponentByName(part)
        if component then
            component:SetLocalPosition(localPosition)
            component:SetLocalOrientation(localOrientation)
        end
    end
end

---Outlines just this component, on top of the entity's own outline.
---@param color integer? Outline index; the entity's current outline when omitted
function componentTransform:setOutline(color)
    local entity = self.owner.spawnable:getEntity()
    local component = self:getComponent()
    if not entity or not component then return end

    utils.sendOutlineEvent(entity, color or self.owner.spawnable.outline or 0, component.name)
end

---Picks an outline colour that differs from the selection outline.
---@return integer
local function getFocusOutlineColor()
    local selectionColor = settings.outlineColor + 1
    return selectionColor == 4 and 5 or 4
end

---Puts the gizmo and the outline back on the entity.
function componentTransform:releaseFocus()
    self:placeArrows(true)
    self:setOutline()
    self.outlinedEntity = nil
end

---Runs every frame while this component is the editor's gizmo target.
---@param idle boolean True while no gizmo drag is in progress
function componentTransform:updateGizmo(idle)
    if not self.editing and not self:readFromComponent() then return end

    self:placeArrows()

    -- Sent again whenever the entity respawns or its own outline changes, as both replace it.
    local entity = self.owner.spawnable:getEntity()
    local entityHash = entity and entity:GetEntityID().hash
    local outline = self.owner.spawnable.outline or 0
    if entityHash and (self.outlinedEntity ~= entityHash or self.outlinedWith ~= outline) then
        if outline ~= 0 then
            self:setOutline(getFocusOutlineColor())
        end
        self.outlinedEntity = entityHash
        self.outlinedWith = outline
    end

    if idle and self.editing and not history.propBeingEdited then
        self:commit()
    end
end

---Drops the component onto the first surface below it.
---@param grouped boolean? True when a caller already recorded a history action
---@param direction Vector4
---@param excludeDict table<number, boolean>?
---@param onComplete fun()?
function componentTransform:dropToSurface(grouped, direction, excludeDict, onComplete)
    local excludeIds = excludeDict or {}
    excludeIds[self.owner.id] = true

    local hit = editor.getRaySceneIntersection(direction, self.position, excludeIds, true)
    if hit.hit then
        if not grouped then
            history.addAction(history.getElementChange(self))
        end
        self:setPosition(hit.result.unscaledHit or hit.result.position)
    end

    if onComplete then onComplete() end
end

-- Only the edited part is written: each write respawns the entity.
function componentTransform:commit()
    self.editing = false

    if self.transformChanged then
        local localPosition, localOrientation = self:getLocalTransform()
        self.owner.spawnable:setComponentLocalTransform(self.componentID, localPosition, localOrientation)
    end
    if self.scaleChanged then
        self.owner.spawnable:setComponentVisualScale(self.componentID, self.scale)
    end

    self.transformChanged = false
    self.scaleChanged = false
end

function componentTransform:drawTransform()
    if not self.editing and not self:readFromComponent() then return end

    positionable.drawTransform(self)

    if history.lastEditedElement == self then
        history.lastEditedElement = self.owner
    end

    -- Not committed from `onEdited`: the position buttons never call it, and `drawProp` calls it
    -- before applying that frame's last change. Not during a gizmo drag either: each commit respawns.
    if self.editing and not history.propBeingEdited and editor.currentAxis == "none" then
        self:commit()
    end
end

-- The editor's gizmo and visualizer arrows belong to the owning entity.
function componentTransform:setVisualizerDirection(direction)
    self.visualizerDirection = direction
end

function componentTransform:setVisualizerState(state)
    self.visualizerState = state
end

function componentTransform:getPath()
    return self.owner:getPath()
end

function componentTransform:serialize()
    return self.owner:serialize()
end

function componentTransform:load(data, silent)
    self.owner:load(data, silent)
end

return componentTransform
