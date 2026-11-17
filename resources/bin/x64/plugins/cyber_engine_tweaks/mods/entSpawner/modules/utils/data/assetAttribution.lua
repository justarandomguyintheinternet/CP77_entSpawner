local pathOrigin = require("modules/utils/data/pathOrigin")
local verifiedAuthors = require("modules/utils/data/verifiedAuthors")

---Infers the author and props pack of a mod asset from its depot path and the list that ships it.
---Every method proposes a candidate with a score; the best scoring author and pack win.
local assetAttribution = {}

---@class AssetAttributionValue
---@field name string Display name; co-authors joined with " & ".
---@field names string[]? Authors only: each author, for co-authored packs.
---@field score number 0-100.
---@field method string Key of `assetAttribution.methods`.
---@field source string? Path fragment or list the value was read from.

---@class AssetAttribution
---@field author AssetAttributionValue?
---@field pack AssetAttributionValue?

---@type table<string, string> Lowercase name -> Nexus Mods account name.
local knownAuthors = {}
for _, name in ipairs(verifiedAuthors.names) do
    knownAuthors[name:lower()] = name
end

---@type table<string, string[]> Lowercase name or alias -> verified authors it stands for.
local authorTokens = {}
for lower, name in pairs(knownAuthors) do
    authorTokens[lower] = { name }
end
for alias, names in pairs(verifiedAuthors.aliases) do
    authorTokens[alias:lower()] = names
end

---@type string[] Names and aliases containing `_`, longest first.
local multiTokenHandles = {}
for token in pairs(authorTokens) do
    if token:find("_", 1, true) then
        multiTokenHandles[#multiTokenHandles + 1] = token
    end
end
table.sort(multiTokenHandles, function (a, b) return #a > #b end)

-- Roots under which the next segment is the pack (or author) folder.
local containerRoots = { base = true, ep1 = true, mod = true, mods = true }

-- Leading words that name a pack, not its author.
local nonAuthorTokens = {
    additional = true, better = true, christmas = true, collectible = true, custom = true, dynamic = true,
    extra = true, holiday = true, improved = true, manual = true, more = true, my = true, new = true,
    real = true, simple = true, the = true, xmas = true, mod = true, mods = true, base = true, test = true
}

-- Folder names too generic to name a pack.
local genericFolders = {
    asset = true, assets = true, base = true, common = true, decoration = true, ent = true, entities = true,
    entity = true, environment = true, gameplay = true, items = true, materials = true, mesh = true,
    meshes = true, misc = true, mod = true, mods = true, models = true, objects = true, prop = true,
    props = true, resources = true, textures = true, prop_base = true, props_base = true, animations = true,
    appearances = true, apps = true, characters = true, ents = true, fx = true, gui = true, icon = true,
    icons = true, journal = true, localization = true, quest = true, sectors = true, sounds = true,
    texture = true, vehicles = true, workspots = true, worlds = true
}

---@type table<string, { label: string, tooltip: string }>
assetAttribution.methods = {
    verifiedAuthor = { label = "Verified author", tooltip = "Path contains the name of a verified Nexus Mods author." },
    verifiedAlias = { label = "Verified alias", tooltip = "Path contains a confirmed handle of verified Nexus Mods author(s)." },
    authorAlias = { label = "Author alias", tooltip = "Path contains a shortened or extended form of a verified author's name." },
    listFolder = { label = "List folder", tooltip = "The spawn list sits in a subfolder, usually named after its author (data/spawnables/.../<author>/<list>.txt); reliable only for a verified author." },
    sharedPrefix = { label = "Shared prefix", tooltip = "Several asset folders start with this prefix (<author>_<pack>)." },
    authorFolder = { label = "Author folder", tooltip = "Path layout mod\\<author>\\<pack>\\..." },
    customRoot = { label = "Custom root", tooltip = "Path starts with a non-game root folder, usually the author's." },
    numberedPrefix = { label = "Handle prefix", tooltip = "Folder prefix looks like a user handle (<author>_<pack>)." },
    prefixGuess = { label = "Prefix guess", tooltip = "Guessed from the folder prefix (<author>_<pack>); may be part of the pack name." },
    packMatch = { label = "Known pack", tooltip = "Another folder with this pack name was attributed to this author." },
    packFolder = { label = "Pack folder", tooltip = "Folder the mod's assets are grouped under." },
    listName = { label = "List name", tooltip = "Name of the spawn list that ships the asset." }
}

assetAttribution.reliableScore = 70
assetAttribution.likelyScore = 50

---@type table<string, table<string, boolean>>? Prefix token -> distinct second tokens following it.
local prefixIndex = nil
---@type table<string, AssetAttributionValue|false> Pack name -> its reliable author, false when ambiguous.
local packAuthors = {}
---@type { version: integer, extras: string }? Inputs of the current indexes.
local indexInputs = nil

---AMM (Appearance Menu Mod) folders and lists group other people's props; they name neither author nor pack.
---@param name string? Lowercase.
---@return boolean
local function isIgnored(name)
    return name ~= nil and (name == "amm" or name:find("^amm_") ~= nil)
end

---Splits a path into segments, dropping ignored folders among the leading ones.
---@param path string Lowercase path with `\`.
---@return string[]
local function splitPath(path)
    local segments = {}
    for segment in path:gmatch("[^\\]+") do
        segments[#segments + 1] = segment
    end

    local kept = {}
    for i, segment in ipairs(segments) do
        if not (i < #segments and i <= 3 and isIgnored(segment)) then
            kept[#kept + 1] = segment
        end
    end
    return kept
end

---Folder segment a mod groups its assets under: the one after a container root, else the root.
---@param segments string[]
---@return string? folder
---@return integer? index
local function getPackFolder(segments)
    if #segments < 2 then return nil end

    if containerRoots[segments[1]] then
        if #segments < 3 then return nil end
        return segments[2], 2
    end

    return segments[1], 1
end

---@param folder string
---@return string? token
---@return string? rest
local function splitPrefix(folder)
    return folder:match("^([^_]+)_(.+)$")
end

---@param name string?
---@return boolean
local function isGeneric(name)
    return name == nil or name == "" or genericFolders[name] == true
end

---Verified author a token abbreviates (`breezy` -> Breezypunk) or extends (`akiwaymods` -> Akiway).
---@param token string
---@return string?
local function findAuthorAlias(token)
    if #token < 5 or nonAuthorTokens[token] or genericFolders[token] or authorTokens[token] then return nil end

    local match = nil
    for lower, name in pairs(knownAuthors) do
        local abbreviates = #lower > #token and lower:sub(1, #token) == token
        local extends = #lower >= 6 and #token > #lower and token:sub(1, #lower) == lower
        if abbreviates or extends then
            if match then return nil end
            match = name
        end
    end
    return match
end

local resolveCandidates

---Rebuilds the prefix and pack indexes from the listed mod paths plus extra paths, unless neither changed.
---@param extraPaths string[]? Lowercase paths with `\`.
function assetAttribution.rebuildIndex(extraPaths)
    local sortedExtras = {}
    for i, path in ipairs(extraPaths or {}) do
        sortedExtras[i] = path
    end
    table.sort(sortedExtras)

    local inputs = { version = pathOrigin.getVersion(), extras = table.concat(sortedExtras, "\n") }
    if prefixIndex and indexInputs and indexInputs.version == inputs.version and indexInputs.extras == inputs.extras then
        return
    end
    indexInputs = inputs

    prefixIndex = {}
    packAuthors = {}

    local corpus = {}
    for path in pairs(pathOrigin.getModdedPaths()) do
        corpus[#corpus + 1] = path
    end
    for _, path in ipairs(extraPaths or {}) do
        corpus[#corpus + 1] = path
    end

    -- eviction_notice and eviction_notice_x share one pack, so prefixes count distinct second tokens.
    for _, path in ipairs(corpus) do
        local folder = getPackFolder(splitPath(path))
        local token, rest = nil, nil
        if folder then token, rest = splitPrefix(folder) end
        if token then
            prefixIndex[token] = prefixIndex[token] or {}
            prefixIndex[token][rest:match("^[^_]+")] = true
        end
    end

    for _, path in ipairs(corpus) do
        local author, pack = resolveCandidates(path)
        if author and pack and author.score >= assetAttribution.reliableScore then
            local known = packAuthors[pack.name]
            if known == nil then
                packAuthors[pack.name] = author
            elseif known and known.name ~= author.name then
                packAuthors[pack.name] = false
            end
        end
    end
end

---@param token string
---@return integer
local function countPrefixFolders(token)
    local count = 0
    for _ in pairs(prefixIndex and prefixIndex[token] or {}) do
        count = count + 1
    end
    return count
end

---@param name string
---@param score number
---@param method string
---@param source string?
---@return AssetAttributionValue
local function value(name, score, method, source)
    return { name = name, score = score, method = method, source = source }
end

---@param names string[]
---@param score number
---@param method string
---@param source string?
---@return AssetAttributionValue
local function authorValue(names, score, method, source)
    return { name = table.concat(names, " & "), names = names, score = score, method = method, source = source }
end

---Verified authors a token names, and whether it did so through an alias.
---@param token string
---@return string[]? names
---@return string method
local function lookupAuthor(token)
    local names = authorTokens[token]
    return names, knownAuthors[token] and "verifiedAuthor" or "verifiedAlias"
end

---@param current AssetAttributionValue?
---@param candidate AssetAttributionValue?
---@return AssetAttributionValue?
local function best(current, candidate)
    if not candidate or candidate.name == "" then return current end
    if not current or candidate.score > current.score then return candidate end
    return current
end

---Pack from the segments following the author's folder, skipping generic ones.
---@param segments string[]
---@param index integer First candidate segment.
---@param score number
---@param method string
---@return AssetAttributionValue?
local function packAfter(segments, index, score, method)
    for i = index, math.min(index + 2, #segments - 1) do
        if not isGeneric(segments[i]) then
            return value(segments[i], i == index and score or score - 10, method, table.concat(segments, "\\", 1, i))
        end
    end
    return nil
end

---Author named by one path segment, alone or as one of its `_` tokens.
---@param segments string[]
---@param i integer
---@return AssetAttributionValue? author
---@return AssetAttributionValue? pack
local function matchAuthorSegment(segments, i)
    local segment = segments[i]
    local source = table.concat(segments, "\\", 1, i)

    local segmentNames, segmentMethod = lookupAuthor(segment)
    if segmentNames then
        return authorValue(segmentNames, 95, segmentMethod, source), packAfter(segments, i + 1, 75, "packFolder")
    end

    -- Handles holding `_` (eva_fan) can't be found token by token.
    for _, handle in ipairs(multiTokenHandles) do
        if segment:sub(1, #handle + 1) == handle .. "_" then
            local names, method = lookupAuthor(handle)
            local rest = segment:sub(#handle + 2)
            local pack
            if isGeneric(rest) then
                pack = packAfter(segments, i + 1, 75, "packFolder")
            else
                pack = value(rest, 80, "packFolder", source)
            end
            return authorValue(names, 95, method, source), pack
        end
    end

    local tokens = {}
    for token in segment:gmatch("[^_]+") do
        tokens[#tokens + 1] = token
    end
    if #tokens < 2 then
        local alias = findAuthorAlias(segment)
        if alias then
            return authorValue({ alias }, 65, "authorAlias", source), packAfter(segments, i + 1, 60, "packFolder")
        end
        return nil, nil
    end

    for t, token in ipairs(tokens) do
        local names, method = lookupAuthor(token)
        local score = t == 1 and 95 or 85
        if not names and t == 1 then
            local alias = findAuthorAlias(token)
            names = alias and { alias } or nil
            method, score = "authorAlias", 65
        end

        if names then
            local rest = {}
            for r, other in ipairs(tokens) do
                if r ~= t and other ~= "by" then rest[#rest + 1] = other end
            end
            local packName = table.concat(rest, "_")
            local pack
            if isGeneric(packName) then
                pack = packAfter(segments, i + 1, score - 20, "packFolder")
            else
                pack = value(packName, score - 15, "packFolder", source)
            end
            return authorValue(names, score, method, source), pack
        end
    end

    return nil, nil
end

---@param normalized string Lowercase path with `\`.
---@return AssetAttributionValue? author
---@return AssetAttributionValue? pack
resolveCandidates = function (normalized)
    local segments = splitPath(normalized)
    local listSource = pathOrigin.getListSource(normalized)
    if listSource and isIgnored(listSource.list:lower()) then
        listSource = nil
    end
    local author, pack = nil, nil
    local authorSegment = nil

    -- Verified author anywhere in the first segments.
    for i = 1, math.min(3, #segments - 1) do
        local segmentAuthor, segmentPack = matchAuthorSegment(segments, i)
        if segmentAuthor then
            author = best(author, segmentAuthor)
            pack = best(pack, segmentPack)
            authorSegment = i
            break
        end
    end

    -- List stored in a subfolder: reliable only when the folder names a verified author.
    local listFolder = listSource and listSource.folder
    if listFolder and not isIgnored(listFolder) then
        local listFile = listFolder .. "/" .. listSource.list .. ".txt"
        local folderNames = authorTokens[listFolder]
        if folderNames then
            author = best(author, authorValue(folderNames, 85, "listFolder", listFile))
        elseif not isGeneric(listFolder) and not nonAuthorTokens[listFolder] then
            author = best(author, authorValue({ listFolder }, 45, "listFolder", listFile))
        end
        pack = best(pack, value(listSource.list, 70, "listName", listFile))
    end

    local folder, folderIndex = getPackFolder(segments)
    if folder then
        local folderSource = table.concat(segments, "\\", 1, folderIndex)
        local token, rest = splitPrefix(folder)
        local authorToken = token and (authorTokens[token] or findAuthorAlias(token))

        if token and not authorToken then
            local shared = countPrefixFolders(token) >= 2
            -- Pack after the author prefix; a generic rest (foo_props) defers to the next folder.
            local function splitPack(score)
                if isGeneric(rest) then
                    return packAfter(segments, folderIndex + 1, 60, "packFolder")
                end
                return value(rest, score, "packFolder", folderSource)
            end

            if shared and not nonAuthorTokens[token] then
                author = best(author, value(token, 75, "sharedPrefix", folderSource))
                pack = best(pack, splitPack(65))
            elseif folderIndex == 1 and not nonAuthorTokens[token] then
                author = best(author, value(token, 40, "customRoot", folderSource))
                pack = best(pack, isGeneric(rest) and packAfter(segments, 2, 60, "packFolder") or value(folder, 55, "packFolder", folderSource))
            elseif token:find("%d") and not nonAuthorTokens[token] then
                author = best(author, value(token, 55, "numberedPrefix", folderSource))
                pack = best(pack, splitPack(55))
            elseif not nonAuthorTokens[token] then
                author = best(author, value(token, 35, "prefixGuess", folderSource))
            end
        elseif not token then
            if folderIndex == 1 then
                author = best(author, value(folder, 45, "customRoot", folderSource))
                pack = best(pack, packAfter(segments, 2, 55, "packFolder"))
            elseif segments[1] == "mod" or segments[1] == "mods" then
                -- mod\<author>\<pack>\file needs at least one folder below the author.
                if #segments >= 4 and not isGeneric(segments[3]) then
                    author = best(author, value(folder, 65, "authorFolder", folderSource))
                    pack = best(pack, value(segments[3], 60, "packFolder", table.concat(segments, "\\", 1, 3)))
                end
            end
        end

        -- Whole folder as the pack, unless it named the author.
        if not isGeneric(folder) and folderIndex ~= authorSegment then
            pack = best(pack, value(folder, 50, "packFolder", folderSource))
        end
    end

    if listSource then
        pack = best(pack, value(listSource.list, 45, "listName", listSource.list .. ".txt"))
    end

    return author, pack
end

---@param path string Depot path, any case or separator.
---@return AssetAttribution
function assetAttribution.resolve(path)
    if not prefixIndex then
        assetAttribution.rebuildIndex()
    end

    local normalized = path:lower():gsub("/", "\\")
    local author, pack = resolveCandidates(normalized)

    local packAuthor = pack and packAuthors[pack.name]
    if packAuthor and (not author or author.score < 60) then
        author = authorValue(packAuthor.names or { packAuthor.name }, 60, "packMatch", pack.name)
    end

    return { author = author, pack = pack }
end

---@param attribution AssetAttributionValue?
---@return "reliable"|"likely"|"guess"|"unknown"
function assetAttribution.getConfidence(attribution)
    if not attribution then return "unknown" end
    if attribution.score >= assetAttribution.reliableScore then return "reliable" end
    if attribution.score >= assetAttribution.likelyScore then return "likely" end
    return "guess"
end

return assetAttribution
