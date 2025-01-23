local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")

---Class for worldAISpotNode
---@class aiSpot : visualized
---@field previewNPC string
---@field spawnNPC boolean
---@field isWorkspotInfinite boolean
---@field isWorkspotStatic boolean
---@field markings table
local aiSpot = setmetatable({}, { __index = visualized })

function aiSpot:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "AI Spot"
    o.spawnDataPath = "data/spawnables/ai/aiSpot/"
    o.modulePath = "ai/aiSpot"
    o.node = "worldAISpotNode"
    o.description = ""
    o.icon = IconGlyphs.MapMarkerStar

    o.previewed = true
    o.previewColor = "fuchsia"

    o.previewNPC = "Character.Judy"
    o.spawnNPC = true

    o.isWorkspotInfinite = true
    o.isWorkspotStatic = false
    o.markings = {}

    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function aiSpot:getVisualizerSize()
    return { x = 0.15, y = 0.15, z = 0.15 }
end

function aiSpot:spawn()
    local worspot = self.spawnData
    self.spawnData = "base\\spawner\\empty_entity.ent"

    visualized.spawn(self)
    self.spawnData = worspot
end

function aiSpot:save()
    local data = visualized.save(self)

    data.previewNPC = self.previewNPC
    data.spawnNPC = self.spawnNPC
    data.isWorkspotInfinite = self.isWorkspotInfinite
    data.isWorkspotStatic = self.isWorkspotStatic
    data.markings = self.markings

    return data
end

function aiSpot:draw()
    visualized.draw(self)
    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Visualize position", "Is Infinite", "Is Static", "Preview NPC", "Preview NPC Record"}) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize position", self.maxPropertyWidth)

    style.mutedText("Preview NPC")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.spawnNPC, changed = style.trackedCheckbox(self.object, "##spawnNPC", self.spawnNPC)

    style.mutedText("Preview NPC Record")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.previewNPC, _ = style.trackedTextField(self.object, "##previewNPC", self.previewNPC, "Character.", 200)

    style.mutedText("Is Infinite")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.isWorkspotInfinite, _ = style.trackedCheckbox(self.object, "##isWorkspotInfinite", self.isWorkspotInfinite)
    style.tooltip("If checked, the NPC will use this spot indefinitely, while streamed in.\nIf unchecked, the NPC will walk to the next spot defined in its community entry.")

    style.mutedText("Is Static")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.isWorkspotStatic, _ = style.trackedCheckbox(self.object, "##isWorkspotStatic", self.isWorkspotStatic)

    if ImGui.TreeNodeEx("Markings", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, _ in pairs(self.markings) do
            ImGui.PushID(key)

            self.markings[key], _ = style.trackedTextField(self.object, "##marking", self.markings[key], "", 200)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.markings, key)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.markings, "")
        end

        ImGui.TreePop()
    end
    style.tooltip("Still requires to assign a NodeRef to this spot.")
end

function aiSpot:getProperties()
    local properties = visualized.getProperties(self)
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

function aiSpot:export()
    local markings = {}
    for _, marking in pairs(self.markings) do
        table.insert(markings, {
            ["$type"] = "CName",
            ["$storage"] = "string",
            ["$value"] = marking
        })
    end

    local data = visualized.export(self)
    data.type = "worldAISpotNode"
    data.data = {
        ["isWorkspotInfinite"] = self.isWorkspotInfinite and 1 or 0,
        ["isWorkspotStatic"] = self.isWorkspotStatic and 1 or 0,
        ["spot"] = {
            ["Data"] = {
                ["$type"] = "AIActionSpot",
                ["resource"] = {
                    ["DepotPath"] = {
                        ["$type"] = "ResourcePath",
                        ["$storage"] = "string",
                        ["$value"] = self.spawnData
                    },
                    ["Flags"] = "Soft"
                }
            }
        },
        ["markings"] = markings
    }

    return data
end

return aiSpot