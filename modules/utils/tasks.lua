---@class tasks
---@field tasksTodo number
---@field tasks table
---@field finalizeCallback function
local tasks = {}

function tasks:new()
	local o = {}

    o.tasksTodo = 0
    o.tasks = {}
    o.finalizeCallback = nil

    self.__index = self
   	return setmetatable(o, self)
end

function tasks:addTask(task)
    table.insert(self.tasks, task)
    self.tasksTodo = self.tasksTodo + 1
end

function tasks:taskCompleted()
    self.tasksTodo = self.tasksTodo - 1

    if self.tasksTodo == 0 then
        self.finalizeCallback()
    end
end

function tasks:run(from, to)
    local from = from or 0
    local to = to or #self.tasks

    for key, task in ipairs(self.tasks) do
        if not (key < from or key > to) then
            task()
        end
    end

    if #self.tasks == 0 then
        self.finalizeCallback()
    end
end

function tasks:onFinalize(callback)
    self.finalizeCallback = callback
end

return tasks