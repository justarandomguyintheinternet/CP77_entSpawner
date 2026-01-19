local utils = require("modules/utils/utils")
config = {}

function config.fileExists(filename)
    local f=io.open(filename,"r")
    if (f~=nil) then io.close(f) return true else return false end
end

function config.tryCreateConfig(path, data)
	if not config.fileExists(path) then
        local file = io.open(path, "w")
        local jconfig = json.encode(data)
        file:write(jconfig)
        file:close()
    end
end

function config.loadFile(path)
    local file = io.open(path, "r")
    local config = {}
    local success = pcall(function ()
        config = json.decode(file:read("*a"))
    end)
    if not success then
        print("Failed to load file: " .. path .. ", restoring empty state")
    end
    file:close()
    return config
end

function config.saveFile(path, data)
    local file = io.open(path, "w")
    local jconfig = json.encode(data)
    file:write(jconfig)
    file:close()
end

function config.loadFiles(path, files)
    local files = files or {}

    for _, file in pairs(dir(path)) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile(path .. file.name)
            table.insert(files, {data = data.spawnable, lastSpawned = nil, name = data.name, fileName = data.name })
        elseif file.type == "directory" then
            config.loadFiles(path .. file.name .. "/", files)
        end
    end

    table.sort(files, function(a, b) return a.name < b.name end)

    return files
end

function config.loadLists(path, paths)
    local paths = paths or {}

    for _, file in pairs(dir(path)) do
        local extension = file.name:match("^.+(%..+)$")
        if extension and extension:lower() == ".txt" then
            local data = io.open(path .. file.name)
            for line in data:lines() do
                table.insert(paths, {data = { spawnData = line }, lastSpawned = nil, name = line, fileName = utils.getFileName(line) })
            end

            data:close()
        elseif file.type == "directory" then
            config.loadLists(path .. file.name .. "/", paths)
        end
    end

    table.sort(paths, function(a, b) return a.name < b.name end)

    return paths
end

local function recursiveAddMissingKeys(source, target)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            recursiveAddMissingKeys(v, target[k])
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function config.backwardComp(path, data)
    local f = config.loadFile(path)

    recursiveAddMissingKeys(data, f)

    config.saveFile(path, f)
end

function config.loadText(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end
    return lines
end

function config.loadRaw(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    return content
end

function config.saveRaw(path, data)
    local file = io.open(path, "w")
    file:write(data)
    file:close()
end

function config.saveRawTable(path, data)
    local file = io.open(path, "w")
    for _, line in pairs(data) do
        file:write(line .. "\n")
    end
    file:close()
end

return config