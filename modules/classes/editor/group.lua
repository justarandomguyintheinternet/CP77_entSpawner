local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups
---@class group : positionable
---@field isUsingSpawnables boolean
local group = setmetatable({}, { __index = positionable })

function group:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/group"

	o.isUsingSpawnables = true
	o.class = utils.combine(o.class, { "group" })

	setmetatable(o, { __index = self })
   	return o
end

---@override
function group:load(data)
	positionable.load(self, data)

	self.pos = utils.getVector(data.pos)
end

---Draw func if this is just a sub group
---@protected
function group:drawProperties()
	self.pos = self:getCenter()

	positionable.drawProperties(self)
end

function group:getDirection(direction)
	local leafs = self:getPositionableLeafs()
	local dir = Vector4.new(0, 0, 0, 0)

	for _, entry in pairs(leafs) do
		dir = utils.addVector(dir, entry:getDirection(direction))
	end

	return Vector4.new(dir.x / #leafs, dir.y / #leafs, dir.z / #leafs, 0)
end

function group:getCenter()
	local center = Vector4.new(0, 0, 0, 0)

	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		center = utils.addVector(center, entry:getPosition())
	end

	return Vector4.new(center.x / #leafs, center.y / #leafs, center.z / #leafs, 0)
end

---Gets all the positionable leaf objects, i.e. positionable's without childs#
---@return positionable[]
function group:getPositionableLeafs()
	local objects = {}

	for _, entry in pairs(self.childs) do
		if utils.isA(entry, "object") then
			table.insert(objects, entry)
		elseif utils.isA(entry, "group") then
			objects = utils.combine(objects, entry:getPositionableLeafs())
		end
	end

	return objects
end

function group:getPosition()
	self.pos = self:getCenter()
	return self.pos
end

function group:setPosition(delta)
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPosition(delta)
	end

	self.pos = self:getCenter()
end

function group:setRotation(delta)
	self.pos = self:getCenter()

	local leafs = self:getPositionableLeafs()

end

function group:serialize()
	local data = positionable.serialize(self)
	data.pos = self:getCenter()

	return data
end

return group