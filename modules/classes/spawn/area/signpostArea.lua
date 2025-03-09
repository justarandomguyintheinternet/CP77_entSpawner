local triggerArea = require("modules/classes/spawn/area/triggerArea")
local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local cache = require("modules/utils/cache")

---Class for worldAudioSignpostTriggerNode
---@class signpostArea : triggerArea
---@field private enter string
---@field private exit string
---@field private maxPropertyWidth number
local signpostArea = setmetatable({}, { __index = triggerArea })

function signpostArea:new()
	local o = triggerArea.new(self)

    o.spawnListType = "files"
    o.dataType = "Audio Signpost Area"
    o.spawnDataPath = "data/spawnables/area/signpostArea/"
    o.modulePath = "area/signpostArea"
    o.node = "worldAudioSignpostTriggerNode"
    o.description = "Purpose is not known yet."
    o.previewNote = "Not previewed in editor."
    o.icon = IconGlyphs.BullhornOutline

    o.triggerType = "Audio Signpost"

    o.enter = ""
    o.exit = ""

    o.maxPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function signpostArea:save()
    local data = triggerArea.save(self)

    data.enter = self.enter
    data.exit = self.exit

    return data
end

function signpostArea:drawSignpost(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldAudioSignpostTriggerNotifier"
        }

        return
    end
end

function signpostArea:getAvailableTriggers()
    return {
        ["Audio Signpost"] = signpostArea.drawSignpost
    }
end

function signpostArea:draw()
    area.draw(self)

    if ImGui.TreeNodeEx(self.triggerType, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawChannelSelect()
        self:drawSignpost(false)

        if not self.maxPropertyWidth then
            self.maxPropertyWidth = utils.getTextMaxWidth({ "Enter Event", "Exit Event" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Enter Event")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.enter, _ = style.trackedSearchDropdown(self.object, "##enter", "Search for event", self.enter, cache.staticData.signposts.enter, style.getMaxWidth(350) - 30)

        style.mutedText("Exit Event")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.exit, _ = style.trackedSearchDropdown(self.object, "##exit", "Search for event", self.exit, cache.staticData.signposts.exit, style.getMaxWidth(350) - 30)

        ImGui.TreePop()
    end
end

function signpostArea:export()
    local data = triggerArea.export(self)

    data.type = "worldAudioSignpostTriggerNode"
    data.data.enterSignpost = {
        ["$type"] = "CName",
        ["$storage"] = "string",
        ["$value"] = self.enter
    }
    data.data.exitSignpost = {
        ["$type"] = "CName",
        ["$storage"] = "string",
        ["$value"] = self.exit
    }

    return data
end

return signpostArea