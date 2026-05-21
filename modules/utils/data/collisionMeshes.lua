local utils = require("modules/utils/utils")

---@class CollisionShapeData
---@field type string
---@field sectorsHashes string[]

local module = {}

---@param line string
---@return string | nil sectorHash, string | nil shapeHash, string | nil shapeType
function module.parseCollisionMeshesFileLine(line)
    local words = {}
    for word in string.gmatch(line, "%S+") do
        table.insert(words, word)
    end
    return words[1], words[2], words[3]
end

---@param path string
---@return { [string]: CollisionShapeData }
function module.parseCollisionMeshesFileToCollisionShapeDatas(path)
    local collisionShapesDatas = {}
    local file = io.open(path, "r")
    if file then
        for line in file:lines() do
            local sectorHash, shapeHash, shapeType = module.parseCollisionMeshesFileLine(line)
            if sectorHash and shapeHash and shapeType then
                if collisionShapesDatas[shapeHash] == nil then
                    collisionShapesDatas[shapeHash] = {
                        type = shapeType,
                        sectorsHashes = {}
                    }
                end
                table.insert(collisionShapesDatas[shapeHash].sectorsHashes, sectorHash)
            end
        end

        file:close()
    end

    return collisionShapesDatas
end

return module
