local area = require("modules/classes/spawn/area/area")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local registry = require("modules/utils/nodeRefRegistry")

---Class for worldGuardAreaNode
---@class guardArea : area
---@field private communityEntries table
---@field private combatCommunityEntries table
---@field private pursuitArea string
---@field private pursuitRange number
---@field private maxGuardPropertyWidth number
local guardArea = setmetatable({}, { __index = area })

local function cname(value)
    return {
        ["$type"] = "CName",
        ["$storage"] = "string",
        ["$value"] = value ~= "" and value or "None"
    }
end

local function nodeRef(value)
    if value and value ~= "" then
        return {
            ["$type"] = "NodeRef",
            ["$storage"] = "string",
            ["$value"] = value
        }
    end

    return {
        ["$type"] = "NodeRef",
        ["$storage"] = "uint64",
        ["$value"] = "0"
    }
end

local function defaultConnectedCommunity()
    return {
        communityRef = "",
        isPrimary = true,
        names = {}
    }
end

function guardArea:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Guard Area"
    o.spawnDataPath = "data/spawnables/area/guardArea/"
    o.modulePath = "area/guardArea"
    o.node = "worldGuardAreaNode"
    o.description = "Defines an area guarded by one or more community entries."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.ShieldAccount or IconGlyphs.Select

    o.communityEntries = { defaultConnectedCommunity() }
    o.combatCommunityEntries = {}
    o.pursuitArea = ""
    o.pursuitRange = 0
    o.maxGuardPropertyWidth = nil

    setmetatable(o, { __index = self })
   	return o
end

function guardArea:save()
    local data = area.save(self)

    data.communityEntries = utils.deepcopy(self.communityEntries)
    data.combatCommunityEntries = utils.deepcopy(self.combatCommunityEntries)
    data.pursuitArea = self.pursuitArea
    data.pursuitRange = self.pursuitRange

    return data
end

function guardArea:addConnectedCommunity()
    history.addAction(history.getElementChange(self.object))
    table.insert(self.communityEntries, defaultConnectedCommunity())
end

function guardArea:drawPropertyLabel(label)
    local x = ImGui.GetCursorPosX()
    style.mutedText(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(x + self.maxGuardPropertyWidth)
end

function guardArea:drawConnectedCommunity(entry, index)
    entry.names = entry.names or {}
    entry.communityRef = entry.communityRef or ""
    entry.isPrimary = entry.isPrimary ~= false

    if ImGui.TreeNodeEx(string.format("Community Entry %d", index), ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawPropertyLabel("Community Ref")
        entry.communityRef, _ = registry.drawNodeRefSelector(style.getMaxWidth(250) - 30, entry.communityRef, self.object, true)

        self:drawPropertyLabel("Primary")
        entry.isPrimary, _ = style.trackedCheckbox(self.object, "##isPrimary", entry.isPrimary)
        style.tooltip("Primary guard area community.")

        if ImGui.TreeNodeEx("Entry Names", ImGuiTreeNodeFlags.SpanFullWidth) then
            for nameIndex, _ in pairs(entry.names) do
                ImGui.PushID(nameIndex)

                entry.names[nameIndex], _ = style.trackedTextField(self.object, "##entryName", entry.names[nameIndex], "enemy_01", style.getMaxWidth(190) - 30)
                ImGui.SameLine()
                if ImGui.Button(IconGlyphs.Delete) then
                    history.addAction(history.getElementChange(self.object))
                    table.remove(entry.names, nameIndex)
                    ImGui.PopID()
                    break
                end
                style.tooltip("Delete")

                ImGui.PopID()
            end

            if ImGui.Button("+ [Entry Name]") then
                history.addAction(history.getElementChange(self.object))
                table.insert(entry.names, "")
            end
            style.tooltip("Leave names empty to connect the whole community.")

            ImGui.TreePop()
        end

        if ImGui.Button(IconGlyphs.Delete .. "##deleteConnectedCommunity") then
            history.addAction(history.getElementChange(self.object))
            table.remove(self.communityEntries, index)
        end
        style.tooltip("Delete connected community")

        ImGui.TreePop()
    end
end

function guardArea:drawConnectedCommunities()
    if ImGui.TreeNodeEx("Community Entries", ImGuiTreeNodeFlags.SpanFullWidth) then
        for index, entry in pairs(self.communityEntries) do
            ImGui.PushID(index)
            self:drawConnectedCommunity(entry, index)
            ImGui.PopID()
        end

        if ImGui.Button("+ [Community Entry]") then
            self:addConnectedCommunity()
        end

        ImGui.TreePop()
    end
end

function guardArea:draw()
    if not self.maxGuardPropertyWidth then
        self.maxGuardPropertyWidth = utils.getTextMaxWidth({ "Visualize", "Outline Path", "Community Ref", "Pursuit Area", "Pursuit Range" }) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    area.draw(self)

    self:drawPropertyLabel("Pursuit Area")
    self.pursuitArea, _ = registry.drawNodeRefSelector(style.getMaxWidth(250) - 30, self.pursuitArea, self.object, true)
    style.tooltip("Optional pursuit area NodeRef. Leave empty for none.")

    self:drawPropertyLabel("Pursuit Range")
    self.pursuitRange, _, _ = style.trackedIntInput(self.object, "##pursuitRange", self.pursuitRange, 0, 9999, 85)

    self:drawConnectedCommunities()
end

local function exportConnectedCommunity(entry)
    local names = {}

    for _, name in pairs(entry.names or {}) do
        if name and name ~= "" then
            table.insert(names, cname(name))
        end
    end

    return {
        ["$type"] = "AIGuardAreaConnectedCommunity",
        ["communityArea"] = {
            ["$type"] = "gameEntityReference",
            ["dynamicEntityUniqueName"] = cname("None"),
            ["names"] = names,
            ["reference"] = nodeRef(entry.communityRef),
            ["sceneActorContextName"] = cname("None"),
            ["slotName"] = cname("None"),
            ["type"] = "EntityRef"
        },
        ["isPrimary"] = entry.isPrimary ~= false and 1 or 0
    }
end

local function exportConnectedCommunities(entries)
    local data = {}

    for _, entry in pairs(entries or {}) do
        if entry.communityRef and entry.communityRef ~= "" then
            table.insert(data, exportConnectedCommunity(entry))
        end
    end

    return data
end

function guardArea:export()
    local data = area.export(self)
    data.type = "worldGuardAreaNode"

    data.data.communityEntries = exportConnectedCommunities(self.communityEntries)
    data.data.combatCommunityEntries = {}
    data.data.pursuitArea = nodeRef(self.pursuitArea)
    data.data.pursuitRange = math.floor(tonumber(self.pursuitRange) or 0)

    return data
end

return guardArea
