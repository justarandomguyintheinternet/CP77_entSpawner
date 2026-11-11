local utils = require("modules/utils/core/utils")
local logger = require("modules/utils/core/logger")
local saveState = require("modules/utils/project/saveState")

local maxHistory = 999
local maxPendingRequests = 16

---@class history
---@field index number
---@field actions table
---@field spawnedUI spawnedUI?
local history = {
    index = 0,
    actions = {},
    spawnedUI = nil,
    propBeingEdited = false,
    ---Element whose property is mid-drag. A drag pushes one history action on the first frame and
    ---then keeps mutating for as long as the user holds the control, so change tracking needs to know
    ---who to re-check once `propBeingEdited` drops back to false.
    ---@type element?
    lastEditedElement = nil,
    pending = {},
    active = nil,
    frameBudgetMs = 2.5
}

---Refresh Spawned UI caches after history operations mutate the tree.
---@param registryAffected boolean? Whether registry/path-sensitive caches should be invalidated.
local function rebuildCache(registryAffected)
    if not history.spawnedUI then
        return
    end

    if history.spawnedUI.invalidateCache then
        history.spawnedUI.invalidateCache(registryAffected == true)
    end

    if history.spawnedUI.cachePaths then
        history.spawnedUI.cachePaths()
    elseif history.spawnedUI.ensureCache then
        history.spawnedUI.ensureCache()
    end
end

---Log a history action failure.
---@param message string Human-readable context for the failure.
---@param err any Error object/message returned by `pcall`.
local function logActionError(message, err)
    logger:error("[history] " .. tostring(message) .. ": " .. tostring(err))
end

---Find an element by runtime ID in a subtree.
---@param node element? Root node to search from.
---@param id number Runtime element ID to match.
---@return element? found
local function findElementByIdRecursive(node, id)
    if not node then
        return nil
    end

    if node.id == id then
        return node
    end

    for _, child in ipairs(node.childs or {}) do
        local found = findElementByIdRecursive(child, id)
        if found then
            return found
        end
    end

    return nil
end

---Capture the runtime IDs of an element's descendants, keyed by path relative to it.
---`serialize` carries no IDs, so a subtree rebuilt by `processUndoEntry` would otherwise come back
---with fresh random ones and become unreachable to every ID-based lookup, selection included.
---@param instance element Root of the subtree to capture.
---@return table<string, number> ids
local function captureSubtreeIds(instance)
    local ids = {}

    local function walk(node, prefix)
        for _, child in ipairs(node.childs or {}) do
            local path = prefix .. "/" .. tostring(child.name)
            ids[path] = child.id
            walk(child, path)
        end
    end

    walk(instance, "")

    return ids
end

---Re-apply IDs captured by `captureSubtreeIds` to a rebuilt subtree.
---@param instance element Root of the rebuilt subtree.
---@param ids table<string, number>? Snapshot to apply.
local function applySubtreeIds(instance, ids)
    if not ids then
        return
    end

    local function walk(node, prefix)
        for _, child in ipairs(node.childs or {}) do
            local path = prefix .. "/" .. tostring(child.name)
            if ids[path] then
                child.id = ids[path]
            end
            walk(child, path)
        end
    end

    walk(instance, "")
end

---Snapshot which elements are currently selected, by runtime ID.
---@return number[] ids
local function captureSelection()
    local ids = {}

    if not history.spawnedUI or not history.spawnedUI.root then
        return ids
    end

    local function walk(node)
        for _, child in ipairs(node.childs or {}) do
            if child.selected then
                ids[#ids + 1] = child.id
            end
            walk(child)
        end
    end

    walk(history.spawnedUI.root)

    return ids
end

---Re-select elements that were selected before an action ran. Purely additive: an element the action
---itself selected is left alone, and IDs that no longer exist are dropped.
---@param ids number[]? Snapshot from `captureSelection`.
local function restoreSelection(ids)
    if not ids or #ids == 0 or not history.spawnedUI or not history.spawnedUI.root then
        return
    end

    local wanted = {}
    for _, id in ipairs(ids) do
        wanted[id] = true
    end

    local function walk(node)
        for _, child in ipairs(node.childs or {}) do
            if wanted[child.id] and not child.selected then
                local ok, err = pcall(child.setSelected, child, true)
                if not ok then
                    logActionError("Selection restore failed", err)
                end
            end
            walk(child)
        end
    end

    walk(history.spawnedUI.root)
end

---Resolve an element by path by walking the in-memory tree.
---@param path string Absolute spawned UI path.
---@return element? found
local function findElementByPathTree(path)
    if not history.spawnedUI or not history.spawnedUI.root then
        return nil
    end

    if path == "" then
        return history.spawnedUI.root
    end

    local current = history.spawnedUI.root
    for segment in string.gmatch(path, "/([^/]+)") do
        local found = nil
        for _, child in ipairs(current.childs or {}) do
            if child.name == segment then
                found = child
                break
            end
        end

        if not found then
            return nil
        end

        current = found
    end

    return current
end

---Resolve an element by path with fallbacks for stale paths/renames.
---@param path string Absolute spawned UI path.
---@param forceRefresh boolean? Force cache rebuild before first lookup.
---@param expectedId number? Optional runtime ID fallback when path changed.
---@param allowExpensiveFallback boolean? When false, skip `spawnedUI.getElementByPath` calls.
---@return element? found
local function resolveElementByPath(path, forceRefresh, expectedId, allowExpensiveFallback)
    if not history.spawnedUI then
        return nil
    end

    if forceRefresh then
        rebuildCache(true)
    end

    local entry = findElementByPathTree(path)
    if entry then
        return entry
    end

    if expectedId then
        entry = findElementByIdRecursive(history.spawnedUI.root, expectedId)
        if entry then
            return entry
        end
    end

    if allowExpensiveFallback == false or not history.spawnedUI.getElementByPath then
        return nil
    end

    entry = history.spawnedUI.getElementByPath(path)
    if entry then
        return entry
    end

    rebuildCache(true)

    entry = history.spawnedUI.getElementByPath(path)
    if entry then
        return entry
    end

    if expectedId and history.spawnedUI.paths then
        for _, node in ipairs(history.spawnedUI.paths) do
            if node and node.ref and node.ref.id == expectedId then
                return node.ref
            end
        end
    end

    return nil
end

---Execute a history action immediately (non-queued).
---@param action table History action implementing undo/redo and optional begin/step/finish.
---@param mode "undo"|"redo" Operation mode to execute.
---@return boolean success
local function runActionImmediate(action, mode)
    if not action then
        return false
    end

    if action.begin then
        local ok, err = pcall(action.begin, mode)
        if not ok then
            logActionError("Action begin failed", err)
            return false
        end
    end

    if action.step then
        local done = false
        while not done do
            local ok, result = pcall(action.step, mode, 1e9)
            if not ok then
                logActionError("Action step failed", result)
                return false
            end
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if not fn then
            return false
        end

        local ok, err = pcall(fn)
        if not ok then
            logActionError("Action " .. mode .. " failed", err)
            return false
        end
    end

    if action.finish then
        local ok, err = pcall(action.finish, mode)
        if not ok then
            logActionError("Action finish failed", err)
        end
    end

    return true
end

---Advance a nested action by one budgeted step.
---@param state table Mutable nested-action state (`started` flag).
---@param action table Nested history action.
---@param mode "undo"|"redo" Operation mode for this nested action.
---@param budgetMs number Time budget in milliseconds for this step.
---@return boolean done True when nested action is fully completed.
local function stepNestedAction(state, action, mode, budgetMs)
    if not state.started then
        if action.begin then
            local ok, err = pcall(action.begin, mode)
            if not ok then
                logActionError("Nested begin failed", err)
                state.started = false
                return true
            end
        end
        state.started = true
    end

    local done = false
    if action.step then
        local ok, result = pcall(action.step, mode, budgetMs)
        if not ok then
            logActionError("Nested step failed", result)
            done = true
        else
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                logActionError("Nested " .. mode .. " failed", err)
            end
        end
        done = true
    end

    if done then
        if action.finish then
            local ok, err = pcall(action.finish, mode)
            if not ok then
                logActionError("Nested finish failed", err)
            end
        end
        state.started = false
    end

    return done
end

---Normalize mixed element lists into direct element references.
---@param elements element[]|{ path : string, ref : element }[] Mixed list of elements or path entries.
---@return element[] normalized
function history.normalizeElements(elements)
    local normalized = {}

    for _, element in ipairs(elements) do
        if element.ref then
            element = element.ref
        end
        table.insert(normalized, element)
    end

    return normalized
end

---Create a composite action that executes nested actions in sequence.
---Undo runs nested actions in reverse order; redo runs forward.
---@param actions table[] List of history actions.
---@return table action Composite history action.
function history.getComposite(actions)
    local action = {}
    local state = nil

    -- Union of what the nested actions touch. getMultiSelectChange and getElementChanges both funnel
    -- through here, so tagging getElementChange plus this covers every element-change path.
    local dirtyElements = {}
    for _, nested in ipairs(actions) do
        if nested.dirtyElements then
            for _, element in ipairs(nested.dirtyElements) do
                dirtyElements[#dirtyElements + 1] = element
            end
        end
    end
    action.dirtyElements = dirtyElements

    action.undo = function()
        for i = #actions, 1, -1 do
            actions[i].undo()
        end
    end

    action.redo = function()
        for _, nested in ipairs(actions) do
            nested.redo()
        end
    end

    action.begin = function(mode)
        state = {
            mode = mode,
            index = mode == "undo" and #actions or 1,
            delta = mode == "undo" and -1 or 1,
            nested = { started = false }
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while state.index >= 1 and state.index <= #actions do
            local nested = actions[state.index]
            local remainingBudget = budgetMs
            if deadline then
                remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
            end

            local doneNested = stepNestedAction(state.nested, nested, mode, remainingBudget)
            if doneNested then
                state.index = state.index + state.delta
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

---Create a move action from a remove action and an insert action.
---@param remove table History action that removes/reparents source elements.
---@param insert table History action that inserts/reparents destination elements.
---@return table action Move history action.
function history.getMove(remove, insert)
    local action = {}
    local state = nil

    action.redo = function()
        remove.redo()
        insert.redo()
    end

    action.undo = function()
        insert.undo()
        remove.undo()
    end

    action.begin = function(mode)
        local sequence = nil
        if mode == "redo" then
            sequence = {
                { action = remove, mode = "redo" },
                { action = insert, mode = "redo" }
            }
        else
            sequence = {
                { action = insert, mode = "undo" },
                { action = remove, mode = "undo" }
            }
        end

        state = {
            mode = mode,
            sequence = sequence,
            phase = 1,
            nested = { started = false }
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while state.phase <= #state.sequence do
            local phase = state.sequence[state.phase]
            local remainingBudget = budgetMs
            if deadline then
                remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
            end

            local donePhase = stepNestedAction(state.nested, phase.action, phase.mode, remainingBudget)
            if donePhase then
                state.phase = state.phase + 1
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

---Create a move-to-new-group action with cache refresh between phases.
---@param insert table Action inserting the newly created group.
---@param remove table Action removing source elements from their old parent(s).
---@param insertElement table Action inserting removed element(s) into the new group.
---@return table action Move-to-new-group history action.
function history.getMoveToNewGroup(insert, remove, insertElement)
    local move = history.getMove(remove, insertElement)
    local action = {}
    local state = nil

    action.redo = function()
        insert.redo()
        if history.spawnedUI and history.spawnedUI.cachePaths then
            history.spawnedUI.cachePaths() -- Very important so that the path of the new group can be found.
        end
        move.redo()
    end

    action.undo = function()
        move.undo()
        insert.undo()
    end

    action.begin = function(mode)
        if mode == "redo" then
            state = {
                mode = mode,
                phase = 1, -- 1: insert.redo, 2: refresh paths, 3: move.redo
                nested = { started = false }
            }
        else
            state = {
                mode = mode,
                phase = 1, -- 1: move.undo, 2: insert.undo
                nested = { started = false }
            }
        end
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while true do
            if mode == "redo" then
                if state.phase == 1 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneInsert = stepNestedAction(state.nested, insert, "redo", remainingBudget)
                    if doneInsert then
                        state.phase = 2
                    end
                elseif state.phase == 2 then
                    if history.spawnedUI and history.spawnedUI.cachePaths then
                        history.spawnedUI.cachePaths()
                    end
                    state.phase = 3
                elseif state.phase == 3 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneMove = stepNestedAction(state.nested, move, "redo", remainingBudget)
                    if doneMove then
                        state.phase = 4
                    end
                else
                    return true
                end
            else
                if state.phase == 1 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneMove = stepNestedAction(state.nested, move, "undo", remainingBudget)
                    if doneMove then
                        state.phase = 2
                    end
                elseif state.phase == 2 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneInsert = stepNestedAction(state.nested, insert, "undo", remainingBudget)
                    if doneInsert then
                        state.phase = 3
                    end
                else
                    return true
                end
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end
    end

    action.finish = function()
        state = nil
    end

    return action
end

---Create an action that swaps serialized state for a single element.
---@param element element Target element to track.
---@return table action Toggle-style action where undo/redo both swap snapshots.
function history.getElementChange(element)
    local action = {}

    if history.spawnedUI and element == history.spawnedUI.multiSelectGroup then -- Multiselect group is not real
        return history.getMultiSelectChange(element.childs)
    end

    action.data = element:serialize()
    action.path = element:getPath()
    action.id = element.id
    -- Property edits on a spawnable (light intensity, mesh path, ...) mutate fields directly and have
    -- no element-level hook; this is the only place that knows which element they touched, so the
    -- change tracker learns about them from here.
    action.dirtyElements = { element }

    local function swap()
        local target = resolveElementByPath(action.path, false, action.id, true)
        if not target then
            logger:warn("[history] Element change target not found for path: " .. tostring(action.path))
            return
        end

        local old = target:serialize()
        target:load(action.data)
        action.data = old
    end

    action.redo = swap
    action.undo = swap

    return action
end

---Create a composite change action for multi-selected elements.
---@param elements element[]|{ path : string, ref : element }[] Element list.
---@return table action Composite element-change action.
function history.getMultiSelectChange(elements)
    return history.getComposite(history.getElementChanges(elements))
end

---Create individual element-change actions for each provided element.
---@param elements element[]|{ path : string, ref : element }[] Element list.
---@return table[] changes
function history.getElementChanges(elements)
    local changes = {}

    for _, element in ipairs(history.normalizeElements(elements)) do
        table.insert(changes, history.getElementChange(element))
    end

    return changes
end

---Create an action that restores the child order of a group.
---
---Children are keyed by name rather than by reference or runtime ID: sibling names are unique, while
---an undo of an earlier removal rebuilds its elements as fresh objects with fresh IDs, which would
---leave captured references pointing at detached copies.
---@param element element Group whose children got reordered.
---@param previous string[] Child names in their order before the reorder.
---@param new string[] Child names in their order after the reorder.
---@return table action Child-order history action.
function history.getChildOrder(element, previous, new)
    local action = {}
    action.path = element:getPath()
    action.id = element.id
    action.dirtyElements = { element }

    local function apply(order)
        local target = resolveElementByPath(action.path, false, action.id, true)
        if not target then
            logger:warn("[history] Child order target not found for path: " .. tostring(action.path))
            return
        end

        local byName = {}
        for _, child in ipairs(target.childs) do
            byName[child.name] = child
        end

        local ordered = {}
        for _, name in ipairs(order) do
            local child = byName[name]
            if child then
                byName[name] = nil
                table.insert(ordered, child)
            end
        end

        -- Children added or renamed since the reorder are not in the recorded order, they keep their
        -- relative position and end up behind the ones that are.
        for _, child in ipairs(target.childs) do
            if byName[child.name] then
                table.insert(ordered, child)
            end
        end

        if #ordered ~= #target.childs then return end

        for index, child in ipairs(ordered) do
            target.childs[index] = child
        end

        saveState.markDirty(target)
        rebuildCache(true)
    end

    action.redo = function()
        apply(new)
    end

    action.undo = function()
        apply(previous)
    end

    return action
end

---Create an action that swaps element state across an old/new rename path.
---@param data table Serialized element snapshot captured before rename.
---@param current string Old path (pre-rename).
---@param new string New path (post-rename).
---@param id number Runtime element ID used as fallback resolution.
---@return table action Rename history action.
function history.getRename(data, current, new, id)
    local action = {}
    action.data = data
    action.old = current
    action.new = new
    action.id = id

    local function swap(path)
        local target = resolveElementByPath(path, true, action.id, true)
        if not target then
            logger:warn("[history] Rename target not found for path: " .. tostring(path))
            return
        end

        local old = target:serialize()
        target:load(action.data)
        action.data = old
    end

    action.redo = function()
        swap(action.old)
    end

    action.undo = function()
        swap(action.new)
    end

    return action
end

---Must be called after the elements are inserted
---@param elements element[]|{ path : string, ref : element }[] Inserted elements.
---@return table action Inverted remove-action wrapper for insertion history.
function history.getInsert(elements)
    local base = history.getRemove(elements)
    local action = {}

    local function invertMode(mode)
        return mode == "redo" and "undo" or "redo"
    end

    action.redo = function()
        if base.undo then
            base.undo()
        end
    end

    action.undo = function()
        if base.redo then
            base.redo()
        end
    end

    if base.begin then
        action.begin = function(mode)
            base.begin(invertMode(mode))
        end
    end

    if base.step then
        action.step = function(mode, budgetMs)
            return base.step(invertMode(mode), budgetMs)
        end
    end

    if base.finish then
        action.finish = function(mode)
            base.finish(invertMode(mode))
        end
    end

    return action
end

---Must be called before the elements are removed / reparented
---@param elements element[]|{ path : string, ref : element }[] Elements about to be removed/reparented.
---@return table action Remove history action.
function history.getRemove(elements)
    local data = {}
    local seenIds = {}
    for _, element in ipairs(history.normalizeElements(elements)) do
        local id = element and element.id or nil
        if element.parent ~= nil and (id == nil or not seenIds[id]) then
            if id ~= nil then
                seenIds[id] = true
            end
            local parentPath = element.parent:getPath()
            table.insert(data, {
                index = utils.indexValue(element.parent.childs, element),
                parentPath = parentPath,
                parentId = element.parent.id,
                path = element:getPath(),
                id = element.id,
                childIds = captureSubtreeIds(element),
                data = element:serialize()
            })
        end
    end

    local insertOrder = {}
    for _, entry in ipairs(data) do
        table.insert(insertOrder, entry)
    end
    table.sort(insertOrder, function(a, b)
        if a.parentPath ~= b.parentPath then
            return a.parentPath < b.parentPath
        end

        local aIndex = a.index ~= -1 and a.index or math.huge
        local bIndex = b.index ~= -1 and b.index or math.huge
        if aIndex ~= bIndex then
            return aIndex < bIndex
        end

        return a.path < b.path
    end)

    local function processRedoEntry(elementData)
        local entry = resolveElementByPath(elementData.path, false, elementData.id, false)
        if entry then
            entry:remove()
        end
    end

    local function processUndoEntry(elementData)
        local parent = resolveElementByPath(elementData.parentPath, false, elementData.parentId, false)
        if parent then
            local existing = resolveElementByPath(elementData.path, false, elementData.id, false)
            if existing then
                local insertAtExisting = elementData.index ~= -1 and elementData.index or nil
                existing:setParent(parent, insertAtExisting)
                return
            end

            local new = require(elementData.data.modulePath):new(history.spawnedUI)
            new:load(elementData.data)
            new.id = elementData.id -- Preserve runtime identity so later history steps can resolve by id.
            applySubtreeIds(new, elementData.childIds) -- Same, for everything below it.
            local insertAt = elementData.index ~= -1 and elementData.index or nil
            new:setParent(parent, insertAt)
        end
    end

    local action = {}
    local state = nil

    action.redo = function()
        for _, elementData in ipairs(data) do
            processRedoEntry(elementData)
        end
    end

    action.undo = function()
        for _, elementData in ipairs(insertOrder) do
            processUndoEntry(elementData)
        end
    end

    action.begin = function(mode)
        state = {
            mode = mode,
            index = 1,
            list = mode == "redo" and data or insertOrder
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        local list = state.list or (mode == "redo" and data or insertOrder)
        while state.index <= #list do
            local elementData = list[state.index]
            if mode == "redo" then
                processRedoEntry(elementData)
            else
                processUndoEntry(elementData)
            end

            state.index = state.index + 1

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

---Clear queued and in-flight undo/redo execution state.
local function clearExecutionQueue()
    history.pending = {}
    history.active = nil
end

---Push a new action onto history, truncating redo tail if needed.
---@param action table History action to append.
function history.addAction(action)
    clearExecutionQueue()
    saveState.onHistoryAction(action)

    if history.index < #history.actions then
        for i = history.index + 1, #history.actions do
            history.actions[i] = nil
        end
    end

    if #history.actions >= maxHistory then
        table.remove(history.actions, 1)
    end

    table.insert(history.actions, action)
    history.index = #history.actions
end

---Queue an undo request for budgeted processing.
---@return boolean accepted False when pending queue is at capacity.
function history.requestUndo()
    if #history.pending >= maxPendingRequests then
        return false
    end

    table.insert(history.pending, "undo")
    return true
end

---Queue a redo request for budgeted processing.
---@return boolean accepted False when pending queue is at capacity.
function history.requestRedo()
    if #history.pending >= maxPendingRequests then
        return false
    end

    table.insert(history.pending, "redo")
    return true
end

---Check whether a queued undo/redo action is currently executing.
---@return boolean busy
function history.isBusy()
    return history.active ~= nil
end

local immediateDepth = 0

---Whether an undo/redo is currently being applied, queued or immediate.
---@return boolean
function history.isReplaying()
    return history.active ~= nil or immediateDepth > 0
end

---Get total queued history work count (pending + in-flight).
---@return number count
function history.getPendingCount()
    local inFlight = history.active and 1 or 0
    return inFlight + #history.pending
end

---Start the next pending undo/redo action, if available.
---@return boolean started True when an action was moved to `history.active`.
local function beginNextPendingAction()
    while #history.pending > 0 do
        local mode = table.remove(history.pending, 1)
        local action = nil
        local shouldStart = true

        if mode == "undo" then
            if history.index == 0 then
                shouldStart = false
            else
                action = history.actions[history.index]
            end
        else
            if history.index == #history.actions then
                shouldStart = false
            else
                action = history.actions[history.index + 1]
            end
        end

        if shouldStart and action then
            history.active = {
                mode = mode,
                action = action,
                failed = false,
                -- Structural actions rebuild elements instead of mutating them, so the selection has
                -- to be re-applied by ID once the tree settles.
                selection = captureSelection()
            }

            if action.begin then
                local ok, err = pcall(action.begin, mode)
                if not ok then
                    logActionError("Queued begin failed", err)
                    history.active = nil
                    shouldStart = false
                end
            end

            if shouldStart then
                return true
            end
        end
    end

    return false
end

---Finalize currently active queued action and apply index updates.
---@param success boolean Whether the active action completed successfully.
local function finishActiveAction(success)
    if not history.active then
        return
    end

    local mode = history.active.mode
    local action = history.active.action
    local selection = history.active.selection

    if action and action.finish then
        local ok, err = pcall(action.finish, mode)
        if not ok then
            logActionError("Queued finish failed", err)
        end
    end

    if success then
        if mode == "undo" then
            history.index = math.max(0, history.index - 1)
        else
            history.index = math.min(#history.actions, history.index + 1)
        end
    end

    history.active = nil
    history.propBeingEdited = false

    -- Undo/redo mutate the tree just as much as the forward action did, and re-dirty a different set
    -- (undoing an insert removes an element, undoing a rename changes a path), so re-run the same
    -- tracking rather than trying to invert it.
    if success then
        saveState.onHistoryAction(action)
    end

    restoreSelection(selection) -- Before the rebuild, so the refreshed cache sees the flags.
    rebuildCache(true)
end

---Process one budgeted step of the active queued action.
---@param budgetMs number Milliseconds available for this processing call.
---@return boolean finished True when the active action finished this call.
local function processActiveStep(budgetMs)
    if not history.active then
        return true
    end

    local action = history.active.action
    local mode = history.active.mode
    local done = false
    local success = true

    if action.step then
        local ok, result = pcall(action.step, mode, budgetMs)
        if not ok then
            logActionError("Queued step failed", result)
            done = true
            success = false
        else
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                logActionError("Queued " .. mode .. " failed", err)
                success = false
            end
        else
            success = false
        end
        done = true
    end

    if done then
        finishActiveAction(success)
        return true
    end

    return false
end

---Advance queued undo/redo execution within a per-frame time budget.
---@param frameBudgetMs number? Optional budget override in milliseconds.
function history.update(frameBudgetMs)
    local budgetMs = frameBudgetMs or history.frameBudgetMs
    if budgetMs <= 0 then
        budgetMs = history.frameBudgetMs
    end

    local deadline = os.clock() + (budgetMs / 1000)
    while os.clock() < deadline do
        if not history.active then
            if not beginNextPendingAction() then
                break
            end
        end

        local remainingMs = math.max((deadline - os.clock()) * 1000, 0)
        if remainingMs <= 0 then
            break
        end

        local finished = processActiveStep(remainingMs)
        if not finished then
            break
        end
    end
end

---Execute one undo action immediately (non-queued).
function history.undo()
    if history.active then
        return
    end
    if history.index == 0 then
        return
    end

    local action = history.actions[history.index]
    local selection = captureSelection()
    immediateDepth = immediateDepth + 1
    local success = runActionImmediate(action, "undo")
    immediateDepth = immediateDepth - 1
    if success then
        history.index = history.index - 1
    end
    history.propBeingEdited = false
    restoreSelection(selection)
    rebuildCache(true)
end

---Execute one redo action immediately (non-queued).
function history.redo()
    if history.active then
        return
    end
    if history.index == #history.actions then
        return
    end

    local action = history.actions[history.index + 1]
    local selection = captureSelection()
    immediateDepth = immediateDepth + 1
    local success = runActionImmediate(action, "redo")
    immediateDepth = immediateDepth - 1
    if success then
        history.index = history.index + 1
    end
    history.propBeingEdited = false
    restoreSelection(selection)
    rebuildCache(true)
end

return history
