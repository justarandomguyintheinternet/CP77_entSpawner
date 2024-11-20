local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local visualizer = require("modules/utils/visualizer")

---Class for any spawnable that has a "basic" visualizer
---@class visualized : spawnable
---@field private previewed boolean
---@field private previewShape string
---@field private previewColor string
local visualized = setmetatable({}, { __index = spawnable })

function visualized:new()
	local o = spawnable.new(self)

    o.dataType = "Visualized"
    o.modulePath = "visualized"

    o.previewed = false
    o.previewShape = "sphere"
    o.previewColor = "green"

    setmetatable(o, { __index = self })
   	return o
end

function visualized:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    if self.previewShape == "sphere" then
        visualizer.addSphere(entity, self:getVisualizerSize(), self.previewColor)
    elseif self.previewShape == "box" then
        visualizer.addBox(entity, self:getVisualizerSize(), self.previewColor)
    end

    visualizer.updateScale(entity, self:getVisualizerSize(), "arrows")
    visualizer.toggleAll(entity, self.previewed)
end

function visualized:save()
    local data = spawnable.save(self)

    data.previewed = self.previewed

    return data
end

---@protected
function visualized:updateScale()
    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getVisualizerSize(), "arrows")
    visualizer.updateScale(entity, self:getVisualizerSize(), self.previewShape)
end

function visualized:setPreview(state)
    self.previewed = state

    local entity = self:getEntity()
    if not entity then return end

    visualizer.toggleAll(entity, self.previewed)
end

function visualized:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "occluder",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Occluder")

            ImGui.SameLine()

            ImGui.PushID("occluder")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticOccluderMeshNode" then
                        entry.spawnable.previewed = false
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldStaticOccluderMeshNode" then
                        entry.spawnable.previewed = true
                        visualizer.toggleAll(entry.spawnable:getEntity(), entry.spawnable.previewed)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}

    return properties
end

return visualized