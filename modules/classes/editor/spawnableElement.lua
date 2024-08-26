local utils = require("modules/utils/utils")
local visualizer = require("modules/utils/visualizer")
local Cron = require("modules/utils/cron")
local settings = require("modules/utils/settings")

local positionable = require("modules/classes/editor/positionable")

---Class for an element holding a spawnable
---@class spawnableElement : positionable
---@field spawnable spawnable
local spawnableElement = setmetatable({}, { __index = positionable })

function spawnableElement:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Element"
	o.modulePath = "modules/classes/editor/spawnableElement"

	o.spawnable = nil
	o.class = utils.combine(o.class, { "spawnableElement" })
	o.expandable = false

	setmetatable(o, { __index = self })
   	return o
end

---@override
function spawnableElement:load(data)
	positionable.load(self, data)

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

	self:setVisible(self.visible, true)

	-- TODO; Do this on spawnable spawn
	if not settings.gizmoOnSelected then return end
	Cron.After(0.1, function ()
		self:setVisualizerState(self.selected)
		self:setVisualizerDirection("all")
	end)
end

function spawnableElement:drawProperties()
	positionable.drawProperties(self)

	self.spawnable:draw()
end

function spawnableElement:setVisible(state, fromRecursive)
	positionable.setVisible(self, state, fromRecursive)

	if self.visible == false or self.hiddenByParent then
		self.spawnable:despawn()
	else
		self.spawnable:spawn()
	end
end

function spawnableElement:setHiddenByParent(state)
	positionable.setHiddenByParent(self, state)

	if self.hiddenByParent or not self.visible then
		self.spawnable:despawn()
	else
		self.spawnable:spawn()
	end
end

function spawnableElement:setVisualizerState(state)
	positionable.setVisualizerState(self, state)

	if not self.spawnable:isSpawned() then return end
	visualizer.showArrows(self.spawnable:getEntity(), state)
end

function spawnableElement:setVisualizerDirection(direction)
	positionable.setVisualizerDirection(self, direction)

	if not self.spawnable:isSpawned() then return end
	local color = ""
	if direction == "x" or direction == "relX" or direction == "pitch" or direction == "scaleX" then color = "red" end
	if direction == "y" or direction == "relY" or direction == "roll" or direction == "scaleY" then color = "green" end
	if direction == "z" or direction == "relZ" or direction == "yaw" or direction == "scaleZ" then color = "blue" end

	visualizer.highlightArrow(self.spawnable:getEntity(), color)
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

function spawnableElement:setPosition(delta)
	self.spawnable.position = utils.addVector(self.spawnable.position, delta)
	self.spawnable:update()
end

function spawnableElement:setRotation(delta)
	if delta.roll == 0 and delta.pitch == 0 and delta.yaw == 0 then return end

	if self.rotationRelative then
		local rot
		if delta.roll ~= 0 then
			rot = Quaternion.SetAxisAngle(Vector4.new(0, 1, 0, 0), Deg2Rad(delta.roll))
		elseif delta.pitch ~= 0 then
			rot = Quaternion.SetAxisAngle(Vector4.new(1, 0, 0, 0), Deg2Rad(delta.pitch))
		elseif delta.yaw ~= 0 then
			rot = Quaternion.SetAxisAngle(Vector4.new(0, 0, 1, 0), Deg2Rad(delta.yaw))
		end
		self.spawnable.rotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self.spawnable.rotation:ToQuat(), rot):ToEulerAngles()
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
	if self.spawnable.scale then return self.spawnable.scale end
end

function spawnableElement:setScale(delta, finished)
	self.spawnable.scale.x = self.spawnable.scale.x + delta.x
	self.spawnable.scale.y = self.spawnable.scale.y + delta.y
	self.spawnable.scale.z = self.spawnable.scale.z + delta.z
	if self.scaleLocked and delta.x ~= 0 then self.spawnable.scale.y = self.spawnable.scale.x  self.spawnable.scale.z = self.spawnable.scale.x end
	if self.scaleLocked and delta.y ~= 0 then self.spawnable.scale.x = self.spawnable.scale.y  self.spawnable.scale.z = self.spawnable.scale.y end
	if self.scaleLocked and delta.z ~= 0 then self.spawnable.scale.y = self.spawnable.scale.z  self.spawnable.scale.x = self.spawnable.scale.z end

	self.spawnable:updateScale(finished)
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

return spawnableElement