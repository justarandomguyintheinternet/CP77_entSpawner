local utils = require("modules/utils/core/utils")
local visualizer = require("modules/utils/preview/visualizer")
local settings = require("modules/utils/core/settings")
local editor = require("modules/utils/editor/editor")
local Cron = require("modules/utils/vendor/Cron")
local intersection = require("modules/utils/editor/intersection")
local history = require("modules/utils/project/history")
local style = require("modules/ui/style")
local saveState = require("modules/utils/project/saveState")

local element = require("modules/classes/editor/element")
local positionable = require("modules/classes/editor/positionable")

---Class for an element holding a spawnable
---@class spawnableElement : positionable
---@field spawnable spawnable
---@field parent positionableGroup|randomizedGroup
---@field silent boolean
local spawnableElement = setmetatable({}, { __index = positionable })

local function invalidateParentAutoCenter(instance)
	local current = instance and instance.parent or nil

	while current do
		if current.invalidateAutoCenterCache then
			current:invalidateAutoCenterCache(true)
			return
		end

		current = current.parent
	end
end

---@return boolean
local function selectedVisualizersEnabled()
	return settings.selectedVisualizersEnabled ~= false
end

function spawnableElement:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Element"
	o.modulePath = "modules/classes/editor/spawnableElement"

	o.spawnable = nil
	o.class = utils.combine(o.class, { "spawnableElement" })
	o.expandable = false
	o.silent = false

	o.randomizationSettings = utils.combineHashTable(o.randomizationSettings, {
		randomizeRotation = false,
		randomizeRotationAxis = 2,
		randomizeAppearance = false
	})

	---Authored rotation that `updateRandomization` re-rolls from, as a serializable euler table.
	---Cleared whenever the rotation is changed by anything else, so the edit becomes the new base.
	o.randomizationBaseRotation = nil
	o.applyingRandomRotation = false

	setmetatable(o, { __index = self })
   	return o
end

function spawnableElement:load(data, silent)
	positionable.load(self, data, silent)

	if self.spawnable then
		self.spawnable:despawn()
	end

	self.spawnable = utils.requireSpawnable(data.spawnable.modulePath):new()
    self.spawnable.object = self
    if data.scaleLocked == nil and self.spawnable.defaultScaleLocked ~= nil then
        self.scaleLocked = self.spawnable.defaultScaleLocked
    end
    self.spawnable:loadSpawnData(data.spawnable, ToVector4(data.spawnable.position), ToEulerAngles(data.spawnable.rotation))
	self.icon = self.spawnable.icon
    self.secondaryIcon = self.spawnable.secondaryIcon or ""
	if self.spawnable.scale then
		self.hasScale = true
	end
	self.silent = silent

	self:setVisible(self.visible, true)

	if not self.silent then
		self.spawnable:registerSpawnedAndAttachedCallback(function (entity)
			-- Delay is needed as entities need some time (?). Its fine for other types tho...
			Cron.After(0.05, function ()
				if settings.gizmoOnSelected and selectedVisualizersEnabled() then
					self:setVisualizerState(self.selected)
					self:setVisualizerDirection("none")
				end

				local original = self.selected
				self.selected = false
				self:setSelected(original)
			end)
		end)

		element.bumpWireframeEpoch(self)
	end

	-- Assigned last: the steps above write the rotation, which clears the base by design.
	-- A payload without the field predates it, and the next randomization captures a fresh base.
	self.randomizationBaseRotation = data.randomizationBaseRotation and utils.deepcopy(data.randomizationBaseRotation) or nil
end

function spawnableElement:getProperties()
	local properties = positionable.getProperties(self)

	properties = utils.combine(properties, self.spawnable:getProperties())

	return properties
end

function spawnableElement:getGroupedProperties()
	local properties = positionable.getGroupedProperties(self)

	for key, value in pairs(self.spawnable:getGroupedProperties()) do
		properties[key] = value
	end

	return properties
end

function spawnableElement:setParent(parent, index)
	local oldParent = self.parent
	positionable.setParent(self, parent, index)

	if self.silent then return end

	self.spawnable:onParentChanged(oldParent)
end

function spawnableElement:setSelected(state)
	local update = self.selected ~= state

	positionable.setSelected(self, state)

	if not update then return end
	if not self.spawnable:isSpawned() then return end

	if settings.outlineSelected and selectedVisualizersEnabled() and state then
		self.spawnable:setOutline(settings.outlineColor + 1)
	else
		self.spawnable:setOutline(0)
	end
end

function spawnableElement:setVisible(state, fromRecursive)
	positionable.setVisible(self, state, fromRecursive)

	if self.silent then return end

	if self.visible == false or self.hiddenByParent then
		self.spawnable:despawn()
	else
		self.spawnable:spawn()
	end
end

function spawnableElement:setHiddenByParent(state)
	positionable.setHiddenByParent(self, state)

	if self.silent then return end

	if self.hiddenByParent or not self.visible then
		self.spawnable:despawn()
	else
		self.spawnable:spawn()
	end
end

function spawnableElement:setVisualizerState(state)
	positionable.setVisualizerState(self, state)

	if not self.spawnable:isSpawned() then return end

	local entity = self.spawnable:getEntity()
	visualizer.showArrows(entity, self.visualizerState)

	-- Size the arrows to the current camera distance the moment they are shown, so hover arrows
	-- appear at the right size immediately (the per-frame driver only tracks the active selection).
	if self.visualizerState then
		visualizer.setArrowScale(entity, self.spawnable:getScaledArrowSize())
	end
end

function spawnableElement:setVisualizerDirection(direction)
	positionable.setVisualizerDirection(self, direction)
	editor.followTransformHover(direction)

	if not self.spawnable:isSpawned() then return end

	local color = "none"
	if direction == "x" or direction == "relX" or direction == "pitch" or direction == "scaleX" then color = "x" end
	if direction == "y" or direction == "relY" or direction == "roll" or direction == "scaleY" then color = "y" end
	if direction == "z" or direction == "relZ" or direction == "yaw" or direction == "scaleZ" then color = "z" end

	if not self.spawnable:isSpawned() or not self.visualizerState then return end

	local entity = self.spawnable:getEntity()
	if not entity then return end

	-- Rotation fields light their ring, the others their arrow.
	if direction == "pitch" or direction == "roll" or direction == "yaw" then
		visualizer.highlightArrow(entity, "none", color)
	else
		visualizer.highlightArrow(entity, color, "none")
	end
    local arrowsComponent = entity:FindComponentByName("arrows")
    if not arrowsComponent then return end

	if direction == "x" or direction == "y" or direction == "z" then
		local diff = Quaternion.MulInverse(EulerAngles.new(0, 0, 0):ToQuat(), self:getRotation():ToQuat())
		pcall(function ()
			arrowsComponent:SetLocalOrientation(diff) -- This seems to fuck with component visibility
		end)
	else
		pcall(function ()
			arrowsComponent:SetLocalOrientation(EulerAngles.new(0, 0, 0):ToQuat())
		end)
	end
end

function spawnableElement:getDirection(direction)
	if not self.spawnable:isSpawned() then
		return Vector4.new(0, 0, 0, 0)
	end

	if direction == "forward" then
		return self.spawnable:getEntity():GetWorldForward()
	elseif direction == "right" then
		return self.spawnable:getEntity():GetWorldRight()
	elseif direction == "up" then
		return self.spawnable:getEntity():GetWorldUp()
	end
end

function spawnableElement:setPosition(position)
    self.spawnable.position = position
    self.spawnable:update()
    invalidateParentAutoCenter(self)
    -- Marked here, not by whoever pushed the history action: a group operation moves every leaf but
    -- names only one element in its action, so the rest would keep stale cached transforms.
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:setPositionDelta(delta)
    self.spawnable.position = utils.addVector(self.spawnable.position, delta)
    self.spawnable:update()
    invalidateParentAutoCenter(self)
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:setRotation(rotation)
    if self.rotationLocked then return end

    if not self.applyingRandomRotation then self.randomizationBaseRotation = nil end

    self.spawnable.rotation = rotation
    self.spawnable:update()
    invalidateParentAutoCenter(self)
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:setRotationDelta(delta)
    if delta.roll == 0 and delta.pitch == 0 and delta.yaw == 0 or self.rotationLocked then return end

    if not self.applyingRandomRotation then self.randomizationBaseRotation = nil end

	if self.rotationRelative then
		self.spawnable.rotation = utils.addEulerRelative(self.spawnable.rotation, delta)
	else
		self.spawnable.rotation = utils.addEuler(self.spawnable.rotation, delta)
	end

    self.spawnable:update()
    invalidateParentAutoCenter(self)
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:getPosition()
	return self.spawnable.position
end

function spawnableElement:getRotation()
	return self.spawnable.rotation
end

function spawnableElement:getScale()
	if self.spawnable.scale then return Vector4.new(self.spawnable.scale.x, self.spawnable.scale.y, self.spawnable.scale.z, 0) end

	return Vector4.new(1, 1, 1, 0)
end

function spawnableElement:setScaleDelta(delta, finished)
	self:addScaleDelta(self.spawnable.scale, delta)

    self.spawnable:updateScale(finished, delta)
    invalidateParentAutoCenter(self)
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:setScale(scale, finished)
	if not self.hasScale then return end

	local delta = {
		x = scale.x - self.spawnable.scale.x,
		y = scale.y - self.spawnable.scale.y,
		z = scale.z - self.spawnable.scale.z
	}

	self.spawnable.scale.x = scale.x
	self.spawnable.scale.y = scale.y
	self.spawnable.scale.z = scale.z

    self.spawnable:updateScale(finished, delta)
    invalidateParentAutoCenter(self)
    saveState.markDirty(self)
    element.bumpWireframeEpoch(self)
end

function spawnableElement:getSize()
	local size = self.spawnable:getSize()
	return Vector4.new(size.x, size.y, size.z, 1)
end

function spawnableElement:getCenter()
	return self.spawnable:getCenter()
end

---Whether a drop anchors on the low point of the bounding box instead of the asset's own origin.
---Read at land time rather than passed down: the setting is global to every drop and the group drop
---queue is asynchronous, so reading it here keeps an in-flight queue consistent with the UI.
---@return boolean
local function dropAnchorsToBoundingBox()
	return settings.dropToFloorMode == 1
end

---@param grouped boolean? True when a caller already recorded a history action.
---@param direction Vector4 Drop direction.
---@param excludeDict table<number, boolean>? Spawnable element ids the drop raycast must ignore.
---@param onComplete fun()? Invoked once the drop has settled, on every exit path.
function spawnableElement:dropToSurface(grouped, direction, excludeDict, onComplete)
	local function finish()
		if onComplete then onComplete() end
	end

	local size = self.spawnable:getSize()
	local bBox = {
		min = Vector4.new(-size.x / 2, -size.y / 2, -size.z / 2, 0),
		max = Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0)
	}

	local toOrigin = utils.multVector(direction, -999)
	local origin = intersection.getBoxIntersection(utils.subVector(self.spawnable:getCenter(), toOrigin), utils.multVector(direction, -1), self.spawnable:getCenter(), self.spawnable.rotation, bBox)

	if not origin.hit then return finish() end

	origin.position = utils.addVector(origin.position, utils.multVector(direction, 0.025))
	local excludeIds = excludeDict or {}
	excludeIds[self.id] = true
	local hit = editor.getRaySceneIntersection(direction, origin.position, excludeIds, true)

	if not hit.hit then return finish() end

	local target = utils.multVector(hit.result.normal, -1)
	local current = origin.normal

	local diff = utils.getAlignmentQuat(current, target, self.spawnable.rotation)

	if not grouped then
		history.addAction(history.getElementChange(self))
	end
	
	local newRotation = utils.multQuat(self.spawnable.rotation:ToQuat(), diff)
	if self.applyRotationWhenDropped then
		self:setRotation(newRotation:ToEulerAngles())
	end
	
	local surfacePoint = hit.result.unscaledHit or hit.result.position -- phyiscal hits dont have unscaledHit
	local newPosition = surfacePoint

	if dropAnchorsToBoundingBox() then
		-- Push back out along the half-extents so the low point of the bounding box rests on the
		-- surface. Evaluated after `setRotation` above, since the rotation moves the center too.
		local offset = utils.multVecXVec(newRotation:Transform(origin.normal), Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0))
		local newCenter = utils.addVector(surfacePoint, utils.multVector(hit.result.normal, offset:Length()))
		newPosition = utils.addVector(newCenter, utils.subVector(self.spawnable.position, self.spawnable:getCenter()))
	end

	if hit.hit then
		self:setPosition(newPosition)
		self:onEdited()
	end

	finish()
end

function spawnableElement:onEdited()
	self.spawnable:onEdited(true)
end

function spawnableElement:remove()
	local oldParent = self.parent
	positionable.remove(self)

	if self.spawnable then
		self.spawnable:despawn()
		self.spawnable:onParentChanged(oldParent)
	end
end

function spawnableElement:drawEntryRandomization()
	positionable.drawEntryRandomization(self)

	style.mutedText("Randomize Rotation")
	ImGui.SameLine()
	self.randomizationSettings.randomizeRotation, changed = style.trackedCheckbox(self, "##randomizeRotation", self.randomizationSettings.randomizeRotation)
	if changed then
		self.parent:applyRandomization(true)
	end

	style.mutedText("Rotation Axis")
	ImGui.SameLine()
	self.randomizationSettings.randomizeRotationAxis, changed = style.trackedCombo(self, "##randomizeRotationAxis", self.randomizationSettings.randomizeRotationAxis, { "Roll", "Pitch", "Yaw" })
	if changed then
		self.parent:applyRandomization(true)
	end

	if not self.spawnable.appIndex then return end

	style.mutedText("Randomize Appearance")
	ImGui.SameLine()
	self.randomizationSettings.randomizeAppearance, changed = style.trackedCheckbox(self, "##randomizeAppearance", self.randomizationSettings.randomizeAppearance)
	if changed then
		self.parent:applyRandomization(true)
	end
end

function spawnableElement:updateRandomization()
	if self.randomizationSettings.randomizeAppearance or self.randomizationSettings.randomizeRotation then
		if self.spawnable.spawning then
			self.spawnable.queueRespawn = true
		end
	end

	if self.randomizationSettings.randomizeRotation then
		-- The random angle is applied as a delta, so it has to start from the authored rotation every
		-- time. Without a remembered base, each re-randomization (seed edit, re-seed, adding a child
		-- to the parent group) would stack another delta onto the previous result and the rotation
		-- would drift instead of being reproducible from the seed.
		local base = self.randomizationBaseRotation

		local angle = math.random() * 360
		local euler = EulerAngles.new(0, 0, 0)
		if self.randomizationSettings.randomizeRotationAxis == 0 then
			euler.roll = angle
		elseif self.randomizationSettings.randomizeRotationAxis == 1 then
			euler.pitch = angle
		elseif self.randomizationSettings.randomizeRotationAxis == 2 then
			euler.yaw = angle
		end

		self.applyingRandomRotation = true
		if base then
			self:setRotation(utils.getEuler(base))
		else
			base = utils.fromEuler(self:getRotation())
		end
		self:setRotationDelta(euler)
		self.applyingRandomRotation = false

		self.randomizationBaseRotation = base
	end

	if self.randomizationSettings.randomizeAppearance then
		self.spawnable.appIndex = math.random(0, #self.spawnable.apps - 1)
		self.spawnable.app = self.spawnable.apps[self.spawnable.appIndex + 1] or "default"

		if not self.spawnable.spawning then
			self.spawnable:respawn()
		end
	end
end

---@param ctx serializeContext?
function spawnableElement:serialize(ctx)
	local data = positionable.serialize(self, ctx)
	data.spawnable = self.spawnable:save()
	data.randomizationBaseRotation = self.randomizationBaseRotation and utils.deepcopy(self.randomizationBaseRotation) or nil

	return data
end

function spawnableElement:export(key, length)
	return self.spawnable:export(key, length)
end

return spawnableElement
