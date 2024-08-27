local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups, with position and rotation
---@class positionableGroup : positionable
local positionableGroup = setmetatable({}, { __index = positionable })

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.class = utils.combine(o.class, { "positionableGroup" })
	o.quickOperations = {
		[IconGlyphs.ContentSaveOutline] = {
			operation = positionableGroup.save,
			condition = function (instance)
				return instance.parent ~= nil and instance.parent:isRoot(true)
			end
		}
	}

	setmetatable(o, { __index = self })
   	return o
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

	local nLeafs = math.max(1, #leafs)

	return Vector4.new(center.x / nLeafs, center.y / nLeafs, center.z / nLeafs, 0)
end

---Gets all the positionable leaf objects, i.e. positionable's without childs
---@return positionable[]
function positionableGroup:getPositionableLeafs()
	local objects = {}

	for _, entry in pairs(self.childs) do
		if utils.isA(entry, "spawnableElement") then
			table.insert(objects, entry)
		elseif utils.isA(entry, "positionableGroup") then
			objects = utils.combine(objects, entry:getPositionableLeafs())
		end
	end

	return objects
end

function positionableGroup:getPosition()
	return self:getCenter()
end

function positionableGroup:setPosition(delta)
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPosition(delta)
	end
end

function positionableGroup:setRotation(delta)
	local pos = self:getCenter()

	local leafs = self:getPositionableLeafs()

	local deltaRotation = Quaternion.SetAxisAngle(Vector4.new(1 * delta.roll, 1 * delta.pitch, 1 * delta.yaw, 0), Deg2Rad(delta.roll * 1 + delta.pitch * 1 + delta.yaw * 1))

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		relativePosition = deltaRotation:Transform(relativePosition)
		entry:setPosition(utils.addVector(pos, relativePosition))

		local entryRot = entry:getRotation():ToQuat()
		entry:setRotation(Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](deltaRotation, entryRot):ToEulerAngles())
	end
end

return positionableGroup