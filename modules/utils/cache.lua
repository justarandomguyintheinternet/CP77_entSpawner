---@diagnostic disable: missing-parameter
local config = require("modules/utils/config")
local builder = require("modules/utils/entityBuilder")
local Cron = require("modules/utils/Cron")

local data = {}
local cache = {}

function cache.load()
    config.tryCreateConfig("data/cache.json", {})
    data = config.loadFile("data/cache.json")
end

function cache.addValue(key, value)
    data[key] = value
    config.saveFile("data/cache.json", data)
end

function cache.getValue(key)
    return nil
end

function cache.generateClothList()
    local meshes = config.loadText("data/spawnables/mesh/all/meshes.txt")
    local start = 0
    local registered = 0 + start
    local loaded = 0 + start
    local factor = 60

    Cron.Every(0.15, function (timer)
        for i = 1, factor do
            if registered + i > #meshes then break end

            local mesh = meshes[registered + i]

            builder.registerLoadResource(mesh, function (resource)
                for _, param in ipairs(resource.parameters) do
                    local dump = tostring(Dump(param, true))

                    if dump then
                        local cloth = dump:match("name: meshMeshParamCloth")
                        local gfx = dump:match("name: meshMeshParamCloth_Graphical")
                        if cloth ~= nil and gfx == nil then
                            print("Found mesh", mesh)
                            local file = io.open("data/spawnables/mesh/cloth/paths.txt", "a")
                            file:write(mesh .. "\n")
                            file:close()
                        end
                    end
                end
                loaded = loaded + 1
            end)
        end
        registered = registered + factor

        print("Loaded: " .. loaded .. "/" .. #meshes)
        print("Not Loaded: " .. registered - loaded)
        print("Registered: " .. registered .. "/" .. #meshes)

        local file = io.open("data/spawnables/mesh/cloth/loaded.txt", "w")
        file:write(tostring(loaded))
        file:close()

        if loaded >= #meshes then
            print("Done")
            timer:Halt()
        end
    end)
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

return cache