local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---@class favoritesUI
---@field spawnUI spawnUI?
---@field filter string
---@field tagAddFilter string
---@field tagFilterFilter string
---@field newTag string
---@field tagAddSize table | {x: number, y: number}
---@field tagFilterSize table | {x: number, y: number}
---@field openPopup boolean
---@field popupItem favorite?
---@field categories category[]
local favoritesUI = {
    spawnUI = nil,
    filter = "",
    tagAddFilter = "",
    tagFilterFilter = "",
    newTag = "",
    tagAddSize = { x = 0, y = 0 },
    tagFilterSize = { x = 0, y = 0 },

    categories = {},

    openPopup = false,
    popupItem = nil
}

---@param spawner spawner
function favoritesUI.init(spawner)
    favoritesUI.spawnUI = spawner.baseUI.spawnUI
end

function favoritesUI.getAllTags(filter)
    local tags = {}

    for _, category in pairs(favoritesUI.categories) do
        for _, favorite in pairs(category.favorites) do
            for tag, _ in pairs(favorite.tags) do
                if (filter == "" or tag:lower():match(filter:lower())) and not tags[tag] then
                    tags[tag] = true
                end
            end
        end
    end

    if favoritesUI.popupItem then
        for tag, _ in pairs(favoritesUI.popupItem.tags) do
            if (filter == "" or tag:lower():match(filter:lower())) and not tags[tag] then
                tags[tag] = true
            end
        end
    end

    tags = utils.getKeys(tags)
    table.sort(tags)

    return tags
end

function favoritesUI.drawTagSelect(selected, canAdd, filter)
    local x, y = 0, 0

    ImGui.SetNextItemWidth(175 * style.viewSize)
    filter, _ = ImGui.InputTextWithHint("##tagFilter", "Search for tag...", filter, 100)

    if filter ~= "" then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            filter = ""
        end
        style.pushButtonNoBG(false)
    end

    local tags = favoritesUI.getAllTags(filter)
    local changed = false

    if canAdd then
        ImGui.SetNextItemWidth(175 * style.viewSize)
        favoritesUI.newTag, changed = ImGui.InputTextWithHint("##newTag", "New tag...", favoritesUI.newTag, 15)

        if favoritesUI.newTag ~= "" then
            ImGui.SameLine()
            style.pushButtonNoBG(true)
            if ImGui.Button(IconGlyphs.TagPlusOutline) then
                selected[favoritesUI.newTag] = true
                favoritesUI.newTag = ""
                changed = true
            end
            style.pushButtonNoBG(false)
        end
    end

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.CollapseAllOutline) then
        selected = {}
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ExpandAllOutline) then
        for _, tag in pairs(tags) do
            selected[tag] = true
        end
    end
    style.pushButtonNoBG(false)

    local nColumns = 3
    if ImGui.BeginTable("##tagSelect", nColumns, ImGuiTableFlags.SizingFixedSame) then
        for row = 1, math.ceil(#tags / nColumns) do
            ImGui.TableNextRow()
            for col = 1, nColumns do
                ImGui.TableSetColumnIndex(col - 1)

                local tagName = tags[(row - 1) * nColumns + col]
                if tagName then
                    local state, changed = ImGui.Checkbox(tagName, selected[tagName] ~= nil)
                    if changed then
                        if not state then
                            selected[tagName] = nil
                        else
                            selected[tagName] = true
                        end
                        changed = true
                    end
                    y = ImGui.GetCursorPosY()
                end
            end
        end

        x = math.max(ImGui.GetColumnWidth() * math.min(#tags, nColumns), 175 * style.viewSize)
        ImGui.EndTable()
        x = x + ImGui.GetCursorPosX() + 30 * style.viewSize + (ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0) -- Account for add button, scrollbar and tree node indent

        if #tags == 0 then
            style.mutedText("No tags.")
            y = ImGui.GetCursorPosY()
        end
    end

    return selected, changed, { x = x, y = y }, filter
end

function favoritesUI.addNewItem(serialized)
    favoritesUI.openPopup = true

    local favorite = require("modules/classes/favorites/favorite"):new(favoritesUI)
    favorite.data = serialized
    favoritesUI.popupItem = favorite
end

function favoritesUI.drawEditFavoritePopup()
    if ImGui.BeginPopupContextItem("##addFavorite") then
        local noCategory = favoritesUI.popupItem.category == nil

        style.setNextItemWidth(200)
        if favoritesUI.openPopup then
            favoritesUI.openPopup = false
            ImGui.SetKeyboardFocusHere()
        end
        favoritesUI.popupItem.name, changed = ImGui.InputTextWithHint("##name", "Name...", favoritesUI.popupItem.name, 100)
        if changed and not noCategory then
            --save
        end
        if ImGui.TreeNodeEx("Tags", ImGuiTreeNodeFlags.SpanFullWidth) then
            if ImGui.BeginChild("##tags", favoritesUI.tagAddSize.x, math.min(favoritesUI.tagAddSize.y, 400 * style.viewSize), false) then
                favoritesUI.popupItem.tags, changed, favoritesUI.tagAddSize, favoritesUI.tagAddFilter = favoritesUI.drawTagSelect(favoritesUI.popupItem.tags, true, favoritesUI.tagAddFilter)
                if changed and not noCategory then
                    --save
                end

                ImGui.EndChild()
            end
            ImGui.TreePop()
        end

        ImGui.Separator()

        style.pushButtonNoBG(true)
        style.pushGreyedOut(noCategory)
        if ImGui.Button(IconGlyphs.CheckCircleOutline) and not noCategory then
            favoritesUI.popupItem = nil
            ImGui.CloseCurrentPopup()
        end
        if noCategory then
            style.tooltip("Please assign a category to this favorite before saving.")
        end
        style.popGreyedOut(noCategory)
        style.pushButtonNoBG(false)

        style.pushButtonNoBG(true)
        ImGui.SameLine()
        if ImGui.Button(IconGlyphs.Delete) then
            favoritesUI.popupItem = nil
            ImGui.CloseCurrentPopup()
        end
        style.pushButtonNoBG(false)
        ImGui.EndPopup()
    elseif not favoritesUI.openPopup then
        favoritesUI.popupItem = nil
    end

    if favoritesUI.openPopup then
        ImGui.OpenPopup("##addFavorite")
    end
end

local f = {}

function favoritesUI.draw()
    ImGui.SetNextItemWidth(300 * style.viewSize)
    favoritesUI.filter, changed = ImGui.InputTextWithHint("##filter", "Search by name... (Supports pattern matching)", favoritesUI.filter, 100)

    if favoritesUI.filter ~= "" then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            favoritesUI.filter = ""
        end
        style.pushButtonNoBG(false)
    end

    if ImGui.TreeNodeEx("Spawn Options", ImGuiTreeNodeFlags.SpanFullWidth) then
        favoritesUI.spawnUI.drawTargetGroupSelector()
        favoritesUI.spawnUI.drawSpawnPosition()

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Search Tags", ImGuiTreeNodeFlags.SpanFullWidth) then
        if ImGui.BeginChild("##searchTags", -1, math.min(favoritesUI.tagFilterSize.y, 300 * style.viewSize), false) then
            f, changed, favoritesUI.tagFilterSize, favoritesUI.tagFilterFilter = favoritesUI.drawTagSelect(f, false, favoritesUI.tagFilterFilter)
            ImGui.EndChild()
        end
        ImGui.TreePop()
    end

    style.spacedSeparator()
end

return favoritesUI