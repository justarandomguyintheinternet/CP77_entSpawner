local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local intersection = require("modules/utils/editor/intersection")
local editor = require("modules/utils/editor/editor")

local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups, with position and rotation
---@class positionableGroup : positionable
---@field origin Vector4
---@field rotation EulerAngles
---@field rotationQuat Quaternion
---@field rotationDragState table?
---@field rotationUIDragStart EulerAngles?
---@field rotationUIDragStartQuat Quaternion?
---@field rotationUIDragValue table
---@field originInitialized boolean
---@field supportsSaving boolean
local positionableGroup = setmetatable({}, { __index = positionable })

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.origin = nil
	o.rotation = nil
	o.rotationQuat = nil
	o.rotationDragState = nil
	o.rotationUIDragStart = nil
	o.rotationUIDragStartQuat = nil
	o.rotationUIDragValue = { roll = nil, pitch = nil }
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
	self.rotationQuat = self.rotation:ToQuat()
end

function positionableGroup:serialize()
	local data = positionable.serialize(self)

	self.origin = self.origin or self:getPosition()
	self.rotation = self.rotation or EulerAngles.new(0, 0, 0)
	self.rotationQuat = self.rotationQuat or self.rotation:ToQuat()
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

	if #leafs == 0 then
		local pos = self:getPosition()
		return pos, pos
	end

	for _, entry in pairs(leafs) do
		local entrySize = entry:getSize()
		local entryPos = entry:getCenter()

		if entrySize and entryPos then
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
		end
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
	local unstableZoneThreshold = 3.6
	local function drawLiveAngleFromStart(value, name, axis)
		local steps = settings.rotSteps
		local formatText = "%.2f"

		if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
			steps = steps * 0.1 * settings.precisionMultiplier
			formatText = "%.3f"
		end

		local displayValue = self.rotationUIDragValue[axis] or value
		local inUnstableZone = math.abs(displayValue) <= unstableZoneThreshold
		if inUnstableZone then
			ImGui.PushStyleColor(ImGuiCol.FrameBg, 1.0, 0.55, 0.0, 0.35)
			ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 1.0, 0.55, 0.0, 0.45)
			ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 1.0, 0.55, 0.0, 0.55)
		end
		local newValue, changed = ImGui.DragFloat("##" .. name, displayValue, steps, -99999, 99999, formatText .. " " .. name, ImGuiSliderFlags.NoRoundToFormat)
		if inUnstableZone then
			ImGui.PopStyleColor(3)
		end
		self.controlsHovered = (ImGui.IsItemHovered() or ImGui.IsItemActive()) or self.controlsHovered

		if (ImGui.IsItemHovered() or ImGui.IsItemActive()) and axis ~= self.visualizerDirection then
			self:setVisualizerDirection(axis)
		end

		local finishedAxis = ImGui.IsItemDeactivatedAfterEdit()

		if changed and not history.propBeingEdited then
			history.addAction(history.getElementChange(self))
			history.propBeingEdited = true
		end

		if changed then
			if not self.rotationUIDragStart then
				self.rotationUIDragStart = EulerAngles.new(rotation.roll, rotation.pitch, rotation.yaw)
				self.rotationUIDragStartQuat = self.rotationQuat or self:getRotation():ToQuat()
				self.rotationUIDragValue.roll = rotation.roll
				self.rotationUIDragValue.pitch = rotation.pitch
				self:beginRotationDrag()
			end

			local start = self.rotationUIDragStart
			local startQuat = self.rotationUIDragStartQuat or start:ToQuat()
			local angleDelta = (axis == "roll" and (newValue - start.roll) or (newValue - start.pitch))
			local localAxis = axis == "roll" and Vector4.new(0, 1, 0, 0) or Vector4.new(1, 0, 0, 0)
			local worldAxis = startQuat:Transform(localAxis):Normalize()
			local stepQuat = Quaternion.SetAxisAngle(worldAxis, Deg2Rad(angleDelta))
			local targetQuat = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](stepQuat, startQuat)

			self.rotationUIDragValue[axis] = newValue
			self:applyRotationDrag(stepQuat, targetQuat, targetQuat:ToEulerAngles())
		end

		if finishedAxis then
			self.rotationUIDragStart = nil
			self.rotationUIDragStartQuat = nil
			self.rotationUIDragValue.roll = nil
			self.rotationUIDragValue.pitch = nil
			self:endRotationDrag()
			history.propBeingEdited = false
			self:onEdited()
		end

		return finishedAxis
	end

	ImGui.PushItemWidth(80 * style.viewSize)
	style.popGreyedOut(not locked)
    finished = drawLiveAngleFromStart(rotation.roll, "Roll", "roll")
	self:handleRightAngleChange("roll", shiftActive and not finished)
    ImGui.SameLine()
    finished = drawLiveAngleFromStart(rotation.pitch, "Pitch", "pitch") or finished
	self:handleRightAngleChange("pitch", shiftActive and not finished)
    ImGui.SameLine()
	finished = self:drawProp(rotation.yaw, "Yaw", "yaw")
	self:handleRightAngleChange("yaw", shiftActive and not finished)
	style.popGreyedOut(locked)
	ImGui.SameLine()
	style.mutedText(IconGlyphs.AlertOutline)
	style.tooltip("Experimental Roll/Pitch\nUnreliable between -3.60° and 3.60°\nUse with caution")
end

function positionableGroup:setRotationIdentity()
	self.rotation = EulerAngles.new(0, 0, 0)
	self.rotationQuat = self.rotation:ToQuat()
end

function positionableGroup:beginRotationDrag()
	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local entries = {}

	for _, entry in pairs(leafs) do
		table.insert(entries, {
			entry = entry,
			startRelativePosition = utils.subVector(entry:getPosition(), pos),
			startRotationQuat = entry:getRotation():ToQuat()
		})
	end

	self.rotationDragState = {
		position = pos,
		entries = entries
	}
end

---@param stepQuat Quaternion
---@param targetQuat Quaternion
---@param targetEuler EulerAngles?
function positionableGroup:applyRotationDrag(stepQuat, targetQuat, targetEuler)
	if self.rotationLocked then return end
	if not self.rotationDragState then
		self:beginRotationDrag()
	end

	local state = self.rotationDragState
	self.rotationQuat = targetQuat
	self.rotation = targetEuler or targetQuat:ToEulerAngles()

	for _, data in pairs(state.entries) do
		local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](stepQuat, data.startRotationQuat):ToEulerAngles()
		data.entry:setRotation(newRotation)

		local newPosition = utils.addVector(state.position, stepQuat:Transform(data.startRelativePosition))
		data.entry:setPosition(newPosition)
	end
end

function positionableGroup:endRotationDrag()
	self.rotationDragState = nil
end

function positionableGroup:setRotation(rotation)
	if self.rotationLocked then return end

	self.rotationDragState = nil
	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local currentQuat = self.rotationQuat or self:getRotation():ToQuat()
	local targetQuat = rotation:ToQuat()
	local deltaQuat = Quaternion.MulInverse(targetQuat, currentQuat)

	self.rotationQuat = targetQuat
	self.rotation = EulerAngles.new(rotation.roll, rotation.pitch, rotation.yaw)

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		local entryQuat = entry:getRotation():ToQuat()

		local newRotation = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](deltaQuat, entryQuat):ToEulerAngles()
		entry:setRotation(newRotation)

		local newPosition = utils.addVector(pos, deltaQuat:Transform(relativePosition))
		entry:setPosition(newPosition)
	end
end

function positionableGroup:getRotation()
	if self.rotation == nil then
		self.rotation = EulerAngles.new(0, 0, 0)
	end
	if self.rotationQuat == nil then
		self.rotationQuat = self.rotation:ToQuat()
	end
	return self.rotation
end

function positionableGroup:setRotationDelta(delta)
	if self.rotationLocked then return end

	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local workingQuat = self.rotationQuat or self:getRotation():ToQuat()
	local deltaQuat = EulerAngles.new(0, 0, 0):ToQuat()

	local function applyLocalAxisDelta(localAxis, angleDeg)
		if angleDeg == 0 then return end

		local worldAxis = workingQuat:Transform(localAxis):Normalize()
		local stepQuat = Quaternion.SetAxisAngle(worldAxis, Deg2Rad(angleDeg))

		deltaQuat = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](stepQuat, deltaQuat)
		workingQuat = Game['OperatorMultiply;QuaternionQuaternion;Quaternion'](stepQuat, workingQuat)
	end

	-- Keep mapping aligned with existing element behavior:
	-- roll -> local Y, pitch -> local X, yaw -> local Z.
	applyLocalAxisDelta(Vector4.new(0, 1, 0, 0), delta.roll)
	applyLocalAxisDelta(Vector4.new(1, 0, 0, 0), delta.pitch)
	applyLocalAxisDelta(Vector4.new(0, 0, 1, 0), delta.yaw)

	self.rotationQuat = workingQuat
	self.rotation = workingQuat:ToEulerAngles()

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

	local excludeDict = excludeDict or {}
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

function positionableGroup:dropChildrenToSurface(_, direction, excludeSelf, excludeDict)
	local leafs = self.childs
	table.sort(leafs, function (a, b)
		return a:getPosition().z < b:getPosition().z
	end)

	local excludeDict = excludeDict or {}
	if excludeSelf then
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
