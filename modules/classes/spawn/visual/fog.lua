local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/visualizer")
local utils = require("modules/utils/utils")
local lcHelper = require("modules/utils/lightChannelHelper")

local propertyNames = {
    "Color",
    "Density Factor",
    "Density Falloff",
    "Absorption",
    "Blend Falloff"
}

---Class for worldStaticFogVolumeNode
---@class fog : spawnable
---@field public scale {x: number, y: number, z: number}
---@field private previewed boolean
---@field public absorption number
---@field public blendFalloff number
---@field public color {r: number, g: number, b: number}
---@field public densityFactor number
---@field public densityFalloff number
---@field private maxPropertyWidth number
---@field public lightChannels boolean[]
local fog = setmetatable({}, { __index = spawnable })

function fog:new()
	local o = spawnable.new(self)

    o.spawnListType = "files"
    o.dataType = "Fog Volume"
    o.spawnDataPath = "data/spawnables/visual/fog/"
    o.modulePath = "visual/fog"
    o.node = "worldStaticFogVolumeNode"
    o.description = "Places a fog volume of variable size."
    o.previewNote = "Might not be properly visible during preview, due to lightChannels not being previewed."
    o.icon = IconGlyphs.WeatherFog
    o.maxPropertyWidth = nil

    o.scale = { x = 5, y = 5, z = 5 }
    o.absorption = 1
    o.blendFalloff = 1
    o.color = { 1, 1, 1 }
    o.densityFactor = 1
    o.densityFalloff = 1
    o.lightChannels = { true, true, true, true, true, true, true, true, true, false, false, false }

    o.previewed = true

    o.uk10 = 1056
    o.uk11 = 512

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
    local probe = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    spawnable.spawn(self)
    self.spawnData = probe
end

function fog:save()
    local data = spawnable.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.absorption = self.absorption
    data.blendFalloff = self.blendFalloff
    data.color = { self.color[1], self.color[2], self.color[3] }
    data.densityFactor = self.densityFactor
    data.densityFalloff = self.densityFalloff
    data.previewed = self.previewed
    data.lightChannels = utils.deepcopy(self.lightChannels)

    return data
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

function fog:draw()
    spawnable.draw(self)

    self.previewed, changed = style.trackedCheckbox(self.object, "Visualize outline", self.previewed)
    if changed then
        visualizer.toggleAll(self:getEntity(), self.previewed)
    end

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Color")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.color, _, finished = style.trackedColor(self.object, "##color", self.color, 60)
    self:updateScale(finished)

    style.mutedText("Density Factor")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.densityFactor, _, finished = style.trackedDragFloat(self.object, "##densityFactor", self.densityFactor, 0.1, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    style.mutedText("Density Falloff")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.densityFalloff, _, finished = style.trackedDragFloat(self.object, "##densityFalloff", self.densityFalloff, 0.1, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    style.mutedText("Absorption")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.absorption, _, finished = style.trackedDragFloat(self.object, "##absorption", self.absorption, 0.1, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    style.mutedText("Blend Falloff")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.blendFalloff, _, finished = style.trackedDragFloat(self.object, "##blendFalloff", self.blendFalloff, 0.1, 0, 9999, "%.2f", 60)
    self:updateScale(finished)

    if ImGui.TreeNodeEx("Light Channels") then
        self.lightChannels = style.drawLightChannelsSelector(self.object, self.lightChannels)
        ImGui.TreePop()
    end
end

function fog:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
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
                        entry.spawnable.previewed = false
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticFogVolumeNode" then
                        entry.spawnable.previewed = true
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
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
        absorption = self.absorption,
        blendFalloff = self.blendFalloff,
        densityFactor = self.densityFactor,
        densityFalloff = self.densityFalloff,
        lightChannels = utils.buildBitfieldString(self.lightChannels, style.lightChannelEnum),
        priority = 255,
        streamingDistance = self.primaryRange
    }

    return data
end

return fog