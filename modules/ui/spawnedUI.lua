local utils = require("modules/utils/utils")
local editor = require("modules/utils/editor/editor")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local input = require("modules/utils/input")

---@class spawnedUI
---@field root element
---@field filter string
---@field newGroupName string
---@field spawner spawner?
---@field paths {path : string, ref : element}[]
---@field containerPaths {path : string, ref : element}[]
---@field selectedPaths {path : string, ref : element}[]
---@field filteredPaths {path : string, ref : element}[]
---@field scrollToSelected boolean
---@field clipboard table Serialized elements
---@field elementCount number
---@field depth number
---@field dividerHovered boolean
---@field dividerDragging boolean
---@field filteredWidestName number
---@field draggingSelected boolean
spawnedUI = {
    root = require("modules/classes/editor/element"):new(spawnedUI),
    multiSelectGroup = require("modules/classes/editor/positionableGroup"):new(spawnedUI),
    filter = "",
    newGroupName = "New Group",
    spawner = nil,

    paths = {},
    containerPaths = {},
    selectedPaths = {},
    filteredPaths = {},
    scrollToSelected = false,

    clipboard = {},

    elementCount = 0,
    depth = 0,
    dividerHovered = false,
    dividerDragging = false,
    filteredWidestName = 0,
    draggingSelected = false,
    draggingThreshold = 0.6
}

---Populates paths, containerPaths, selectedPaths and filteredPaths, must be updated each frame
function spawnedUI.cachePaths()
    spawnedUI.paths = {}
    spawnedUI.containerPaths = {}
    spawnedUI.selectedPaths = {}
    spawnedUI.filteredPaths = {}
    spawnedUI.filteredWidestName = 0

    for _, path in pairs(spawnedUI.root:getPathsRecursive(true)) do
        table.insert(spawnedUI.paths, path)

        if path.ref.expandable then
            table.insert(spawnedUI.containerPaths, path)
        end
        if path.ref.selected then
            table.insert(spawnedUI.selectedPaths, path)
        end
        if spawnedUI.filter ~= "" and not path.ref.expandable and (path.ref.name:lower():match(spawnedUI.filter:lower())) ~= nil then
            table.insert(spawnedUI.filteredPaths, path)
            spawnedUI.filteredWidestName = math.max(spawnedUI.filteredWidestName, ImGui.CalcTextSize(path.ref.name))
        end
    end
end

---@param path string
---@return element?
function spawnedUI.getElementByPath(path)
    if path == "" then return spawnedUI.root end

    for _, element in pairs(spawnedUI.paths) do
        if element.path == path then
            return element.ref
        end
    end
end

---Adds an element to the root
---@param element element
function spawnedUI.addRootElement(element)
    element:setParent(spawnedUI.root)
end

---Returns all the elements that are not children of any selected element
---@param elements {path : string, ref : element}[]
---@return {path : string, ref : element}[]
function spawnedUI.getRoots(elements)
    local roots = {}

    for _, entry in pairs(elements) do
        if entry.ref.parent ~= nil and not entry.ref.parent:isParentOrSelfSelected() then -- Check on parent
            table.insert(roots, entry)
        end
    end

    return roots
end

---@protected
---@param elements {path : string, tempPath: string, ref : element}[]
---@return element
function spawnedUI.findCommonParent(elements)
    if #elements == 0 then return spawnedUI.root end
    if #elements == 1 then return elements[1].ref.parent end

    local commonPath = ""

    -- Avoid modifying original paths
    for _, entry in pairs(elements) do
        entry.tempPath = entry.path
    end

    local found = false -- Break condition
    while not found do
        local canidate = string.match(elements[1].tempPath, "^/[^/]+") -- All paths must match with this
        for _, entry in pairs(elements) do
            if not (string.match(entry.tempPath, "^/[^/]+") == canidate) then found = true break end

            entry.tempPath = string.gsub(entry.tempPath, "^/[^/]+", "")
        end
        if not found then
            commonPath = commonPath .. canidate
        end
    end

    if commonPath == "" then return spawnedUI.root end
    return spawnedUI.getElementByPath(commonPath)
end

function spawnedUI.registerHotkeys()
    input.registerImGuiHotkey({ ImGuiKey.Z, ImGuiKey.LeftCtrl }, function()
        history.undo()
    end)
    input.registerImGuiHotkey({ ImGuiKey.Y, ImGuiKey.LeftCtrl }, function()
        history.redo()
    end)
    input.registerImGuiHotkey({ ImGuiKey.A, ImGuiKey.LeftCtrl }, function()
        for _, entry in pairs(spawnedUI.paths) do
            entry.ref:setSelected(true)
        end
    end)
    input.registerImGuiHotkey({ ImGuiKey.C, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        spawnedUI.clipboard = spawnedUI.copy(true)
    end)
    input.registerImGuiHotkey({ ImGuiKey.V, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.clipboard == 0 then return end

        local target
        if #spawnedUI.selectedPaths > 0 then
            target = spawnedUI.selectedPaths[1].ref
        end

        history.addAction(history.getInsert(spawnedUI.paste(spawnedUI.clipboard, target)))
    end)
    input.registerImGuiHotkey({ ImGuiKey.X, ImGuiKey.LeftCtrl }, function ()
        if #spawnedUI.selectedPaths == 0 then return end

        spawnedUI.cut(true)
    end)
    input.registerImGuiHotkey({ ImGuiKey.Delete }, function()
        history.addAction(history.getRemove(spawnedUI.getRoots(spawnedUI.selectedPaths)))
        for _, entry in pairs(spawnedUI.getRoots(spawnedUI.selectedPaths)) do
            entry.ref:remove()
        end
    end)
    input.registerImGuiHotkey({ ImGuiKey.D, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        local data = spawnedUI.copy(true)
        history.addAction(history.getInsert(spawnedUI.paste(data, spawnedUI.selectedPaths[1].ref)))
    end)
    input.registerImGuiHotkey({ ImGuiKey.G, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        spawnedUI.moveToNewGroup(true)
    end)
    input.registerImGuiHotkey({ ImGuiKey.Backspace }, function()
        if #spawnedUI.selectedPaths == 0 then return end
        spawnedUI.moveToRoot(true)
    end)
    input.registerImGuiHotkey({ ImGuiKey.Escape }, function()
        if #spawnedUI.selectedPaths == 0 then return end
        spawnedUI.unselectAll()
    end)
    input.registerImGuiHotkey({ ImGuiKey.H }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        local changes = {}
        for _, entry in pairs(spawnedUI.selectedPaths) do
		    table.insert(changes, history.getElementChange(entry.ref))
            entry.ref:setVisible(not entry.ref.visible, true)
        end

        history.addAction({
            undo = function()
                for _, change in pairs(changes) do
                    change.undo()
                end
            end,
            redo = function()
                for _, change in pairs(changes) do
                    change.redo()
                end
            end
        })
    end)
end

---@protected
function spawnedUI.multiSelectActive()
    return ImGui.IsKeyDown(ImGuiKey.LeftCtrl)
end

---@protected
function spawnedUI.rangeSelectActive()
    return ImGui.IsKeyDown(ImGuiKey.LeftShift)
end

function spawnedUI.unselectAll()
    for _, entry in pairs(spawnedUI.selectedPaths) do
        entry.ref:setSelected(false)
    end
end

---@protected
---@param element element The element that was clicked on with range select active
function spawnedUI.handleRangeSelect(element)
    local paths = spawnedUI.filter ~= "" and spawnedUI.filteredPaths or spawnedUI.paths

    if #spawnedUI.selectedPaths == 0 then -- Select from first to element
        for _, entry in pairs(paths) do
            if entry.ref == element then
                break
            end
            entry.ref:setSelected(true)
        end
    else
        local inRange = false
        for _, entry in pairs(paths) do
            if entry.ref == spawnedUI.selectedPaths[1].ref then -- From first selected down to element
                if inRange then
                    break
                else
                    inRange = true
                end
            end
            if entry.ref == element then -- From element down to first selected
                if not inRange then
                    inRange = true
                else
                    break
                end
            end
            if inRange then
                entry.ref:setSelected(true)
            end
        end
    end
end

---@protected
---@param element element
function spawnedUI.handleDrag(element)
    if ImGui.IsItemHovered() and ImGui.IsMouseDragging(0, spawnedUI.draggingThreshold) and not spawnedUI.draggingSelected then -- Start dragging
        if not element.selected then
            spawnedUI.unselectAll()
            element:setSelected(true)
        end
        spawnedUI.draggingSelected = true
    elseif not ImGui.IsMouseDragging(0, spawnedUI.draggingThreshold) and ImGui.IsItemHovered() and spawnedUI.draggingSelected then -- Drop on element
        spawnedUI.draggingSelected = false

        if element:isValidDropTarget(spawnedUI.selectedPaths) and not element.selected then
            local roots = spawnedUI.getRoots(spawnedUI.selectedPaths)
            local remove = history.getRemove(roots)
            for _, entry in pairs(roots) do
                entry.ref:setParent(element)
            end
            local insert = history.getInsert(roots)
            history.addAction(history.getMove(remove, insert))
        end
    elseif ImGui.IsItemHovered() and spawnedUI.draggingSelected then
        if element.selected then
            ImGui.SetMouseCursor(ImGuiMouseCursor.NotAllowed)
        elseif not element:isValidDropTarget(spawnedUI.selectedPaths) then
            ImGui.SetMouseCursor(ImGuiMouseCursor.NotAllowed)
        else
            ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
        end
    end
end

---@protected
---@param isMulti boolean
---@param element element?
---@return table
function spawnedUI.copy(isMulti, element)
    local copied = {}

    if element and (not element.selected or not isMulti) then
        table.insert(copied, element:serialize())
    elseif isMulti then
        for _, entry in pairs(spawnedUI.selectedPaths) do
            if not entry.ref.parent:isParentOrSelfSelected() then
                table.insert(copied, entry.ref:serialize())
            end
        end
    end

    return copied
end

---@protected
---@param elements table Serialized elements
---@param element element? The element to paste to
---@return element[]
function spawnedUI.paste(elements, element)
    spawnedUI.unselectAll()

    local pasted = {}
    local parent = spawnedUI.root
    local index = #parent.childs + 1

    if element then
        parent = element.parent
        index = utils.indexValue(parent.childs, element) + 1
        if element.expandable then
            parent = element
            index = 1
        end
    end

    for _, entry in pairs(elements) do
        local new = require(entry.modulePath):new(spawnedUI)
        new:load(entry)
        new:setParent(parent, index)
        new:setSelected(true)
        index = index + 1
        table.insert(pasted, new)
    end

    return pasted
end

---@param isMulti boolean
---@param element element?
function spawnedUI.moveToRoot(isMulti, element)
    if isMulti then
        local elements = {}
        for _, entry in pairs(spawnedUI.selectedPaths) do
            if not entry.ref:isRoot(false) and not entry.ref.parent:isParentOrSelfSelected() then
                table.insert(elements, entry.ref)
            end
        end
        local remove = history.getRemove(elements)
        for _, entry in pairs(elements) do
            entry:setParent(spawnedUI.root)
        end
        local insert = history.getInsert(elements)
        history.addAction(history.getMove(remove, insert))
    elseif element then
        spawnedUI.unselectAll()

        local remove = history.getRemove({ element })
        element:setParent(spawnedUI.root)
        local insert = history.getInsert({ element })
        history.addAction(history.getMove(remove, insert))

        element:setSelected(true)
        spawnedUI.scrollToSelected = true
    end
end

---@param isMulti boolean
---@param element element?
function spawnedUI.moveToNewGroup(isMulti, element)
    local group = require("modules/classes/editor/positionableGroup"):new(spawnedUI)
    group.name = "New Group"

    if isMulti then
        local parents = spawnedUI.getRoots(spawnedUI.selectedPaths)
        local common = spawnedUI.findCommonParent(parents)

        -- Find lowest index of element in common parent
        local index = nil
        for _, entry in pairs(parents) do
            local indexInCommon = utils.indexValue(common.childs, entry.ref)

            if indexInCommon ~= -1 then
                if not index then index = indexInCommon end
                index = math.min(index, indexInCommon)
            end
        end

        if not index then index = 1 end

        group:setParent(common, index)
        local insert = history.getInsert({ group })
        local remove = history.getRemove(parents)

        for _, entry in pairs(parents) do
            entry.ref:setParent(group)
        end

        local insertElements = history.getInsert(parents)
        history.addAction(history.getMoveToNewGroup(insert, remove, insertElements))
    elseif element then
        group:setParent(element.parent, utils.indexValue(element.parent.childs, element))
        local insert = history.getInsert({ group }) -- Insertion of group
        local remove = history.getRemove({ element }) -- Removal of element
        element:setParent(group)
        local insertElement = history.getInsert({ element }) -- Insertion of element into group

        history.addAction(history.getMoveToNewGroup(insert, remove, insertElement))
    end

    spawnedUI.unselectAll()
    group:setSelected(true)
    group.editName = true
    group.focusNameEdit = 2
    spawnedUI.scrollToSelected = true
end

---@param isMulti boolean
---@param element element?
function spawnedUI.cut(isMulti, element)
    spawnedUI.clipboard = {}

    if isMulti then
        history.addAction(history.getRemove(spawnedUI.getRoots(spawnedUI.selectedPaths)))
        for _, entry in pairs(spawnedUI.getRoots(spawnedUI.selectedPaths)) do
            table.insert(spawnedUI.clipboard, entry.ref:serialize())
            entry.ref:remove()
        end
    elseif element then
        history.addAction(history.getRemove({ element }))
        table.insert(spawnedUI.clipboard, element:serialize())
        element:remove()
    end
end

function spawnedUI.drawDragWindow()
    if spawnedUI.draggingSelected then
        ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)

        local x, y = ImGui.GetMousePos()
        ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Always)
        if ImGui.Begin("##drag", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.AlwaysAutoResize) then
            local text = #spawnedUI.selectedPaths == 1 and spawnedUI.selectedPaths[1].ref.name or (#spawnedUI.selectedPaths .. " elements")
            ImGui.Text(text)
            ImGui.End()
        end
    end
end

---@protected
---@param element element
function spawnedUI.drawContextMenu(element)
    if ImGui.BeginPopupContextItem("##contextMenu" .. spawnedUI.elementCount, ImGuiPopupFlags.MouseButtonRight) then
        local isMulti = #spawnedUI.selectedPaths > 1 and element.selected

        style.mutedText(isMulti and #spawnedUI.selectedPaths .. " elements" or element.name)
        ImGui.Separator()

        if ImGui.MenuItem("Delete", "DEL") then
            if isMulti then
                history.addAction(history.getRemove(spawnedUI.getRoots(spawnedUI.selectedPaths)))
                for _, entry in pairs(spawnedUI.getRoots(spawnedUI.selectedPaths)) do
                    entry.ref:remove()
                end
            else
                history.addAction(history.getRemove({ element }))
                element:remove()
            end
        end
        if ImGui.MenuItem("Copy", "CTRL-C") then
            spawnedUI.clipboard = spawnedUI.copy(isMulti, element)
        end
        if ImGui.MenuItem("Paste", "CTRL-V") then
            history.addAction(history.getInsert(spawnedUI.paste(spawnedUI.clipboard, element)))
        end
        if ImGui.MenuItem("Cut", "CTRL-X") then
            spawnedUI.cut(isMulti, element)
        end
        if ImGui.MenuItem("Duplicate", "CTRL-D") then
            local data = spawnedUI.copy(isMulti, element)
            history.addAction(history.getInsert(spawnedUI.paste(data, element)))
        end
        if ImGui.MenuItem("Move to Root", "BACKSPACE") then
            spawnedUI.moveToRoot(isMulti, element)
        end
        if ImGui.MenuItem("Move to new group", "CTRL-G") then
            spawnedUI.moveToNewGroup(isMulti, element)
        end

        ImGui.EndPopup()
    end
end

---@protected
---@param element element
function spawnedUI.drawSideButtons(element)
    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

    -- Right side buttons
    local totalX, _ = ImGui.CalcTextSize(IconGlyphs.EyeOutline)
    local gotoX, _ = ImGui.CalcTextSize(IconGlyphs.ArrowTopRight)
    if spawnedUI.filter ~= "" then
        totalX = totalX + gotoX + ImGui.GetStyle().ItemSpacing.x
    end

    for icon, data in pairs(element.quickOperations) do
        if data.condition(element) then
            totalX = totalX + ImGui.CalcTextSize(icon) + ImGui.GetStyle().ItemSpacing.x
        end
    end

    local scrollBarAddition = (ImGui.GetScrollMaxY() > 0 and not spawnedUI.dividerDragging) and ImGui.GetStyle().ScrollbarSize or 0

    local cursorX = ImGui.GetWindowWidth() - totalX - ImGui.GetStyle().CellPadding.x / 2 - scrollBarAddition + ImGui.GetScrollX()
    ImGui.SetCursorPosX(cursorX)

    for icon, data in pairs(element.quickOperations) do
        if data.condition(element) then
            if ImGui.Button(icon) then
                data.operation(element)
            end
            ImGui.SameLine()
            ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))
        end
    end

    if spawnedUI.filter ~= "" then
        if ImGui.Button(IconGlyphs.ArrowTopRight) then
            spawnedUI.unselectAll()
            element:setSelected(true)
            element:expandAllParents()
            spawnedUI.scrollToSelected = true
            spawnedUI.filter = ""
        end
        ImGui.SameLine()
        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))
    end

    local visible = element.visible and not isGettingDragged
    style.pushStyleColor(not visible, ImGuiCol.Text, style.mutedColor)

    if ImGui.Button(IconGlyphs.EyeOutline) then
        if spawnedUI.multiSelectActive() then
            element:setVisibleRecursive(not element.visible)
        else
            element:setVisible(not element.visible)
        end
    end
    style.popStyleColor(not visible)
end

---@protected
---@param element element
function spawnedUI.drawElementChilds(element)
    -- Draw childs
    if element.expandable and element.headerOpen then
        if spawnedUI.filter == "" then spawnedUI.depth = spawnedUI.depth + 1 end
        for _, child in pairs(element.childs) do
            spawnedUI.drawElement(child, false)
        end
        if spawnedUI.filter == "" then spawnedUI.depth = spawnedUI.depth - 1 end
    end
end

---@protected
---@param element element
---@param dummy boolean
function spawnedUI.drawElement(element, dummy)
    spawnedUI.elementCount = spawnedUI.elementCount + 1

    local isGettingDragged = element and element.selected and spawnedUI.draggingSelected

    ImGui.PushID(spawnedUI.elementCount)

    if not dummy then
        ImGui.TableNextRow(ImGuiTableRowFlags.None)
    else
        ImGui.TableNextRow(ImGuiTableRowFlags.None, ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2)
    end
    if spawnedUI.elementCount % 2 == 0 then
        ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, 0.2, 0.2, 0.2, 0.3)
    else
        ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, 0.3, 0.3, 0.3, 0.3)
    end

    ImGui.TableNextColumn()

    if dummy then
        ImGui.PopID()
        return
    end

    -- Base selectable
    ImGui.SetCursorPosX((spawnedUI.depth) * 17 * style.viewSize) -- Indent element
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 15, spawnedUI.cellPadding * 2)

    -- Grey out if getting dragged
    style.pushStyleColor(isGettingDragged, ImGuiCol.HeaderHovered, 0, 0, 0, 0)
    style.pushStyleColor(isGettingDragged, ImGuiCol.HeaderActive, 0, 0, 0, 0)
    style.pushStyleColor(isGettingDragged, ImGuiCol.Header, 0, 0, 0, 0)

    local previous = element.selected
    local newState = ImGui.Selectable("##item" .. spawnedUI.elementCount, element.selected, ImGuiSelectableFlags.SpanAllColumns)
    element:setSelected(newState)
    element:setHovered(ImGui.IsItemHovered())

    if element.selected then
        if spawnedUI.scrollToSelected then
            ImGui.SetScrollHereY(0.5)
            spawnedUI.scrollToSelected = false
        elseif element.selected ~= previous and spawnedUI.rangeSelectActive() then
            spawnedUI.handleRangeSelect(element)
        end
    end

    if not spawnedUI.multiSelectActive() and not spawnedUI.rangeSelectActive() and previous ~= element.selected and not spawnedUI.draggingSelected then
        for _, entry in pairs(spawnedUI.selectedPaths) do
            entry.ref:setSelected(false)
        end
        if previous == true and #spawnedUI.selectedPaths > 1 then element:setSelected(true) end
    elseif spawnedUI.draggingSelected and previous ~= element.selected then -- Disregard any changes due to dragging
        element:setSelected(previous)
    end

    spawnedUI.handleDrag(element)
    spawnedUI.drawContextMenu(element)

    style.popStyleColor(isGettingDragged, 3)
    ImGui.PopStyleVar()

    -- Styles
    ImGui.SameLine()
    ImGui.PushStyleColor(ImGuiCol.Button, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 1 * style.viewSize)
    ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
    style.pushStyleColor(isGettingDragged, ImGuiCol.Text, style.extraMutedColor)

    -- Icon or expand button
    ImGui.SetItemAllowOverlap()
    if not element.expandable and element.icon ~= "" then
        ImGui.AlignTextToFramePadding()
        ImGui.Text(element.icon)
    elseif element.expandable then
        ImGui.PushID(element.name)
        local text = element.headerOpen and IconGlyphs.MenuDownOutline or IconGlyphs.MenuRightOutline
        if ImGui.Button(text) then
            if spawnedUI.multiSelectActive() then
                element:setHeaderStateRecursive(not element.headerOpen)
            else
                element.headerOpen = not element.headerOpen
            end
        end
    end

    ImGui.SameLine()

    ImGui.SetCursorPosX((spawnedUI.depth) * 17 * style.viewSize + 25 * style.viewSize)
    ImGui.AlignTextToFramePadding()
    if element.editName then
        input.windowHovered = false
        if element.focusNameEdit > 0 then
            ImGui.SetKeyboardFocusHere()
            element.focusNameEdit = element.focusNameEdit - 1
        end
        element:drawName()
    else
        ImGui.Text(element.name)
    end

    if ImGui.IsItemHovered() and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
        element.editName = true
        element.focusNameEdit = 1
        element:setSelected(true)
    end

    if spawnedUI.filter ~= "" then
        ImGui.SameLine()
        ImGui.SetCursorPosX(spawnedUI.filteredWidestName + 25 * style.viewSize + 5 * style.viewSize)
        style.mutedText("[" .. element:getPath() .. "]")
    end

    ImGui.SameLine()

    spawnedUI.drawSideButtons(element)

    ImGui.PopStyleColor(2)
    ImGui.PopStyleVar(2)

    ImGui.PopID()

    spawnedUI.drawElementChilds(element)
end

function spawnedUI.drawHierarchy()
    spawnedUI.elementCount = 0
    spawnedUI.depth = 0
    spawnedUI.cellPadding = 3 * style.viewSize

    local _, ySpace = ImGui.GetContentRegionAvail()
    if ySpace - settings.editorBottomSize < 75 * style.viewSize then
        settings.editorBottomSize = ySpace - 75 * style.viewSize
    end
    local nRows = math.floor((ySpace - settings.editorBottomSize) / (ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2))

    ImGui.BeginChild("##hierarchy", 0, ySpace - settings.editorBottomSize, false, ImGuiWindowFlags.NoMove)
    input.updateWindowState()

    -- Start the table
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 7.5 * style.viewSize, spawnedUI.cellPadding)
    ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarSize, 12 * style.viewSize)
    if ImGui.BeginTable("##hierarchyTable", 1, ImGuiTableFlags.ScrollX or ImGuiTableFlags.NoHostExtendX) then
        if spawnedUI.filter == "" then
            for _, child in pairs(spawnedUI.root.childs) do
                spawnedUI.drawElement(child, false)
            end
        else
            for _, entry in pairs(spawnedUI.filteredPaths) do
                spawnedUI.drawElement(entry.ref, false)
            end
        end

        if spawnedUI.elementCount < nRows then
            for _ = 1, nRows - spawnedUI.elementCount do
                spawnedUI.drawElement(nil, true)
            end
        end

        ImGui.EndTable()
    end
    ImGui.PopStyleVar(2)

    ImGui.EndChild()
end

function spawnedUI.drawDivider()
    local minSize = 200 * style.viewSize

    if spawnedUI.dividerHovered then
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.4, 0.4, 0.4, 1.0) -- RGBA values
    else
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.2, 0.2, 0.2, 1.0) -- RGBA values
    end

    ImGui.BeginChild("##verticalDividor", 0, 7.5 * style.viewSize, false, ImGuiWindowFlags.NoMove )
    local wx, wy = ImGui.GetContentRegionAvail()
    local textWidth, textHeight = ImGui.CalcTextSize(IconGlyphs.DragHorizontalVariant)

    ImGui.SetCursorPosX((wx - textWidth) / 2)
    ImGui.SetCursorPosY(1 * style.viewSize + (wy - textHeight) / 2)
    ImGui.Text(IconGlyphs.DragHorizontalVariant)

    ImGui.EndChild()
    if spawnedUI.dividerHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
        settings.editorBottomSize = minSize
        settings.save()
    end
    spawnedUI.dividerHovered = ImGui.IsItemHovered()
    if spawnedUI.dividerHovered and ImGui.IsMouseDragging(0, 0) then
        spawnedUI.dividerDragging = true
    end
    if spawnedUI.dividerDragging and not ImGui.IsMouseDragging(0, 0) then
        spawnedUI.dividerDragging = false
    end
    if spawnedUI.dividerDragging then
        local _, dy = ImGui.GetMouseDragDelta(0, 0)
        settings.editorBottomSize = settings.editorBottomSize - dy
        settings.editorBottomSize = math.max(settings.editorBottomSize, minSize)
        ImGui.ResetMouseDragDelta()

        settings.save()
    end
    if spawnedUI.dividerHovered or spawnedUI.dividerDragging then
        ImGui.SetMouseCursor(ImGuiMouseCursor.ResizeNS)
    end
    ImGui.PopStyleColor()
end

---@protected
function spawnedUI.drawEditorSettings()
    if not editor.active then return end

    if ImGui.TreeNodeEx("Edit Mode Settings") then
        if ImGui.Button("Reset Camera") then
            editor.camera.transition(editor.camera.cameraTransform.position, editor.camera.playerTransform.position, math.max(0.5, (1 / 250) * utils.distanceVector(editor.camera.cameraTransform.position, editor.camera.playerTransform.position)))
        end

        ImGui.TreePop()
    end
end

---@protected
function spawnedUI.drawTop()
    ImGui.PushItemWidth(200 * style.viewSize)
    spawnedUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for element...', spawnedUI.filter, 100)
    ImGui.PopItemWidth()

    if spawnedUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            spawnedUI.filter = ''
            if #spawnedUI.selectedPaths == 1 then
                spawnedUI.selectedPaths[1].ref:expandAllParents()
                spawnedUI.scrollToSelected = true
            end
        end
    end

    ImGui.PushItemWidth(200 * style.viewSize)
    spawnedUI.newGroupName = ImGui.InputTextWithHint('##newG', 'New group name...', spawnedUI.newGroupName, 100)
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("Add group") then
        local group = require("modules/classes/editor/positionableGroup"):new(spawnedUI)
        group.name = spawnedUI.newGroupName
        spawnedUI.addRootElement(group)
        history.addAction(history.getInsert({ group }))
    end

    style.pushButtonNoBG(true)

    local state = editor.active
    -- style.pushStyleColor(state, ImGuiCol.Text, 0xfffcdb03)
    if ImGui.Button(IconGlyphs.Rotate3d) then
        editor.toggle(not editor.active)
    end
    -- style.popStyleColor(state)
    style.tooltip("Toggle 3D-Editor mode")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ContentSaveAllOutline) then
        for _, entry in pairs(spawnedUI.paths) do
            if utils.isA(entry.ref, "positionableGroup") and entry.ref.parent ~= nil and entry.ref.parent:isRoot(true) then
                entry.ref:save()
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.CollapseAllOutline) then
        spawnedUI.root:setHeaderStateRecursive(false)
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ExpandAllOutline) then
        spawnedUI.root:setHeaderStateRecursive(true)
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.EyeMinusOutline) then
        if spawnedUI.filter ~= "" then
            for _, entry in pairs(spawnedUI.filteredPaths) do
                entry.ref:setVisible(false)
            end
        else
            spawnedUI.root:setVisibleRecursive(false)
        end
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.EyePlusOutline) then
        if spawnedUI.filter ~= "" then
            for _, entry in pairs(spawnedUI.filteredPaths) do
                entry.ref:setVisible(true)
            end
        else
            spawnedUI.root:setVisibleRecursive(true)
        end
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.Undo) then
        history.undo()
    end
    if ImGui.IsItemHovered() then style.setCursorRelative(10, 10) end
    style.tooltip(tostring(history.index) .. " actions left")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.Redo) then
        history.redo()
    end
    if ImGui.IsItemHovered() then style.setCursorRelative(10, 10) end
    style.tooltip(tostring(#history.actions - history.index) .. " actions left")

    style.pushButtonNoBG(false)

    spawnedUI.drawEditorSettings()
end

function spawnedUI.drawProperties()
    local _, wy = ImGui.GetContentRegionAvail()
    ImGui.BeginChild("##properties", 0, wy, false, ImGuiWindowFlags.HorizontalScrollbar)

    local nSelected = #spawnedUI.selectedPaths
    spawnedUI.multiSelectGroup.childs = {}

    if nSelected == 0 then
        style.mutedText("Nothing selected.")
    elseif nSelected == 1 then
        spawnedUI.selectedPaths[1].ref:drawProperties()
    else
        style.mutedText("Selection (" .. nSelected .. " elements)")
        style.spacedSeparator()
        for _, entry in pairs(spawnedUI.getRoots(spawnedUI.selectedPaths)) do
            table.insert(spawnedUI.multiSelectGroup.childs, entry.ref)
        end
        spawnedUI.multiSelectGroup:drawProperties()
    end

    ImGui.EndChild()
end

function spawnedUI.draw()
    spawnedUI.cachePaths()

    spawnedUI.drawTop()

    ImGui.Separator()
    ImGui.Spacing()

    ImGui.AlignTextToFramePadding()

    spawnedUI.drawDragWindow()
    spawnedUI.drawHierarchy()
    spawnedUI.drawDivider()
    spawnedUI.drawProperties()

    -- Dropped on not a valid target
    if spawnedUI.draggingSelected and not ImGui.IsMouseDragging(0, spawnedUI.draggingThreshold) then
        spawnedUI.draggingSelected = false
    end
end

return spawnedUI