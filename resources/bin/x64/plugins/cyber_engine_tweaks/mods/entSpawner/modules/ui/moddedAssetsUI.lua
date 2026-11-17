local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")
local moddedAssets = require("modules/utils/pipeline/moddedAssets")
local assetAttribution = require("modules/utils/data/assetAttribution")

---Export tab counter of the mod assets used by the listed groups, and its details popup.
local moddedAssetsUI = {}

local POPUP_ID = IconGlyphs.PackageVariantClosed .. " Modded assets##wb-moddedAssets-wui"

---@type { key: string, label: string }[]
local groupByModes = {
    { key = "group", label = "Group" },
    { key = "file", label = "File" },
    { key = "author", label = "Author" },
    { key = "pack", label = "Props Pack" }
}

local state = {
    requestOpen = false,
    groupBy = "group",
    filter = "",
    ---@type boolean? Open state applied to every header for one frame.
    setAllOpen = nil
}

-- Material 700 hues, as 0xRRGGBB.
local palette = {
    0xC62828, 0xAD1457, 0x6A1B9A, 0x4527A0, 0x283593, 0x1565C0, 0x00838F,
    0x00695C, 0x2E7D32, 0x558B2F, 0xEF6C00, 0xD84315, 0x6D4C41, 0x546E7A
}

---@param rgb integer 0xRRGGBB.
---@param alpha integer 0-255.
---@return integer ImGui ABGR color.
local function toImColor(rgb, alpha)
    local r = math.floor(rgb / 65536) % 256
    local g = math.floor(rgb / 256) % 256
    local b = rgb % 256
    return alpha * 16777216 + b * 65536 + g * 256 + r
end

---@param text string
---@return integer
local function hashColor(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + text:byte(i)) % 2147483647
    end
    return palette[(hash % #palette) + 1]
end

---@param attribution AssetAttributionValue
---@param kind "Author"|"Props pack"
---@return string
local function getAttributionTooltip(attribution, kind)
    local method = assetAttribution.methods[attribution.method] or { label = attribution.method, tooltip = "" }
    local confidence = assetAttribution.getConfidence(attribution)

    return string.format("%s: %s\nDetected by: %s (%s)", kind, attribution.name, method.label, confidence)
end

---Draws a colored tag, faded by confidence, with the detection method as tooltip.
---@param attribution AssetAttributionValue?
---@param kind "Author"|"Props pack"
local function drawTag(attribution, kind)
    if not attribution then
        style.mutedText("Unknown")
        if kind == "Author" then
            style.tooltip("No author could be read from the path or its spawn list.")
        end
        return
    end

    local confidence = assetAttribution.getConfidence(attribution)
    local label = attribution.name .. (confidence == "guess" and " ?" or "")
    local rgb = hashColor(kind .. attribution.name)
    local fillAlpha = confidence == "reliable" and 0xFF or (confidence == "likely" and 0xB0 or 0x60)
    local isPack = kind == "Props pack"

    local scale = style.viewSize or 1
    local textWidth, textHeight = ImGui.CalcTextSize(label)
    local height = ImGui.GetTextLineHeight()
    local paddingX = 6 * scale
    local width = textWidth + paddingX * 2
    local x, y = ImGui.GetCursorScreenPos()
    local drawList = ImGui.GetWindowDrawList()
    local radius = (isPack and 3 or height / 2)

    ImGui.ImDrawListAddRectFilled(drawList, x, y, x + width, y + height, toImColor(rgb, isPack and math.floor(fillAlpha * 0.55) or fillAlpha), radius)
    if isPack then
        ImGui.ImDrawListAddRect(drawList, x, y, x + width, y + height, toImColor(rgb, fillAlpha), radius, 0, math.max(1, scale))
    end
    ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize(), x + paddingX, y + math.floor((height - textHeight) / 2), style.regularColor, label)

    ImGui.Dummy(width, height)
    style.tooltip(getAttributionTooltip(attribution, kind))
end

---@param use ModdedAssetUse
---@return string
local function formatElements(use)
    local names = {}
    for name, count in pairs(use.elements) do
        table.insert(names, count > 1 and string.format("%s (x%d)", name, count) or name)
    end
    table.sort(names)

    local maxShown = 12
    local shown = {}
    for i = 1, math.min(#names, maxShown) do
        shown[i] = "  - " .. names[i]
    end
    if #names > maxShown then
        table.insert(shown, string.format("  ... and %d more", #names - maxShown))
    end

    return table.concat(shown, "\n")
end

---@param asset ModdedAssetEntry
local function drawAssetTooltip(asset)
    if not ImGui.IsItemHovered() then return end

    local lines = { asset.path, "" }
    local groups = {}
    for _, use in pairs(asset.groups) do
        table.insert(groups, use)
    end
    table.sort(groups, function (a, b) return a.name < b.name end)

    for _, use in ipairs(groups) do
        table.insert(lines, string.format("%s (%d)", use.name, use.uses))
        table.insert(lines, formatElements(use))
    end

    if #asset.lists > 0 then
        table.insert(lines, "\nListed by:")
        for _, list in ipairs(asset.lists) do
            table.insert(lines, "  - " .. list.file)
        end
    end
    table.insert(lines, "\nRight-click to copy the path.")

    style.tooltip(table.concat(lines, "\n"))
end

---@param id string
---@param path string
local function drawCopyContext(id, path)
    if ImGui.BeginPopupContextItem(id) then
        if ImGui.MenuItem("Copy path") then
            ImGui.SetClipboardText(path)
        end
        ImGui.EndPopup()
    end
end

---Spawn New "Type > Variant" labels of the spawnables using an asset, most used first.
---@param asset ModdedAssetEntry
---@return string[]
local function getTypeLabels(asset)
    if asset.typeLabels then return asset.typeLabels end

    -- Required lazily: spawnUI is loaded by baseUI long before the popup draws.
    local spawnUI = require("modules/ui/spawnUI")
    local getLabel = type(spawnUI) == "table" and spawnUI.getVariantLabelByModulePath or nil
    local counts, labels = {}, {}

    for typeKey, count in pairs(asset.types) do
        local modulePath, nested = moddedAssets.parseTypeKey(typeKey)
        local label = (getLabel and getLabel(modulePath)) or (modulePath ~= "" and modulePath or "Unknown")
        if nested then
            label = label .. " (instance data)"
        end
        if not counts[label] then
            table.insert(labels, label)
        end
        counts[label] = (counts[label] or 0) + count
    end

    table.sort(labels, function (a, b)
        if counts[a] == counts[b] then return a < b end
        return counts[a] > counts[b]
    end)

    asset.typeLabels = labels

    return labels
end

---@param asset ModdedAssetEntry
---@param query string
---@return boolean
local function matchesFilter(asset, query)
    if query == "" then return true end

    local parts = { asset.path, asset.author and asset.author.name or "", asset.pack and asset.pack.name or "", table.concat(getTypeLabels(asset), " ") }
    for _, use in pairs(asset.groups) do
        table.insert(parts, use.name)
    end
    for _, list in ipairs(asset.lists) do
        table.insert(parts, list.file)
    end

    return utils.matchSearch(table.concat(parts, " "):lower(), query:lower())
end

---@class ModdedAssetSection
---@field key string
---@field label string
---@field assets ModdedAssetEntry[]
---@field uses integer
---@field author AssetAttributionValue? Shared by every asset of the section.
---@field pack AssetAttributionValue?
---@field tooltip string?
---@field sortKey string

---@param assets ModdedAssetEntry[]
---@param groupOrder table<string, integer> Project file name -> export list index.
---@return ModdedAssetSection[]
local function buildSections(assets, groupOrder)
    local sections = {}
    local byKey = {}

    local function section(key, label, sortKey)
        local entry = byKey[key]
        if not entry then
            entry = { key = key, label = label, assets = {}, uses = 0, sortKey = sortKey }
            byKey[key] = entry
            table.insert(sections, entry)
        end
        return entry
    end

    for _, asset in ipairs(assets) do
        if state.groupBy == "group" then
            for fileName, use in pairs(asset.groups) do
                local entry = section("g:" .. fileName, use.name, string.format("%06d", groupOrder[fileName] or 0))
                table.insert(entry.assets, asset)
                entry.uses = entry.uses + use.uses
            end
        elseif state.groupBy == "file" then
            if #asset.lists == 0 then
                local entry = section("f:", "Not in any spawn list", "1")
                entry.tooltip = "These assets are not listed by any .txt file in data/spawnables."
                table.insert(entry.assets, asset)
                entry.uses = entry.uses + asset.uses
            end
            for _, list in ipairs(asset.lists) do
                local entry = section("f:" .. list.file, list.file, "0" .. list.file:lower())
                entry.tooltip = "data/spawnables/" .. list.file
                table.insert(entry.assets, asset)
                entry.uses = entry.uses + asset.uses
            end
        elseif state.groupBy == "author" then
            local author = asset.author
            local name = author and author.name or nil
            local entry = section("a:" .. (name or ""), name or "Unknown author", name and ("0" .. name:lower()) or "1")
            if author and (not entry.author or entry.author.score < author.score) then
                entry.author = author
            end
            table.insert(entry.assets, asset)
            entry.uses = entry.uses + asset.uses
        else
            local packName = asset.pack and asset.pack.name or nil
            local packKey = moddedAssets.getPackKey(asset)
            local entry = section("p:" .. packKey, packName or "Unknown pack", packName and ("0" .. packName:lower() .. packKey) or "1")
            entry.author = entry.author or asset.author
            entry.pack = entry.pack or asset.pack
            table.insert(entry.assets, asset)
            entry.uses = entry.uses + asset.uses
        end
    end

    table.sort(sections, function (a, b) return a.sortKey < b.sortKey end)

    return sections
end

---@param section ModdedAssetSection
---@param index integer
local function drawSection(section, index)
    ImGui.TableNextRow()
    ImGui.TableSetColumnIndex(0)

    if state.setAllOpen ~= nil then
        ImGui.SetNextItemOpen(state.setAllOpen)
    end

    local open = ImGui.TreeNodeEx(string.format("%s  (%d)###moddedAssetSection%s", section.label, #section.assets, section.key), ImGuiTreeNodeFlags.SpanFullWidth + ImGuiTreeNodeFlags.DefaultOpen)
    if section.tooltip then
        style.tooltip(section.tooltip)
    end

    if state.groupBy == "author" or state.groupBy == "pack" then
        ImGui.TableSetColumnIndex(2)
        drawTag(section.author, "Author")
        if state.groupBy == "pack" then
            ImGui.TableSetColumnIndex(3)
            drawTag(section.pack, "Props pack")
        end
    end

    ImGui.TableSetColumnIndex(4)
    style.mutedText(tostring(section.uses))

    if not open then return end

    for rowIndex, asset in ipairs(section.assets) do
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.TreeNodeEx(asset.fileName .. "###moddedAsset" .. index .. "_" .. rowIndex, ImGuiTreeNodeFlags.Leaf + ImGuiTreeNodeFlags.NoTreePushOnOpen + ImGuiTreeNodeFlags.SpanFullWidth)
        drawAssetTooltip(asset)
        drawCopyContext("##moddedAssetCtx" .. index .. "_" .. rowIndex, asset.path)

        ImGui.TableSetColumnIndex(1)
        local typeLabels = getTypeLabels(asset)
        ImGui.Text(typeLabels[1] or "-")
        if #typeLabels > 1 then
            ImGui.SameLine()
            style.mutedText(string.format("+%d", #typeLabels - 1))
        end
        style.tooltip(table.concat(typeLabels, "\n"))

        if state.groupBy ~= "author" then
            ImGui.TableSetColumnIndex(2)
            drawTag(asset.author, "Author")
        end
        if state.groupBy ~= "pack" then
            ImGui.TableSetColumnIndex(3)
            drawTag(asset.pack, "Props pack")
        end

        ImGui.TableSetColumnIndex(4)
        local uses = asset.uses
        if state.groupBy == "group" then
            local key = section.key:sub(3)
            uses = asset.groups[key] and asset.groups[key].uses or uses
        end
        ImGui.Text(tostring(uses))
    end

    ImGui.TreePop()
end

---@param report ModdedAssetReport
---@param groups table[]
---@param resolveFileName fun(group: table): string?
local function drawPopupContent(report, groups, resolveFileName)
    style.mutedText(string.format("%d assets, %d uses, %d authors, %d props packs", #report.assets, report.uses, report.authors, report.packs))

    if #report.missingGroups > 0 then
        style.styledText(IconGlyphs.AlertOutline .. " Missing project file: " .. table.concat(report.missingGroups, ", "), style.warnColor)
    end

    ImGui.Spacing()

    ImGui.AlignTextToFramePadding()
    ImGui.Text("Group by:")
    for _, mode in ipairs(groupByModes) do
        ImGui.SameLine()
        if style.switchTabButton(mode.label .. "##moddedAssetsGroupBy" .. mode.key, state.groupBy == mode.key, 0, 0) then
            state.groupBy = mode.key
        end
    end

    state.filter = style.drawSearchFilterRow("##moddedAssetsFilter", state.filter, { width = 260, hint = "Filter by path, author, pack, group or list..." })

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.CollapseAllOutline .. "##moddedAssetsCollapse") then
        state.setAllOpen = false
    end
    style.tooltip("Collapse all")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ExpandAllOutline .. "##moddedAssetsExpand") then
        state.setAllOpen = true
    end
    style.tooltip("Expand all")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.Reload .. "##moddedAssetsRescan") then
        moddedAssets.invalidateAll()
    end
    style.tooltip("Rescan the groups' saved projects")
    style.pushButtonNoBG(false)

    local groupOrder = {}
    for index, group in ipairs(groups) do
        local fileName = resolveFileName(group)
        if fileName and not groupOrder[fileName] then
            groupOrder[fileName] = index
        end
    end

    local filtered = {}
    for _, asset in ipairs(report.assets) do
        if matchesFilter(asset, state.filter) then
            table.insert(filtered, asset)
        end
    end

    local sections = buildSections(filtered, groupOrder)
    local footerHeight = ImGui.GetFrameHeightWithSpacing()
    local _, availableHeight = ImGui.GetContentRegionAvail()
    local tableHeight = math.max(120 * style.viewSize, availableHeight - footerHeight)
    local flags = ImGuiTableFlags.RowBg + ImGuiTableFlags.BordersInnerV + ImGuiTableFlags.BordersOuterH + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY + ImGuiTableFlags.SizingStretchProp

    if ImGui.BeginTable("##moddedAssetsTable", 5, flags, 0, tableHeight) then
        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableSetupColumn("Asset", ImGuiTableColumnFlags.WidthStretch, 0.38)
        ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthStretch, 0.18)
        ImGui.TableSetupColumn("Author", ImGuiTableColumnFlags.WidthStretch, 0.16)
        ImGui.TableSetupColumn("Props Pack", ImGuiTableColumnFlags.WidthStretch, 0.20)
        ImGui.TableSetupColumn("Uses", ImGuiTableColumnFlags.WidthStretch, 0.08)
        ImGui.TableHeadersRow()

        for index, section in ipairs(sections) do
            drawSection(section, index)
        end

        if #sections == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0)
            style.mutedText(#report.assets == 0 and "No modded asset in the listed groups." or "No asset matches the filter.")
        end

        ImGui.EndTable()
    end

    state.setAllOpen = nil

    if ImGui.Button("Close##moddedAssetsClose") then
        ImGui.CloseCurrentPopup()
    end
end

---@param report ModdedAssetReport?
---@param groups table[]
---@param resolveFileName fun(group: table): string?
local function drawPopup(report, groups, resolveFileName)
    if state.requestOpen then
        ImGui.OpenPopup(POPUP_ID)
        state.requestOpen = false
    end

    if not ImGui.IsPopupOpen(POPUP_ID) then return end

    ImGui.SetNextWindowSize(860 * style.viewSize, 560 * style.viewSize, ImGuiCond.Appearing)

    if ImGui.BeginPopupModal(POPUP_ID, true, ImGuiWindowFlags.NoSavedSettings) then
        if report then
            drawPopupContent(report, groups, resolveFileName)
        else
            style.mutedText("Scanning groups...")
        end
        ImGui.EndPopup()
    end
end

---Draws the modded assets counter row and its popup. Scans one saved project per frame.
---@param groups table[] Export list entries.
---@param resolveFileName fun(group: table): string?
function moddedAssetsUI.draw(groups, resolveFileName)
    local report, scanned, total = moddedAssets.update(groups, resolveFileName)

    if total == 0 then return end

    ImGui.AlignTextToFramePadding()
    if not report then
        style.mutedText(string.format("%s Scanning groups for modded assets... (%d/%d)", IconGlyphs.PackageVariantClosed, scanned, total))
    elseif #report.assets == 0 then
        style.mutedText(IconGlyphs.PackageVariantClosed .. " No modded assets used")
        style.tooltip("Every resource used by the listed groups comes from the base game or its DLC.")
    else
        ImGui.Text(string.format("%s %d modded asset%s", IconGlyphs.PackageVariantClosed, #report.assets, #report.assets == 1 and "" or "s"))
        ImGui.SameLine()
        style.mutedText(string.format("from %d author%s, %d props pack%s", report.authors, report.authors == 1 and "" or "s", report.packs, report.packs == 1 and "" or "s"))
        style.tooltip("Resources that are not part of the game. Players will need the mods that ship them.")
    end

    ImGui.SameLine()
    local disabled = not report or #report.assets == 0
    style.pushGreyedOut(disabled)
    if ImGui.Button(style.resolveActionLabel(IconGlyphs.Magnify, "Details", "moddedAssetsOpen")) and not disabled then
        state.requestOpen = true
    end
    style.popGreyedOut(disabled)
    style.tooltip("List the modded assets used by the listed groups")

    drawPopup(report, groups, resolveFileName)
end

---Drops the cached scan of a project after it was saved.
---@param fileName string
function moddedAssetsUI.invalidate(fileName)
    moddedAssets.invalidate(fileName)
end

return moddedAssetsUI
