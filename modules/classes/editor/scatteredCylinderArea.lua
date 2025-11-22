local scatteredValue = require("modules/classes/editor/scatteredValue")
local scatteredAreaBase = require("modules/classes/editor/scatteredAreaBase")

---@class scatteredCylinderArea : scatteredAreaBase
---@field r scatteredValue
---@field z scatteredValue
local scatteredCylinderArea = scatteredAreaBase:new()

---@param owner element
---@return scatteredCylinderArea
function scatteredCylinderArea:new(owner)
	local o = scatteredAreaBase:new(owner)
    
    o.r = scatteredValue:new(-5, 5, "EQUAL")
	o.r.label = "R"
	o.r.lowerBound = -10000
	o.r.upperBound = 10000
	o.r.owner = owner

    o.z = scatteredValue:new(0, 0, "MIRROR")
	o.z.label = "Z"
	o.z.lowerBound = -10000
	o.z.upperBound = 10000
	o.z.owner = owner

	self.__index = self
   	local outClass = setmetatable(o, self)
    outClass:calculateVolume()
    return outClass
end

function scatteredCylinderArea:calculateVolume() 
    local circleArea = self.r.min * self.r.min * math.pi
    local h = self.z.max - self.z.min

    if h == 0 then
        h = 1
    end

    self.volume = circleArea * h
end

---@return Vector4
function scatteredCylinderArea:getRandomInstancePositionOffset()
    local angle = math.random() * 2 * math.pi
	local r = math.sqrt(math.random()) * self.r.min

	local x = r * math.cos(angle)
	local y = r * math.sin(angle)
	local z = math.random(self.z.min, self.z.max)

    return Vector4.new(x, y, z, 1)
end

---@return void
function scatteredCylinderArea:draw()
    local changedR = self.r:draw()
    local changedZ = self.z:draw()
    if changedR or changedZ then
        self:calculateVolume()
    end
end

---@param owner element
---@param data table
---@return scatteredRectangleArea
function scatteredCylinderArea:load(owner, data)
    local new = scatteredAreaBase.load(self, owner, data)

    new.r = scatteredValue:load(owner, data.r)
    new.z = scatteredValue:load(owner, data.z)
    
    return new
end

---@return table
function scatteredCylinderArea:serialize()
    local baseData = scatteredAreaBase.serialize(self)

    baseData.r = self.r:serialize()
    baseData.z = self.z:serialize()

    return baseData
end

return scatteredCylinderArea