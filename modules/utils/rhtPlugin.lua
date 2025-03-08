---@class rht
---@field public spawnUI spawnUI?
local rht = {
    spawnUI = nil
}

local typeMap = {
    ["worldPopulationSpawnerNode"] = {
        data = "recordID",
        category = "Entity",
        sub = "Record"
    },
    ["worldDeviceNode"] = {
        data = "templatePath",
        category = "Entity",
        sub = "Device"
    },
    ["worldEntityNode"] = {
        data = "templatePath",
        category = "Entity",
        sub = "Template"
    },
    ["worldMeshNode"] = {
        data = "meshPath",
        category = "Mesh",
        sub = "Mesh"
    },
    ["worldInstancedMeshNode"] = {
        data = "meshPath",
        category = "Mesh",
        sub = "Mesh"
    },
    ["worldStaticDecalNode"] = {
        data = "materialPath",
        category = "Deco",
        sub = "Decals"
    },
    ["worldStaticParticleNode"] = {
        dataRetrieval = function (node)
            return ResRef.FromHash(node.nodeInstance:GetNode().particleSystem.hash):ToString()
        end,
        category = "Deco",
        sub = "Particles"
    },
    ["worldEffectNode"] = {
        data = "effectPath",
        category = "Deco",
        sub = "Effects"
    },
    ["worldStaticSoundEmitterNode"] = {
        dataRetrieval = function (node)
            local settings = node.nodeInstance:GetNode().Settings
            if not settings then return "" end

            if #settings.EventsOnActive < 1 then return "" end

            return settings.EventsOnActive[1].event.value
        end,
        category = "Deco",
        sub = "Static Audio Emitter"
    },
    ["worldAISpotNode"] = {
        dataRetrieval = function (node)
            local spot = node.nodeInstance:GetNode().spot
            if not spot then return "" end
            if not spot.resource then return "" end

            return ResRef.FromHash(spot.resource.hash):ToString()
        end,
        category = "AI",
        sub = "AI Spot"
    },
    ["worldReflectionProbeNode"] = {
        dataRetrieval = function (node)
            local probe = node.nodeInstance:GetNode().probeDataRef
            if not probe then return "" end

            return ResRef.FromHash(probe.hash):ToString()
        end,
        category = "Meta",
        sub = "Reflection Probe"
    }
}

local function getTypeIndex(node)
    for key, _ in pairs(typeMap) do
        if Reflection.GetClass(node.nodeType):IsA(key) then
            return key
        end
    end

    return nil
end

local function isWorldNode(node)
    local isNode = node and node.sectorPath and node.instanceIndex

    if not isNode then return false end

    return getTypeIndex(node) ~= nil
end

function rht.sendToSearch(node)
    local typeIndex = getTypeIndex(node)
    if not typeIndex then return end

    if typeMap[typeIndex].dataRetrieval then
        rht.spawnUI.filter = typeMap[typeIndex].dataRetrieval(node)
    else
        rht.spawnUI.filter = node[typeMap[typeIndex].data]
    end
    rht.spawnUI.selectedType = rht.spawnUI.getCategoryIndex(typeMap[typeIndex].category) - 1
    rht.spawnUI.updateCategory()
    rht.spawnUI.selectedVariant = rht.spawnUI.getVariantIndex(typeMap[typeIndex].category, typeMap[typeIndex].sub) - 1
    rht.spawnUI.updateVariant()

    rht.spawnUI.updateFilter()
end

function rht.init(spawner)
    rht.spawnUI = spawner.baseUI.spawnUI

    local mod = GetMod("RedHotTools")
    if not mod then return end

    mod.RegisterExtension({
        getTargetActions = function(node)
            if isWorldNode(node) then
                return {
                    type = "button",
                    label = "[OS] Send to search",
                    callback = rht.sendToSearch
                }
            end
        end
    })
end

return rht