local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

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
	local center = Vector4.new(0, 0, 0, 0)

	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		center = utils.addVector(center, entry:getPosition())
	end

	local nLeafs = math.max(1, #leafs)

	return Vector4.new(center.x / nLeafs, center.y / nLeafs, center.z / nLeafs, 0)
end

function positionableGroup:setPositionDelta(delta)
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPositionDelta(delta)
	end
end

function positionableGroup:drawRotation(rotation)
	ImGui.PushItemWidth(80 * style.viewSize)
	style.pushGreyedOut(true)
    self:drawProp(rotation.roll, "Roll", "roll")
    ImGui.SameLine()
    self:drawProp(rotation.pitch, "Pitch", "pitch")
	style.popGreyedOut(true)
    ImGui.SameLine()
	self:drawProp(rotation.yaw, "Yaw", "yaw")
end

-- TODO: Track rotation of group independently, use that for rotation axis for objects (In global space, convert group axis to local space (unit vector - (group axis - object axis)))

function positionableGroup:setRotation(delta)
	if delta.roll ~= 0 or delta.pitch ~= 0 or delta.yaw == 0 then return end

	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		relativePosition = utils.subVector(Vector4.RotateAxis(relativePosition, Vector4.new(0, 0, 1, 0), Deg2Rad(delta.yaw)), relativePosition)
		entry:setPositionDelta(relativePosition)
		entry:setRotation(delta)
	end
end

return positionableGroup