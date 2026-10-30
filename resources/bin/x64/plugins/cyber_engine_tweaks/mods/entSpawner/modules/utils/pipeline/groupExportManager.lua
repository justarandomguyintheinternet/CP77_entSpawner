local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local Cron = require("modules/utils/vendor/Cron")
local pipelineCommon = require("modules/utils/pipeline/common")
local groupExportSidecar = require("modules/utils/pipeline/groupExportSidecar")
local bendedCollisionExport = require("modules/utils/pipeline/bendedCollisionExport")
local nodeStreaming = require("modules/utils/data/nodeStreaming")
local logger = require("modules/utils/core/logger")

local groupExportManager = {}
local EXPORT_ERROR_LOG_PATH = "data/export_errors.log"

local function createExportRuntime(previous)
    local buildChunkSize = previous and previous.buildChunkSize or 220
    local buildTimeBudgetMs = previous and previous.buildTimeBudgetMs or 6
    local exportChunkSize = previous and previous.exportChunkSize or 90
    local exportTimeBudgetMs = previous and previous.exportTimeBudgetMs or 6

    return {
        active = false,
        paused = false,
        phase = "idle", -- idle|build|export|finalize
        timer = nil,
        resumeAction = nil,
        pauseReason = nil,
        groups = {},
        totalGroups = 0,
        groupIndex = 1,
        completedGroups = 0,
        current = nil,
        project = nil,
        projectPath = nil,
        sidecarPath = nil,
        state = nil,
        mode = "full", -- full|incremental
        incremental = nil,
        groupContributions = {},
        incrementalStats = {
            changed = 0,
            unchanged = 0,
            removed = 0
        },
        disabledNodeCount = 0,
        request = nil,
        buildChunkSize = buildChunkSize,
        buildTimeBudgetMs = buildTimeBudgetMs,
        exportChunkSize = exportChunkSize,
        exportTimeBudgetMs = exportTimeBudgetMs
    }
end

groupExportManager.state = createExportRuntime()
groupExportManager.pendingToasts = {}

local function appendExportErrorLog(line)
    local file, openErr = io.open(EXPORT_ERROR_LOG_PATH, "a")
    if not file then
        logger:error(string.format("[Group Export Manager] Failed to open export log \"%s\": %s", EXPORT_ERROR_LOG_PATH, tostring(openErr)))
        return
    end

    local ok, writeErr = pcall(function ()
        file:write(line .. "\n")
    end)
    file:close()

    if not ok then
        logger:error(string.format("[Group Export Manager] Failed to write export log \"%s\": %s", EXPORT_ERROR_LOG_PATH, tostring(writeErr)))
    end
end

local function getRuntimeNames(runtime)
    local projectName = runtime and runtime.project and runtime.project.name or "unknown_project"
    local groupName = runtime and runtime.current and runtime.current.name
    if not groupName and runtime and runtime.groups and runtime.groupIndex then
        local listed = runtime.groups[runtime.groupIndex]
        groupName = listed and listed.name or nil
    end

    return projectName, groupName or "unknown_group"
end

local function logExportError(runtime, phase, message)
    local projectName, groupName = getRuntimeNames(runtime)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] phase=%s project=%s group=%s error=%s", timestamp or "unknown_time", tostring(phase), tostring(projectName), tostring(groupName), tostring(message))

    logger:error("[Group Export Manager] " .. line)
    appendExportErrorLog(line)
end

local function queueToast(kind, duration, text)
    local ok, err = pcall(function ()
        pipelineCommon.queueToast(groupExportManager.pendingToasts, kind, duration, text)
    end)
    if not ok then
        logger:warn(string.format("[Group Export Manager] Failed to queue toast: %s", tostring(err)))
    end
end

local function haltRuntimeTimer(runtime)
    if runtime and runtime.timer then
        Cron.Halt(runtime.timer)
        runtime.timer = nil
    end
end

local function hasBlockingIssues(runtime)
    local check = runtime and runtime.request and runtime.request.hasBlockingIssues
    if check then
        return check() == true
    end

    return false
end

local function pauseExport(runtime, reason, onResume)
    if not runtime or not runtime.active then
        return false
    end

    haltRuntimeTimer(runtime)
    runtime.paused = true
    runtime.resumeAction = onResume
    runtime.pauseReason = reason or "Resolve the export issue popup to continue."
    return true
end

local clearCurrentGroup

local function abortExport(runtime, phase, message)
    logExportError(runtime, phase, message)
    haltRuntimeTimer(runtime)
    clearCurrentGroup(runtime)

    if groupExportManager.state == runtime then
        groupExportManager.state = createExportRuntime(runtime)
    end

    queueToast("error", 7000, string.format("Export failed (%s): %s", tostring(phase), tostring(message)))
end

clearCurrentGroup = function (runtime)
    if not runtime then
        return
    end

    if runtime.current then
        runtime.current.root = nil
        runtime.current.nodes = nil
        runtime.current.nodeRefMap = nil
        runtime.current.spawnables = nil
        runtime.current.buildQueue = nil
        runtime.current = nil
    end
end

local function addChildFast(parent, child)
    if not parent or not child then
        return
    end

    child.parent = parent
    parent.childs = parent.childs or {}
    table.insert(parent.childs, child)
end

local function queueBuildEntry(current, data, parent)
    current.buildTail = current.buildTail + 1
    current.buildQueue[current.buildTail] = { data = data, parent = parent }
    current.buildTotal = current.buildTotal + 1
end

local function registerGroupContribution(runtime, group, contribution)
    if not runtime or not group then
        return
    end

    -- Keyed by the project file, not the display name: two export entries may show the same name,
    -- and a renamed group would otherwise lose the entry it was exported under.
    local key = groupExportSidecar.resolveGroupFileName(group)
    if key == ".json" then
        -- Neither a file nor a name to fall back on: nothing a later export could match this by.
        return
    end

    runtime.groupContributions[key] = {
        signature = group.signature or "",
        sectorName = contribution and contribution.sectorName or "",
        deviceHashes = utils.deepcopy(contribution and contribution.deviceHashes or {}),
        psEntryIds = utils.deepcopy(contribution and contribution.psEntryIds or {}),
        childs = utils.deepcopy(contribution and contribution.childs or {}),
        communities = utils.deepcopy(contribution and contribution.communities or {}),
        spotNodes = utils.deepcopy(contribution and contribution.spotNodes or {}),
        nodeRefs = utils.deepcopy(contribution and contribution.nodeRefs or {})
    }
end

---Node classes a community spawnable can export as, decided by its area type.
local COMMUNITY_AREA_NODE_TYPES = {
    ["worldCompiledCommunityAreaNode"] = true,
    ["worldCompiledCommunityAreaNode_Streamable"] = true
}

local function appendCommunityState(target, communities, sector)
    local sectorCommunities = {}
    local sectorCommunitiesByRef = {}

    for _, node in ipairs(sector and sector.nodes or {}) do
        if node and COMMUNITY_AREA_NODE_TYPES[node.type] then
            table.insert(sectorCommunities, node)

            local nodeRef = tostring(node.nodeRef or "")
            if nodeRef ~= "" then
                sectorCommunitiesByRef[nodeRef] = node
            end
        end
    end

    for index, community in ipairs(communities or {}) do
        local stateCommunity = utils.deepcopy(community)
        local sourceNode = community and community.node
        local canonicalNode = nil

        -- Fresh exports still share this exact table with the sector. Incremental
        -- exports restore the sector and sidecar independently, so fall back to
        -- the stable NodeRef (or relative community order for invalid empty refs).
        for _, node in ipairs(sectorCommunities) do
            if node == sourceNode then
                canonicalNode = node
                break
            end
        end

        if not canonicalNode and sourceNode then
            local nodeRef = tostring(sourceNode.nodeRef or "")
            if nodeRef ~= "" then
                canonicalNode = sectorCommunitiesByRef[nodeRef]
            end
        end

        -- The positional fallback only holds while every community of the group is still in its
        -- own sector. An always loaded hosted one was moved out by the previous export, so matching
        -- it by index would bind it to an unrelated community's node.
        if not canonicalNode and not community.hostedInAlwaysLoaded then
            canonicalNode = sectorCommunities[index]
        end
        if canonicalNode then
            stateCommunity.node = canonicalNode
        end

        table.insert(target, stateCommunity)
    end
end

---Move the area nodes of `Regular` communities out of their own sector and into the always loaded
---one, which is where every shipped `Regular` community keeps its node. A node that is not found
---is one a previous export already moved, restored from the sidecar, so it is only added.
---@param project table
---@param communities table
---@param alwaysLoaded table
local function hostAlwaysLoadedCommunities(project, communities, alwaysLoaded)
    if type(alwaysLoaded) ~= "table" or type(alwaysLoaded.nodes) ~= "table" then
        return
    end

    for _, community in ipairs(communities or {}) do
        local node = community.hostedInAlwaysLoaded and community.node or nil

        if type(node) == "table" then
            for _, sector in ipairs(project.sectors or {}) do
                for index, sectorNode in ipairs(sector.nodes or {}) do
                    if sectorNode == node then
                        table.remove(sector.nodes, index)
                        break
                    end
                end
            end

            table.insert(alwaysLoaded.nodes, node)
        end
    end
end

---Numbers the top-level handles of every node, unique within its sector. WolvenKit 10 templates
---pre-create some handles (filterData, Settings) with HandleId "0", which the import script's merge
---keeps unless the export sets one, and "0" resolves to the sector's first node.
---@param sectors table[]
local function assignHandleIds(sectors)
    for _, sector in ipairs(sectors or {}) do
        local nextId = 1000000

        for _, node in ipairs(sector.nodes or {}) do
            local keys = {}
            for key, value in pairs(type(node.data) == "table" and node.data or {}) do
                if type(value) == "table" and type(value.Data) == "table" and value.Data["$type"] then
                    table.insert(keys, key)
                end
            end
            table.sort(keys)

            for _, key in ipairs(keys) do
                node.data[key].HandleId = tostring(nextId)
                nextId = nextId + 1
            end
        end
    end
end

local function mergeGroupExportData(runtime, group, data, devices, psEntries, subChilds, communities, spots, duplicateNodes)
    local project = runtime.project
    local state = runtime.state

    table.insert(project.sectors, data)

    for hash, device in pairs(devices) do
        project.devices[hash] = device
    end

    for psid, entry in pairs(psEntries) do
        project.psEntries[psid] = entry
    end

    appendCommunityState(state.communities, communities, data)
    utils.combine(state.spotNodes, utils.deepcopy(spots or {}))
    utils.combine(state.childs, utils.deepcopy(subChilds or {}))

    if runtime.request and runtime.request.collectDuplicateNodeRefs then
        runtime.request.collectDuplicateNodeRefs(state.nodeRefs, duplicateNodes or data.nodes or {})
    end

    registerGroupContribution(runtime, group, groupExportSidecar.buildContribution(data, devices, psEntries, subChilds, communities, spots))
end

local function buildSubsetMap(source, keys)
    local result = {}
    if type(source) ~= "table" then
        return result
    end

    for _, key in ipairs(keys or {}) do
        local normalizedKey = tostring(key)
        if source[normalizedKey] ~= nil then
            result[normalizedKey] = utils.deepcopy(source[normalizedKey])
        end
    end

    return result
end

local function mapSectorsByName(sectors)
    local result = {}

    for _, sector in ipairs(sectors or {}) do
        if sector and sector.name and sector.name ~= "" then
            result[sector.name] = sector
        end
    end

    return result
end

local function validateSidecarDocument(meta, runtime)
    if type(meta) ~= "table" then
        return false, "metadata is invalid"
    end

    if tonumber(meta.schemaVersion) ~= groupExportSidecar.SCHEMA_VERSION then
        return false, string.format("unsupported sidecar schema (expected %d)", groupExportSidecar.SCHEMA_VERSION)
    end

    if tostring(meta.projectName or "") ~= tostring(runtime.project.name or "") then
        return false, "project mismatch"
    end

    if tostring(meta.version or "") ~= tostring(runtime.project.version or "") then
        return false, "version mismatch"
    end

    if type(meta.groups) ~= "table" then
        return false, "group metadata is missing"
    end

    return true
end

local function isReusableGroupEntry(entry, sectorsByName, existingProject)
    if type(entry) ~= "table" then
        return false
    end

    if type(entry.sectorName) ~= "string" or entry.sectorName == "" then
        return false
    end

    if not sectorsByName[entry.sectorName] then
        return false
    end

    if type(entry.deviceHashes) ~= "table" or type(entry.psEntryIds) ~= "table" then
        return false
    end

    if type(entry.childs) ~= "table" or type(entry.communities) ~= "table" or type(entry.spotNodes) ~= "table" or type(entry.nodeRefs) ~= "table" then
        return false
    end

    local existingDevices = existingProject and existingProject.devices or {}
    for _, hash in ipairs(entry.deviceHashes or {}) do
        if existingDevices[tostring(hash)] == nil then
            return false
        end
    end

    local existingPsEntries = existingProject and existingProject.psEntries or {}
    for _, psid in ipairs(entry.psEntryIds or {}) do
        if existingPsEntries[tostring(psid)] == nil then
            return false
        end
    end

    return true
end

local function prepareIncrementalRuntime(runtime)
    local exportPath = runtime.projectPath
    local sidecarPath = runtime.sidecarPath

    if not config.fileExists(exportPath) then
        return false, "base export file not found"
    end

    if not config.fileExists(sidecarPath) then
        return false, "sidecar metadata file not found"
    end

    local existingProject = config.loadFile(exportPath)
    if type(existingProject) ~= "table" or tostring(existingProject.name or "") ~= tostring(runtime.project.name) then
        return false, "base export file is invalid or mismatched"
    end
    if tostring(existingProject.version or "") ~= tostring(runtime.project.version or "") then
        return false, "base export version mismatch"
    end

    local meta = config.loadFile(sidecarPath)
    local validMeta, metaErr = validateSidecarDocument(meta, runtime)
    if not validMeta then
        return false, metaErr
    end

    local sectorsByName = mapSectorsByName(existingProject.sectors)
    local knownFiles = {}
    local changed = 0
    local unchanged = 0

    for _, group in ipairs(runtime.groups) do
        local key = groupExportSidecar.resolveGroupFileName(group)
        knownFiles[key] = true
        local sidecarGroup = meta.groups[key]
        local matchesSignature = sidecarGroup and sidecarGroup.signature == group.signature

        if matchesSignature and isReusableGroupEntry(sidecarGroup, sectorsByName, existingProject) then
            group.incrementalReuse = true
            group.sidecarEntry = sidecarGroup
            group.cachedSector = sectorsByName[sidecarGroup.sectorName]
            unchanged = unchanged + 1
        else
            group.incrementalReuse = false
            group.sidecarEntry = nil
            group.cachedSector = nil
            changed = changed + 1
        end
    end

    local removed = 0
    for previousFile, _ in pairs(meta.groups or {}) do
        if not knownFiles[previousFile] then
            removed = removed + 1
        end
    end

    runtime.incremental = {
        existingProject = existingProject
    }

    runtime.incrementalStats.changed = changed
    runtime.incrementalStats.unchanged = unchanged
    runtime.incrementalStats.removed = removed

    return true
end

local function mergeReusedGroupExportData(runtime, group)
    local existingProject = runtime.incremental and runtime.incremental.existingProject
    local entry = group and group.sidecarEntry
    local sector = group and group.cachedSector
    if not existingProject or not entry or not sector then
        return false, "reused group data is missing"
    end

    local devices = buildSubsetMap(existingProject.devices, entry.deviceHashes)
    local psEntries = buildSubsetMap(existingProject.psEntries, entry.psEntryIds)
    local childs = utils.deepcopy(entry.childs or {})
    local communities = utils.deepcopy(entry.communities or {})
    local spots = utils.deepcopy(entry.spotNodes or {})
    local duplicateNodes = utils.deepcopy(entry.nodeRefs or {})

    mergeGroupExportData(
        runtime,
        group,
        utils.deepcopy(sector),
        devices,
        psEntries,
        childs,
        communities,
        spots,
        duplicateNodes
    )

    return true
end

local function buildSidecarDocument(runtime)
    local sidecarDocument = groupExportSidecar.createDocument(
        runtime.project.name,
        runtime.project.version
    )

    for _, group in ipairs(runtime.groups or {}) do
        local key = groupExportSidecar.resolveGroupFileName(group)
        local contribution = runtime.groupContributions[key]
        if contribution then
            sidecarDocument.groups[key] = utils.deepcopy(contribution)
        end
    end

    return sidecarDocument
end

local function finalizeDeviceParents(project, childs)
    for hash, device in pairs(project.devices) do
        for _, childHash in pairs(device.children) do
            local child = project.devices[childHash]
            if child then
                -- A reused group brings its devices back from the previous export, where this pass
                -- already ran and left `parents` filled in. Without the guard every incremental
                -- export would append the same parent to them again.
                local known = false
                for _, existing in pairs(child.parents) do
                    if existing == hash then
                        known = true
                        break
                    end
                end

                if not known then
                    table.insert(child.parents, hash)
                end
            end
        end
    end

    -- TODO: Aggregate all parents of double entries, so a device that isnt a device can be linked to multiple parents
    local additionalEntries = {}
    for _, child in pairs(childs) do
        local hash = utils.nodeRefStringToHashString(child.ref)
        if not additionalEntries[hash] then
            additionalEntries[hash] = {
                hash = hash,
                className = child.className,
                nodePosition = child.nodePosition,
                parents = { child.parent },
                children = {}
            }
        else
            table.insert(additionalEntries[hash].parents, child.parent)
        end
    end

    for _, child in pairs(additionalEntries) do
        project.devices[child.hash] = child
    end
end

local function getTopRootChild(root, element)
    if not root or not element then
        return nil
    end

    local current = element
    while current and current.parent and current.parent ~= root do
        current = current.parent
    end

    if current and current.parent == root then
        return current
    end

    return nil
end

local function shouldExportNode(runtime, node)
    local check = runtime and runtime.request and runtime.request.shouldExportNode
    if check then
        return check(node)
    end

    return true
end

local function isExportDisabled(runtime, node)
    local check = runtime and runtime.request and runtime.request.isExportDisabled
    return check and check(node) or false
end

local function prepareCurrentGroupForExport(runtime)
    local current = runtime.current
    if not current or not current.root then
        return
    end

    local group = current.group
    local root = current.root
    local center = root:getPosition()
    local sectorCategory = runtime.request.sectorCategory

    current.exported = {
        name = utils.createFileName(group.name):lower():gsub(" ", "_"),
        min = {
            x = center.x - group.streamingX,
            y = center.y - group.streamingY,
            z = center.z - group.streamingZ
        },
        max = {
            x = center.x + group.streamingX,
            y = center.y + group.streamingY,
            z = center.z + group.streamingZ
        },
        category = sectorCategory[group.category + 1],
        level = group.level,
        nodes = {},
        prefabRef = group.prefabRef,
        variantIndices = { 0 },
        variants = {}
    }

    current.devices = {}
    current.psEntries = {}
    current.childs = {}
    current.communities = {}
    current.spotNodes = {}

    local variantNodes = {
        default = {}
    }
    local variantInfo = {}
    local variantOrder = {}
    local variantSeen = {}

    for _, variant in pairs(group.variantData or {}) do
        local variantName, isDefaultVariant = pipelineCommon.normalizeVariantName(variant.name)
        if not variantNodes[variantName] then
            variantNodes[variantName] = {}
        end
        if not variantInfo[variantName] then
            variantInfo[variantName] = {
                defaultOn = variant and variant.defaultOn
            }
        end
        if not isDefaultVariant and not variantSeen[variantName] then
            variantSeen[variantName] = true
            table.insert(variantOrder, variantName)
        end
    end

    for _, node in ipairs(current.spawnables) do
        if utils.isA(node, "spawnableElement") and not node.spawnable.noExport and isExportDisabled(runtime, node) then
            runtime.disabledNodeCount = runtime.disabledNodeCount + 1
        elseif utils.isA(node, "spawnableElement") and not node.spawnable.noExport and shouldExportNode(runtime, node) then
            if node.parent == root then
                table.insert(variantNodes.default, { ref = node })
            else
                local top = getTopRootChild(root, node)
                local variant = top and group.variantData and group.variantData[top.name]
                if variant then
                    local variantName = pipelineCommon.normalizeVariantName(variant and variant.name)
                    if not variantNodes[variantName] then
                        variantNodes[variantName] = {}
                    end
                    table.insert(variantNodes[variantName], { ref = node })
                end
            end
        end
    end

    current.nodes = variantNodes.default

    local index = 1
    for _, variantName in ipairs(variantOrder) do
        local variantList = variantNodes[variantName] or {}
        table.insert(current.exported.variantIndices, #current.nodes)
        utils.combine(current.nodes, variantList)

        table.insert(current.exported.variants, {
            name = variantName,
            index = index,
            defaultOn = variantInfo[variantName] and variantInfo[variantName].defaultOn and 1 or 0,
            ref = group.variantRef
        })
        index = index + 1
    end

    current.nodeRefMap = {}
    for _, object in ipairs(current.nodes) do
        if utils.isA(object.ref, "spawnableElement") and object.ref.spawnable and object.ref.spawnable.nodeRef and object.ref.spawnable.nodeRef ~= "" then
            current.nodeRefMap[object.ref.spawnable.nodeRef] = object
        end
    end

    -- Bended collision: one node per parent group, emitted after the group's last bended mesh.
    current.collisionLast = {}
    current.collisionSources = {}
    -- Key of the node each extra exported node (split piece, collision) follows.
    current.inserted = {}
    for index, object in ipairs(current.nodes) do
        local spawnable = object.ref.spawnable
        if spawnable and spawnable.exportCollision and spawnable.getExportCollision then
            current.collisionLast[object.ref.parent or root] = index
        end
    end

    current.totalNodes = #current.nodes
    current.nodeIndex = 1
end

---Gathers a bended mesh's collision; after its group's last bended mesh, appends the group's collision nodes.
---@param current table
---@param element table
---@param key integer Index of the element in `current.nodes`.
local function exportBendedCollision(current, element, key)
    local parent = element.parent or current.root
    local last = current.collisionLast[parent]
    if not last then return end

    local source = bendedCollisionExport.collect(element)
    if source then
        current.collisionSources[parent] = current.collisionSources[parent] or {}
        table.insert(current.collisionSources[parent], source)
    end

    if key ~= last then return end

    local sources = current.collisionSources[parent]
    current.collisionSources[parent] = nil
    if not sources then return end

    for _, node in ipairs(bendedCollisionExport.buildNodes(parent.name or current.exported.name, sources)) do
        table.insert(current.exported.nodes, node)
        table.insert(current.inserted, key)
    end
end

---Variant ranges start later by the extra nodes inserted before them.
---@param current table
local function shiftVariantIndices(current)
    if not current.inserted or #current.inserted == 0 then return end

    local indices = current.exported.variantIndices
    for i = 2, #indices do
        local start = indices[i]
        local shift = 0
        for _, key in ipairs(current.inserted) do
            if key <= start then
                shift = shift + 1
            end
        end
        indices[i] = start + shift
    end
end

local beginNextGroup

local function scheduleNextGroup(runtime)
    Cron.NextTick(function ()
        if groupExportManager.state == runtime and runtime.active then
            beginNextGroup(runtime)
        end
    end)
end

local function advanceGroup(runtime, clearCurrent)
    if clearCurrent ~= false then
        clearCurrentGroup(runtime)
    end

    runtime.groupIndex = runtime.groupIndex + 1
    runtime.completedGroups = runtime.completedGroups + 1
    scheduleNextGroup(runtime)
end

local function finalizeExportRuntime(runtime)
    runtime.phase = "finalize"
    haltRuntimeTimer(runtime)
    clearCurrentGroup(runtime)

    local toastKind = nil
    local toastDuration = 3500
    local toastMessage = nil

    local ok, err = pcall(function ()
        if not runtime.finalizePrepared then
            finalizeDeviceParents(runtime.project, runtime.state.childs)

            if runtime.request and runtime.request.collectMissingSplineNodeRefs then
                for _, sector in ipairs(runtime.project.sectors or {}) do
                    runtime.request.collectMissingSplineNodeRefs(sector.nodes or {})
                end
            end

            -- Sector-wide, unlike the checks above: a patrol spline and the workspots it drives
            -- are referenced by NodeRef, so they routinely sit in different groups and land in
            -- different sectors. The check gets the whole project to resolve those refs.
            if runtime.request and runtime.request.collectInfinitePatrolWorkspots then
                runtime.request.collectInfinitePatrolWorkspots(runtime.project.sectors or {})
            end

            local alwaysLoaded = nil
            if runtime.request and runtime.request.handleCommunities then
                alwaysLoaded = runtime.request.handleCommunities(runtime.project.name, runtime.state.communities, runtime.state.spotNodes, runtime.state.nodeRefs)
            end

            if alwaysLoaded then
                -- Before the sector joins the project, so the move never has to skip it.
                hostAlwaysLoadedCommunities(runtime.project, runtime.state.communities, alwaysLoaded)
                table.insert(runtime.project.sectors, alwaysLoaded)
            end

            -- Last, once every node sits in its final sector: the flags depend on the sector category.
            nodeStreaming.applyToSectors(runtime.project.sectors)
            assignHandleIds(runtime.project.sectors)

            runtime.finalizePrepared = true
        end

        if hasBlockingIssues(runtime) then
            pauseExport(runtime, "Resolve the export issue popup to continue.", function ()
                finalizeExportRuntime(runtime)
            end)
            return
        end

        local saved, saveErr = config.saveFile(runtime.projectPath, runtime.project)
        if saved then
            local sidecarSaved, sidecarErr = config.saveFile(runtime.sidecarPath, buildSidecarDocument(runtime))
            if not sidecarSaved then
                logExportError(runtime, "finalize_sidecar", string.format("Failed to save sidecar \"%s\": %s", tostring(runtime.sidecarPath), tostring(sidecarErr)))
                queueToast("warning", 5000, "Export succeeded but metadata sidecar could not be saved")
            end

            -- Written after the sector, so a failure here never costs the export itself.
            if runtime.request and runtime.request.writeInteractionTweak then
                local tweakOk, tweakPath = pcall(runtime.request.writeInteractionTweak, runtime.project.name)
                if tweakOk and tweakPath then
                    queueToast("info", 6000, string.format("Wrote %s -- copy it into r6/tweaks/", tostring(tweakPath)))
                    logger:info("[Group Export Manager] Wrote interaction records to " .. tostring(tweakPath))
                elseif not tweakOk then
                    logExportError(runtime, "finalize_tweak", "Failed to write the interaction records file")
                    queueToast("warning", 5000, "Export succeeded but the interaction records file could not be written")
                end
            end

            local projectLabel = runtime.request and runtime.request.projectName or runtime.project.name
            toastKind = "success"
            toastDuration = 2500
            toastMessage = string.format("Exported \"%s\"", projectLabel)
            if runtime.disabledNodeCount > 0 then
                toastMessage = toastMessage .. string.format(" (%d disabled node%s excluded)", runtime.disabledNodeCount, runtime.disabledNodeCount == 1 and "" or "s")
            end
            logger:info("[Group Export Manager] " .. toastMessage)
        else
            toastKind = "error"
            toastDuration = 7000
            toastMessage = string.format("Export failed: %s", tostring(saveErr or "unknown_error"))
            logExportError(runtime, "finalize_save", toastMessage)
            logger:error("[Group Export Manager] " .. toastMessage)
        end
    end)

    if not ok then
        toastKind = "error"
        toastDuration = 7000
        toastMessage = string.format("Export failed: %s", tostring(err))
        logExportError(runtime, "finalize_exception", toastMessage)
        logger:error("[Group Export Manager] " .. toastMessage)
    end

    if runtime.paused then
        return
    end

    if groupExportManager.state == runtime then
        groupExportManager.state = createExportRuntime(runtime)
    end

    if toastKind and toastMessage then
        queueToast(toastKind, toastDuration, toastMessage)
    end
end

beginNextGroup = function (runtime)
    if not runtime.active then
        return
    end

    if runtime.groupIndex > runtime.totalGroups then
        if runtime.completedGroups < runtime.totalGroups then
            runtime.completedGroups = runtime.totalGroups
        end
        finalizeExportRuntime(runtime)
        return
    end

    local group = runtime.groups[runtime.groupIndex]
    if not group then
        advanceGroup(runtime, false)
        return
    end

    if group.incrementalReuse then
        local merged, mergeErr = pcall(function ()
            local okReuse, reason = mergeReusedGroupExportData(runtime, group)
            if not okReuse then
                error(reason or "unknown incremental reuse error")
            end
        end)

        if not merged then
            abortExport(runtime, "reuse_group", string.format("Failed reusing group \"%s\": %s", tostring(group.name), tostring(mergeErr)))
            return
        end

        if hasBlockingIssues(runtime) then
            pauseExport(runtime, "Resolve the export issue popup to continue.", function ()
                advanceGroup(runtime, false)
            end)
            return
        end

        advanceGroup(runtime, false)
        return
    end

    -- The project file, not the group's name: since the two were split, a renamed group would
    -- otherwise look like a missing project and be skipped.
    local path = "data/objects/" .. groupExportSidecar.resolveGroupFileName(group)
    if not config.fileExists(path) then
        queueToast("warning", 3500, string.format("Skipped missing group \"%s\"", tostring(group.name)))
        advanceGroup(runtime, false)
        return
    end

    local blob = config.loadFile(path)
    if type(blob) ~= "table" or next(blob) == nil then
        abortExport(runtime, "prepare_group", string.format("Group file is invalid or empty for \"%s\"", tostring(group.name)))
        return
    end

    runtime.current = {
        group = group,
        name = group.name,
        buildQueue = {},
        buildHead = 1,
        buildTail = 0,
        buildTotal = 0,
        buildProcessed = 0,
        spawnables = {}
    }

    local ok, err = pcall(function ()
        local root = require("modules/classes/editor/positionableGroup"):new(runtime.request.spawner.baseUI.spawnedUI)
        root:load(pipelineCommon.copyNodeDataWithoutChildren(blob), true)
        runtime.current.root = root

        for _, child in pairs(blob.childs or {}) do
            queueBuildEntry(runtime.current, child, root)
        end
    end)

    if not ok then
        abortExport(runtime, "prepare_group", string.format("Failed preparing group \"%s\": %s", tostring(group.name), tostring(err)))
        return
    end

    runtime.phase = "build"
    runtime.timer = Cron.OnUpdate(function (timer)
        if groupExportManager.state ~= runtime or not runtime.active or runtime.phase ~= "build" or not runtime.current then
            timer:Halt()
            return
        end

        local current = runtime.current
        local processed = 0
        local startedAt = pipelineCommon.nowMs()
        local maxPerTick = math.max(1, runtime.buildChunkSize or 1)
        local budgetMs = math.max(0.1, runtime.buildTimeBudgetMs or 1)

        while processed < maxPerTick and current.buildHead <= current.buildTail do
            local entry = current.buildQueue[current.buildHead]
            current.buildQueue[current.buildHead] = nil
            current.buildHead = current.buildHead + 1

            local okBuild, buildErr = pcall(function ()
                local modulePath = entry.data.modulePath or entry.parent:getModulePathByType(entry.data)
                local new = require(modulePath):new(runtime.request.spawner.baseUI.spawnedUI)
                new:load(pipelineCommon.copyNodeDataWithoutChildren(entry.data), true)
                addChildFast(entry.parent, new)

                if utils.isA(new, "spawnableElement") then
                    table.insert(current.spawnables, new)
                end

                for _, child in pairs(entry.data.childs or {}) do
                    queueBuildEntry(current, child, new)
                end
            end)

            current.buildProcessed = current.buildProcessed + 1
            if not okBuild then
                timer:Halt()
                runtime.timer = nil
                local nodeName = entry and entry.data and entry.data.name or "Unknown"
                abortExport(runtime, "build_node", string.format("Build failed in group \"%s\" on node \"%s\": %s", tostring(current.name), tostring(nodeName), tostring(buildErr)))
                return
            end

            processed = processed + 1
            if (pipelineCommon.nowMs() - startedAt) >= budgetMs then
                break
            end
        end

        if current.buildHead > current.buildTail then
            timer:Halt()
            runtime.timer = nil

            local okPrepare, prepareErr = pcall(function ()
                prepareCurrentGroupForExport(runtime)
            end)
            if not okPrepare then
                abortExport(runtime, "prepare_export", string.format("Failed preparing export for group \"%s\": %s", tostring(current.name), tostring(prepareErr)))
                return
            end

            runtime.phase = "export"

            if (runtime.current.totalNodes or 0) == 0 then
                mergeGroupExportData(runtime, runtime.current.group, runtime.current.exported, runtime.current.devices, runtime.current.psEntries, runtime.current.childs, runtime.current.communities, runtime.current.spotNodes)
                if hasBlockingIssues(runtime) then
                    pauseExport(runtime, "Resolve the export issue popup to continue.", function ()
                        clearCurrentGroup(runtime)
                        advanceGroup(runtime, false)
                    end)
                    return
                end
                clearCurrentGroup(runtime)
                advanceGroup(runtime, false)
                return
            end

            local exportTick
            exportTick = function (exportTimer)
                if groupExportManager.state ~= runtime or not runtime.active or runtime.phase ~= "export" or not runtime.current then
                    exportTimer:Halt()
                    return
                end

                local exportCurrent = runtime.current
                local exportProcessed = 0
                local exportStartedAt = pipelineCommon.nowMs()
                local exportMaxPerTick = math.max(1, runtime.exportChunkSize or 1)
                local exportBudgetMs = math.max(0.1, runtime.exportTimeBudgetMs or 1)

                while exportProcessed < exportMaxPerTick and exportCurrent.nodeIndex <= exportCurrent.totalNodes do
                    local key = exportCurrent.nodeIndex
                    local object = exportCurrent.nodes[key]

                    local okExport, exportErr = pcall(function ()
                        if object and utils.isA(object.ref, "spawnableElement") and not object.ref.spawnable.noExport and shouldExportNode(runtime, object.ref) then
                            for index, node in ipairs(object.ref.spawnable:exportNodes(key, exportCurrent.totalNodes)) do
                                table.insert(exportCurrent.exported.nodes, node)
                                if index > 1 then
                                    table.insert(exportCurrent.inserted, key)
                                end
                            end

                            if object.ref.spawnable.exportCollision and object.ref.spawnable.getExportCollision then
                                exportBendedCollision(exportCurrent, object.ref, key)
                            end

                            if object.ref.spawnable.node == "worldDeviceNode" then
                                runtime.request.handleDevice(object, exportCurrent.devices, exportCurrent.psEntries, exportCurrent.childs, exportCurrent.nodeRefMap)
                            elseif COMMUNITY_AREA_NODE_TYPES[object.ref.spawnable.node] then
                                table.insert(exportCurrent.communities, {
                                    data = object.ref.spawnable.entries,
                                    node = exportCurrent.exported.nodes[#exportCurrent.exported.nodes],
                                    areaType = object.ref.spawnable:getAreaType(),
                                    hostedInAlwaysLoaded = object.ref.spawnable:isAlwaysLoadedHosted()
                                })
                            elseif object.ref.spawnable.node == "worldAISpotNode" then
                                table.insert(exportCurrent.spotNodes, {
                                    ref = object.ref.spawnable.nodeRef,
                                    position = utils.fromVector(object.ref:getPosition()),
                                    yaw = object.ref.spawnable.rotation.yaw,
                                    markings = object.ref.spawnable.markings,
                                    name = object.ref.name
                                })
                            end
                        end
                    end)

                    if not okExport then
                        exportTimer:Halt()
                        runtime.timer = nil
                        local nodeName = object and object.ref and object.ref.name or tostring(key)
                        abortExport(runtime, "export_node", string.format("Export failed in group \"%s\" on node \"%s\": %s", tostring(exportCurrent.name), tostring(nodeName), tostring(exportErr)))
                        return
                    end

                    exportCurrent.nodeIndex = exportCurrent.nodeIndex + 1
                    exportProcessed = exportProcessed + 1

                    if hasBlockingIssues(runtime) then
                        pauseExport(runtime, "Resolve the export issue popup to continue.", function ()
                            runtime.phase = "export"
                            runtime.timer = Cron.OnUpdate(exportTick)
                        end)
                        return
                    end

                    if (pipelineCommon.nowMs() - exportStartedAt) >= exportBudgetMs then
                        break
                    end
                end

                if exportCurrent.nodeIndex > exportCurrent.totalNodes then
                    exportTimer:Halt()
                    runtime.timer = nil

                    shiftVariantIndices(exportCurrent)
                    mergeGroupExportData(runtime, exportCurrent.group, exportCurrent.exported, exportCurrent.devices, exportCurrent.psEntries, exportCurrent.childs, exportCurrent.communities, exportCurrent.spotNodes)
                    if hasBlockingIssues(runtime) then
                        pauseExport(runtime, "Resolve the export issue popup to continue.", function ()
                            clearCurrentGroup(runtime)
                            advanceGroup(runtime, false)
                        end)
                        return
                    end
                    clearCurrentGroup(runtime)
                    advanceGroup(runtime, false)
                end
            end

            runtime.timer = Cron.OnUpdate(exportTick)
        end
    end)
end

function groupExportManager.start(request)
    if groupExportManager.state.active then return false end
    if not request or not request.spawner or not request.projectName or request.projectName == "" then return false end
    if not request.groups or not request.sectorCategory or not request.version then return false end
    if not request.handleDevice or not request.handleCommunities then return false end

    local runtime = createExportRuntime(groupExportManager.state)
    local requestedMode = request.mode == "incremental" and "incremental" or "full"
    utils.resetExportBufferIds()
    runtime.active = true
    runtime.phase = "build"
    runtime.mode = requestedMode
    runtime.groups = {}
    runtime.totalGroups = 0
    runtime.groupIndex = 1
    runtime.completedGroups = 0
    runtime.groupContributions = {}
    runtime.project = {
        name = utils.createFileName(request.projectName):lower():gsub(" ", "_"),
        xlFormat = request.xlFormat,
        sectors = {},
        devices = {},
        psEntries = {},
        version = request.version
    }
    runtime.projectPath = groupExportSidecar.getExportPath(runtime.project.name)
    runtime.sidecarPath = groupExportSidecar.getSidecarPath(runtime.project.name)
    runtime.state = {
        nodeRefs = {},
        spotNodes = {},
        communities = {},
        childs = {}
    }
    runtime.request = {
        projectName = request.projectName,
        sectorCategory = request.sectorCategory,
        spawner = request.spawner,
        shouldExportNode = request.shouldExportNode,
        handleDevice = request.handleDevice,
        handleCommunities = request.handleCommunities,
        collectMissingSplineNodeRefs = request.collectMissingSplineNodeRefs,
        collectDuplicateNodeRefs = request.collectDuplicateNodeRefs,
        collectInfinitePatrolWorkspots = request.collectInfinitePatrolWorkspots,
        hasBlockingIssues = request.hasBlockingIssues
    }

    local legacyMigrated, legacyDidMigrate, legacySidecarPath, currentSidecarPath = groupExportSidecar.migrateLegacySidecar(runtime.project.name)
    if not legacyMigrated then
        local message = string.format("Failed to rename legacy metadata sidecar \"%s\" to \"%s\"", tostring(legacySidecarPath), tostring(currentSidecarPath))
        logExportError(runtime, "prepare_sidecar", message)
        queueToast("warning", 5000, "Legacy metadata sidecar could not be renamed")
    elseif legacyDidMigrate then
        logger:info(string.format("[Group Export Manager] Renamed legacy metadata sidecar \"%s\" to \"%s\"", tostring(legacySidecarPath), tostring(currentSidecarPath)))
    end

    for _, group in ipairs(request.groups) do
        local mappedGroup = {
            name = group.name,
            fileName = group.fileName,
            category = group.category,
            level = group.level,
            streamingX = group.streamingX,
            streamingY = group.streamingY,
            streamingZ = group.streamingZ,
            prefabRef = group.prefabRef,
            variantRef = group.variantRef,
            variantData = utils.deepcopy(group.variantData or {}),
            incrementalReuse = false,
            sidecarEntry = nil,
            cachedSector = nil
        }
        mappedGroup.signature = groupExportSidecar.buildGroupSignature(mappedGroup, {
            version = request.version
        })

        table.insert(runtime.groups, mappedGroup)
    end
    runtime.totalGroups = #runtime.groups

    if request.buildChunkSize and request.buildChunkSize > 0 then
        runtime.buildChunkSize = request.buildChunkSize
    end
    if request.buildTimeBudgetMs and request.buildTimeBudgetMs > 0 then
        runtime.buildTimeBudgetMs = request.buildTimeBudgetMs
    end
    if request.exportChunkSize and request.exportChunkSize > 0 then
        runtime.exportChunkSize = request.exportChunkSize
    end
    if request.exportTimeBudgetMs and request.exportTimeBudgetMs > 0 then
        runtime.exportTimeBudgetMs = request.exportTimeBudgetMs
    end

    if runtime.mode == "incremental" and runtime.totalGroups > 0 then
        local incrementalReady, incrementalErr = prepareIncrementalRuntime(runtime)
        if not incrementalReady then
            runtime.mode = "full"
            runtime.incremental = nil

            for _, group in ipairs(runtime.groups) do
                group.incrementalReuse = false
                group.sidecarEntry = nil
                group.cachedSector = nil
            end

            queueToast("warning", 5000, string.format("Update Changed fallback to Full Export: %s", tostring(incrementalErr or "metadata unavailable")))
        else
            queueToast(
                "info",
                5000,
                string.format(
                    "Update Changed: %d changed, %d reused, %d removed",
                    runtime.incrementalStats.changed or 0,
                    runtime.incrementalStats.unchanged or 0,
                    runtime.incrementalStats.removed or 0
                )
            )
        end
    end

    groupExportManager.state = runtime

    if runtime.totalGroups == 0 then
        groupExportManager.state = createExportRuntime(runtime)
        return true
    end

    scheduleNextGroup(runtime)
    return true
end

function groupExportManager.cancel(reason, suppressToast)
    local runtime = groupExportManager.state
    if not runtime or not runtime.active then
        return false
    end

    haltRuntimeTimer(runtime)
    clearCurrentGroup(runtime)
    groupExportManager.state = createExportRuntime(runtime)

    if not suppressToast then
        local message = "Export cancelled"
        if reason and reason ~= "" then
            message = message .. " (" .. reason .. ")"
        end
        queueToast("warning", 3500, message)
    end

    return true
end

function groupExportManager.resume()
    local runtime = groupExportManager.state
    if not runtime or not runtime.active or not runtime.paused then
        return false
    end

    local resumeAction = runtime.resumeAction
    runtime.paused = false
    runtime.resumeAction = nil
    runtime.pauseReason = nil

    if resumeAction then
        local ok, err = pcall(function ()
            resumeAction()
        end)

        if not ok then
            abortExport(runtime, "resume", string.format("Failed resuming export: %s", tostring(err)))
            return false
        end
    end

    return true
end

function groupExportManager.isActive()
    return groupExportManager.state.active == true
end

function groupExportManager.isPaused()
    return groupExportManager.state.active == true and groupExportManager.state.paused == true
end

function groupExportManager.getState()
    return groupExportManager.state
end

function groupExportManager.drawToasts()
    pipelineCommon.drawQueuedToasts(groupExportManager.pendingToasts)
end

---@param style style
---@return boolean drawn
function groupExportManager.drawProgress(style)
    local runtime = groupExportManager.state
    if not runtime or not runtime.active then
        return false
    end

    local phaseProgress = 0
    local phaseText = ""
    local counterText = ""
    local helpText = ""

    if runtime.phase == "build" and runtime.current then
        local current = runtime.current
        local total = math.max(1, current.buildTotal or 0)
        phaseProgress = (current.buildProcessed or 0) / total
        phaseText = string.format("Preparing \"%s\"", current.name or "Group")
        counterText = string.format("%d/%d", current.buildProcessed or 0, current.buildTotal or 0)
        helpText = "Building group hierarchy in chunks."
    elseif runtime.phase == "export" and runtime.current then
        local current = runtime.current
        local total = math.max(1, current.totalNodes or 0)
        local completed = math.max(0, (current.nodeIndex or 1) - 1)
        phaseProgress = completed / total
        phaseText = string.format("Exporting \"%s\"", current.name or "Group")
        counterText = string.format("%d/%d", completed, current.totalNodes or 0)
        helpText = "Serializing nodes in chunks."
    elseif runtime.mode == "incremental" and not runtime.current and runtime.groupIndex <= runtime.totalGroups then
        local currentGroup = runtime.groups and runtime.groups[runtime.groupIndex]
        phaseProgress = 0
        phaseText = string.format("Updating \"%s\"", currentGroup and currentGroup.name or "Group")
        counterText = ""
        if currentGroup and currentGroup.incrementalReuse then
            helpText = "Reusing unchanged group data from the previous export."
        else
            helpText = "Preparing changed group for rebuild."
        end
    else
        phaseProgress = 1
        phaseText = "Finalizing export"
        counterText = ""
        helpText = "Writing final export file."
    end

    if runtime.paused then
        phaseText = "Paused: " .. phaseText
        helpText = runtime.pauseReason or "Resolve the export issue popup to continue."
    end

    local totalGroups = math.max(1, runtime.totalGroups or 0)
    local overall = math.min(1, ((runtime.completedGroups or 0) + phaseProgress) / totalGroups)

    local overallCounter = string.format("%d/%d", runtime.completedGroups or 0, runtime.totalGroups or 0)
    if counterText ~= "" then
        overallCounter = overallCounter .. " | " .. counterText
    end

    pipelineCommon.drawCancelableProgress({
        style = style,
        phaseText = phaseText,
        progress = overall,
        counterText = overallCounter,
        helpText = helpText,
        onCancel = function ()
            groupExportManager.cancel("user request")
        end
    })

    return true
end

return groupExportManager
