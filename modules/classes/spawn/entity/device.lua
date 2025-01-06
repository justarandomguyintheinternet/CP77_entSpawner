local entity = require("modules/classes/spawn/entity/entity")
local style = require("modules/ui/style")

---Class for worldDeviceNode
---@class device : entity
---@field public deviceConnections {deviceClassName : string, nodeRef : string}[]
---@field public connectionsHeaderState boolean
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

    o.deviceConnections = {}
    o.connectionsHeaderState = false

    setmetatable(o, { __index = self })
   	return o
end

function device:save()
    local data = entity.save(self)
    data.deviceConnections = self.deviceConnections

    return data
end

function device:draw()
    entity.draw(self)

    self.connectionsHeaderState = ImGui.TreeNodeEx("Device Connections")

    if self.connectionsHeaderState then
        for index, connection in pairs(self.deviceConnections) do
            ImGui.PushID(key)

            connection.deviceClassName, _, _ = style.trackedTextField(self.object, "##className", connection.deviceClassName, "gameDeviceComponentPS", 150)
            style.tooltip("Device class name of the connected device. Name of the gameDeviceComponentPS used in the devices gameDeviceComponent")
            ImGui.SameLine()
            connection.nodeRef, _, _ = style.trackedTextField(self.object, "##deviceNodeRef", connection.nodeRef, "$/#foobar", 150)
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

function device:export(index, length)
    local data = entity.export(self, index, length)

    data.type = "worldDeviceNode"
    data.data.deviceConnections = {}

    for _, connection in pairs(self.deviceConnections) do
        table.insert(data.data.deviceConnections, {
            ["$type"] = "worldDeviceConnections",
            ["deviceClassName"] = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = connection.deviceClassName
            },
            ["nodeRefs"] = {
                {
                    ["$type"] = "NodeRef",
                    ["$storage"] = "string",
                    ["$value"] = connection.nodeRef
                }
            }
        })
    end

    return data
end

return device