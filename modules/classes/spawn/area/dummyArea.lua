local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local area = require("modules/classes/spawn/area/area")

---Class for dummy area, useful for getting outline
---@class dummyArea : area
local dummyArea = setmetatable({}, { __index = area })

function dummyArea:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "Dummy Area"
    o.spawnDataPath = "data/spawnables/area/dummy/"
    o.modulePath = "area/dummyArea"
    o.node = "---"
    o.description = "Spawns a dummy area, which can be used for getting an outline for a gameStaticAreaShapeComponent."
    o.previewNote = "Does not do anything or get exported."
    o.icon = IconGlyphs.SelectionOff

    o.noExport = true

    setmetatable(o, { __index = self })
   	return o
end

function dummyArea:draw()
    area.draw(self)
    style.mutedText("This area does not do anything and is not exported.")

    if ImGui.Button("Copy outline to clipboard") then
        local paths = self:loadOutlinePaths()
        local markers = {}
        local height = 0

        if utils.indexValue(paths, self.outlinePath) ~= -1 then
            for _, child in pairs(self.object.sUI.getElementByPath(self.outlinePath).childs) do
                if utils.isA(child, "spawnableElement") and child.spawnable.modulePath == "area/outlineMarker" then
                    local offset = utils.subVector(child.spawnable.position, self.position)

                    table.insert(markers, {
                        ["$type"] = "Vector3",
                        ["X"] = offset.x,
                        ["Y"] = offset.y,
                        ["Z"] = offset.z
                    })
                    height = child.spawnable.height
                end
            end
        end

        utils.insertClipboardValue("outline", {
            height = height,
            points = markers
        })
    end
end

return dummyArea