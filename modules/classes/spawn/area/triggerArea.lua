local area = require("modules/classes/spawn/area/area")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

local channels = {
    "TC_Default", "TC_Player", "TC_Camera", "TC_Human", "TC_SoundReverbArea", "TC_SoundAmbientArea", "TC_Quest", "TC_Projectiles", "TC_Vehicle", "TC_Environment", "TC_WaterNullArea", "TC_Custom0", "TC_Custom1", "TC_Custom2", "TC_Custom3", "TC_Custom4", "TC_Custom5", "TC_Custom6", "TC_Custom7", "TC_Custom8", "TC_Custom9", "TC_Custom10", "TC_Custom11", "TC_Custom12", "TC_Custom13", "TC_Custom14"
}

---Class for worldTriggerAreaNode
---@class triggerArea : area
---@field trigger table?
---@field triggerType string
---@field channels table
---@field private preventionActivationTable table
---@field private preventionNotifierTable table
local triggerArea = setmetatable({}, { __index = area })

function triggerArea:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Trigger Area"
    o.spawnDataPath = "data/spawnables/area/triggerArea/"
    o.modulePath = "area/triggerArea"
    o.node = "worldTriggerAreaNode"
    o.description = "General purpose node for an area with an associated trigger. For more specific triggers, use the specific trigger nodes."
    o.previewNote = "Triggers are not previewed in editor."
    o.icon = IconGlyphs.SelectSearch

    o.triggerType = "Interior"
    o.trigger = nil
    o.channels = { false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }

    o.preventionActivationTable = utils.enumTable("worldQuestPreventionNotifierActivation")
    o.preventionNotifierTable = utils.enumTable("worldQuestPreventionNotifierType")

    setmetatable(o, { __index = self })
   	return o
end

function triggerArea:loadSpawnData(data, position, rotation)
    area.loadSpawnData(self, data, position, rotation)

    if not self.trigger then
        self:getAvailableTriggers()[self.triggerType](self, true)
    end
end

function triggerArea:drawInterior(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldInteriorAreaNotifier",
            gameRestrictionIDs = {},
            setTier2 = false,
            treatAsInterior = true
        }

        return
    end

    local max = utils.getTextMaxWidth({"Set Tier 2", "Treat As Interior"}) + 8 * ImGui.GetStyle().ItemSpacing.x

    style.mutedText("Set Tier 2")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.setTier2, _ = style.trackedCheckbox(self.object, "##setTier2", self.trigger.setTier2)
    style.tooltip("Sets the gameplay tier to 2, meaning no weapons, no vehicle calls, no radio and no consumables.")

    style.mutedText("Treat As Interior")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.treatAsInterior, _ = style.trackedCheckbox(self.object, "##treatAsInterior", self.trigger.treatAsInterior)

    if ImGui.TreeNodeEx("Game Restrictions", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, restriction in pairs(self.trigger.gameRestrictionIDs) do
            ImGui.PushID(index)
            restriction["$value"], _ = style.trackedTextField(self.object, "##restriction", restriction["$value"], "GameplayRestriction.", 230)
            style.tooltip("Gameplay restriction TweakDB entry. Search for \"GameplayRestriction\" in CETs TweakDB browser.")
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.trigger.gameRestrictionIDs, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.trigger.gameRestrictionIDs, {
                ["$type"] = "TweakDBID",
                ["$storage"] = "string",
                ["$value"] = ""
            })
        end

        ImGui.TreePop()
    end
end

function triggerArea:drawLocation(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldLocationAreaNotifier",
            districtID = {
                ["$type"] = "TweakDBID",
                ["$storage"] = "string",
                ["$value"] = ""
            },
            sendNewLocationNotification = true
        }

        return
    end

    local max = utils.getTextMaxWidth({"DistrictID", "Send Notification"}) + 8 * ImGui.GetStyle().ItemSpacing.x

    style.mutedText("DistrictID")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.districtID["$value"], _ = style.trackedTextField(self.object, "##districtID", self.trigger.districtID["$value"], "Districts.Kabuki", 160)

    style.mutedText("Send Notification")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.sendNewLocationNotification, _ = style.trackedCheckbox(self.object, "##sendNotification", self.trigger.sendNewLocationNotification)
    style.tooltip("Sends a notification to the player when they enter the area for the first time.")
end

function triggerArea:drawQuestNotifier(changed)
    if changed then
        self.trigger = {
            ["$type"] = "questTriggerNotifier_Quest"
        }

        return
    end
end

function triggerArea:drawPrevention(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldQuestPreventionNotifier",
            activation = "Always",
            ["type"] = "Clear"
        }

        return
    end

    local max = utils.getTextMaxWidth({"Activation", "Type"}) + 8 * ImGui.GetStyle().ItemSpacing.x

    style.mutedText("Activation")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    local value, changed = style.trackedCombo(self.object, "##activation", utils.indexValue(self.preventionActivationTable, self.trigger.activation) - 1, self.preventionActivationTable)
    if changed then
        self.trigger.activation = self.preventionActivationTable[value + 1]
    end

    style.mutedText("Type")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    local value, changed = style.trackedCombo(self.object, "##type", utils.indexValue(self.preventionNotifierTable, self.trigger["type"]) - 1, self.preventionNotifierTable)
    if changed then
        self.trigger["type"] = self.preventionNotifierTable[value + 1]
    end
end

function triggerArea:drawVehicleForbidden(changed)
    if changed then
        self.trigger = {
            ["$type"] = "worldVehicleForbiddenAreaNotifier",
            innerAreaSpeedLimit = 30,
            dismount = false,
            enableSummoning = false,
            innerAreaBoundToOuterArea = true
        }

        return
    end

    local max = utils.getTextMaxWidth({"Speed Limit", "Dismount", "Enable Summoning"}) + 8 * ImGui.GetStyle().ItemSpacing.x

    style.mutedText("Speed Limit")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.innerAreaSpeedLimit, _ = style.trackedDragFloat(self.object, "##innerAreaSpeedLimit", self.trigger.innerAreaSpeedLimit, 0.1, 0, 9999, "%.1f Limit", 90)

    style.mutedText("Dismount")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.dismount, _ = style.trackedCheckbox(self.object, "##dismount", self.trigger.dismount)

    style.mutedText("Enable Summoning")
    ImGui.SameLine()
    ImGui.SetCursorPosX(max)
    self.trigger.enableSummoning, _ = style.trackedCheckbox(self.object, "##enableSummoning", self.trigger.enableSummoning)
end

function triggerArea:drawContentBlock(changed)
    if changed then
        self.trigger = {
            ["$type"] = "questContentBlockTriggerAreaNotifier",
            resetTokenSpawnTimer = true
        }

        return
    end

    style.mutedText("Reset Token Spawn Timer")
    ImGui.SameLine()
    self.trigger.resetTokenSpawnTimer, _ = style.trackedCheckbox(self.object, "##resetTokenSpawnTimer", self.trigger.resetTokenSpawnTimer)
end

function triggerArea:getAvailableTriggers()
    return {
        ["Interior"] = triggerArea.drawInterior,
        ["Location"] = triggerArea.drawLocation,
        ["Quest Notifier"] = triggerArea.drawQuestNotifier,
        ["Prevention"] = triggerArea.drawPrevention,
        ["Vehicle Forbidden"] = triggerArea.drawVehicleForbidden,
        ["Content Block"] = triggerArea.drawContentBlock
    }
end

function triggerArea:drawChannelSelect()
    if ImGui.TreeNodeEx("Trigger Channels", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, name in pairs(channels) do
            self.channels[key], _ = style.trackedCheckbox(self.object, name, self.channels[key])
        end
        ImGui.TreePop()
    end
end

function triggerArea:draw()
    area.draw(self)

    local triggers = self:getAvailableTriggers()
    local triggerNames = utils.getKeys(triggers)

    style.mutedText("Trigger Type")
    ImGui.SameLine()
    local value, changed = style.trackedCombo(self.object, "##triggerType", utils.indexValue(triggerNames, self.triggerType) - 1, triggerNames, 120)
    if changed then
        self.triggerType = triggerNames[value + 1]
        triggers[self.triggerType](self, true)
    end

    if ImGui.TreeNodeEx(self.triggerType, ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawChannelSelect()
        triggers[self.triggerType](self, false)
        ImGui.TreePop()
    end
end

function triggerArea:save()
    local data = area.save(self)

    data.trigger = utils.deepcopy(self.trigger)
    data.triggerType = self.triggerType
    data.channels = utils.deepcopy(self.channels)

    return data
end

local function replaceBool(data)
    for k, v in pairs(data) do
        if type(v) == "table" then
            replaceBool(v)
        elseif type(v) == "boolean" then
            data[k] = v and 1 or 0
        end
    end
end

local function getExportTrigger(trigger)
    local data = utils.deepcopy(trigger)

    replaceBool(data)

    return data
end

function triggerArea:export()
    local data = area.export(self)
    data.type = "worldTriggerAreaNode"

    local trigger = getExportTrigger(self.trigger)
    local includedChannels = {}

    for key, channel in pairs(channels) do
        if self.channels[key] then
            table.insert(includedChannels, channel)
        end
    end
    trigger.includeChannels = table.concat(includedChannels, ",")

    data.data["notifiers"] = {
        {
            ["Data"] = trigger
        }
    }

    return data
end

return triggerArea