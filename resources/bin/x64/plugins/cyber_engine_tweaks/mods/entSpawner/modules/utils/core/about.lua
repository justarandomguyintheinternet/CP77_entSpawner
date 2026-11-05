---Mod metadata (version, credits) and the descriptors for everything World Builder relies on.
---
---This module is the public face of that data: other mods reach it through
---`GetMod("entSpawner")`, which exposes `.version`, `.about`, `.getVersion()` and
---`.getDependencies()`. Nothing here requires another module, so it stays safe to pull in from
---anywhere in the mod, including before the game is up.
---
---States are resolved on demand instead of at load time: plugins register at different points
---during startup, so a status read once would go stale.

---@alias aboutState "ok"|"outdated"|"missing"|"unknown"

---@class aboutDependency
---@field id string Stable identifier, safe to match on from other mods.
---@field name string Display name.
---@field required boolean Whether the mod needs it to work as intended.
---@field blocking boolean? Required to the point that World Builder refuses to start without it.
---@field minVersion string? Lowest version that satisfies the requirement.
---@field provides string What it brings to World Builder.
---@field url string? Where to get it.
---@field missingIssue string? Message used by `getBlockingIssues` instead of the default one.
---@field check fun(): aboutState, string? Current state, plus the detected version when known.

---@class aboutDependencyStatus
---@field id string
---@field name string
---@field required boolean
---@field blocking boolean
---@field minVersion string?
---@field provides string
---@field url string?
---@field state aboutState
---@field detectedVersion string?
---@field installed boolean Present in any version.
---@field satisfied boolean Present and new enough.

local ARCHIVE_XL_VERSION = "1.28.1"
local CODEWARE_VERSION = "1.21.2"
local COLLISION_PREVIEW_ARCHIVE = "scc_collision.archive"

local about = {
    name = "World Builder",
    version = "2.0.0",
    author = "NexusGuy999",
    maintainer = "Akiway",
    contributors = { "spiritualspirit", "tordalor", "Spuddeh", "MisterChedda", "SunliveQ", "theCyanideX" },
    thanks = "A huge thank you to everyone supporting World Builder: the testers, the bug reporters, everyone sending feedback and ideas, and everyone sharing what they build with it. The mod keeps growing because of you.",
    states = {
        ok = "ok",
        outdated = "outdated",
        missing = "missing",
        unknown = "unknown"
    }
}

local archiveCache = {}

---Archives cannot appear while the game is running, so one lookup per name is enough.
---@param name string
---@return boolean
local function archiveInstalled(name)
    if archiveCache[name] == nil then
        local ok, exists = pcall(ModArchiveExists, name)
        archiveCache[name] = ok and exists == true
    end

    return archiveCache[name]
end

---@param name string
---@return any
local function getMod(name)
    local ok, mod = pcall(GetMod, name)
    if not ok then
        return nil
    end

    return mod
end

---@param plugin any
---@return string?
local function getPluginVersion(plugin)
    if plugin == nil then
        return nil
    end

    -- Plugins are not necessarily plain tables, so the getter is read through pcall as well.
    local readable, getter = pcall(function()
        return plugin.Version
    end)

    if not readable or type(getter) ~= "function" then
        return nil
    end

    local ok, version = pcall(getter)
    if not ok or version == nil then
        return nil
    end

    return tostring(version)
end

---State of an ArchiveXL-style plugin, both of which expose `Version()` and `Require()`.
---@param plugin any
---@param minVersion string
---@return aboutState
---@return string?
local function checkPlugin(plugin, minVersion)
    if not plugin then
        return about.states.missing
    end

    local version = getPluginVersion(plugin)
    local ok, satisfied = pcall(function()
        return plugin.Require(minVersion)
    end)

    if ok and not satisfied then
        return about.states.outdated, version
    end

    return about.states.ok, version
end

---Whether a Redscript ScriptableService of that name is registered.
---@param name string
---@return boolean
local function hasScriptableService(name)
    local ok, service = pcall(function()
        return Game.GetScriptableServiceContainer():GetService(name)
    end)

    return ok and service ~= nil
end

---Whether a class of that name exists in the RTTI, which is how a native plugin that only
---registers types shows up from Lua.
---@param name string
---@return boolean
local function hasNativeClass(name)
    local ok, class = pcall(function()
        return Reflection.GetClass(name)
    end)

    return ok and class ~= nil
end

---@type aboutDependency[]
about.dependencies = {
    {
        id = "cyberEngineTweaks",
        name = "Cyber Engine Tweaks",
        required = true,
        provides = "Hosts the whole editor, and provides the Lua runtime, the ImGui interface and the game bindings it is built on.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/107",
        check = function()
            -- This code only ever executes inside CET, so its presence is a given.
            local ok, version = pcall(GetVersion)
            return about.states.ok, ok and version ~= nil and tostring(version) or nil
        end
    },
    {
        id = "red4ext",
        name = "RED4ext",
        required = true,
        provides = "Loads plugins for ArchiveXL and Codeware and World Builder.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/2380",
        check = function()
            -- It has no Lua side of its own; it is what loads ArchiveXL and Codeware, so either
            -- of those answering proves it is there.
            if ArchiveXL or Codeware then
                return about.states.ok
            end

            return about.states.unknown
        end
    },
    {
        id = "archiveXL",
        name = "ArchiveXL",
        required = true,
        blocking = true,
        minVersion = ARCHIVE_XL_VERSION,
        provides = "Defines the .xl format the Export tab writes to, and loads the streaming sectors and custom resources those files describe.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/4198",
        check = function()
            return checkPlugin(ArchiveXL, ARCHIVE_XL_VERSION)
        end
    },
    {
        id = "codeware",
        name = "Codeware",
        required = true,
        blocking = true,
        minVersion = CODEWARE_VERSION,
        provides = "Gives World Builder the game access it needs to spawn and export objects. Also used for the Bended Mesh preview.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/7780",
        check = function()
            return checkPlugin(Codeware, CODEWARE_VERSION)
        end
    },
    {
        id = "redscriptPart",
        name = "World Builder Redscript part",
        required = true,
        blocking = true,
        missingIssue = "Redscript part of the mod is not installed",
        provides = "Registers the EntityBuilder service from r6\\scripts\\WorldBuilder, which reports when spawned entities are assembled and attached, and when their resources have finished loading.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/1511",
        check = function()
            -- The service is registered by the mod's own .reds file, which only gets compiled
            -- when Redscript is installed: one check covers both.
            if hasScriptableService("EntityBuilder") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "collisionPreviewArchive",
        name = "Collision Mesh Preview archive",
        required = false,
        provides = "Makes collision meshes visible in the world. Optional file on the World Builder Nexus page.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/20660?tab=files",
        check = function()
            if archiveInstalled(COLLISION_PREVIEW_ARCHIVE) then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "unlimitedGeometryCacheStreaming",
        name = "UnlimitedGeometryCacheStreaming",
        required = false,
        provides = "Needed for Collision Meshes: keeps their collision working anywhere on the map, not only near their original sector.\nMods that use Collision Meshes need it too.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/29096",
        check = function()
            -- No Lua API, so it is detected through the two halves it registers: the .reds service
            -- and the native RTTI class. Either one answering counts as installed, so an unexpected
            -- lookup result cannot report a working install as missing.
            if hasNativeClass("UnlimitedGeometryCacheStreamingNative")
                or hasScriptableService("UnlimitedGeometryCacheStreamingService") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "worldBuilderTools",
        name = "World Builder Tools",
        required = false,
        provides = "Included with World Builder. Lets the Spline preview NPC follow your exact tangents instead of engine-computed ones.",
        check = function()
            -- The plugin registers a global RTTI function rather than a class, so ask it directly.
            local ok, ready = pcall(function()
                return WBSplineToolsReady ~= nil and WBSplineToolsReady()
            end)

            if ok and ready then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "redHotTools",
        name = "Red Hot Tools",
        required = false,
        provides = "Adds World Builder actions to its World Inspector (search, Replacer, copy AXL node mutation). Required for the Spline preview NPC.",
        url = "https://github.com/psiberx/cp2077-red-hot-tools",
        check = function()
            if getMod("RedHotTools") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "removalEditor",
        name = "Removal Editor",
        required = false,
        provides = "Lets the Replacer hide the original object it replaces, by adding it to a Removal Editor preset.",
        check = function()
            if getMod("removalEditor") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "appearanceMenuMod",
        name = "Appearance Menu Mod",
        required = false,
        provides = "Adds the AMM props to the spawn list, under Entity > Template (AMM). Not needed to import AMM presets from data\\AMMImport.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/790",
        check = function()
            if getMod("AppearanceMenuMod") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "windowUtils",
        name = "WindowUtils",
        required = false,
        provides = "Adds extra window handling to the World Builder windows.",
        check = function()
            if getMod("WindowUtils") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "windowSwitcher",
        name = "WindowSwitcher",
        required = false,
        provides = "Adds a World Builder taskbar entry, hidden while in 3D-Editor mode.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/30005",
        check = function()
            if getMod("WindowSwitcher") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "xUtils",
        name = "XUtils",
        required = false,
        provides = "While its free camera is active, new objects spawn at the camera instead of at player height.",
        check = function()
            if getMod("XUtils") then
                return about.states.ok
            end

            return about.states.missing
        end
    },
    {
        id = "freefly",
        name = "FreeFly",
        required = false,
        provides = "While flying, new objects spawn at the camera instead of at player height. Flight pauses while in 3D-Editor mode.",
        url = "https://www.nexusmods.com/cyberpunk2077/mods/780",
        check = function()
            if getMod("freefly") then
                return about.states.ok
            end

            return about.states.missing
        end
    }
}

---@return string
function about.getVersion()
    return about.version
end

---@param id string
---@return aboutDependency?
function about.getDependency(id)
    for _, dependency in ipairs(about.dependencies) do
        if dependency.id == id then
            return dependency
        end
    end

    return nil
end

---Current state of one dependency, given either its id or its descriptor.
---@param dependency aboutDependency|string
---@return aboutDependencyStatus?
function about.getDependencyStatus(dependency)
    local entry = type(dependency) == "string" and about.getDependency(dependency) or dependency
    if type(entry) ~= "table" or type(entry.check) ~= "function" then
        return nil
    end

    local ok, state, detectedVersion = pcall(entry.check)
    if not ok or state == nil then
        state, detectedVersion = about.states.unknown, nil
    end

    return {
        id = entry.id,
        name = entry.name,
        required = entry.required == true,
        blocking = entry.blocking == true,
        minVersion = entry.minVersion,
        provides = entry.provides,
        url = entry.url,
        state = state,
        detectedVersion = detectedVersion,
        installed = state == about.states.ok or state == about.states.outdated,
        satisfied = state == about.states.ok
    }
end

---Current state of every dependency, in declaration order.
---@return aboutDependencyStatus[]
function about.getDependencies()
    local statuses = {}

    for _, dependency in ipairs(about.dependencies) do
        local status = about.getDependencyStatus(dependency)
        if status then
            table.insert(statuses, status)
        end
    end

    return statuses
end

---Messages for the dependencies that keep the mod from starting at all.
---@return string[]
function about.getBlockingIssues()
    local issues = {}

    for _, dependency in ipairs(about.dependencies) do
        if dependency.blocking then
            local status = about.getDependencyStatus(dependency)

            if status and status.state == about.states.missing then
                table.insert(issues, dependency.missingIssue or (dependency.name .. " is not installed"))
            elseif status and status.state == about.states.outdated then
                table.insert(issues, dependency.name .. " version is outdated, please update to " .. tostring(dependency.minVersion))
            end
        end
    end

    return issues
end

return about
