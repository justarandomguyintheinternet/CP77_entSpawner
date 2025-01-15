local triggerArea = require("modules/classes/spawn/area/triggerArea")
local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local channels = {
    "TC_Default", "TC_Player", "TC_Camera", "TC_Human", "TC_SoundReverbArea", "TC_SoundAmbientArea", "TC_Quest", "TC_Projectiles", "TC_Vehicle", "TC_Environment", "TC_WaterNullArea", "TC_Custom0", "TC_Custom1", "TC_Custom2", "TC_Custom3", "TC_Custom4", "TC_Custom5", "TC_Custom6", "TC_Custom7", "TC_Custom8", "TC_Custom9", "TC_Custom10", "TC_Custom11", "TC_Custom12", "TC_Custom13", "TC_Custom14"
}

---Class for worldAmbientAreaNode
---@class ambientArea : triggerArea
local ambientArea = setmetatable({}, { __index = triggerArea })

function ambientArea:new()
	local o = triggerArea.new(self)

    o.spawnListType = "files"
    o.dataType = "Ambient Area"
    o.spawnDataPath = "data/spawnables/area/ambientArea/"
    o.modulePath = "area/ambientArea"
    o.node = "worldAmbientAreaNode"
    o.description = "Trigger used for modifying the soundstage."
    o.previewNote = "Not previewed in editor."
    o.icon = IconGlyphs.SelectSearch

    o.triggerType = "Ambient"
    o.channels = { false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }

    setmetatable(o, { __index = self })
   	return o
end

function ambientArea:drawEvents(eventKey, default)
    if ImGui.TreeNodeEx(eventKey, ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, event in pairs(self.trigger.Settings.Data[eventKey]) do
            ImGui.PushID(tostring(index) .. eventKey)
            event["event"]["$value"], _ = style.trackedTextField(self.object, "##event", event["event"]["$value"], default, 250)

            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.trigger.Settings.Data[eventKey], index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.trigger.Settings.Data[eventKey], {
                ["$type"] = "audioAudEventStruct",
                ["event"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = ""
                }
            })
        end

        ImGui.TreePop()
    end
end

function ambientArea:drawAmbient(changed)
    if changed then
        self.trigger = {
            ["$type"] = "audioAmbientAreaNotifier",
            ["Settings"] = {
                ["Data"] = {
                    ["$type"] = "audioAmbientAreaSettings",
                    ["EventsOnActive"] = {},
                    ["EventsOnEnter"] = {},
                    ["EventsOnExit"] = {},
                    ["outerDistance"] = 10,
                    ["Parameters"] = {},
                    ["Priority"] = 16,
                    ["Reverb"] = {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = ""
                    },
                    ["verticalOuterDistance"] = 1,
                    ["isMusic"] = false,
                }
            }
        }

        return
    end

    local max = utils.getTextMaxWidth({"Outer Distance", "Priority", "Reverb", "Vertical Outer Distance", "Is Music"}) + 8 * ImGui.GetStyle().ItemSpacing.x

    style.mutedText("Priority")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.Settings.Data.Priority, changed = style.trackedDragFloat(self.object, "##Priority", self.trigger.Settings.Data.Priority, 1, 0, 9999, "%.0f", 75)
    if changed then
        self.trigger.Settings.Data.Priority = math.floor(self.trigger.Settings.Data.Priority)
    end

    style.mutedText("Outer Distance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.Settings.Data.outerDistance, _ = style.trackedDragFloat(self.object, "##outerDistance", self.trigger.Settings.Data.outerDistance, 0.01, 0, 9999, "%.2f", 75)

    style.mutedText("Vertical Outer Distance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.Settings.Data.verticalOuterDistance, _ = style.trackedDragFloat(self.object, "##verticalOuterDistance", self.trigger.Settings.Data.verticalOuterDistance, 0.01, 0, 9999, "%.2f", 75)

    style.mutedText("Reverb")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.Settings.Data.Reverb["$value"], _ = style.trackedTextField(self.object, "##reverb", self.trigger.Settings.Data.Reverb["$value"], "revb_interior_room_medium", 225)

    style.mutedText("Is Music")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.Settings.Data.isMusic, _ = style.trackedCheckbox(self.object, "##isMusic", self.trigger.Settings.Data.isMusic)

    self:drawEvents("EventsOnActive", "amb_int_roomtone_office_med_01_aircon")
    self:drawEvents("EventsOnEnter", "mus_e3_amb_silent")
    self:drawEvents("EventsOnExit", "mus_e3_amb_megabuilding")

    if ImGui.TreeNodeEx("Parameters", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, parameter in pairs(self.trigger.Settings.Data["Parameters"]) do
            ImGui.PushID(tostring(index) .. "parameter")
            parameter["name"]["$value"], _ = style.trackedTextField(self.object, "##parameter", parameter["name"]["$value"], "amb_interior", 175)
            ImGui.SameLine()
            parameter["value"], _ = style.trackedDragFloat(self.object, "##value", parameter["value"], 0.01, 0, 1, "%.2f", 75)

            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.trigger.Settings.Data["Parameters"], index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.trigger.Settings.Data["Parameters"], {
                ["$type"] = "audioAudParameter",
                ["name"] = {
                    ["$type"] = "CName",
                    ["$storage"] ="string",
                    ["$value"] = "amb_interior"
                },
                ["value"] = 1
            })
        end

        ImGui.TreePop()
    end
end

function ambientArea:drawChannelSelect()
    if ImGui.TreeNodeEx("Trigger Channels", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, name in pairs(channels) do
            self.channels[key], _ = style.trackedCheckbox(self.object, name, self.channels[key])
        end
        ImGui.TreePop()
    end
end

function ambientArea:getAvailableTriggers()
    return {
        ["Ambient"] = ambientArea.drawAmbient
    }
end

function ambientArea:draw()
    area.draw(self)

    if ImGui.TreeNodeEx(self.triggerType, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawChannelSelect()
        self:drawAmbient(false)
        ImGui.TreePop()
    end
end

function ambientArea:export()
    local data = triggerArea.export(self)
    data.type = "worldAmbientAreaNode"

    return data
end

return ambientArea