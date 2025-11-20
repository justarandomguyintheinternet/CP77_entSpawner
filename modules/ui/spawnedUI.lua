local utils = require("modules/utils/utils")
local editor = require("modules/utils/editor/editor")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local input = require("modules/utils/input")
local registry = require("modules/utils/nodeRefRegistry")

---@class spawnedUI
---@field root element
---@field filter string
---@field newGroupName string
---@field newGroupRandomized boolean
---@field spawner spawner?
---@field paths {path : string, ref : element}[]
---@field containerPaths {path : string, ref : element}[]
---@field selectedPaths {path : string, ref : element}[]
---@field filteredPaths {path : string, ref : element}[]
---@field scrollToSelected boolean
---@field openContextMenu {state : boolean, path : string}
---@field clipboard table Serialized elements
---@field elementCount number
---@field depth number
---@field dividerHovered boolean
---@field dividerDragging boolean
---@field filteredWidestName number
---@field draggingSelected boolean
---@field infoWindowSize table
---@field nameBeingEdited boolean
---@field clipper any
---@field clipperIndex number
spawnedUI = {
    root = require("modules/classes/editor/element"):new(spawnedUI),
    multiSelectGroup = require("modules/classes/editor/positionableGroup"):new(spawnedUI),
    filter = "",
    newGroupName = "New_Group",
    newGroupRandomized = false,
    spawner = nil,

    paths = {},
    containerPaths = {},
    selectedPaths = {},
    filteredPaths = {},
    scrollToSelected = false,
    openContextMenu = {
        state = false,
        path = ""
    },
    nameBeingEdited = false,

    clipboard = {},

    elementCount = 0,
    depth = 0,
    dividerHovered = false,
    dividerDragging = false,
    filteredWidestName = 0,
    draggingSelected = false,
    infoWindowSize = { x = 0, y = 0 },

    clipper = nil,
    clipperIndex = 1
}

---Populates paths, containerPaths, selectedPaths and filteredPaths, must be updated each frame
function spawnedUI.cachePaths()
    spawnedUI.paths = {}
    spawnedUI.containerPaths = {}
    spawnedUI.selectedPaths = {}
    spawnedUI.filteredPaths = {}
    spawnedUI.filteredWidestName = 0
    spawnedUI.nameBeingEdited = false

    for _, path in pairs(spawnedUI.root:getPathsRecursive(true)) do
        table.insert(spawnedUI.paths, path)

        if path.ref.expandable then
            table.insert(spawnedUI.containerPaths, path)
        end
        if path.ref.selected then
            table.insert(spawnedUI.selectedPaths, path)
        end
        if spawnedUI.filter ~= "" and not path.ref.expandable and utils.matchSearch(path.ref.name, spawnedUI.filter) then
            table.insert(spawnedUI.filteredPaths, path)
            spawnedUI.filteredWidestName = math.max(spawnedUI.filteredWidestName, ImGui.CalcTextSize(path.ref.name))
        end
        if path.ref.editName then
            spawnedUI.nameBeingEdited = true
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

---@param element element
---@return boolean
function spawnedUI.isOnlySelected(element)
    if #spawnedUI.selectedPaths == 1 and spawnedUI.selectedPaths[1].ref == element then
        return true
    end
    return false
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

---@param element element
---@return number
local function getNumVisibleElementsRecursive(element)
    local num = 1

    if not element.expandable then
        return num
    end

    if element.headerOpen then
        for _, child in pairs(element.childs) do
            num = num + getNumVisibleElementsRecursive(child)
        end
    end

    return num
end

---Returns the total number of elements which should be rendered in the hierarchy
---@return number
function spawnedUI.getNumVisibleElements()
    local num = getNumVisibleElementsRecursive(spawnedUI.root) - 1

    return num
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

---Sets the specified element as the new target for spawning
---@param element element
function spawnedUI.setElementSpawnNewTarget(element)
    local elementPath = element:getPath()
    if not element.expandable then
        elementPath = element.parent:getPath()
    end

    local idx = 1
    for _, entry in pairs(spawnedUI.containerPaths) do
        if entry.path == elementPath then
            break
        end
        idx = idx + 1
    end

    spawnedUI.spawner.baseUI.spawnUI.selectedGroup = idx
end

local function hotkeyRunConditionProperties()
    return input.context.hierarchy.hovered or input.context.hierarchy.focused or (editor.active and (input.context.viewport.hovered or input.context.viewport.focused))
end

local function hotkeyRunConditionGlobal()
    return input.context.hierarchy.hovered or input.context.viewport.hovered
end

function spawnedUI.registerHotkeys()
    input.registerImGuiHotkey({ ImGuiKey.Z, ImGuiKey.LeftCtrl }, function()
        history.undo()
    end)
    input.registerImGuiHotkey({ ImGuiKey.Y, ImGuiKey.LeftCtrl }, function()
        history.redo()
    end)
    input.registerImGuiHotkey({ ImGuiKey.A, ImGuiKey.LeftCtrl }, function()
        if spawnedUI.nameBeingEdited then return end

        for _, entry in pairs(spawnedUI.paths) do
            entry.ref:setSelected(true)
        end
    end, hotkeyRunConditionGlobal)
    input.registerImGuiHotkey({ ImGuiKey.S, ImGuiKey.LeftCtrl }, function()
        for _, entry in pairs(spawnedUI.paths) do
            if utils.isA(entry.ref, "positionableGroup") and entry.ref.supportsSaving and entry.ref.parent ~= nil and entry.ref.parent:isRoot(true) then
                entry.ref:save()
            end
        end
    end)
    input.registerImGuiHotkey({ ImGuiKey.C, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 or spawnedUI.nameBeingEdited then return end

        spawnedUI.clipboard = spawnedUI.copy(true)
    end, hotkeyRunConditionProperties)
    input.registerImGuiHotkey({ ImGuiKey.V, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.clipboard == 0 or spawnedUI.nameBeingEdited then return end

        local target
        if #spawnedUI.selectedPaths > 0 then
            target = spawnedUI.selectedPaths[1].ref
        end

        history.addAction(history.getInsert(spawnedUI.paste(spawnedUI.clipboard, target)))
    end, hotkeyRunConditionProperties)
    input.registerImGuiHotkey({ ImGuiKey.X, ImGuiKey.LeftCtrl }, function ()
        if #spawnedUI.selectedPaths == 0 then return end

        spawnedUI.cut(true)
    end, hotkeyRunConditionProperties)
    input.registerImGuiHotkey({ ImGuiKey.Delete }, function()
        history.addAction(history.getRemove(spawnedUI.getRoots(spawnedUI.selectedPaths)))
        for _, entry in pairs(spawnedUI.getRoots(spawnedUI.selectedPaths)) do
            entry.ref:remove()
        end
    end, hotkeyRunConditionGlobal)
    input.registerImGuiHotkey({ ImGuiKey.D, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        local data = spawnedUI.copy(true)
        history.addAction(history.getInsert(spawnedUI.paste(data, spawnedUI.selectedPaths[1].ref)))
    end)
    input.registerImGuiHotkey({ ImGuiKey.G, ImGuiKey.LeftCtrl }, function()
        if #spawnedUI.selectedPaths == 0 then return end

        spawnedUI.moveToNewGroup(true)
    end)

    -- Inputs that might get pressed while using properties panel, so use hotkeyRunConditionProperties
    input.registerImGuiHotkey({ ImGuiKey.Backspace }, function()
        if #spawnedUI.selectedPaths == 0 or spawnedUI.nameBeingEdited then return end
        spawnedUI.moveToRoot(true)
    end, hotkeyRunConditionProperties)
    input.registerImGuiHotkey({ ImGuiKey.Escape }, function()
        if #spawnedUI.selectedPaths == 0 or editor.grab or editor.rotate or editor.scale then return end -- Escape is also used for cancling editing
        spawnedUI.unselectAll()
    end, hotkeyRunConditionProperties)
    input.registerImGuiHotkey({ ImGuiKey.H }, function()
        if #spawnedUI.selectedPaths == 0 or spawnedUI.nameBeingEdited then return end

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
    end, hotkeyRunConditionProperties)

    input.registerImGuiHotkey({ ImGuiKey.E, ImGuiKey.LeftCtrl }, function ()
        if #spawnedUI.selectedPaths == 0 then return end

        local isMulti = #spawnedUI.selectedPaths > 1

        if isMulti then
            spawnedUI.multiSelectGroup:dropToSurface(true, Vector4.new(0, 0, -1, 0))
        else
            spawnedUI.selectedPaths[1].ref:dropToSurface(false, Vector4.new(0, 0, -1, 0))
        end
    end)

    input.registerImGuiHotkey({ ImGuiKey.N, ImGuiKey.LeftCtrl }, function ()
        if #spawnedUI.selectedPaths == 0 then
            spawnedUI.spawner.baseUI.spawnUI.selectedGroup = 0
            return
        end

        spawnedUI.setElementSpawnNewTarget(spawnedUI.selectedPaths[1].ref)
    end)

    input.registerImGuiHotkey({ ImGuiKey.F, ImGuiKey.LeftCtrl }, function ()
        if #spawnedUI.selectedPaths ~= 1 then
            return
        end

        local icon = spawnedUI.selectedPaths[1].ref.icon
        if icon == "" then
            icon = IconGlyphs.Group
        end
        spawnedUI.spawner.baseUI.spawnUI.favoritesUI.addNewItem(spawnedUI.selectedPaths[1].ref:serialize(), spawnedUI.selectedPaths[1].ref.name, icon)
    end)

    -- Open context menu for selected from editor mode
    input.registerMouseAction(ImGuiMouseButton.Right, function()
        if #spawnedUI.selectedPaths == 0 or editor.grab or editor.rotate or editor.scale then return end

        spawnedUI.openContextMenu.state = true
        spawnedUI.openContextMenu.path = spawnedUI.selectedPaths[1].path
    end,
    function ()
        return editor.active and (input.context.viewport.hovered or input.context.hierarchy.hovered)
    end)
end

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

    if #spawnedUI.selectedPaths == 1 and spawnedUI.selectedPaths[1].ref == element then -- Select from first to element
        for _, entry in pairs(paths) do
            if entry.ref == element then
                break
            end
            entry.ref:setSelected(true)
        end
    else
        local inRange = false
        if spawnedUI.selectedPaths[1].ref == element then -- Bottom to top selection
            for i = #paths, 1, -1 do
                if paths[i].ref == spawnedUI.selectedPaths[1].ref then
                    break
                end
                if paths[i].ref.selected then
                    inRange = true
                end
                if inRange then
                    paths[i].ref:setSelected(true)
                end
            end
        end

        inRange = false
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
function spawnedUI.handleReorder(element)
    local _, mouseY = ImGui.GetMousePos()
    local _, itemY = ImGui.GetItemRectMin()
    local _ , sizeY = ImGui.GetItemRectSize()
    local shift = ((mouseY - itemY) < sizeY / 2) and 0 or 1

    local adjust = 0

    local roots = spawnedUI.getRoots(spawnedUI.selectedPaths)
    local remove = history.getRemove(roots)
    for _, entry in pairs(roots) do
        if entry.ref.parent == element.parent and utils.indexValue(element.parent.childs, element) > utils.indexValue(element.parent.childs, entry.ref) then
            adjust = 1
        end
        entry.ref:setParent(element.parent, utils.indexValue(element.parent.childs, element) + shift - adjust)
    end
    local insert = history.getInsert(roots)
    history.addAction(history.getMove(remove, insert))
end

---@protected
---@param element element
function spawnedUI.handleDrag(element)
    if ImGui.IsItemHovered() and ImGui.IsMouseDragging(0, style.draggingThreshold) and not spawnedUI.draggingSelected then -- Start dragging
        if not element.selected then
            spawnedUI.unselectAll()
            element:setSelected(true)
        end
        spawnedUI.draggingSelected = true
    elseif not ImGui.IsMouseDragging(0, style.draggingThreshold) and ImGui.IsItemHovered() and spawnedUI.draggingSelected then -- Drop on element
        spawnedUI.draggingSelected = false

        if not element.selected then
            if ImGui.IsKeyDown(ImGuiKey.LeftShift) and element:isValidDropTarget(spawnedUI.selectedPaths, false) then
                spawnedUI.handleReorder(element)
            elseif element:isValidDropTarget(spawnedUI.selectedPaths, true) then
                local roots = spawnedUI.getRoots(spawnedUI.selectedPaths)
                local remove = history.getRemove(roots)
                for _, entry in pairs(roots) do
                    entry.ref:setParent(element)
                end
                local insert = history.getInsert(roots)
                history.addAction(history.getMove(remove, insert))
            end
        end
    elseif ImGui.IsItemHovered() and spawnedUI.draggingSelected then
        if element.selected then
            ImGui.SetMouseCursor(ImGuiMouseCursor.NotAllowed)
        elseif not ImGui.IsKeyDown(ImGuiKey.LeftShift) and not element:isValidDropTarget(spawnedUI.selectedPaths, true) then
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

    if settings.moveCloneToParent == 2 then
        parent = parent.parent or parent
    end

    for _, entry in pairs(elements) do
        local new = require(entry.modulePath):new(spawnedUI)

        if entry.modulePath == "modules/classes/editor/randomizedGroup" then
            entry.seed = -1
        end

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
            text = (ImGui.IsKeyDown(ImGuiKey.LeftShift) and "Reorder " or "") .. text
            ImGui.Text(text)
            ImGui.End()
        end
    end
end

---@protected
---@param element element
function spawnedUI.drawContextMenu(element, path)
    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Appearing)

    if ImGui.BeginPopupContextItem("##contextMenu" .. path, ImGuiPopupFlags.MouseButtonRight) then
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
        if utils.isA(element, "positionable") then
            if ImGui.MenuItem("Drop to floor", "CTRL-E") then
                if isMulti then
                    spawnedUI.multiSelectGroup:dropToSurface(true, Vector4.new(0, 0, -1, 0))
                else
                    element:dropToSurface(false, Vector4.new(0, 0, -1, 0))
                end
            end
        end
        if element.expandable then
            if ImGui.MenuItem("Drop Children to Floor") then
                element:dropChildrenToSurface(Vector4.new(0, 0, -1, 0))
            end
            if ImGui.MenuItem("Set as \"Spawn New\" group", "CTRL-N") then
                local idx = 1
                local elementPath = element:getPath()
                for _, entry in pairs(spawnedUI.containerPaths) do
                    if entry.path == elementPath then
                        break
                    end
                    idx = idx + 1
                end
                spawnedUI.spawner.baseUI.spawnUI.selectedGroup = idx
            end
            if ImGui.MenuItem("Set Origin to Center") then
                element:setOriginToCenter()
            end
            if ImGui.MenuItem("Set Player Position as Origin") then
                element:setOrigin(GetPlayer():GetWorldPosition())
            end
            if ImGui.MenuItem("Set Current Rotation as Identity") then
                element:setRotationIdentity()
            end
        end
        if element.parent ~= nil and element.parent.expandable and not element.parent:isRoot(true) then
            if ImGui.MenuItem("Set Origin to Element") then
                element.parent:setOrigin(element:getPosition())
            end
        end
        if ImGui.MenuItem(not element.expandable and "Make Favorite" or "Make Prefab", "CTRL-F") then
            local icon = element.icon
            if icon == "" then
                icon = IconGlyphs.Group
            end

            spawnedUI.spawner.baseUI.spawnUI.favoritesUI.addNewItem(element:serialize(), element.name, icon)
        end

        ImGui.EndPopup()
    end

    if spawnedUI.openContextMenu.state and spawnedUI.openContextMenu.path == path then
        spawnedUI.openContextMenu.state = false

        ImGui.OpenPopup("##contextMenu" .. spawnedUI.openContextMenu.path)
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
            ImGui.SetNextItemAllowOverlap()
            if ImGui.Button(icon) then
                data.operation(element)
            end
            ImGui.SameLine()
            ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))
        end
    end

    if spawnedUI.filter ~= "" then
        ImGui.SetNextItemAllowOverlap()
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

    ImGui.SetNextItemAllowOverlap()
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

    if (spawnedUI.clipperIndex - 1 >= spawnedUI.clipper.DisplayStart and spawnedUI.clipperIndex - 1 < spawnedUI.clipper.DisplayEnd) or dummy then
        local isGettingDragged = element and element.selected and spawnedUI.draggingSelected

        ImGui.PushID(spawnedUI.elementCount)

        ImGui.TableNextRow(ImGuiTableRowFlags.None, ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2)
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
        ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 15, spawnedUI.cellPadding * 2 + style.viewSize) -- + style.viewSize is a ugly fix to make the gaps smaller

        -- Grey out if getting dragged
        style.pushStyleColor(isGettingDragged, ImGuiCol.HeaderHovered, 0, 0, 0, 0)
        style.pushStyleColor(isGettingDragged, ImGuiCol.HeaderActive, 0, 0, 0, 0)
        style.pushStyleColor(isGettingDragged, ImGuiCol.Header, 0, 0, 0, 0)

        local previous = element.selected
        local newState = ImGui.Selectable("##item" .. spawnedUI.elementCount, element.selected, ImGuiSelectableFlags.SpanAllColumns + ImGuiSelectableFlags.AllowOverlap)
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
                if entry.ref ~= element then
                    entry.ref:setSelected(false)
                end
            end
            if previous == true and #spawnedUI.selectedPaths > 1 then element:setSelected(true) end
        elseif spawnedUI.draggingSelected and previous ~= element.selected then -- Disregard any changes due to dragging
            element:setSelected(previous)
        end

        spawnedUI.handleDrag(element)

        local elementPath = element:getPath()
        spawnedUI.drawContextMenu(element, elementPath)

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

        local leftOffset = 25 * style.viewSize -- Accounts for icon

        -- Icon or expand button
        if not element.expandable and element.icon ~= "" then
            ImGui.AlignTextToFramePadding()
            ImGui.Text(element.icon)
        elseif element.expandable then
            ImGui.PushID(element.name)
            local text = element.headerOpen and IconGlyphs.MenuDownOutline or IconGlyphs.MenuRightOutline
            ImGui.SetNextItemAllowOverlap()
            if ImGui.Button(text) then
                if spawnedUI.multiSelectActive() then
                    element:setHeaderStateRecursive(not element.headerOpen)
                else
                    element.headerOpen = not element.headerOpen
                end
            end

            if element.icon ~= "" then
                ImGui.SameLine()
                ImGui.AlignTextToFramePadding()
                ImGui.Text(element.icon)
                leftOffset = 45 * style.viewSize
            end

            ImGui.PopID()
        end

        ImGui.SameLine()

        ImGui.SetCursorPosX((spawnedUI.depth) * 17 * style.viewSize + leftOffset)
        ImGui.AlignTextToFramePadding()
        if element.editName then
            input.windowHovered = false
            if element.focusNameEdit > 0 then
                ImGui.SetKeyboardFocusHere()
                element.focusNameEdit = element.focusNameEdit - 1
            end
            element:drawName()
        else
            ImGui.SetNextItemAllowOverlap()
            ImGui.Text(element.name)
        end

        if element.hovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
            element.editName = true
            element.focusNameEdit = 1
            element:setSelected(true)
        end

        if spawnedUI.filter ~= "" then
            ImGui.SameLine()
            ImGui.SetCursorPosX(spawnedUI.filteredWidestName + 25 * style.viewSize + 5 * style.viewSize)
            style.mutedText("[" .. elementPath .. "]")
        end

        ImGui.SameLine()

        spawnedUI.drawSideButtons(element)

        ImGui.PopStyleColor(2)
        ImGui.PopStyleVar(2)
        style.popStyleColor(isGettingDragged)

        ImGui.PopID()
    elseif not dummy then
        element:setHovered(false)
    end

    spawnedUI.clipperIndex = spawnedUI.clipperIndex + 1

    spawnedUI.drawElementChilds(element)
end

function spawnedUI.drawHierarchy()
    spawnedUI.elementCount = 0
    spawnedUI.depth = 0
    spawnedUI.cellPadding = 3 * style.viewSize

    local _, ySpace = ImGui.GetContentRegionAvail()

    if ySpace < 0 then return end

    if ySpace - settings.editorBottomSize < 75 * style.viewSize and not spawnedUI.spawner.baseUI.loadTabSize then
        settings.editorBottomSize = ySpace - 75 * style.viewSize
    end
    local nRows = math.floor((ySpace - settings.editorBottomSize) / (ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2))

    ImGui.BeginChild("##hierarchy", 0, ySpace - settings.editorBottomSize, false, ImGuiWindowFlags.NoMove)
    input.updateContext("hierarchy")

    -- Start the table
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, 7.5 * style.viewSize, spawnedUI.cellPadding)
    ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarSize, 12 * style.viewSize)
    if ImGui.BeginTable("##hierarchyTable", 1, ImGuiTableFlags.ScrollX or ImGuiTableFlags.NoHostExtendX) then
        if spawnedUI.filter == "" then
            if spawnedUI.scrollToSelected then
                -- Temporarily render everything, so that SetScrollHereY works
                spawnedUI.clipperIndex = 1
                spawnedUI.clipper = { DisplayStart = -1, DisplayEnd = spawnedUI.getNumVisibleElements() }

                for _, child in pairs(spawnedUI.root.childs) do
                    spawnedUI.drawElement(child, false)
                end
            else
                spawnedUI.clipper = ImGuiListClipper.new()
                spawnedUI.clipperIndex = 1
                spawnedUI.clipper:Begin(spawnedUI.getNumVisibleElements(), ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2)

                while (spawnedUI.clipper:Step()) do
                    spawnedUI.clipperIndex = 1
                    for _, child in pairs(spawnedUI.root.childs) do
                        spawnedUI.drawElement(child, false)
                    end
                end
            end
        else
            spawnedUI.clipper = ImGuiListClipper.new()
            spawnedUI.clipperIndex = 1
            spawnedUI.clipper:Begin(#spawnedUI.filteredPaths, ImGui.GetFrameHeight() + spawnedUI.cellPadding * 2 - style.viewSize * 2)

            while (spawnedUI.clipper:Step()) do
                spawnedUI.clipperIndex = 1
                for _, entry in pairs(spawnedUI.filteredPaths) do
                    spawnedUI.drawElement(entry.ref, false)
                end
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
function spawnedUI.drawTop()
    ImGui.PushItemWidth(200 * style.viewSize)
    spawnedUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for element...', spawnedUI.filter, 100)
    ImGui.PopItemWidth()

    if spawnedUI.filter ~= '' then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            spawnedUI.filter = ''
            if #spawnedUI.selectedPaths == 1 then
                spawnedUI.selectedPaths[1].ref:expandAllParents()
                spawnedUI.scrollToSelected = true
            end
        end
        style.pushButtonNoBG(false)
    end

    ImGui.PushItemWidth(200 * style.viewSize)
    spawnedUI.newGroupName, changed = ImGui.InputTextWithHint('##newG', 'New group name...', spawnedUI.newGroupName, 100)
    if changed then
        spawnedUI.newGroupName = utils.createFileName(spawnedUI.newGroupName)
    end
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("Add group") then
        local group = require("modules/classes/editor/positionableGroup"):new(spawnedUI)

        if spawnedUI.newGroupRandomized then
            group = require("modules/classes/editor/randomizedGroup"):new(spawnedUI)
        end

        group.name = spawnedUI.newGroupName
        spawnedUI.addRootElement(group)
        history.addAction(history.getInsert({ group }))
    end
    ImGui.SameLine()
    spawnedUI.newGroupRandomized = style.toggleButton(IconGlyphs.Dice5Outline, spawnedUI.newGroupRandomized)
    style.tooltip("Make new group randomized")

    style.pushButtonNoBG(true)

    local state = editor.active
    style.pushStyleColor(state, ImGuiCol.Text, 0xfffcdb03)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    ImGui.PushStyleColor(ImGuiCol.Border, 1, 1, 0, 0.3)
    if ImGui.Button(IconGlyphs.Rotate3d) then
        editor.toggle(not editor.active)
    end
    ImGui.PopStyleColor()
    ImGui.PopStyleVar()
    style.popStyleColor(state)
    style.tooltip("Toggle 3D-Editor mode")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ContentSaveAllOutline) then
        for _, entry in pairs(spawnedUI.paths) do
            if utils.isA(entry.ref, "positionableGroup") and entry.ref.supportsSaving and entry.ref.parent ~= nil and entry.ref.parent:isRoot(true) then
                entry.ref:save()
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.CollapseAllOutline) then
        for _, child in pairs(spawnedUI.root.childs) do
            child:setHeaderStateRecursive(false)
        end
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

    ImGui.SameLine()

    style.mutedText(IconGlyphs.InformationOutline)
    if ImGui.IsItemHovered() then
        local x, y = ImGui.GetMousePos()
        local width, _ = GetDisplayResolution()
        ImGui.SetNextWindowPos(math.min(x + 10 * style.viewSize, width - spawnedUI.infoWindowSize.x - 30 * style.viewSize), y + 10 * style.viewSize, ImGuiCond.Always)

        if ImGui.Begin("##popup", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.AlwaysAutoResize) then
            style.mutedText("GENERAL")
            ImGui.Separator()
            ImGui.Spacing()

            ImGui.MenuItem("Undo", "CTRL-Z")
            ImGui.MenuItem("Redo", "CTRL-Y")
            ImGui.MenuItem("Select all", "CTRL-A")
            ImGui.MenuItem("Unselect all", "ESC")
            ImGui.MenuItem("Save all", "CTRL-S")

            style.mutedText("SCENE HIERARCHY")
            ImGui.Separator()
            ImGui.Spacing()

            ImGui.MenuItem("Open context menu on selected", "RMB")
            ImGui.MenuItem("Copy selected", "CTRL-C")
            ImGui.MenuItem("Paste selected", "CTRL-V")
            ImGui.MenuItem("Duplicate selected", "CTRL-D")
            ImGui.MenuItem("Cut selected", "CTRL-X")
            ImGui.MenuItem("Delete selected", "DEL")
            ImGui.MenuItem("Toggle selected visibility", "H")
            ImGui.MenuItem("Multiselect", "Hold CTRL")
            ImGui.MenuItem("Range select", "Hold SHIFT")
            ImGui.MenuItem("Move selected to root", "BACKSPACE")
            ImGui.MenuItem("Move selected to new group", "CTRL-G")
            ImGui.MenuItem("Drop selected to floor", "CTRL-E")
            ImGui.MenuItem("Set as \"Spawn New\" group", "CTRL-N")

            style.mutedText("3D-EDITOR Camera")
            ImGui.Separator()
            ImGui.Spacing()
            ImGui.MenuItem("Rotate camera", "Hold MMB")
            ImGui.MenuItem("Move camera", "SHIFT + Hold MMB")
            ImGui.MenuItem("Zoom", "CTRL + Hold MMB")
            ImGui.MenuItem("Center camera on selected", "TAB")

            style.mutedText("3D-EDITOR")
            ImGui.Separator()
            ImGui.Spacing()

            ImGui.MenuItem("Repeat last spawn under cursor", "CTRL-R")
            ImGui.MenuItem("Open spawn new popup", "SHIFT-A")
            ImGui.MenuItem("Open depth select menu", "SHIFT-D")
            ImGui.MenuItem("Select / Confirm", "LMB")
            ImGui.MenuItem("Box Select", "CTRL + LMB Drag")
            ImGui.MenuItem("Open context menu / Cancel", "RMB")
            ImGui.MenuItem("Move selected on axis", "G -> X/Y/Z")
            ImGui.MenuItem("Move selected, locked on axis", "G -> SHIFT + X/Y/Z")
            ImGui.MenuItem("Rotate selected", "R -> X/Y/Z  -> (Numeric)")
            ImGui.MenuItem("Scale selected on axis", "S -> X/Y/Z -> (Numeric)")
            ImGui.MenuItem("Scale selected, locked on axis", "S -> SHIFT + X/Y/Z  -> (Numeric)")

            ImGui.End()
        end

        local x, y = ImGui.GetWindowSize()
        spawnedUI.infoWindowSize = { x = x, y = y }
    end

    style.pushButtonNoBG(false)
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
    registry.update()

    spawnedUI.drawTop()

    ImGui.Separator()
    ImGui.Spacing()

    ImGui.AlignTextToFramePadding()

    spawnedUI.drawDragWindow()
    spawnedUI.drawHierarchy()
    spawnedUI.drawDivider()
    spawnedUI.drawProperties()

    -- Dropped on not a valid target
    if spawnedUI.draggingSelected and not ImGui.IsMouseDragging(0, style.draggingThreshold) then
        spawnedUI.draggingSelected = false
    end
end

return spawnedUI