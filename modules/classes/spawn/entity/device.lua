local entity = require("modules/classes/spawn/entity/entity")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local registry = require("modules/utils/nodeRefRegistry")

local propertyNames = {
    "Device Class Name",
    "Persistent"
}

---Class for worldDeviceNode
---@class device : entity
---@field public deviceConnections {deviceClassName : string, nodeRef : string}[]
---@field public connectionsHeaderState boolean
---@field public deviceClassName string
---@field public persistent boolean
---@field private maxPropertyWidth number?
---@field public controllerComponent string
local device = setmetatable({}, { __index = entity })

function device:new()
	local o = entity.new(self)

    o.dataType = "Device"
    o.modulePath = "entity/device"
    o.spawnDataPath = "data/spawnables/entity/device/"
    o.node = "worldDeviceNode"
    o.description = "Spawns an entity (.ent), as a worldDeviceNode. This allows it to be connected to other worldDeviceNodes."
    o.previewNote = "Device connections / functionality is not previewed."

    o.icon = IconGlyphs.DesktopClassic

    o.deviceClassName = ""
    o.deviceConnections = {}
    o.connectionsHeaderState = false
    o.persistent = false

    o.maxPropertyWidth = nil
    o.controllerComponent = ""

    setmetatable(o, { __index = self })
   	return o
end

function device:save()
    local data = entity.save(self)
    data.deviceConnections = utils.deepcopy(self.deviceConnections)
    data.deviceClassName = self.deviceClassName
    data.persistent = self.persistent
    data.controllerComponent = self.controllerComponent

    return data
end

function device:onAssemble(entRef)
    entity.onAssemble(self, entRef)

    for _, component in pairs(entRef:GetComponents()) do
        if component:IsA("gameDeviceComponent") then
            self.controllerComponent = component.name.value

            if self.deviceClassName == "" and component.persistentState then
                self.deviceClassName = component.persistentState:GetClassName().value
            end
        end
    end
end

function device:draw()
    entity.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Device Class Name")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.deviceClassName, _, _ = style.trackedTextField(self.object, "##nodeClassName", self.deviceClassName, "gameDeviceComponentPS", 150)
    style.tooltip("Device class name of this device. Name of the gameDeviceComponentPS used in the gameDeviceComponent")

    style.mutedText("Persistent")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.persistent, _, _ = style.trackedCheckbox(self.object, "##persistent", self.persistent)
    if self.nodeRef == "" then
        self.persistent = false
        style.tooltip("Requires NodeRef to be set.")
    else
        style.tooltip("If true, the device will get an entry in the .psrep file. Not all devices need this, still subject to more testing.")
    end
    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.Reload) then
        Game.GetPersistencySystem():ForgetObject(PersistentID.ForComponent(entEntityID.new({ hash = loadstring("return " .. utils.nodeRefStringToHashString(self.nodeRef) .. "ULL", "")() }), self.controllerComponent), true)
    end
    style.pushButtonNoBG(false)
    style.tooltip("Reloads the devices persistent state.\nApplies to the actual device in the world (Imported), not the editor.")

    self.connectionsHeaderState = ImGui.TreeNodeEx("Device Connections")

    if self.connectionsHeaderState then
        for index, connection in pairs(self.deviceConnections) do
            ImGui.PushID(key)

            connection.deviceClassName, _, _ = style.trackedTextField(self.object, "##className", connection.deviceClassName, "gameDeviceComponentPS", 150)
            style.tooltip("Device class name of the connected device. Name of the gameDeviceComponentPS used in the devices gameDeviceComponent")
            ImGui.SameLine()
            connection.nodeRef, _ = registry.drawNodeRefSelector(style.getMaxWidth(250) - 30, connection.nodeRef, self.object, false)
            style.tooltip("NodeRef of the connected device. Can be set using \"World Node\" section of the target device")
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                table.remove(self.deviceConnections, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            table.insert(self.deviceConnections, { deviceClassName = "", nodeRef = "" })
        end

        ImGui.TreePop()
    end
end

function device:getPSData()
    for _, data in pairs(self.instanceDataChanges) do
        if data.persistentState and data.persistentState.Data then
            return data.persistentState.Data
        end
    end
end

function device:export(index, length)
    local data = entity.export(self, index, length)

    data.type = "worldDeviceNode"
    data.data.deviceConnections = {}

    local connections = {}

    -- Group by deviceClassName
    for _, connection in pairs(self.deviceConnections) do
        if not connections[connection.deviceClassName] then
            connections[connection.deviceClassName] = {}
        end

        table.insert(connections[connection.deviceClassName], connection.nodeRef)
    end

    for className, connection in pairs(connections) do
        local nodeRefs = {}

        for _, nodeRef in pairs(connection) do
            table.insert(nodeRefs, {
                ["$type"] = "NodeRef",
                ["$storage"] = "string",
                ["$value"] = nodeRef
            })
        end

        table.insert(data.data.deviceConnections, {
            ["$type"] = "worldDeviceConnections",
            ["deviceClassName"] = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = className
            },
            ["nodeRefs"] = nodeRefs
        })
    end

    return data
end

return device