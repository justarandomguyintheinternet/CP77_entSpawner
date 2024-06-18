local Cron = require("modules/utils/Cron")

---Class for handling the execution of multiple tasks, can be synchronous or asynchronous, with optional delay between tasks
---@class tasks
---@field tasksTodo number
---@field tasks table
---@field finalizeCallback function
---@field synchronous boolean
---@field taskDelay number
local tasks = {}

function tasks:new()
	local o = {}

    o.tasksTodo = 0
    o.tasks = {}
    o.finalizeCallback = nil
    o.synchronous = false
    o.taskDelay = 0

    self.__index = self
   	return setmetatable(o, self)
end

---Adds a task to the task list
---@param task function
function tasks:addTask(task)
    self.tasks[#self.tasks + 1] = task
    self.tasksTodo = self.tasksTodo + 1
end

---Must be called in the callback of a task, once it has been completed
function tasks:taskCompleted()
    self.tasksTodo = self.tasksTodo - 1

    if self.tasksTodo == 0 then
        self.finalizeCallback()
    end

    if not self.synchronous then return end
    if #self.tasks <= 0 then return end

    table.remove(self.tasks, 1)
    if self.taskDelay > 0 then
        Cron.After(self.taskDelay, function ()
            self.tasks[1]()
        end)
    else
        self.tasks[1]()
    end
end

---Runs all tasks in the task list
---@param synchronous boolean If true, tasks will be executed synchronously
function tasks:run(synchronous)
    self.synchronous = synchronous

    if #self.tasks == 0 then
        self.finalizeCallback()
        return
    end

    if not self.synchronous then
        for _, task in ipairs(self.tasks) do
            task()
        end
    else
        self.tasks[1]()
    end
end

---Function to be called when all tasks have been completed
---@param callback function
function tasks:onFinalize(callback)
    self.finalizeCallback = callback
end

return tasks