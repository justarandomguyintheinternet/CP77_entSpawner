local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")

local element = require("modules/classes/editor/element")

---Element with position and rotation, handles the rendering / editing of those. Values have to be provided by the inheriting class
---@class positionable : element
---@field transformExpanded boolean
---@field rotationRelative boolean
local positionable = setmetatable({}, { __index = element })

function positionable:new(sUI)
	local o = element.new(self, sUI)

	o.modulePath = "modules/classes/editor/positionable"

	o.transformExpanded = true
	o.rotationRelative = false
	o.class = utils.combine(o.class, { "positionable" })

	setmetatable(o, { __index = self })
   	return o
end

---@override
function positionable:load(data)
	element.load(self, data)
	self.transformExpanded = data.transformExpanded
	self.rotationRelative = data.rotationRelative
	if self.transformExpanded == nil then self.transformExpanded = true end
	if self.rotationRelative == nil then self.rotationRelative = false end
end

---@protected
function positionable:drawProperties()
	ImGui.SetNextItemOpen(self.transformExpanded)
	self.transformExpanded = ImGui.TreeNodeEx("Transform", ImGuiTreeNodeFlags.SpanFullWidth)

	if self.transformExpanded then
		local position = self:getPosition()
		local rotation = self:getRotation()

		self:drawPosition(position)
		self:drawRelativePosition()
		self:drawRotation(rotation)
		ImGui.TreePop()
	end
end

---@protected
function positionable:drawProp(prop, name, axis)
	local steps = (axis == "roll" or axis == "pitch" or axis == "yaw") and settings.rotSteps or settings.posSteps

    local newValue, changed = ImGui.DragFloat("##" .. name, prop, steps, -99999, 99999, "%.2f " .. name)
	if ImGui.IsItemDeactivatedAfterEdit() then history.propBeingEdited = false end
	if changed and not history.propBeingEdited then
		history.addAction(history.getElementChange(self))
		history.propBeingEdited = true
	end
    if changed then
		if axis == "x" then self:setPosition(Vector4.new(newValue - prop, 0, 0, 0)) end
		if axis == "y" then self:setPosition(Vector4.new(0, newValue - prop, 0, 0)) end
		if axis == "z" then self:setPosition(Vector4.new(0, 0, newValue - prop, 0)) end
		if axis == "relX" then
			local v = self:getDirection("right")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		end
		if axis == "relY" then
			local v = self:getDirection("forward")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		end
		if axis == "relZ" then
			local v = self:getDirection("up")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		end
		if axis == "roll" then
			self:setRotation(EulerAngles.new(newValue - prop, 0, 0))
		end
		if axis == "pitch" then
			self:setRotation(EulerAngles.new(0, newValue - prop, 0))
		end
		if axis == "yaw" then
			self:setRotation(EulerAngles.new(0, 0, newValue - prop))
		end
    end
end

---@protected
function positionable:drawPosition(position)
	ImGui.PushItemWidth(80 * style.viewSize)
	self:drawProp(position.x, "X", "x")
    ImGui.SameLine()
	self:drawProp(position.y, "Y", "y")
    ImGui.SameLine()
	self:drawProp(position.z, "Z", "z")
    ImGui.PopItemWidth()

    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.AccountArrowLeftOutline) then
		history.addAction(history.getElementChange(self))
		local pos = Game.GetPlayer():GetWorldPosition()
        self:setPosition(Vector4.new(pos.x - position.x, pos.y - position.y, pos.z - position.z, 0))
    end
    style.pushButtonNoBG(false)
	if ImGui.IsItemHovered() then style.setCursorRelative(5, 5) end
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
function positionable:drawRotation(rotation)
    ImGui.PushItemWidth(80 * style.viewSize)
    self:drawProp(rotation.roll, "Roll", "roll")
    ImGui.SameLine()
    self:drawProp(rotation.pitch, "Pitch", "pitch")
    ImGui.SameLine()
	self:drawProp(rotation.yaw, "Yaw", "yaw")
    ImGui.SameLine()
	self.rotationRelative = ImGui.Checkbox("Relative", self.rotationRelative)
    ImGui.PopItemWidth()
end

function positionable:setPosition(delta)
end

function positionable:getPosition()
	return Vector4.new(0, 0, 0, 0)
end

function positionable:setRotation(delta)
end

function positionable:getRotation()
	return EulerAngles.new(0, 0, 0)
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

	data.transformExpanded = self.transformExpanded
	data.rotationRelative = self.rotationRelative
	data.pos = utils.fromVector(self:getPosition()) -- For savedUI

	return data
end

return positionable