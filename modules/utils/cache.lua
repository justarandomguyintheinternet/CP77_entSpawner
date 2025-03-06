local config = require("modules/utils/config")
local tasks = require("modules/utils/tasks")
local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")

local sanitizeSpawnData = false
local data = {}
local cache = {}

local version = 9

function cache.load()
    config.tryCreateConfig("data/cache.json", { version = version })
    data = config.loadFile("data/cache.json")

    if not data.version or data.version < version then
        data = { version = version }
        config.saveFile("data/cache.json", data)
        print("[entSpawner] Cache is outdated, resetting cache")
    end

    if not sanitizeSpawnData then return end
    cache.generateDevicePSClassList()
    cache.generateRecordsList()

    cache.removeDuplicates("data/spawnables/ai/aiSpot/paths_workspot.txt")
    cache.removeDuplicates("data/spawnables/entity/templates/paths_ent.txt")
    cache.removeDuplicates("data/spawnables/mesh/all/paths_mesh.txt")
    cache.removeDuplicates("data/spawnables/mesh/physics/paths_filtered_mesh.txt")
    cache.removeDuplicates("data/spawnables/visual/particles/paths_particle.txt")
    cache.removeDuplicates("data/spawnables/visual/decals/paths_mi.txt")
    cache.removeDuplicates("data/spawnables/visual/effects/paths_effect.txt")
end

function cache.addValue(key, value)
    data[key] = value
    config.saveFile("data/cache.json", data)
end

function cache.getValue(key)
    local value = data[key]
    if type(value) == "table" then
        return utils.deepcopy(value)
    end
    return value
end

function cache.reset()
    config.saveFile("data/cache.json", { version = version })
end

function cache.removeDuplicates(path)
    local data = config.loadText(path)

    local new = {}

    for _, entry in pairs(data) do
        new[entry] = entry
    end

    config.saveRawTable(path, new)
end

function cache.generateRecordsList()
    if config.fileExists("data/spawnables/entity/records/records.txt") then return end

    local records = {
        "gamedataAttachableObject_Record",
        "gamedataCarriableObject_Record",
        "gamedataCharacter_Record",
        "gamedataProp_Record",
        "gamedataSpawnableObject_Record",
        "gamedataSubCharacter_Record",
        "gamedataVehicle_Record",
    }

    local file = io.open("data/spawnables/entity/records/records.txt", "w")

    for _, record in pairs(records) do
        for _, entry in pairs(TweakDB:GetRecords(record)) do
            file:write(entry:GetID().value .. "\n")
        end
    end

    file:close()
end

function cache.generateStaticAudioList()
    if config.fileExists("data/spawnables/visual/sounds/sounds.txt") then return end

    local data = config.loadFile("data.json")["Data"]["RootChunk"]["root"]["Data"]["events"]
    local sounds = {}

    for _, entry in pairs(data) do
        table.insert(sounds, entry["redId"]["$value"])
    end

    config.saveRawTable("data/spawnables/visual/sounds/sounds.txt", sounds)
end

function cache.generateDevicePSClassList()
    config.saveFile("deviceComponentPSClasses.json", utils.getDerivedClasses("gameDeviceComponent"))
end

local function shouldExclude(args)
    local variants = {
        "_apps",
        "_rigs",
        "_infinite",
        "_tiling",
        "_bBox_max",
        "_bBox_min",
        "_collision"
    }

    for _, arg in pairs(args) do
        local name = arg
        for _, variant in pairs(variants) do
            name = name:gsub(variant, "")
        end

        for _, exclusion in pairs(settings.cacheExlusions) do
            if name == exclusion then
                return true
            end
        end
    end
end

---Tries to get the cached value for each key, if any of the keys is not cached, the notFound callback is called with a task object on which task:taskCompleted() must be called once the value has been put into the cache
---@param ... string List of keys to check
---@return table { notFound = function (notFoundCallback) -> { found = function (foundCallback) } }
function cache.tryGet(...)
    local arg = {...}
    local missing = false

    for _, key in pairs(arg) do
        local value = cache.getValue(key)

        if value == nil then
            missing = true
        end
    end

    if shouldExclude(arg) then
        missing = true
    end

    return {
        ---Callback for when one of the keys was not cached, callback gets a task object on which it shall call task:taskCompleted() once the value is found
        ---@param notFoundCallback function
        notFound = function (notFoundCallback)
            local task = tasks:new()
            if missing then
                task:addTask(function ()
                    notFoundCallback(task)
                end)
            end

            return {
                ---Callback for when all keys are cached
                found = function (foundCallback)
                    task:onFinalize(function ()
                        foundCallback()
                    end)
                    task:run()
                end
            }
        end
    }
end

return cache