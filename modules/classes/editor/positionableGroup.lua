local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups, with position and rotation
---@class positionableGroup : positionable
---@field origin Vector4
---@field rotation EulerAngles
---@field originInitialized boolean
---@field supportsSaving boolean
local positionableGroup = setmetatable({}, { __index = positionable })

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.origin = nil
	o.rotation = nil
	o.originInitialized = false
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

function positionableGroup:load(data, silent)
	positionable.load(self, data, silent)

	-- load default values to support previous implementations
	data.origin = data.origin or self:getPosition()
	data.originInitialized = data.originInitialized or (#self.childs > 0)
	data.rotation = data.rotation or EulerAngles.new(0, 0, 0)

	self.origin = Vector4.new(data.origin.x, data.origin.y, data.origin.z, 0)
	self.originInitialized = true

	self.rotation = EulerAngles.new(data.rotation.roll, data.rotation.pitch, data.rotation.yaw)
end

function positionableGroup:serialize()
	local data = positionable.serialize(self)

	data.origin = { x = self.origin.x, y = self.origin.y, z = self.origin.z }
	data.originInitialized = self.originInitialized
	data.rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw }

	return data
end

function positionableGroup:addChild(child)
	positionable.addChild(self, child)

	if not self.originInitialized then
		self.origin = child:getPosition()
		self.originInitialized = true
	end
end

function positionableGroup:getDirection(direction)
    local groupQuat = self:getRotation():ToQuat()

    if direction == "forward" then
        return groupQuat:GetForward()
    elseif direction == "right" then
        return groupQuat:GetRight()
    elseif direction == "up" then
        return groupQuat:GetUp()
    else
		return groupQuat:GetForward()
    end
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

function positionableGroup:setOriginToCenter()
	local center = Vector4.new(0, 0, 0, 0)

	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		center = utils.addVector(center, entry:getPosition())
	end

	local nLeafs = math.max(1, #leafs)

	self.origin = Vector4.new(center.x / nLeafs, center.y / nLeafs, center.z / nLeafs, 0)
	if nLeafs > 0 then
		self.originInitialized = true
	end
end

function positionableGroup:setOrigin(v)
	self.origin = v
	self.originInitialized = true
end

function positionableGroup:getPosition()
	if self.origin == nil then
		self:setOriginToCenter()
	end
	return self.origin
end

function positionableGroup:setPosition(position)
	local delta = utils.subVector(position, self:getPosition())
	self:setPositionDelta(delta)
end

function positionableGroup:setPositionDelta(delta)
	self.origin = utils.addVector(self.origin, delta)
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
	style.popGreyedOut(not locked)
    finished = self:drawProp(rotation.roll, "Roll", "roll")
    ImGui.SameLine()
    finished = self:drawProp(rotation.pitch, "Pitch", "pitch")
    ImGui.SameLine()
	finished = self:drawProp(rotation.yaw, "Yaw", "yaw")
	self:handleRightAngleChange("yaw", shiftActive and not finished)
	style.popGreyedOut(locked)
end

function positionableGroup:setRotationIdentity()
	self.rotation = EulerAngles.new(0, 0, 0)
end

function positionableGroup:setRotation(rotation)
	if self.rotationLocked then return end

	self:setRotationDelta(utils.subEuler(rotation, self.rotation))
end

function positionableGroup:getRotation()
	if self.rotation == nil then
		self.rotation = EulerAngles.new(0, 0, 0)
	end
	return self.rotation
end

function positionableGroup:setRotationDelta(delta)
	if self.rotationLocked then return end

	self.rotation = utils.addEuler(self.rotation, delta)
	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)

		-- Apply ZXY rotation order
		if delta.yaw ~= 0 then
			relativePosition = Vector4.RotateAxis(relativePosition, Vector4.new(0, 0, 1, 0), Deg2Rad(delta.yaw)) -- Z axis (yaw)
		end
		if delta.pitch ~= 0 then
			relativePosition = Vector4.RotateAxis(relativePosition, Vector4.new(1, 0, 0, 0), Deg2Rad(delta.pitch)) -- X axis (pitch)
		end
		if delta.roll ~= 0 then
			relativePosition = Vector4.RotateAxis(relativePosition, Vector4.new(0, 1, 0, 0), Deg2Rad(delta.roll)) -- Y axis (roll)
		end

		local originalPosition = entry:getPosition()
		local newPositionDelta = utils.subVector(relativePosition, utils.subVector(originalPosition, pos))

		entry:setPositionDelta(newPositionDelta)
		
		local entryEulerAngles = entry:getRotation()
		local entryQuat = entryEulerAngles:ToQuat()
		local deltaQuat = delta:ToQuat()
		local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](deltaQuat, entryQuat):ToEulerAngles()
		entry:setRotation(newRotation)
	end
end

function positionableGroup:onEdited()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:onEdited()
	end
end

function positionableGroup:dropToSurface(_, direction)
	local leafs = self:getPositionableLeafs()
	table.sort(leafs, function (a, b)
		return a:getPosition().z < b:getPosition().z
	end)

	local task = require("modules/utils/tasks"):new()
	task.tasksTodo = #leafs
	task.taskDelay = 0.03

	for _, entry in pairs(leafs) do
		task:addTask(function ()
			entry:dropToSurface(true, direction)
			task:taskCompleted()
		end)
	end

	history.addAction(history.getElementChange(self))

	task:run(true)
end

return positionableGroup
