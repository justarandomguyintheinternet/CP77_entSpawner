local utils = require("modules/utils/utils")
local visualizer = require("modules/utils/visualizer")
local settings = require("modules/utils/settings")
local editor = require("modules/utils/editor/editor")
local Cron = require("modules/utils/Cron")
local intersection = require("modules/utils/editor/intersection")

local positionable = require("modules/classes/editor/positionable")

---Class for an element holding a spawnable
---@class spawnableElement : positionable
---@field spawnable spawnable
---@field silent boolean
local spawnableElement = setmetatable({}, { __index = positionable })

function spawnableElement:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Element"
	o.modulePath = "modules/classes/editor/spawnableElement"

	o.spawnable = nil
	o.class = utils.combine(o.class, { "spawnableElement" })
	o.expandable = false

	o.silent = false

	setmetatable(o, { __index = self })
   	return o
end

function spawnableElement:load(data, silent)
	positionable.load(self, data, silent)

	if self.spawnable then
		self.spawnable:despawn()
	end

	self.spawnable = require("modules/classes/spawn/" .. data.spawnable.modulePath):new()
    self.spawnable.object = self
    self.spawnable:loadSpawnData(data.spawnable, ToVector4(data.spawnable.position), ToEulerAngles(data.spawnable.rotation))
	self.icon = self.spawnable.icon
	if self.spawnable.scale then
		self.hasScale = true
	end
	self.silent = silent

	self:setVisible(self.visible, true)

	self.spawnable:registerSpawnedAndAttachedCallback(function (entity)
		-- Delay is needed as entities need some time (?). Its fine for other types tho...
		Cron.After(0.05, function ()
			if settings.gizmoOnSelected or editor.active then
				self:setVisualizerState(self.selected)
				self:setVisualizerDirection("none")
			end

			local original = self.selected
			self.selected = false
			self:setSelected(original)
		end)
	end)
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

function spawnableElement:setSelected(state)
	local update = self.selected ~= state

	positionable.setSelected(self, state)

	if not update or (not settings.outlineSelected and not editor.active) then return end
	if not self.spawnable:isSpawned() then return end

	if state then
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
	visualizer.showArrows(self.spawnable:getEntity(), self.visualizerState)
end

function spawnableElement:setVisualizerDirection(direction)
	positionable.setVisualizerDirection(self, direction)

	if not self.spawnable:isSpawned() then return end
	local color = "none"
	if direction == "x" or direction == "relX" or direction == "pitch" or direction == "scaleX" then color = "x" end
	if direction == "y" or direction == "relY" or direction == "roll" or direction == "scaleY" then color = "y" end
	if direction == "z" or direction == "relZ" or direction == "yaw" or direction == "scaleZ" then color = "z" end

	if not self.spawnable:isSpawned() or not self.spawnable:getEntity() or not self.visualizerState then return end

	visualizer.highlightArrow(self.spawnable:getEntity(), color)
	if direction == "x" or direction == "y" or direction == "z" then
		local diff = Quaternion.MulInverse(EulerAngles.new(0, 0, 0):ToQuat(), self:getRotation():ToQuat())
		self.spawnable:getEntity():FindComponentByName("arrows"):SetLocalOrientation(diff) -- This seems to fuck with component visibility
	else
		self.spawnable:getEntity():FindComponentByName("arrows"):SetLocalOrientation(EulerAngles.new(0, 0, 0):ToQuat())
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
end

function spawnableElement:setPositionDelta(delta)
	self.spawnable.position = utils.addVector(self.spawnable.position, delta)
	self.spawnable:update()
end

function spawnableElement:setRotation(rotation)
	self.spawnable.rotation = rotation
	self.spawnable:update()
end

function spawnableElement:setRotationDelta(delta)
	if delta.roll == 0 and delta.pitch == 0 and delta.yaw == 0 then return end

	if self.rotationRelative then
		self.spawnable.rotation = utils.addEulerRelative(self.spawnable.rotation, delta)
	else
		self.spawnable.rotation = utils.addEuler(self.spawnable.rotation, delta)
	end

	self.spawnable:update()
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
	self.spawnable.scale.x = self.spawnable.scale.x + delta.x
	self.spawnable.scale.y = self.spawnable.scale.y + delta.y
	self.spawnable.scale.z = self.spawnable.scale.z + delta.z
	if self.scaleLocked and delta.x ~= 0 then self.spawnable.scale.y = self.spawnable.scale.x  self.spawnable.scale.z = self.spawnable.scale.x end
	if self.scaleLocked and delta.y ~= 0 then self.spawnable.scale.x = self.spawnable.scale.y  self.spawnable.scale.z = self.spawnable.scale.y end
	if self.scaleLocked and delta.z ~= 0 then self.spawnable.scale.y = self.spawnable.scale.z  self.spawnable.scale.x = self.spawnable.scale.z end

	self.spawnable:updateScale(finished)
end

function spawnableElement:setScale(scale, finished)
	if not self.hasScale then return end

	self.spawnable.scale.x = scale.x
	self.spawnable.scale.y = scale.y
	self.spawnable.scale.z = scale.z

	self.spawnable:updateScale(finished)
end

function spawnableElement:dropToSurface()
	local size = self.spawnable:getSize()
	local bBox = {
		["min"] = Vector4.new(-size.x / 2, -size.y / 2, -size.z / 2, 0),
		["max"] = Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0)
	}

	local origin = intersection.getBoxIntersection(utils.subVector(self.spawnable.position, Vector4.new(0, 0, 999, 0)), Vector4.new(0, 0, 1, 0), self.spawnable.position, self.spawnable.rotation, bBox)
	if not origin.hit then return end

	origin.position.z = origin.position.z + 0.05
	local hit = editor.getRaySceneIntersection(Vector4.new(0, 0, -1, 0), origin.position, self.spawnable)

	local target = utils.multVector(hit.result.normal, -1)
	local current = origin.normal

	local quatDiff = Quaternion.MulInverse(Quaternion.BuildFromDirectionVector(), Quaternion.BuildFromDirectionVector(origin.normal))
	local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.spawnable.rotation:ToQuat(), quatDiff)

	self:setRotation(newRotation:ToEulerAngles())

	-- if hit.hit then
	-- 	self:setPosition(utils.addVector(hit.result.position, Vector4.new(0, 0, - self.spawnable.bBox.min.z, 0)))
	-- end
end

function spawnableElement:onEdited()
	self.spawnable:onEdited(true)
end

function spawnableElement:remove()
	positionable.remove(self)

	if not self.spawnable then return end
	self.spawnable:despawn()
end

function spawnableElement:serialize()
	local data = positionable.serialize(self)
	data.spawnable = self.spawnable:save()

	return data
end

function spawnableElement:export(key, length)
	return self.spawnable:export(key, length)
end

return spawnableElement