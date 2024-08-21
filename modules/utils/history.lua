local utils = require("modules/utils/utils")

local maxHistory = 100

---@class history
---@field index number
---@field actions table
---@field spawnedUI spawnedUI?
local history = {
    index = 0,
    actions = {},
    spawnedUI = nil,
    propBeingEdited = false
}

function history.getMoveToNewGroup(insert, remove, insertElement)
    local move = history.getMove(remove, insertElement)

    return {
        redo = function()
            insert.redo()
            history.spawnedUI.cachePaths()
            move.redo()
        end,
        undo = function()
            move.undo()
            insert.undo()
        end
    }
end

function history.getMove(remove, insert)
    return {
        redo = function()
            remove.redo()
            insert.redo()
        end,
        undo = function()
            insert.undo()
            remove.undo()
        end
    }
end

function history.getElementChange(element)
    local action = {}
    action.data = element:serialize()
    action.path = element:getPath()

    action.redo = function()
        local old = history.spawnedUI.getElementByPath(action.path):serialize()
        history.spawnedUI.getElementByPath(action.path):load(action.data)
        action.data = old
    end
    action.undo = function()
        local old = history.spawnedUI.getElementByPath(action.path):serialize()
        history.spawnedUI.getElementByPath(action.path):load(action.data)
        action.data = old
    end

    return action
end

function history.getRename(data, current, new)
    local action = {}
    action.data = data
    action.old = current
    action.new = new

    action.redo = function()
        local old = history.spawnedUI.getElementByPath(action.old):serialize()
        history.spawnedUI.getElementByPath(action.old):load(action.data)
        action.data = old
    end
    action.undo = function()
        local old = history.spawnedUI.getElementByPath(action.new):serialize()
        history.spawnedUI.getElementByPath(action.new):load(action.data)
        action.data = old
    end

    return action
end

---Must be called after the elements are inserted
---@param elements element[]|{ path : string, ref : element }[]
---@return table
function history.getInsert(elements)
    local action = history.getRemove(elements)
    local redo = action.redo
    action.redo = action.undo
    action.undo = redo

    return action
end

---Must be called before the elements are removed / reparented
---@param elements element[]|{ path : string, ref : element }[]
---@return table
function history.getRemove(elements)
    local data = {}
    for _, element in pairs(elements) do
        if element.ref then element = element.ref end
        local parentPath = element.parent:getPath()
        table.insert(data, { index = utils.indexValue(element.parent.childs, element), parentPath = parentPath, path = element:getPath(), data = element:serialize() })
    end

    return {
        redo = function()
            for _, element in pairs(data) do
                local entry = spawnedUI.getElementByPath(element.path)
                if entry then
                    entry:remove()
                end
            end
        end,
        undo = function()
            for _, element in pairs(data) do
                local parent = spawnedUI.getElementByPath(element.parentPath)
                if parent then
                    local new = require(element.data.modulePath):new(parent.sUI)
                    new:load(element.data)
                    new:setParent(parent, element.index)
                end
            end
        end
    }
end

function history.addAction(action)
    if history.index < #history.actions then
        for i = history.index, #history.actions do
            history.actions[i] = nil
        end
    end

    table.insert(history.actions, action)
    history.index = #history.actions
end

function history.undo()
    if history.index == 0 then return end

    history.actions[history.index].undo()
    history.index = history.index - 1
end

function history.redo()
    if history.index == #history.actions then return end
    history.index = history.index + 1
    history.actions[history.index].redo()
end

return history