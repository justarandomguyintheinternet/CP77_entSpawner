local spawnable = require("modules/classes/spawn/spawnable")
local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/preview/visualizer")
local utils = require("modules/utils/core/utils")
local lcHelper = require("modules/utils/ui/lightChannelHelper")

local propertyNames = {
    "Color",
    "Absolute Density",
    "Density Factor",
    "Density Falloff",
    "Height Falloff",
    "Absorption",
    "Blend Falloff",
    "Ambient Scale",
    "Priority"
}

-- What projects saved before these fields existed exported.
local LEGACY_PRIORITY = 255
local LEGACY_ABSOLUTE = false

---Class for worldStaticFogVolumeNode
---@class fog : visualized
---@field public scale {x: number, y: number, z: number}
---@field private previewed boolean
---@field public absolute boolean Density in absolute units instead of a factor of the area's global fog.
---@field public absorption number Negative uses the engine default.
---@field public blendFalloff number
---@field public color number[] RGB, 0 to 1.
---@field public densityFactor number
---@field public densityFalloff number
---@field public applyHeightFalloff boolean
---@field public ambientScale number
---@field public priority integer
---@field private maxPropertyWidth number
---@field public lightChannels boolean[]
local fog = setmetatable({}, { __index = visualized })

function fog:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Fog Volume"
    o.spawnDataPath = "data/spawnables/visual/fog/"
    o.modulePath = "visual/fog"
    o.node = "worldStaticFogVolumeNode"
    o.description = "Places a fog volume of variable size."
    o.previewNote = "Might not be properly visible during preview, due to lightChannels not being previewed."
    o.icon = IconGlyphs.WeatherFog
    o.maxPropertyWidth = nil

    -- Vanilla-like defaults: absolute 81%, absorption -1 46%, priority 5 56%, height falloff 74%.
    o.scale = { x = 5, y = 5, z = 5 }
    o.absolute = true
    o.absorption = -1
    o.blendFalloff = 0
    o.color = { 1, 1, 1 }
    o.densityFactor = 0.05
    o.densityFalloff = 0
    o.applyHeightFalloff = true
    o.ambientScale = 1
    o.priority = 5
    o.lightChannels = { true, true, true, true, true, true, true, true, true, false, false, false }

    o.previewed = true
    o.previewShape = "box"

    setmetatable(o, { __index = self })
   	return o
end

function fog:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    visualizer.addBox(entity, { x = self.scale.x / 2, y = self.scale.y / 2, z = self.scale.z / 2 }, "yellow")

    local component = entFogVolumeComponent.new()
    component.name = "fog"
    component.size = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.absorption = self.absorption
    component.blendFalloff = self.blendFalloff
    component.color = Color.new({ Red = math.floor(self.color[1] * 255), Green = math.floor(self.color[2] * 255), Blue = math.floor(self.color[3] * 255), Alpha = 255 })
    component.densityFactor = self.densityFactor
    component.densityFalloff = self.densityFalloff
    entity:AddComponent(component)

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    visualizer.toggleAll(entity, self.previewed)
end

function fog:spawn()
    self:spawnAsPlaceholderEntity()
end

function fog:save()
    local data = visualized.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.absorption = self.absorption
    data.blendFalloff = self.blendFalloff
    data.color = { self.color[1], self.color[2], self.color[3] }
    data.densityFactor = self.densityFactor
    data.densityFalloff = self.densityFalloff
    data.absolute = self.absolute
    data.applyHeightFalloff = self.applyHeightFalloff
    data.ambientScale = self.ambientScale
    data.priority = self.priority
    data.lightChannels = utils.deepcopy(self.lightChannels)

    return data
end

function fog:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, rotation)

    if data.priority == nil then self.priority = LEGACY_PRIORITY end
    if data.absolute == nil then self.absolute = LEGACY_ABSOLUTE end

    -- loadSpawnData shares tables with its long-lived payload.
    self.scale = utils.deepcopy(self.scale)
    self.color = utils.deepcopy(self.color)
    self.lightChannels = utils.deepcopy(self.lightChannels)
end

---@protected
function fog:updateScale(finished)
    if finished then
        self:respawn()
    end
end

function fog:getSize()
    return self.scale
end

---Draws a muted label and moves the cursor to the property column.
---@param label string
function fog:propertyLabel(label)
    style.mutedText(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
end

function fog:draw()
    spawnable.draw(self)

    self:drawPreviewCheckbox("Visualize outline")

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    local finished, changed

    self:propertyLabel("Color")
    self.color, _, finished = style.trackedColor(self.object, "##color", self.color, 60)
    self:updateScale(finished)

    self:propertyLabel("Absolute Density")
    self.absolute, changed = style.trackedCheckbox(self.object, "##absolute", self.absolute)
    style.tooltip("On: Density Factor is the fog density itself.\nOff: it multiplies the global fog density of the area, so the volume can vanish where that fog is thin.")
    self:updateScale(changed)

    self:propertyLabel("Density Factor")
    self.densityFactor, _, finished = style.trackedDragFloat(self.object, "##densityFactor", self.densityFactor, 0.001, 0, 9999, "%.3f", 60)
    style.tooltip("Vanilla volumes mostly use 0.01 to 0.05.")
    self:updateScale(finished)

    self:propertyLabel("Density Falloff")
    self.densityFalloff, _, finished = style.trackedDragFloat(self.object, "##densityFalloff", self.densityFalloff, 0.01, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    self:propertyLabel("Height Falloff")
    self.applyHeightFalloff, changed = style.trackedCheckbox(self.object, "##applyHeightFalloff", self.applyHeightFalloff)
    self:updateScale(changed)

    self:propertyLabel("Absorption")
    local absorptionFormat = self.absorption < 0 and "Default" or "%.2f"
    self.absorption, _, finished = style.trackedDragFloat(self.object, "##absorption", self.absorption, 0.01, -1, 9999, absorptionFormat, 60)
    style.tooltip("Below 0 uses the engine's default absorption, like most vanilla volumes.")
    if finished and self.absorption < 0 then
        self.absorption = -1
    end
    self:updateScale(finished)

    self:propertyLabel("Blend Falloff")
    self.blendFalloff, _, finished = style.trackedDragFloat(self.object, "##blendFalloff", self.blendFalloff, 0.01, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    self:propertyLabel("Ambient Scale")
    self.ambientScale, _, finished = style.trackedDragFloat(self.object, "##ambientScale", self.ambientScale, 0.01, 0, 10, "%.2f", 60)
    self:updateScale(finished)

    self:propertyLabel("Priority")
    self.priority, changed, finished = style.trackedIntInput(self.object, "##priority", self.priority, 0, 255, 80, 1, 5)
    style.tooltip("Order among overlapping volumes. Vanilla uses 1 to 10, mostly 5.")
    -- A step button click changes the value without a deactivation.
    self:updateScale(finished or (changed and not ImGui.IsItemActive()))

    if ImGui.TreeNodeEx("Light Channels") then
        self.lightChannels = style.drawLightChannelsSelector(self.object, self.lightChannels)
        ImGui.TreePop()
    end
end

function fog:getProperties()
    return self:addNodeProperty(spawnable.getProperties(self))
end

function fog:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "fog",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Fog Volume")

            ImGui.SameLine()

            ImGui.PushID("fog")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticFogVolumeNode" then
                        entry.spawnable:setPreview(false)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticFogVolumeNode" then
                        entry.spawnable:setPreview(true)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    properties["lcGrouped"] = lcHelper.getGroupedProperties(self)

    return properties
end

function fog:export()
    local data = spawnable.export(self)
    data.type = "worldStaticFogVolumeNode"
    data.scale = self.scale
    data.data = {
        color = {
            ["Red"] = math.floor(self.color[1] * 255),
            ["Green"] = math.floor(self.color[2] * 255),
            ["Blue"] = math.floor(self.color[3] * 255),
            ["Alpha"] = 255
        },
        absolute = self.absolute and 1 or 0,
        absorption = self.absorption,
        blendFalloff = self.blendFalloff,
        densityFactor = self.densityFactor,
        densityFalloff = self.densityFalloff,
        applyHeightFalloff = self.applyHeightFalloff and 1 or 0,
        ambientScale = self.ambientScale,
        lightChannels = utils.buildBitfieldString(self.lightChannels, style.lightChannelEnum),
        priority = math.floor(self.priority),
        streamingDistance = self.primaryRange
    }

    return data
end

return fog
