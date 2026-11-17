---Tells modded depot paths apart from vanilla ones through the spawn lists: a path is modded when a
---third-party `.txt` under `data/spawnables/` lists it and no shipped list does.
local pathOrigin = {}

---@param lists string[] Paths relative to `data/spawnables/`.
---@return table<string, boolean>
local function toListSet(lists)
    local set = {}
    for _, list in ipairs(lists) do
        set[("data/spawnables/" .. list):lower()] = true
    end

    return set
end

-- Shipped lists of vanilla depot paths, all lowercase with `\`. A new one must be added here, or
-- its paths read as modded.
local shippedDepotLists = toListSet({
    "ai/aiSpot/paths_workspot.txt",
    "area/conversationArea/groups/paths_conversation_groups.txt",
    "area/conversationArea/scenes/paths_conversation_scenes.txt",
    "entity/device/paths_device_ent.txt",
    "entity/templates/paths_ent.txt",
    "lights/iesProfiles/paths_ies.txt",
    "mesh/all/paths_mesh.txt",
    "mesh/all/w2meshes.txt",
    "mesh/bakedDestruction/paths_baked_destruction.txt",
    "mesh/bended/paths_bended.txt",
    "mesh/cloth/paths.txt",
    "mesh/destructible/paths_destructible.txt",
    "mesh/physicalDestruction/paths_physical_destruction.txt",
    "mesh/physics/paths_filtered_mesh.txt",
    "mesh/roadIntersection/paths_road_intersection.txt",
    "meta/reflectionProbe/paths_envprobe.txt",
    "visual/decals/paths_mi.txt",
    "visual/effects/paths_effect.txt",
    "visual/particles/paths_particle.txt"
})

-- Shipped lists that hold no depot path: records, sound names, collision hashes.
local shippedOtherLists = toListSet({
    "audio/sounds/sounds.txt",
    "colliders/collision_meshes.txt",
    "entity/records/records.txt"
})

-- Depot roots shipped whole by the game.
local vanillaRoots = { engine = true, dlc = true, scc = true }

-- Second-level folders the game ships under `base\` and `ep1\`.
local vanillaFolders = {
    base = {
        animations = true, characters = true, cinematics = true, dependencies = true, entities = true,
        environment = true, fx = true, gameplay = true, items = true, journal = true, lighting = true,
        localization = true, materials = true, mechanical = true, media = true, movies = true,
        open_world = true, physics = true, prefabs = true, quest = true, sound = true, spawner = true,
        static = true, streaming = true, surfaces = true, systems = true, textures = true, tmp = true,
        vehicles = true, weapons = true, weather = true, workspots = true, worlds = true
    },
    ep1 = {
        animations = true, base = true, characters = true, entities = true, environment = true, fx = true,
        gameplay = true, items = true, journal = true, lighting = true, localization = true,
        mechanical = true, media = true, movies = true, openworld = true, prefabs = true, quest = true,
        sound = true, surfaces = true, users = true, vehicles = true, weapons = true, weather = true,
        workspots = true, worlds = true
    }
}

---@class PathOriginListSource
---@field list string Third-party list file name, without extension.
---@field folder string? Subfolder holding the list below its spawn list root, if any.
---@field file string List path relative to `data/spawnables/`.

---@type table<string, PathOriginListSource[]> Lowercase paths with `\` -> lists citing them, in load order.
local moddedPaths = {}

-- Bumped on every change to `moddedPaths`.
local version = 0

---@type table<string, boolean>? Only alive during a scan.
local shippedPaths = nil

---Starts collecting shipped paths, so `endListScan` can drop third-party lines citing vanilla assets.
function pathOrigin.beginListScan()
    shippedPaths = {}
end

---Settles the modded paths against the shipped ones collected since `beginListScan`.
function pathOrigin.endListScan()
    if not shippedPaths then return end

    for path in pairs(moddedPaths) do
        if shippedPaths[path] then
            moddedPaths[path] = nil
            version = version + 1
        end
    end

    shippedPaths = nil
end

---Records the entries one list file just added.
---@param listPath string List file path, as passed to `io.open`.
---@param entries ConfigSpawnPathEntry[]
---@param firstIndex integer Index of the first entry read from this file.
---@param rootPath string? Spawn list root the file was found under.
function pathOrigin.registerList(listPath, entries, firstIndex, rootPath)
    local listKey = listPath:lower()

    if shippedOtherLists[listKey] then return end

    if shippedDepotLists[listKey] then
        if not shippedPaths then return end

        for index = firstIndex, #entries do
            shippedPaths[entries[index].name] = true
        end

        return
    end

    local relative = listPath:gsub("\\", "/")
    if rootPath and relative:sub(1, #rootPath) == rootPath then
        relative = relative:sub(#rootPath + 1)
    end

    local folder = relative:match("([^/]+)/[^/]+$")
    local source = {
        list = (relative:match("([^/]+)$") or relative):gsub("%.[tT][xX][tT]$", ""):gsub("%.[tT][xX][tT]$", ""),
        folder = folder and folder:lower() or nil,
        file = listPath:gsub("\\", "/"):gsub("^data/spawnables/", "")
    }

    for index = firstIndex, #entries do
        local path = entries[index].name
        if path:find("[\\/]") then
            local key = path:lower():gsub("/", "\\")
            local sources = moddedPaths[key]
            if not sources then
                moddedPaths[key] = { source }
                version = version + 1
            else
                local known = false
                for _, existing in ipairs(sources) do
                    if existing.file == source.file then known = true break end
                end
                if not known then
                    sources[#sources + 1] = source
                    version = version + 1
                end
            end
        end
    end
end

---@param normalizedPath string Lowercase path with `\`.
---@return boolean
function pathOrigin.isModded(normalizedPath)
    return moddedPaths[normalizedPath] ~= nil
end

---Third-party list that first listed a modded path.
---@param normalizedPath string Lowercase path with `\`.
---@return PathOriginListSource?
function pathOrigin.getListSource(normalizedPath)
    local sources = moddedPaths[normalizedPath]
    return sources and sources[1]
end

---Every third-party list citing a modded path.
---@param normalizedPath string Lowercase path with `\`.
---@return PathOriginListSource[]
function pathOrigin.getListSources(normalizedPath)
    return moddedPaths[normalizedPath] or {}
end

---@return table<string, PathOriginListSource[]> Every modded path, keyed by lowercase path with `\`.
function pathOrigin.getModdedPaths()
    return moddedPaths
end

---@return integer version Changes whenever the modded paths or their lists do.
function pathOrigin.getVersion()
    return version
end

---Whether a path sits in a folder the game ships, by its first one or two segments.
---@param normalizedPath string Lowercase path with `\`.
---@return boolean
function pathOrigin.isVanillaLocation(normalizedPath)
    local root, folder = normalizedPath:match("^([^\\]+)\\([^\\]+)\\")
    if not root then return false end
    if vanillaRoots[root] then return true end

    local folders = vanillaFolders[root]
    return folders ~= nil and folders[folder] == true
end

---Whether a depot path is a mod asset: listed only by a third-party list, or outside the game's folders.
---@param normalizedPath string Lowercase path with `\`.
---@return boolean
function pathOrigin.isModAsset(normalizedPath)
    return moddedPaths[normalizedPath] ~= nil or not pathOrigin.isVanillaLocation(normalizedPath)
end

return pathOrigin
