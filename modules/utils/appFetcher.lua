local utils = require("modules/utils/utils")
local config = require("modules/utils/config")

fetcher = {
    inProgress = {},
    apps = {},
    nums = {}
}

function fetcher.queueFetching(object)
    pcall(function()
        fetcher.apps = config.loadFile("data/apps.json")

        if fetcher.apps[object.path] == nil then
            fetcher.apps[object.path] = {}
        end

        config.saveFile("data/apps.json", fetcher.apps)
        object:getEntitiy():ScheduleAppearanceChange("")

        fetcher.inProgress[object] = object
        fetcher.nums[object] = object.sUI.spawner.settings.appFetchTrys
    end)
end

function fetcher.update()
    for _, object in pairs(fetcher.inProgress) do
        fetcher.nums[object] = fetcher.nums[object] - 1

        object:getEntitiy():ScheduleAppearanceChange("")
        if not utils.has_value(fetcher.apps[object.path], object:getEntitiy():GetCurrentAppearanceName().value) then
            table.insert(fetcher.apps[object.path], object:getEntitiy():GetCurrentAppearanceName().value)
            print(object:getEntitiy():GetCurrentAppearanceName().value)
        end

        if fetcher.nums[object] <= 0 then
            fetcher.inProgress[object] = nil
            config.saveFile("data/apps.json", fetcher.apps)
            object.apps = fetcher.apps[object.path]
            if #object.apps ~= 0 then
                object.app = object.apps[1]
                object:getEntitiy():ScheduleAppearanceChange(object.app)
            end
        end
    end
end

return fetcher