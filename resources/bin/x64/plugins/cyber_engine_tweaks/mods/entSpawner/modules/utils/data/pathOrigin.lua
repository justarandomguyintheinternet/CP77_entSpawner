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

---@type table<string, boolean> Lowercase paths with `\`.
local moddedPaths = {}

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
        end
    end

    shippedPaths = nil
end

---Records the entries one list file just added.
---@param listPath string List file path, as passed to `io.open`.
---@param entries ConfigSpawnPathEntry[]
---@param firstIndex integer Index of the first entry read from this file.
function pathOrigin.registerList(listPath, entries, firstIndex)
    local listKey = listPath:lower()

    if shippedOtherLists[listKey] then return end

    if shippedDepotLists[listKey] then
        if not shippedPaths then return end

        for index = firstIndex, #entries do
            shippedPaths[entries[index].name] = true
        end

        return
    end

    for index = firstIndex, #entries do
        local path = entries[index].name
        if path:find("[\\/]") then
            moddedPaths[(path:lower():gsub("/", "\\"))] = true
        end
    end
end

---@param normalizedPath string Lowercase path with `\`.
---@return boolean
function pathOrigin.isModded(normalizedPath)
    return moddedPaths[normalizedPath] == true
end

return pathOrigin
