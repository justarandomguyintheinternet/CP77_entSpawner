local config = require("modules/utils/config")
local tasks = require("modules/utils/tasks")
local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")

local sanitizeSpawnData = false
local data = {}

---@class cache
---@field staticData {ambientData : table, staticData : table, ambientQuad : table, ambientMetadata : table, staticMetadata : table, ambientMetadataAll : table, staticMetadataAll : table, signposts : table} 
local cache = {
    staticData = {}
}

local version = 9

function cache.load()
    config.tryCreateConfig("data/cache.json", { version = version })
    data = config.loadFile("data/cache.json")

    if not data.version or data.version < version then
        data = { version = version }
        config.saveFile("data/cache.json", data)
        print("[entSpawner] Cache is outdated, resetting cache")
    end

    cache.loadStaticData()

    if not sanitizeSpawnData then return end
    cache.generateDevicePSClassList()
    cache.generateRecordsList()
    cache.generateAudioFiles()

    cache.removeDuplicates("data/spawnables/ai/aiSpot/paths_workspot.txt")
    cache.removeDuplicates("data/spawnables/entity/templates/paths_ent.txt")
    cache.removeDuplicates("data/spawnables/mesh/all/paths_mesh.txt")
    cache.removeDuplicates("data/spawnables/mesh/physics/paths_filtered_mesh.txt")
    cache.removeDuplicates("data/spawnables/visual/particles/paths_particle.txt")
    cache.removeDuplicates("data/spawnables/visual/decals/paths_mi.txt")
    cache.removeDuplicates("data/spawnables/visual/effects/paths_effect.txt")
end

function cache.loadStaticData()
    cache.staticData.ambientData = config.loadFile("data/audio/ambientDataFull.json")
    cache.staticData.staticData = config.loadFile("data/audio/staticDataFull.json")
    cache.staticData.ambientQuad = config.loadFile("data/audio/ambientQuadFull.json")
    cache.staticData.ambientMetadata = config.loadFile("data/audio/ambientMetadataFull.json")
    cache.staticData.staticMetadata = config.loadFile("data/audio/staticMetadataFull.json")
    cache.staticData.ambientMetadataAll = config.loadFile("data/audio/ambientMetadataAll.json")
    cache.staticData.staticMetadataAll = config.loadFile("data/audio/staticMetadataAll.json")
    cache.staticData.signposts = config.loadFile("data/audio/signpostsData.json")
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

local function removeDuplicatesTable(data)
    local new = {}
    local hash = {}

    for _, entry in pairs(data) do
        if not hash[entry] then
            table.insert(new, entry)
            hash[entry] = true
        end
    end

    return new
end

local function extractMetadata(metaData)
    local meta = {}
    local all = {}

    for _, data in pairs(metaData) do
        for _, event in pairs(data.events) do
            if not meta[event] then
                meta[event] = {}
            end
            table.insert(meta[event], data.metadata)
            table.insert(all, data.metadata)
        end
    end

    for key, data in pairs(meta) do
        meta[key] = removeDuplicatesTable(data)
    end

    all = removeDuplicatesTable(all)
    return meta, all
end

function cache.generateAudioFiles()
    local ambientData = config.loadFile("data/audio/ambientData.json")
    local ambientMetadata = config.loadFile("data/audio/ambientMetadata.json")
    local ambientQuad = config.loadFile("data/audio/ambientQuad.json")
    local signposts = config.loadFile("data/audio/signposts.json")
    local staticData = config.loadFile("data/audio/staticData.json")
    local staticMetadata = config.loadFile("data/audio/staticMetadata.json")

    config.saveFile("data/audio/signpostsData.json", {
        enter = removeDuplicatesTable(signposts.enter),
        exit = removeDuplicatesTable(signposts.exit)
    })

    config.saveFile("data/audio/ambientDataFull.json", {
        onEnter = removeDuplicatesTable(ambientData.onEnter),
        onActive = removeDuplicatesTable(ambientData.onActive),
        onExit = removeDuplicatesTable(ambientData.onExit),
        parameters = removeDuplicatesTable(ambientData.parameters),
        reverb = removeDuplicatesTable(ambientData.reverb)
    })

    config.saveFile("data/audio/staticDataFull.json", {
        onEnter = removeDuplicatesTable(staticData.onEnter),
        onActive = removeDuplicatesTable(staticData.onActive),
        onExit = removeDuplicatesTable(staticData.onExit),
        parameters = removeDuplicatesTable(staticData.parameters),
        reverb = removeDuplicatesTable(staticData.reverb)
    })

    local quads = {}
    for _, entry in pairs(ambientQuad) do
        if not quads[entry.events[1]] then
            quads[entry.events[1]] = entry.events
        end
    end
    config.saveFile("data/audio/ambientQuadFull.json", quads)

    local amb, ambAll = extractMetadata(ambientMetadata)
    local stat, statAll = extractMetadata(staticMetadata)
    config.saveFile("data/audio/ambientMetadataFull.json", amb)
    config.saveFile("data/audio/staticMetadataFull.json", stat)
    config.saveFile("data/audio/ambientMetadataAll.json", ambAll)
    config.saveFile("data/audio/staticMetadataAll.json", statAll)
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