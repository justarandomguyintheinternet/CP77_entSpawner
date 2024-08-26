local utils = require("modules/utils/utils")

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

	self:setVisible(self.visible, true)
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
	self.spawnable.rotation = utils.addEuler(self.spawnable.rotation, delta)
	self.spawnable:update()
end

function spawnableElement:getPosition()
	return self.spawnable.position
end

function spawnableElement:getRotation()
	return self.spawnable.rotation
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