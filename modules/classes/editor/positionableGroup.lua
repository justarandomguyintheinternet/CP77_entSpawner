local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")
local editor = require("modules/utils/editor/editor")

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
	o.applyRotationWhenDropped = false

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

	self.origin = self.origin or self:getPosition()
	self.rotation = self.rotation or EulerAngles.new(0, 0, 0)
	self.originInitialized = self.originInitialized or (#self.childs > 0)

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

function positionableGroup:getWorldMinMax()
	local min = Vector4.new(math.huge, math.huge, math.huge, 0)
	local max = Vector4.new(-math.huge, -math.huge, -math.huge, 0)

	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		local entrySize = entry:getSize()
		local entryPos = entry:getCenter()

		if not entrySize or not entryPos then
			goto continue
		end

		local entryMin = utils.subVector(entryPos, utils.multVector(entrySize, 0.5))
		local entryMax = utils.addVector(entryPos, utils.multVector(entrySize, 0.5))

		min = Vector4.new(
			math.min(min.x, entryMin.x),
			math.min(min.y, entryMin.y),
			math.min(min.z, entryMin.z),
			0
		)

		max = Vector4.new(
			math.max(max.x, entryMax.x),
			math.max(max.y, entryMax.y),
			math.max(max.z, entryMax.z),
			0
		)
		::continue::
	end

	return min, max
end

function positionableGroup:getCenter()
	local min, max = self:getWorldMinMax()
	return utils.addVector(utils.multVector(utils.subVector(max, min), 0.5), min)
end

function positionableGroup:setOriginToCenter()
	if #self.childs == 0 then return end
	self.origin = self:getCenter()
	self.originInitialized = true
end

function positionableGroup:setOrigin(v)
	self.origin = v
	self.originInitialized = true
end

function positionableGroup:getPosition()
	if self.origin == nil then
		if #self.childs == 0 then
			self.origin = Vector4.new(0, 0, 0, 1)
		else
			self:setOriginToCenter()
		end
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

	local deltaQuat = delta:ToQuat()

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		local entryQuat = entry:getRotation():ToQuat()

		local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](deltaQuat, entryQuat):ToEulerAngles()
		entry:setRotation(newRotation)

		local newPosition = utils.addVector(pos, deltaQuat:Transform(relativePosition))
		entry:setPosition(newPosition)
	end
end

function positionableGroup:onEdited()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:onEdited()
	end
end

function positionableGroup:getSize()
	local min, max = self:getWorldMinMax()
	return utils.subVector(max, min)
end

function positionableGroup:dropToSurface(isMulti, direction, excludeDict)
	if isMulti then self:dropChildrenToSurface(isMulti, direction); return end

	local excludeDict = {}
	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		excludeDict[entry.id] = true
	end

	local size = self:getSize()
	local bBox = {
		min = Vector4.new(-size.x / 2, -size.y / 2, -size.z / 2, 0),
		max = Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0)
	}

	local toOrigin = utils.multVector(direction, -999)
	local origin = intersection.getBoxIntersection(utils.subVector(self:getCenter(), toOrigin), utils.multVector(direction, -1), self:getCenter(), self:getRotation(), bBox --[[ -9 +9 ]])

	if not origin.hit then return end

	origin.position = utils.addVector(origin.position, utils.multVector(direction, 0.025))
	local hit = editor.getRaySceneIntersection(direction, origin.position, excludeDict, true)

	if not hit.hit then return end

	local target = utils.multVector(hit.result.normal, -1)
	local current = origin.normal

	local axis = current:Cross(target)
	local angle = Vector4.GetAngleBetween(current, target)
	local diff = Quaternion.SetAxisAngle(self:getRotation():ToQuat():TransformInverse(axis):Normalize(), math.rad(angle))

	if not grouped then
		history.addAction(history.getElementChange(self))
	end

	local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](self:getRotation():ToQuat(), diff)
	if self.applyRotationWhenDropped then
		self:setRotation(newRotation:ToEulerAngles())
	end

	local offset = utils.multVecXVec(newRotation:Transform(origin.normal), Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0))
	local newCenter = utils.addVector(hit.result.unscaledHit or hit.result.position, utils.multVector(hit.result.normal, offset:Length())) -- phyiscal hits dont have unscaledHit

	if hit.hit then
		self:setPosition(utils.addVector(newCenter, utils.subVector(self:getPosition(), self:getCenter())))
		self:onEdited()
	end
end

function positionableGroup:dropChildrenToSurface(_, direction, excludeSelf)
	local leafs = self:getPositionableLeafs()
	table.sort(leafs, function (a, b)
		return a:getPosition().z < b:getPosition().z
	end)

	local excludeDict = nil
	if excludeSelf then
		excludeDict = {}
		for _, entry in pairs(leafs) do
			excludeDict[entry.id] = true
		end
	end

	local task = require("modules/utils/tasks"):new()
	task.tasksTodo = #leafs
	task.taskDelay = 0.03

	for _, entry in pairs(leafs) do
		task:addTask(function ()
			entry:dropToSurface(false, direction, excludeDict)
			task:taskCompleted()
		end)
	end

	history.addAction(history.getElementChange(self))

	task:run(true)
end

return positionableGroup
