local triggerArea = require("modules/classes/spawn/area/triggerArea")
local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local registry = require("modules/utils/nodeRefRegistry")

---Class for worldInterestingConversationsAreaNode
---@class conversationArea : triggerArea
---@field private groups table
---@field private scenes table
---@field private workspots table
---@field private savingStrategy number
---@field private savingStrategyEnums table
local conversationArea = setmetatable({}, { __index = triggerArea })

function conversationArea:new()
	local o = triggerArea.new(self)

    o.spawnListType = "files"
    o.dataType = "Conversation Area"
    o.spawnDataPath = "data/spawnables/area/conversationArea/"
    o.modulePath = "area/conversationArea"
    o.node = "worldInterestingConversationsAreaNode"
    o.description = "Trigger used for activating conversation scenes."
    o.previewNote = "Not previewed in editor."
    o.icon = IconGlyphs.AccountVoice

    o.triggerType = "Conversation"

    o.groups = {}
    o.scenes = {}
    o.workspots = {}
    o.savingStrategy = 0
    o.savingStrategyEnums = utils.enumTable("audioConversationSavingStrategy")

    setmetatable(o, { __index = self })
   	return o
end

function conversationArea:save()
    local data = triggerArea.save(self)

    data.groups = utils.deepcopy(self.groups)
    data.scenes = utils.deepcopy(self.scenes)
    data.workspots = utils.deepcopy(self.workspots)
    data.savingStrategy = self.savingStrategy

    return data
end

function conversationArea:drawConversation(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldInterestingConversationsAreaNotifier"
        }

        return
    end

    if ImGui.TreeNodeEx("Conversation Groups", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, group in pairs(self.groups) do
            ImGui.PushID(tostring(index) .. "group")

            self.groups[index] = style.trackedTextField(self.object, "##group", group, "base\\open_world\\...\\ripperdoc.conversations", style.getMaxWidth(200) - 30)

            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.groups, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.groups, "")
        end

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Conversation Scenes", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, scene in pairs(self.scenes) do
            ImGui.PushID(tostring(index) .. "scene")

            self.scenes[index] = style.trackedTextField(self.object, "##scene", scene, "base\\open_world\\scenes\\...\\wbr_jpn_chat_001.scene", style.getMaxWidth(200) - 30)

            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.scenes, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.scenes, "")
        end

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Workspots", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, workspot in pairs(self.workspots) do
            ImGui.PushID(tostring(index) .. "workspot")

            self.workspots[index], _ = registry.drawNodeRefSelector(style.getMaxWidth(250) - 30, workspot, self.object, true)

            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.workspots, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.workspots, "")
        end

        ImGui.TreePop()
    end

    style.mutedText("Saving Strategy")
    ImGui.SameLine()
    self.savingStrategy, _ = style.trackedCombo(self.object, "##savingStrategy", self.savingStrategy, self.savingStrategyEnums, 100)
end

function conversationArea:getAvailableTriggers()
    return {
        ["Conversation"] = conversationArea.drawConversation
    }
end

function conversationArea:draw()
    area.draw(self)

    if ImGui.TreeNodeEx(self.triggerType, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawChannelSelect()
        self:drawConversation(false)
        ImGui.TreePop()
    end
end

function conversationArea:export()
    local data = triggerArea.export(self)
    data.type = "worldInterestingConversationsAreaNode"

    local groups = {}
    local scenes = {}
    local workspots = {}

    for _, group in pairs(self.groups) do
        table.insert(groups, {
            ["DepotPath"] = {
                ["$type"] = "ResourcePath",
                ["$storage"] = "string",
                ["$value"] = group
            },
            ["Flags"] = "Default"
        })
    end

    for _, scene in pairs(self.scenes) do
        table.insert(scenes, {
            ["Data"] = {
                ["$type"] = "worldConversationData",
                ["sceneFilename"] = {
                    ["DepotPath"] = {
                        ["$type"] = "ResourcePath",
                        ["$storage"] = "string",
                        ["$value"] = scene
                    },
                    ["Flags"] = "Default"
                }
            }
        })
    end

    for _, workspot in pairs(self.workspots) do
        table.insert(workspots, {
            ["$type"] = "NodeRef",
            ["$storage"] = "string",
            ["$value"] = workspot
        })
    end

    data.data.conversationGroups = groups
    data.data.conversations = scenes
    data.data.savingStrategy = self.savingStrategyEnums[self.savingStrategy + 1]
    data.data.workspots = workspots

    return data
end

return conversationArea