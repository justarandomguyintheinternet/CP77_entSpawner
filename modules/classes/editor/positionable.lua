local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")
local style = require("modules/ui/style")

local element = require("modules/classes/editor/element")

---Element with position, rotation and optionally scale, handles the rendering / editing of those. Values have to be provided by the inheriting class
---@class positionable : element
---@field transformExpanded boolean
---@field rotationRelative boolean
---@field hasScale boolean
---@field scaleLocked boolean
---@field visualizerState boolean
---@field visualizerDirection string
---@field controlsHovered boolean
local positionable = setmetatable({}, { __index = element })

function positionable:new(sUI)
	local o = element.new(self, sUI)

	o.modulePath = "modules/classes/editor/positionable"

	o.transformExpanded = true
	o.rotationRelative = false
	o.hasScale = false
	o.scaleLocked = true

	o.visualizerState = false
	o.visualizerDirection = "all"
	o.controlsHovered = false

	o.class = utils.combine(o.class, { "positionable" })

	setmetatable(o, { __index = self })
   	return o
end

function positionable:load(data, silent)
	element.load(self, data, silent)
	self.transformExpanded = data.transformExpanded
	self.rotationRelative = data.rotationRelative
	self.scaleLocked = data.scaleLocked
	if self.scaleLocked == nil then self.scaleLocked = true end
	if self.transformExpanded == nil then self.transformExpanded = true end
	if self.rotationRelative == nil then self.rotationRelative = false end
end

function positionable:drawTransform()
	local position = self:getPosition()
	local rotation = self:getRotation()
	local scale = self:getScale()
	self.controlsHovered = false

	self:drawPosition(position)
	self:drawRelativePosition()
	self:drawRotation(rotation)
	self:drawScale(scale)

	if not self.controlsHovered and self.visualizerDirection ~= "all" then
		if not settings.gizmoOnSelected then
			self:setVisualizerState(false) -- Set vis state first, as loading the mesh app (vis direction) can screw with it
		end
		self:setVisualizerDirection("all")
	end
end

function positionable:getProperties()
	local properties = element.getProperties(self)

	table.insert(properties, {
		id = "transform",
		name = "Transform",
		draw = function ()
			self:drawTransform()
		end
	})

	return properties
end

function positionable:setSelected(state)
	if state ~= self.selected and not self.hovered and settings.gizmoOnSelected then
		self:setVisualizerState(state)
	end

	element.setSelected(self, state)
end

function positionable:setHovered(state)
	if (not self.selected or not settings.gizmoOnSelected) and state ~= self.hovered then
		self:setVisualizerState(state)
		self:setVisualizerDirection("all")
	end

	element.setHovered(self, state)
end

function positionable:setVisualizerDirection(direction)
	if not settings.gizmoOnSelected then
		if direction ~= "all" and not self.hovered and not self.visualizerState then
			self:setVisualizerState(true)
		end
	end
	self.visualizerDirection = direction
end

function positionable:setVisualizerState(state)
	if not settings.gizmoActive then state = false end

	self.visualizerState = state
end

function positionable:onEdited() end

---@protected
function positionable:drawProp(prop, name, axis)
	local steps = (axis == "roll" or axis == "pitch" or axis == "yaw") and settings.rotSteps or settings.posSteps
	local formatText = "%.2f"

	if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
		steps = steps * 0.1 * settings.precisionMultiplier -- Shift usually is a x10 multiplier, so get rid of that first
		formatText = "%.3f"
	end

    local newValue, changed = ImGui.DragFloat("##" .. name, prop, steps, -99999, 99999, formatText .. " " .. name, ImGuiSliderFlags.NoRoundToFormat)
	self.controlsHovered = (ImGui.IsItemHovered() or ImGui.IsItemActive()) or self.controlsHovered
	if (ImGui.IsItemHovered() or ImGui.IsItemActive()) and axis ~= self.visualizerDirection then
		self:setVisualizerDirection(axis)
	end

	local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		history.propBeingEdited = false
		self:onEdited()
	end
	if changed and not history.propBeingEdited then
		history.addAction(history.getElementChange(self))
		history.propBeingEdited = true
	end
    if changed or finished then
		if axis == "x" then
			self:setPosition(Vector4.new(newValue - prop, 0, 0, 0))
		elseif axis == "y" then
			self:setPosition(Vector4.new(0, newValue - prop, 0, 0))
		elseif axis == "z" then
			self:setPosition(Vector4.new(0, 0, newValue - prop, 0))
		elseif axis == "relX" then
			local v = self:getDirection("right")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		elseif axis == "relY" then
			local v = self:getDirection("forward")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		elseif axis == "relZ" then
			local v = self:getDirection("up")
			self:setPosition(Vector4.new((v.x * newValue), (v.y * newValue), (v.z * newValue), 0))
		elseif axis == "roll" then
			self:setRotation(EulerAngles.new(newValue - prop, 0, 0))
		elseif axis == "pitch" then
			self:setRotation(EulerAngles.new(0, newValue - prop, 0))
		elseif axis == "yaw" then
			self:setRotation(EulerAngles.new(0, 0, newValue - prop))
		elseif axis == "scaleX" then
			self:setScale({ x = newValue - prop, y = 0, z = 0 }, finished)
		elseif axis == "scaleY" then
			self:setScale({ x = 0, y = newValue - prop, z = 0 }, finished)
		elseif axis == "scaleZ" then
			self:setScale({ x = 0, y = 0, z = newValue - prop }, finished)
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
	style.pushGreyedOut(not self.visible or self.hiddenByParent)
    self:drawProp(0, "Rel X", "relX")
	ImGui.SameLine()
    self:drawProp(0, "Rel Y", "relY")
	ImGui.SameLine()
    self:drawProp(0, "Rel Z", "relZ")
	style.popGreyedOut(not self.visible or self.hiddenByParent)
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

	self.rotationRelative, _ = style.toggleButton(IconGlyphs.HorizontalRotateClockwise, self.rotationRelative)
	style.tooltip("Toggle relative rotation")
    ImGui.PopItemWidth()
end

function positionable:drawScale(scale)
	if not self.hasScale then return end

	ImGui.PushItemWidth(80 * style.viewSize)

	self:drawProp(scale.x, "Scale X", "scaleX")
	ImGui.SameLine()
	self:drawProp(scale.y, "Scale Y", "scaleY")
	ImGui.SameLine()
	self:drawProp(scale.z, "Scale Z", "scaleZ")

	ImGui.SameLine()
	self.scaleLocked, _ = style.toggleButton(IconGlyphs.LinkVariant, self.scaleLocked)
	style.tooltip("Locks the X, Y, and Z axis scales together")

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

function positionable:setScale(delta, finished)

end

function positionable:getScale()
	return Vector4.new(1, 1, 1, 0)
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
	data.scaleLocked = self.scaleLocked
	data.pos = utils.fromVector(self:getPosition()) -- For savedUI

	return data
end

return positionable