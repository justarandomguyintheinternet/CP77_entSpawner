local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups
---@class positionableGroup : positionable
---@field isUsingSpawnables boolean
local positionableGroup = setmetatable({}, { __index = positionable })

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.isUsingSpawnables = true
	o.class = utils.combine(o.class, { "positionableGroup" })

	setmetatable(o, { __index = self })
   	return o
end

---@override
function positionableGroup:load(data)
	positionable.load(self, data)

	self.pos = utils.getVector(data.pos)
end

---Draw func if this is just a sub group
---@protected
function positionableGroup:drawProperties()
	self.pos = self:getCenter()

	positionable.drawProperties(self)
end

function positionableGroup:getDirection(direction)
	local leafs = self:getPositionableLeafs()
	local dir = Vector4.new(0, 0, 0, 0)

	for _, entry in pairs(leafs) do
		if entry.visible then
			dir = utils.addVector(dir, entry:getDirection(direction))
		end
	end

	return Vector4.new(dir.x / #leafs, dir.y / #leafs, dir.z / #leafs, 0)
end

function positionableGroup:getCenter()
	local center = Vector4.new(0, 0, 0, 0)

	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		center = utils.addVector(center, entry:getPosition())
	end

	return Vector4.new(center.x / #leafs, center.y / #leafs, center.z / #leafs, 0)
end

---Gets all the positionable leaf objects, i.e. positionable's without childs#
---@return positionable[]
function positionableGroup:getPositionableLeafs()
	local objects = {}

	for _, entry in pairs(self.childs) do
		if utils.isA(entry, "object") then
			table.insert(objects, entry)
		elseif utils.isA(entry, "positionableGroup") then
			objects = utils.combine(objects, entry:getPositionableLeafs())
		end
	end

	return objects
end

function positionableGroup:getPosition()
	self.pos = self:getCenter()
	return self.pos
end

function positionableGroup:setPosition(delta)
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPosition(delta)
	end

	self.pos = self:getCenter()
end

function positionableGroup:setRotation(delta)
	self.pos = self:getCenter()

	local leafs = self:getPositionableLeafs()

	local deltaRotation = Quaternion.SetAxisAngle(Vector4.new(1 * delta.roll, 1 * delta.pitch, 1 * delta.yaw, 0), Deg2Rad(delta.roll * 1 + delta.pitch * 1 + delta.yaw * 1))

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), self.pos)
		relativePosition = deltaRotation:Transform(relativePosition)
		entry:setPosition(utils.addVector(self.pos, relativePosition))

		local entryRot = entry:getRotation():ToQuat()
		entry:setRotation(Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](deltaRotation, entryRot):ToEulerAngles())
	end
end

function positionableGroup:serialize()
	local data = positionable.serialize(self)
	data.pos = self:getCenter()

	return data
end

return positionableGroup