local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups, with position and rotation
---@class positionableGroup : positionable
---@field yaw number
---@field supportsSaving boolean
local positionableGroup = setmetatable({}, { __index = positionable })

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.yaw = 0
	o.class = utils.combine(o.class, { "positionableGroup" })
	o.quickOperations = {
		[IconGlyphs.ContentSaveOutline] = {
			operation = positionableGroup.save,
			condition = function (instance)
				return instance.parent ~= nil and instance.parent:isRoot(true)
			end
		}
	}
	o.supportsSaving = true

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

function positionableGroup:setPosition(position)
	local delta = utils.subVector(position, self:getPosition())
	self:setPositionDelta(delta)
end

function positionableGroup:setPositionDelta(delta)
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPositionDelta(delta)
	end
end

function positionableGroup:drawRotation(rotation)
	local locked = self.rotationLocked
	local shiftActive = ImGui.IsKeyDown(ImGuiKey.LeftShift) and not ImGui.IsMouseDragging(0, 0)
	local finished = false

	ImGui.PushItemWidth(80 * style.viewSize)
	style.pushGreyedOut(true)
    finished = self:drawProp(rotation.roll, "Roll", "roll")
    ImGui.SameLine()
    finished = self:drawProp(rotation.pitch, "Pitch", "pitch")
	style.popGreyedOut(not locked)
    ImGui.SameLine()
	finished = self:drawProp(rotation.yaw, "Yaw", "yaw")
	self:handleRightAngleChange("yaw", shiftActive and not finished)
	style.popGreyedOut(locked)
end

-- TODO: Track rotation of group independently, use that for rotation axis for objects (In global space, convert group axis to local space (unit vector - (group axis - object axis)))

function positionableGroup:setRotation(rotation)
	if self.rotationLocked then return end

	self:setRotationDelta(EulerAngles.new(0, 0, rotation.yaw - self.yaw))
	self.yaw = rotation.yaw
end

function positionableGroup:getRotation()
	return EulerAngles.new(0, 0, self.yaw)
end

function positionableGroup:setRotationDelta(delta)
	if delta.roll ~= 0 or delta.pitch ~= 0 or delta.yaw == 0 or self.rotationLocked then return end

	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		relativePosition = utils.subVector(Vector4.RotateAxis(relativePosition, Vector4.new(0, 0, 1, 0), Deg2Rad(delta.yaw)), relativePosition)
		entry:setPositionDelta(relativePosition)
		entry:setRotationDelta(delta)
	end
end

function positionableGroup:onEdited()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:onEdited()
	end
end

function positionableGroup:dropToSurface(_, direction, physicalOnly, applyAngle)
	local leafs = self:getPositionableLeafs()
	table.sort(leafs, function (a, b)
		return a:getPosition().z < b:getPosition().z
	end)

	local task = require("modules/utils/tasks"):new()
	task.tasksTodo = #leafs
	task.taskDelay = 0.03

	for _, entry in pairs(leafs) do
		task:addTask(function ()
			entry:dropToSurface(true, direction, physicalOnly, applyAngle)
			task:taskCompleted()
		end)
	end

	history.addAction(history.getElementChange(self))

	task:run(true)
end

return positionableGroup