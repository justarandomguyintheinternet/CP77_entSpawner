local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local input = require("modules/utils/input")

---@class favoritesUI
---@field spawnUI spawnUI?
---@field newItemCategory string
---@field tagAddFilter string Tag filter for adding new tags
---@field tagFilterFilter string Tag filter for filtering tags
---@field tagMergeFilter string
---@field tagMergeTags table
---@field newTag string
---@field newMergeTag string
---@field tagAddSize table | {x: number, y: number}
---@field tagFilterSize table | {x: number, y: number}
---@field tagMergeSize table | {x: number, y: number}
---@field openPopup boolean
---@field popupItem favorite?
---@field categories category[]
local favoritesUI = {
    spawnUI = nil,

    newItemCategory = "",
    newCategoryName = "New Category",
    newCategoryIcon = "EmoticonOutline",
    newCategoryIconSearch = "",
    selectCategorySearch = "",
    tagAddFilter = "",
    tagFilterFilter = "",
    tagMergeFilter = "",
    tagMergeTags = {},
    newTag = "",
    newMergeTag = "",
    tagAddSize = { x = 0, y = 0 },
    tagFilterSize = { x = 0, y = 0 },
    tagMergeSize = { x = 0, y = 0 },

    categories = {},

    openPopup = false,
    popupItem = nil
}
local iconKeys = {}

---@param spawner spawner
function favoritesUI.init(spawner)
    favoritesUI.spawnUI = spawner.baseUI.spawnUI

    iconKeys = utils.getKeys(IconGlyphs)
    table.sort(iconKeys)

    for _, file in pairs(dir("data/favorite")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local category = require("modules/classes/favorites/category"):new(favoritesUI)
            category:load(config.loadFile("data/favorite/" .. file.name), file.name)

            if favoritesUI.categories[category.name] then
                local target = favoritesUI.categories[category.name]
                local origin = category

                if #target.favorites < #origin.favorites then
                    target = origin
                    origin = favoritesUI.categories[category.name]
                end
                target:merge(origin)

                -- Merging will remove category.name from the list, so we have to re-add it (Due to identical names)
                favoritesUI.categories[target.name] = target
            else
                favoritesUI.categories[category.name] = category
            end
        end
    end
end

function favoritesUI.updateCategoryName(oldName, newName)
    favoritesUI.categories[newName] = favoritesUI.categories[oldName]
    favoritesUI.categories[oldName] = nil
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

---@param selected table Hashtable of selected tags
---@param canAdd boolean Whether new tags can be added
---@param filter string Filter for tags
---@param showANDFilter boolean
---@return table selected
---@return boolean changed
---@return table size
---@return string filter
function favoritesUI.drawTagSelect(selected, canAdd, filter, showANDFilter)
    local x, y = 0, 0

    -- Search in existing tags
    ImGui.SetNextItemWidth(175 * style.viewSize)
    filter, _ = ImGui.InputTextWithHint("##tagFilter", "Search for tag...", filter, 100)

    if style.drawNoBGConditionalButton(filter ~= "", IconGlyphs.Close) then
        filter = ""
    end

    local tags = favoritesUI.getAllTags(filter)
    local edited = false

    -- Add new tag
    if canAdd then
        ImGui.SetNextItemWidth(175 * style.viewSize)
        favoritesUI.newTag, _ = ImGui.InputTextWithHint("##newTag", "New tag...", favoritesUI.newTag, 15)

        if style.drawNoBGConditionalButton(favoritesUI.newTag ~= "", IconGlyphs.TagPlusOutline) then
            if not selected[favoritesUI.newTag] then
                selected[favoritesUI.newTag] = true
                if not settings.favoritesTagsAND then
                    settings.filterTags[favoritesUI.newTag] = true
                    settings.save()
                end
            end
            favoritesUI.newTag = ""
            edited = true
        end
    end

    -- Select/Unselect all
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.CollapseAllOutline) then
        selected = {}
        edited = true
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ExpandAllOutline) then
        for _, tag in pairs(tags) do
            selected[tag] = true
        end
        edited = true
    end
    style.pushButtonNoBG(false)
    if showANDFilter then
        ImGui.SameLine()
        local AND = not settings.favoritesTagsAND
        style.pushButtonNoBG(true)
        style.pushStyleColor(AND, ImGuiCol.Text, style.mutedColor)
        if ImGui.Button(IconGlyphs.SetCenter) then
            settings.favoritesTagsAND = not settings.favoritesTagsAND
            settings.save()
        end
        style.popStyleColor(AND)
        style.pushButtonNoBG(false)
        style.tooltip("AND filter mode (Leave off for OR filter)")
    end

    -- Draw table of tags
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
                        edited = true
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

    return selected, edited, { x = x, y = y }, filter
end

function favoritesUI.addNewItem(serialized, name, icon)
    favoritesUI.openPopup = true

    -- Null transforms, to make deep comparing for merging possible
    if serialized.modulePath == "modules/classes/editor/spawnableElement" then
        serialized.pos = { x = 0, y = 0, z = 0, w = 0 }
        serialized.spawnable.position = { x = 0, y = 0, z = 0, w = 0 }
        serialized.spawnable.rotation = { roll = 0, pitch = 0, yaw = 0 }
        serialized.spawnable.nodeRef = ""

        -- Do this to account for old bug where during AMM import things would get converted to base entity class
        if serialized.spawnable.modulePath == "entity/entity" then
            serialized.spawnable.modulePath = "entity/entityTemplate"
        end
    end
    serialized.visible = true
    serialized.headerOpen = false

    local favorite = require("modules/classes/favorites/favorite"):new(favoritesUI)
    favorite.data = serialized
    favorite.name = name
    favorite.category = favoritesUI.categories[favoritesUI.newItemCategory]
    if favorite.category then
        favorite.category:addFavorite(favorite)
    end

    local iconKey = utils.indexValue(IconGlyphs, icon)
    if iconKey == -1 then iconKey = "" end
    favorite.icon = iconKey
    favoritesUI.popupItem = favorite
end

function favoritesUI.drawEditFavoritePopup()
    -- Do this to make sure cursor is over the popup, so if edit mode is active Shift-A doesnt activate the menu
    if ImGui.IsPopupOpen("##addFavorite") then
        style.setCursorRelativeAppearing(-5, -5)
    end

    if ImGui.BeginPopupContextItem("##addFavorite") then
        input.updateContext("main")

        local noCategory = favoritesUI.popupItem.category == nil

        -- Edit name
        style.setNextItemWidth(200)
        if favoritesUI.openPopup then
            favoritesUI.openPopup = false
            ImGui.SetKeyboardFocusHere()
        end
        favoritesUI.popupItem.name, changed = ImGui.InputTextWithHint("##name", "Name...", favoritesUI.popupItem.name, 100)
        if changed then
            favoritesUI.popupItem.data.name = favoritesUI.popupItem.name
            if not noCategory then
                favoritesUI.popupItem.category:save()
            end
        end
        if not noCategory and favoritesUI.popupItem.category:isNameDuplicate(favoritesUI.popupItem.name) then
            ImGui.SameLine()
            style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
            style.tooltip("Name already exists in this category.")
        end

        -- Select tag
        if ImGui.TreeNodeEx("Tags", ImGuiTreeNodeFlags.SpanFullWidth) then
            if ImGui.BeginChild("##tags", favoritesUI.tagAddSize.x, math.min(favoritesUI.tagAddSize.y, 400 * style.viewSize), false) then
                favoritesUI.popupItem.tags, changed, favoritesUI.tagAddSize, favoritesUI.tagAddFilter = favoritesUI.drawTagSelect(favoritesUI.popupItem.tags, true, favoritesUI.tagAddFilter, false)
                if changed and not noCategory then
                    if favoritesUI.popupItem.category.grouped then
                        favoritesUI.popupItem.category:loadVirtualGroups()
                    end
                    favoritesUI.popupItem.category:save()
                end

                ImGui.EndChild()
            end
            ImGui.TreePop()
        end

        -- Select category
        local categoryName, changed = favoritesUI.drawSelectCategory(favoritesUI.popupItem.category and favoritesUI.popupItem.category.name or "No Category")
        if changed then
            favoritesUI.newItemCategory = categoryName -- Just use the last selected category
            if favoritesUI.popupItem.category then
                favoritesUI.popupItem.category:removeFavorite(favoritesUI.popupItem)
            end
            favoritesUI.categories[categoryName]:addFavorite(favoritesUI.popupItem)
        end

        ImGui.Separator()

        -- Confirm / delete
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
            if favoritesUI.popupItem.category then
                favoritesUI.popupItem.category:removeFavorite(favoritesUI.popupItem)
            end
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

function favoritesUI.removeUnusedTags()
    local tags = favoritesUI.getAllTags("")
    local changed = false

    for tag, _ in pairs(settings.filterTags) do
        if not utils.has_value(tags, tag) then
            settings.filterTags[tag] = nil
            changed = true
        end
    end

    if changed then
        settings.save()
    end
end

function favoritesUI.drawSelectIcon(current, search)
    local changed = false

    style.setNextItemWidth(42)
    if (ImGui.BeginCombo("##icon", IconGlyphs[current])) then
        input.updateContext("main")

        local interiorWidth = 250 - (2 * ImGui.GetStyle().FramePadding.x) - 30
        style.setNextItemWidth(interiorWidth)
        search, _ = ImGui.InputTextWithHint("##iconSearch", "Icon...", search, 100)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            search = ""
        end
        style.pushButtonNoBG(false)

        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 120 * style.viewSize) then
            for _, key in pairs(iconKeys) do
                if key:lower():match(search:lower()) and ImGui.Selectable(IconGlyphs[key] .. "|" .. key) then
                    current = key
                    changed = true
                    ImGui.CloseCurrentPopup()
                end
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()
    end

    return current, search, changed
end

function favoritesUI.drawAddCategory()
    favoritesUI.newCategoryIcon, favoritesUI.newCategoryIconSearch, _ = favoritesUI.drawSelectIcon(favoritesUI.newCategoryIcon, favoritesUI.newCategoryIconSearch)

    ImGui.SameLine()

    style.setNextItemWidth(200)
    favoritesUI.newCategoryName, _ = ImGui.InputTextWithHint("##newCategoryName", "Category Name...", favoritesUI.newCategoryName, 100)

    ImGui.SameLine()

    local categoryExists = favoritesUI.categories[favoritesUI.newCategoryName] ~= nil
    if style.drawNoBGConditionalButton(favoritesUI.newCategoryName ~= "", IconGlyphs.Plus, categoryExists) and not categoryExists then
        local category = require("modules/classes/favorites/category"):new(favoritesUI)
        category:setName(favoritesUI.newCategoryName)
        category.icon = favoritesUI.newCategoryIcon
        category:generateFileName()
        category:save()

        favoritesUI.categories[favoritesUI.newCategoryName] = category
        favoritesUI.newCategoryName = "New Category"
        favoritesUI.newCategoryIcon = "EmoticonOutline"
    end
    if categoryExists then
        style.tooltip("Category already exists.")
    end
end

function favoritesUI.drawSelectCategory(categoryName)
    local changed = false

    style.setNextItemWidth(200)

    if (ImGui.BeginCombo("##selectCategory", (favoritesUI.categories[categoryName] and (IconGlyphs[favoritesUI.categories[categoryName].icon] .. " ") or "") .. categoryName)) then
        input.updateContext("main")

        local interiorWidth = 225 - (2 * ImGui.GetStyle().FramePadding.x) - 30
        style.setNextItemWidth(interiorWidth)
        favoritesUI.selectCategorySearch, _ = ImGui.InputTextWithHint("##selectCategorySearch", "Category Name...", favoritesUI.selectCategorySearch, 100)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            favoritesUI.selectCategorySearch = ""
        end
        style.pushButtonNoBG(false)

        local categories = utils.getKeys(favoritesUI.categories)
        table.sort(categories)

        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 120 * style.viewSize) then
            for _, key in pairs(categories) do
                if key:lower():match(favoritesUI.selectCategorySearch:lower()) and ImGui.Selectable(IconGlyphs[favoritesUI.categories[key].icon] .. " " .. key) then
                    categoryName = key
                    ImGui.CloseCurrentPopup()
                    changed = true
                end
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()
    end

    return categoryName, changed
end

function favoritesUI.pushRow(context)
    ImGui.TableNextRow(ImGuiTableRowFlags.None, ImGui.GetFrameHeight() + context.padding * 2 - style.viewSize * 2)
    if context.row % 2 == 0 then
        ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, 0.2, 0.2, 0.2, 0.3)
    else
        ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, 0.3, 0.3, 0.3, 0.3)
    end

    ImGui.TableNextColumn()
end

function favoritesUI.drawMain()
    local cellPadding = 3 * style.viewSize
    local _, y = ImGui.GetContentRegionAvail()
    y = math.max(y, 300 * style.viewSize)
    local nRows = math.floor(y / (ImGui.GetFrameHeight() + cellPadding * 2 - style.viewSize * 2))

    local context = {
        row = 0,
        depth = 0,
        padding = cellPadding
    }

    if ImGui.BeginChild("##favoritesList", -1, y, false) then
        if ImGui.BeginTable("##favoritesListTable", 1, ImGuiTableFlags.ScrollX or ImGuiTableFlags.NoHostExtendX) then
            local keys = utils.getKeys(favoritesUI.categories)
            table.sort(keys)

            for _, key in pairs(keys) do
                context.depth = 0
                favoritesUI.categories[key]:draw(context)
            end

            if context.row < nRows then
                for i = context.row, nRows - 1 do
                    favoritesUI.pushRow(context)
                    context.row = context.row + 1
                end
            end

            ImGui.EndTable()
        end
        ImGui.EndChild()
    end
end

function favoritesUI.drawMergeTags()
    if ImGui.TreeNodeEx("Tags to rename / merge", ImGuiTreeNodeFlags.SpanFullWidth) then
        if ImGui.BeginChild("##mergeTags", -1, math.min(favoritesUI.tagMergeSize.y, 300 * style.viewSize), false) then
            favoritesUI.tagMergeTags, _, favoritesUI.tagMergeSize, favoritesUI.tagMergeFilter = favoritesUI.drawTagSelect(favoritesUI.tagMergeTags, false, favoritesUI.tagMergeFilter, false)
            ImGui.EndChild()
        end
        ImGui.TreePop()
    end

    style.mutedText("New tag name")
    ImGui.SameLine()
    style.setNextItemWidth(200)
    favoritesUI.newMergeTag, _ = ImGui.InputTextWithHint("##newMergeTag", "New tag name...", favoritesUI.newMergeTag, 15)

    local newTagNotEmpty = favoritesUI.newMergeTag ~= ""
    if newTagNotEmpty then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
    end
    if favoritesUI.newMergeTag ~= "" and ImGui.Button(IconGlyphs.CheckCircleOutline) then
        for _, category in pairs(favoritesUI.categories) do
            category:renameTags(favoritesUI.tagMergeTags, favoritesUI.newMergeTag)
        end

        favoritesUI.newMergeTag = ""
        favoritesUI.tagMergeTags = {}
    end
    style.pushButtonNoBG(newTagNotEmpty and false or true)
end

function favoritesUI.draw()
    favoritesUI.removeUnusedTags()

    style.setNextItemWidth(250)
    settings.favoritesFilter, changed = ImGui.InputTextWithHint("##filter", "Search by name... (Supports pattern matching)", settings.favoritesFilter, 100)
    if changed then
        settings.save()
    end

    if style.drawNoBGConditionalButton(settings.favoritesFilter ~= "", IconGlyphs.Close) then
        settings.favoritesFilter = ""
        settings.save()
    end

    if ImGui.TreeNodeEx("Spawn Options", ImGuiTreeNodeFlags.SpanFullWidth) then
        favoritesUI.spawnUI.drawTargetGroupSelector()
        favoritesUI.spawnUI.drawSpawnPosition()

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Add Category", ImGuiTreeNodeFlags.SpanFullWidth) then
        favoritesUI.drawAddCategory()

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Rename Tags", ImGuiTreeNodeFlags.SpanFullWidth) then
        favoritesUI.drawMergeTags()

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Search Tags", ImGuiTreeNodeFlags.SpanFullWidth) then
        if ImGui.BeginChild("##searchTags", -1, math.min(favoritesUI.tagFilterSize.y, 300 * style.viewSize), false) then
            settings.filterTags, changed, favoritesUI.tagFilterSize, favoritesUI.tagFilterFilter = favoritesUI.drawTagSelect(settings.filterTags, false, favoritesUI.tagFilterFilter, true)
            if changed then
                settings.save()
            end

            ImGui.EndChild()
        end
        ImGui.TreePop()
    end

    style.spacedSeparator()

    favoritesUI.drawMain()
end

return favoritesUI