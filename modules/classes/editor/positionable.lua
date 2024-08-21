local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")

local element = require("modules/classes/editor/element")

---Element with position and rotation
---@class positionable : element
---@field pos Vector4
---@field rot EulerAngles
---@field transformExpanded boolean
---@field rotationRelative boolean
local positionable = setmetatable({}, { __index = element })

function positionable:new(sUI)
	local o = element.new(self, sUI)

	o.modulePath = "modules/classes/editor/positionable"

	o.pos = Vector4.new(0, 0, 0, 0)
    o.rot = EulerAngles.new(0, 0, 0)
	o.transformExpanded = true
	o.rotationRelative = false
	o.class = utils.combine(o.class, { "positionable" })

	setmetatable(o, { __index = self })
   	return o
end

---@override
function positionable:load(data)
	element.load(self, data)

	self.pos = utils.getVector(data.pos)
	self.rot = utils.getEuler(data.rot)
	self.transformExpanded = data.transformExpanded == nil and true or data.transformExpanded
	self.rotationRelative = data.rotationRelative == nil and false or data.rotationRelative
end

---@protected
function positionable:drawProperties()
	ImGui.SetNextItemOpen(self.transformExpanded)
	self.transformExpanded = ImGui.TreeNodeEx("Transform", ImGuiTreeNodeFlags.SpanFullWidth + ImGuiTreeNodeFlags.NoTreePushOnOpen)

	if self.transformExpanded then
		self:drawPosition()
		self:drawRelativePosition()
		self:drawRotation()
		ImGui.TreePop()
	end
end

---@protected
function positionable:drawProp(prop, name, axis)
	local steps = (axis == "roll" or axis == "pitch" or axis == "yaw") and settings.rotSteps or settings.posSteps

    prop, changed = ImGui.DragFloat("##" .. name, prop, steps, -99999, 99999, "%.2f " .. name)
	if ImGui.IsItemDeactivatedAfterEdit() then history.propBeingEdited = false end
	if changed and not history.propBeingEdited then
		history.addAction(history.getElementChange(self))
		history.propBeingEdited = true
	end
    if changed then
		if axis == "x" then self:setPosition(Vector4.new(prop - self.pos[axis], 0, 0, 0)) end
		if axis == "y" then self:setPosition(Vector4.new(0, prop - self.pos[axis], 0, 0)) end
		if axis == "z" then self:setPosition(Vector4.new(0, 0, prop - self.pos[axis], 0)) end
		if axis == "relX" then
			local v = self:getDirection("right")
			self:setPosition(Vector4.new((v.x * prop), (v.y * prop), (v.z * prop), 0))
		end
		if axis == "relY" then
			local v = self:getDirection("forward")
			self:setPosition(Vector4.new((v.x * prop), (v.y * prop), (v.z * prop), 0))
		end
		if axis == "relZ" then
			local v = self:getDirection("up")
			self:setPosition(Vector4.new((v.x * prop), (v.y * prop), (v.z * prop), 0))
		end
		if axis == "roll" then
			self:setRotation(EulerAngles.new(prop - self.rot.roll, 0, 0))
		end
		if axis == "pitch" then
			self:setRotation(EulerAngles.new(0, prop - self.rot.pitch, 0))
		end
		if axis == "yaw" then
			self:setRotation(EulerAngles.new(0, 0, prop - self.rot.yaw))
		end
    end
end

---@protected
function positionable:drawPosition()
	ImGui.PushItemWidth(80 * style.viewSize)
	self:drawProp(self.pos.x, "X", "x")
    ImGui.SameLine()
	self:drawProp(self.pos.y, "Y", "y")
    ImGui.SameLine()
	self:drawProp(self.pos.z, "Z", "z")
    ImGui.PopItemWidth()

    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.AccountArrowLeftOutline) then
		history.addAction(history.getElementChange(self))
		local pos = Game.GetPlayer():GetWorldPosition()
        self:setPosition(Vector4.new(pos.x - self.pos.x, pos.y - self.pos.y, pos.z - self.pos.z, 0))
    end
    style.pushButtonNoBG(false)
	style.setCursorRelative(5, 5)
	style.tooltip("Set to player position")
end

---@protected
function positionable:drawRelativePosition()
    ImGui.PushItemWidth(80 * style.viewSize)
    self:drawProp(0, "Rel X", "relX")
	ImGui.SameLine()
    self:drawProp(0, "Rel Y", "relY")
	ImGui.SameLine()
    self:drawProp(0, "Rel Z", "relZ")
    ImGui.PopItemWidth()
end

---@protected
function positionable:drawRotation()
    ImGui.PushItemWidth(80 * style.viewSize)
    self:drawProp(self.rot.roll, "Roll", "roll")
    ImGui.SameLine()
    self:drawProp(self.rot.pitch, "Pitch", "pitch")
    ImGui.SameLine()
	self:drawProp(self.rot.yaw, "Yaw", "yaw")
    ImGui.SameLine()
	self.rotationRelative = ImGui.Checkbox("Relative", self.rotationRelative)
    ImGui.PopItemWidth()
end

function positionable:setPosition(delta)
	self.pos = utils.addVector(self.pos, delta)
end

function positionable:getPosition()
	return self.pos
end

function positionable:setRotation(delta)
	self.rot = utils.addEuler(self.rot, delta)
end

function positionable:getRotation()
	return self.rot
end

function positionable:getDirection(direction)
	if direction == "right" then
		return Vector4.new(1, 0, 0, 0)
	elseif direction == "forward" then
		return Vector4.new(0, 1, 0, 0)
	elseif direction == "up" then
		return Vector4.new(0, 0, 1, 0)
	end
end

function positionable:serialize()
	local data = element.serialize(self)

	data.pos = utils.fromVector(self.pos)
	data.rot = utils.fromEuler(self.rot)
	data.transformExpanded = self.transformExpanded
	data.rotationRelative = self.rotationRelative

	return data
end

return positionable