local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")

---Class for worldCompiledCommunityAreaNode_Streamable
---@class community : visualized
---@field entries table
---@field periodEnums table
local community = setmetatable({}, { __index = visualized })

function community:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Community"
    o.spawnDataPath = "data/spawnables/ai/community/"
    o.modulePath = "ai/communityArea"
    o.node = "worldCompiledCommunityAreaNode_Streamable"
    o.description = ""
    o.icon = IconGlyphs.AccountGroup

    o.previewed = true
    o.previewColor = "palegreen"

    o.primaryRange = 250
    o.secondaryRange = 200
    o.streamingMultiplier = 5

    o.entries = {}
    o.periodEnums = {
        "Morning",
        "Day",
        "Evening",
        "Night",
        "Midnight",
        "1:00 AM",
        "2:00 AM",
        "3:00 AM",
        "4:00 AM",
        "5:00 AM",
        "6:00 AM",
        "7:00 AM",
        "8:00 AM",
        "9:00 AM",
        "10:00 AM",
        "11:00 AM",
        "Noon",
        "1:00 PM",
        "2:00 PM",
        "3:00 PM",
        "4:00 PM",
        "5:00 PM",
        "6:00 PM",
        "7:00 PM",
        "8:00 PM",
        "9:00 PM",
        "10:00 PM",
        "11:00 PM"
    }

    setmetatable(o, { __index = self })
   	return o
end


function community:save()
    local data = visualized.save(self)

    data.entries = utils.deepcopy(self.entries)

    return data
end

local function drawHeaderText(key, text)
    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() - 8 * style.viewSize)
    ImGui.Text(string.format("[%d] %s", key, text))
end

function community:drawDeleteContext(key, tbl)
    if ImGui.BeginPopupContextItem("##remove" .. key, ImGuiPopupFlags.MouseButtonRight) then
        if ImGui.MenuItem("Delete") then
            history.addAction(history.getElementChange(self.object))
            table.remove(tbl, key)
        end
        ImGui.EndPopup()
    end
end

function community:drawPhaseAppearances(phase)
    if ImGui.TreeNodeEx("Appearances", ImGuiTreeNodeFlags.SpanFullWidth) then
        for appKey, _ in pairs(phase.appearances) do
            ImGui.PushID(appKey)

            phase.appearances[appKey], _ = style.trackedTextField(self.object, "##appearance", phase.appearances[appKey], "default", 200)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(phase.appearances, appKey)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+ [Appearance]") then
            history.addAction(history.getElementChange(self.object))
            table.insert(phase.appearances, "")
        end

        ImGui.TreePop()
    end
end

function community:drawSpotNodeRefs(period)
    if ImGui.TreeNodeEx("Spot NodeRef's", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, _ in pairs(period.spotNodeRefs) do
            ImGui.PushID(key)

            period.spotNodeRefs[key], _ = style.trackedTextField(self.object, "##node", period.spotNodeRefs[key], "", 200)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(period.spotNodeRefs, key)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+ [Spot Ref]") then
            history.addAction(history.getElementChange(self.object))
            period.markings = {}
            table.insert(period.spotNodeRefs, "")
        end

        ImGui.TreePop()
    end
end

function community:drawMarkings(period)
    if ImGui.TreeNodeEx("Markings", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, _ in pairs(period.markings) do
            ImGui.PushID(key)

            period.markings[key], _ = style.trackedTextField(self.object, "##marking", period.markings[key], "", 200)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(period.markings, key)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+ [Marking]") then
            history.addAction(history.getElementChange(self.object))
            period.spotNodeRefs = {}
            table.insert(period.markings, "")
        end

        ImGui.TreePop()
    end
end

function community:drawPeriod(periods, periodKey)
    local period = periods[periodKey]

    if ImGui.TreeNodeEx("##" .. tostring(periodKey), ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawDeleteContext(periodKey, periods)
        drawHeaderText(periodKey, self.periodEnums[period.hour + 1])

        local max = utils.getTextMaxWidth({"Hour", "Is Sequence", "Quantity"}) + 4 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()

        style.mutedText("Hour")
        ImGui.SameLine()
        ImGui.SetCursorPosX(max)
        period.hour, _ = style.trackedCombo(self.object, "##hour", period.hour, self.periodEnums)

        style.mutedText("Is Sequence")
        ImGui.SameLine()
        ImGui.SetCursorPosX(max)
        period.isSequence, _ = style.trackedCheckbox(self.object, "##isSequence", period.isSequence)
        style.tooltip("If true, the NPC(s) will use their assigned AISpot's in the same order as they are listed.\nOtherwise they will use them randomly.\nOnly relevant if AISpots are not set to be infinite.")

        style.mutedText("Quantity")
        ImGui.SameLine()
        ImGui.SetCursorPosX(max)
        period.quantity, changed = style.trackedDragFloat(self.object, "##quantity", period.quantity, 1, 0, 9999, "%.0f", 75)
        if changed then
            period.quantity = math.floor(period.quantity)
        end

        self:drawMarkings(period)
        self:drawSpotNodeRefs(period)

        ImGui.TreePop()
    else
        self:drawDeleteContext(periodKey, periods)
        drawHeaderText(periodKey, self.periodEnums[period.hour + 1])
    end
end

function community:drawPhasePeriods(phase)
    if ImGui.TreeNodeEx("Time Periods", ImGuiTreeNodeFlags.SpanFullWidth) then
        for periodKey, _ in pairs(phase.timePeriods) do
            ImGui.PushID(periodKey)

            self:drawPeriod(phase.timePeriods, periodKey)

            ImGui.PopID()
        end

        if ImGui.Button("+ [Period]") then
            history.addAction(history.getElementChange(self.object))
            table.insert(phase.timePeriods, {
                hour = 1,
                isSequence = false,
                markings = {},
                quantity = 1,
                spotNodeRefs = {}
            })
        end

        ImGui.TreePop()
    end
end

function community:drawPhases(entry)
    if ImGui.TreeNodeEx("Phases", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, phase in pairs(entry.phases) do
            ImGui.PushID(key)

            if ImGui.TreeNodeEx("##" .. tostring(key), ImGuiTreeNodeFlags.SpanFullWidth) then
                self:drawDeleteContext(key, entry.phases)
                drawHeaderText(key, phase.phaseName)

                style.mutedText("Phase Name")
                ImGui.SameLine()
                phase.phaseName, _ = style.trackedTextField(self.object, "##phaseName", phase.phaseName, "uniqueName", 200)

                self:drawPhaseAppearances(phase)
                self:drawPhasePeriods(phase)

                ImGui.TreePop()
            else
                self:drawDeleteContext(key, entry.phases)
                drawHeaderText(key, phase.phaseName)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+ [Phase]") then
            history.addAction(history.getElementChange(self.object))
            table.insert(entry.phases, {
                phaseName = "default",
                appearances = { "default" },
                timePeriods = {}
            })
        end
        ImGui.TreePop()
    end
end

function community:drawEntries()
    if ImGui.TreeNodeEx("Entries", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, entry in pairs(self.entries) do
            ImGui.PushID(key)

            if ImGui.TreeNodeEx("##" .. tostring(key), ImGuiTreeNodeFlags.SpanFullWidth) then
                self:drawDeleteContext(key, self.entries)
                drawHeaderText(key, entry.entryName)

                local max = utils.getTextMaxWidth({"Entry Name", "Character Record", "Initial Phase Name", "Active On Start"}) + 10 * ImGui.GetStyle().ItemSpacing.x

                style.mutedText("Entry Name")
                ImGui.SameLine()
                ImGui.SetCursorPosX(max)
                entry.entryName, _ = style.trackedTextField(self.object, "##entryName", entry.entryName, "uniqueName", 200)

                style.mutedText("Character Record")
                ImGui.SameLine()
                ImGui.SetCursorPosX(max)
                entry.characterRecordId, _ = style.trackedTextField(self.object, "##characterRecordId", entry.characterRecordId, "Character.", 200)

                style.mutedText("Initial Phase Name")
                ImGui.SameLine()
                ImGui.SetCursorPosX(max)
                entry.initialPhaseName, _ = style.trackedTextField(self.object, "##initialPhaseName", entry.initialPhaseName, "", 200)

                style.mutedText("Active On Start")
                ImGui.SameLine()
                ImGui.SetCursorPosX(max)
                entry.entryActiveOnStart, _ = style.trackedCheckbox(self.object, "##activeOnStart", entry.entryActiveOnStart)

                self:drawPhases(entry)

                ImGui.TreePop()
            else
                self:drawDeleteContext(key, self.entries)
                drawHeaderText(key, entry.entryName)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+ [Entry]") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.entries, {
                entryName = "name",
                characterRecordId = "Character.Judy",
                initialPhaseName = "default",
                entryActiveOnStart = true,
                phases = {}
            })
        end

        ImGui.TreePop()
    end
end

function community:draw()
    visualized.draw(self)

    local x = utils.getTextMaxWidth({"Preview Sphere", "CommunityID (NodeRef)"}) + 4 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    self:drawPreviewCheckbox("Preview Sphere", x)
    style.tooltip("Preview a sphere, to make the community selectable in editor mode.")

    style.mutedText("CommunityID (NodeRef)")
    ImGui.SameLine()
    ImGui.SetCursorPosX(x)
    self.nodeRef, _, _ = style.trackedTextField(self.object, "##commID", self.nodeRef, "$/#foobar", 110)

    self:drawEntries()
end

function community:getProperties()
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

function community:export()
    local ref = utils.nodeRefStringToHashString(self.nodeRef)

    local entries = {}

    for _, entry in pairs(self.entries) do
        local phases = {}
        for _, phase in pairs(entry.phases) do
            local periods = {}

            for _, period in pairs(phase.timePeriods) do
                local ids = {}

                for _, ref in pairs(period.spotNodeRefs) do
                    table.insert(ids, {
                        ["$type"] = "worldGlobalNodeID",
                        ["hash"] = utils.nodeRefStringToHashString(ref)
                    })
                end

                table.insert(periods, {
                    ["$type"] = "communityCommunityEntryPhaseTimePeriodData",
                    ["isSequence"] = period.isSequence and 1 or 0,
                    ["periodName"] = {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = self.periodEnums[period.hour + 1]
                    },
                    ["spotNodeIds"] = ids
                })
            end

            table.insert(phases, {
                ["$type"] = "communityCommunityEntryPhaseSpotsData",
                ["entryPhaseName"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = phase.phaseName
                },
                ["timePeriodsData"] = periods
            })
        end

        table.insert(entries, {
            ["$type"] = "communityCommunityEntrySpotsData",
            ["entryName"] = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = entry.entryName
            },
            ["phasesData"] = phases
        })
    end

    local data = visualized.export(self)
    data.type = "worldCompiledCommunityAreaNode_Streamable"
    data.data = {
        ["sourceObjectId"] = {
            ["$type"] = "entEntityID",
            ["hash"] = ref
        },
        ["area"] = {
            ["Data"] = {
                ["$type"] = "communityArea",
                ["entriesData"] = entries
            }
        }
    }

    return data
end

return community