local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local cache = require("modules/utils/cache")
local builder = require("modules/utils/entityBuilder")
local Cron = require("modules/utils/Cron")

---Class for worldAISpotNode
---@class aiSpot : visualized
---@field previewNPC string
---@field spawnNPC boolean
---@field isWorkspotInfinite boolean
---@field isWorkspotStatic boolean
---@field markings table
---@field maxPropertyWidth number
---@field npcID entEntityID
---@field npcSpawning boolean
---@field cronID number
---@field workspotSpeed number
---@field rigs table
local aiSpot = setmetatable({}, { __index = visualized })

function aiSpot:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "AI Spot"
    o.spawnDataPath = "data/spawnables/ai/aiSpot/"
    o.modulePath = "ai/aiSpot"
    o.node = "worldAISpotNode"
    o.description = ""
    o.icon = IconGlyphs.MapMarkerStar

    o.previewed = true
    o.previewColor = "fuchsia"

    o.previewNPC = "Character.Judy"
    o.spawnNPC = true
    o.workspotSpeed = 3

    o.isWorkspotInfinite = true
    o.isWorkspotStatic = false
    o.markings = {}

    o.maxPropertyWidth = nil
    o.npcID = nil
    o.npcSpawning = false
    o.cronID = nil
    o.rigs = {}

    o.streamingMultiplier = 5

    setmetatable(o, { __index = self })
   	return o
end

function aiSpot:getVisualizerSize()
    return { x = 0.15, y = 0.15, z = 0.15 }
end

function aiSpot:getBBox()
    return {
        min = { x = -0.01, y = -0.01, z = -0.005 },
        max = { x = 0.01, y = 0.01, z = 0.005 }
    }
end

function aiSpot:onNPCSpawned(npc)
    Game.GetWorkspotSystem():PlayInDeviceSimple(self:getEntity(), npc, false, "workspot", "", "", 0, gameWorkspotSlidingBehaviour.PlayAtResourcePosition)

    self.cronID = Cron.Every(0.25, function ()
        if not self.npcID or not self:isSpawned() then return end
        local npc = self:getNPC()

        if Game.GetWorkspotSystem():GetExtendedInfo(npc).exiting or not Game.GetWorkspotSystem():IsActorInWorkspot(npc) then
            Game.GetWorkspotSystem():SendFastExitSignal(npc, Vector3.new(), false, false, true)
            Cron.After(0.1, function ()
                Game.GetWorkspotSystem():PlayInDeviceSimple(self:getEntity(), npc, false, "workspot", "", "", 0, gameWorkspotSlidingBehaviour.PlayAtResourcePosition)
            end)
        end
    end)

    npc:SetIndividualTimeDilation("", self.workspotSpeed)
end

function aiSpot:onAssemble(entity)
    visualized.onAssemble(self, entity)

    local component = entity:FindComponentByName("workspot")
    component.workspotResource = ResRef.FromString(self.spawnData)

    if self.spawnNPC then
        local spec = DynamicEntitySpec.new()
        spec.recordID = self.previewNPC
        spec.position = self.position
        spec.orientation = self.rotation:ToQuat()
        spec.alwaysSpawned = true
        self.npcID = Game.GetDynamicEntitySystem():CreateEntity(spec)
        self.npcSpawning = true

        builder.registerAttachCallback(self.npcID, function (entity)
            self:onNPCSpawned(entity)
        end)
    end
end

function aiSpot:spawn()
    local worspot = self.spawnData
    self.spawnData = "base\\spawner\\workspot_device.ent"

    visualized.spawn(self)
    self.spawnData = worspot

    cache.tryGet(self.spawnData .. "_rigs")
    .notFound(function (task)
        builder.registerLoadResource(self.spawnData, function(resource)
            local rigs = {}

            for _, set in ipairs(resource.workspotTree.finalAnimsets) do
                table.insert(rigs, ResRef.FromHash(set.rig.hash):ToString())
            end

            cache.addValue(self.spawnData .. "_rigs", rigs)

            task:taskCompleted()
        end)
    end)
    .found(function ()
        self.rigs = cache.getValue(self.spawnData .. "_rigs")
    end)
end

function aiSpot:despawn()
    visualized.despawn(self)

    if self.cronID then
        Cron.Halt(self.cronID)
        self.cronID = nil
    end

    if not self.npcID then return end

    Game.GetDynamicEntitySystem():DeleteEntity(self.npcID)
    self.npcID = nil
    self.npcSpawning = false
end

function aiSpot:getNPC()
    if not self.npcID then return end

    return Game.GetDynamicEntitySystem():GetEntity(self.npcID)
end

function aiSpot:onEdited(edited)
    if not self:isSpawned() or not edited then return end

    local handle = self:getNPC()
    if not handle then return end

    local cmd = AITeleportCommand.new()
    cmd.position = self.position
    cmd.rotation = self.rotation.yaw
    cmd.doNavTest = false

    handle:GetAIControllerComponent():SendCommand(cmd)

    Cron.After(0.1, function ()
        local handle = self:getNPC()
        if not handle then return end

        Game.GetWorkspotSystem():PlayInDeviceSimple(self:getEntity(), handle, false, "workspot", "", "", 0, gameWorkspotSlidingBehaviour.PlayAtResourcePosition)
    end)
end

function aiSpot:save()
    local data = visualized.save(self)

    data.previewNPC = self.previewNPC
    data.spawnNPC = self.spawnNPC
    data.workspotSpeed = self.workspotSpeed
    data.isWorkspotInfinite = self.isWorkspotInfinite
    data.isWorkspotStatic = self.isWorkspotStatic
    data.markings = self.markings

    return data
end

function aiSpot:draw()
    visualized.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Visualize position", "Is Infinite", "Is Static", "Preview NPC", "Preview NPC Record", "Animation Speed"}) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    if ImGui.TreeNodeEx("Previewing Options", ImGuiTreeNodeFlags.SpanFullWidth) then
        if ImGui.TreeNodeEx("Supported Rigs", ImGuiTreeNodeFlags.SpanFullWidth) then
            for _, rig in pairs(self.rigs) do
                style.mutedText(rig)
            end

            ImGui.TreePop()
        end

        self:drawPreviewCheckbox("Visualize position", self.maxPropertyWidth)

        style.mutedText("Preview NPC")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.spawnNPC, changed = style.trackedCheckbox(self.object, "##spawnNPC", self.spawnNPC)
        if changed then
            self:respawn()
        end

        style.mutedText("Preview NPC Record")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.previewNPC, _, finished = style.trackedTextField(self.object, "##previewNPC", self.previewNPC, "Character.", 200)
        if finished then
            self:respawn()
        end

        if self.spawnNPC then
            local npc = self:getNPC()

            style.mutedText("Animation Speed")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.maxPropertyWidth)
            self.workspotSpeed, changed, _ = style.trackedDragFloat(self.object, "##workspotSpeed", self.workspotSpeed, 0.1, 0, 25, "%.2f", 60)
            style.tooltip("Speed of the animation of the NPC in the workspot. Preview only.")
            if changed then
                npc:SetIndividualTimeDilation("", self.workspotSpeed)
            end

            if ImGui.Button("Forward Workspot") then
                Game.GetWorkspotSystem():SendForwardSignal(npc)
            end
        end

        ImGui.TreePop()
    end

    style.mutedText("Is Infinite")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.isWorkspotInfinite, _ = style.trackedCheckbox(self.object, "##isWorkspotInfinite", self.isWorkspotInfinite)
    style.tooltip("If checked, the NPC will use this spot indefinitely, while streamed in.\nIf unchecked, the NPC will walk to the next spot defined in its community entry.")

    style.mutedText("Is Static")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.isWorkspotStatic, _ = style.trackedCheckbox(self.object, "##isWorkspotStatic", self.isWorkspotStatic)

    if ImGui.TreeNodeEx("Markings", ImGuiTreeNodeFlags.SpanFullWidth) then
        for key, _ in pairs(self.markings) do
            ImGui.PushID(key)

            self.markings[key], _ = style.trackedTextField(self.object, "##marking", self.markings[key], "", 200)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.markings, key)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.markings, "")
        end

        ImGui.TreePop()
    end
    style.tooltip("Still requires to assign a NodeRef to this spot.")
end

function aiSpot:getProperties()
    local properties = visualized.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })
    return properties
end

function aiSpot:export()
    local markings = {}
    for _, marking in pairs(self.markings) do
        table.insert(markings, {
            ["$type"] = "CName",
            ["$storage"] = "string",
            ["$value"] = marking
        })
    end

    local data = visualized.export(self)
    data.type = "worldAISpotNode"
    data.data = {
        ["isWorkspotInfinite"] = self.isWorkspotInfinite and 1 or 0,
        ["isWorkspotStatic"] = self.isWorkspotStatic and 1 or 0,
        ["spot"] = {
            ["Data"] = {
                ["$type"] = "AIActionSpot",
                ["resource"] = {
                    ["DepotPath"] = {
                        ["$type"] = "ResourcePath",
                        ["$storage"] = "string",
                        ["$value"] = self.spawnData
                    },
                    ["Flags"] = "Soft"
                }
            }
        },
        ["markings"] = markings
    }

    return data
end

return aiSpot