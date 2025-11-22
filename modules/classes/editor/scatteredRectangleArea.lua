local scatteredValue = require("modules/classes/editor/scatteredValue")

local densityScale = 1000 -- 10m³

---@class scatteredRectangleArea
---@field volume number
---@field x scatteredValue
---@field y scatteredValue
---@field z scatteredValue
local scatteredRectangleArea = {}

---@param owner element
---@return scatteredRectangleArea
function scatteredRectangleArea:new(owner)
	local o = {}
    
    o.x = scatteredValue:new(-5, 5, "MIRROR")
	o.x.label = "X"
	o.x.lowerBound = -10000
	o.x.upperBound = 10000
	o.x.owner = owner

    o.y = scatteredValue:new(-5, 5, "MIRROR")
	o.y.label = "Y"
	o.y.lowerBound = -10000
	o.y.upperBound = 10000
	o.y.owner = owner

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

function scatteredRectangleArea:calculateVolume() 
   local lenX = self.x.max - self.x.min 
   local lenY = self.y.max - self.y.min
   local lenZ = self.z.max - self.z.min

   -- to avoid no instances when area is a flat shape
   if lenZ == 0 then
    lenZ = 1
   end

   self.volume = lenX * lenY * lenZ
end

---@param density scatteredValue
---@return number
function scatteredRectangleArea:getInstancesCount(density)
    local min = (density.min / densityScale) * self.volume
    local max = (density.max / densityScale) * self.volume

    return math.floor(math.random(min, max))
end

---@return Vector4
function scatteredRectangleArea:getRandomInstancePositionOffset()
    local posXmin = self.x.min
	local posXmax = self.x.max

	local posYmin = self.y.min
	local posYmax = self.y.max
	
	local posZmin = self.z.min
	local posZmax = self.z.max

	local rPosX = math.random(posXmin, posXmax)
	local rPosY = math.random(posYmin, posYmax)
	local rPosZ = math.random(posZmin, posZmax)

	return Vector4.new(rPosX, rPosY, rPosZ, 1)
end

---@return void
function scatteredRectangleArea:draw()
    local changedX = self.x:draw()
    local changedY = self.y:draw()
    local changedZ = self.z:draw()
    if changedX or changedY or changedZ then
        self:calculateVolume()
    end
end

---@param owner element
---@param data table
---@return scatteredRectangleArea
function scatteredRectangleArea:load(owner, data)
    local new = self:new(owner)

    new.volume = data.volume
    new.x = scatteredValue:load(owner, data.x)
    new.y = scatteredValue:load(owner, data.y)
    new.z = scatteredValue:load(owner, data.z)

    return new
end

---@return table
function scatteredRectangleArea:serialize()
    return {
        volume = self.volume,
        x = self.x:serialize(),
        y = self.y:serialize(),
        z = self.z:serialize()
    }
end

return scatteredRectangleArea