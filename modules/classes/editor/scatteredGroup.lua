local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local Cron = require("modules/utils/Cron")
local scatteredRectangleArea = require("modules/classes/editor/scatteredRectangleArea")
local scatteredCylinderArea = require("modules/classes/editor/scatteredCylinderArea")
local scatteredPrismArea = require("modules/classes/editor/scatteredPrismArea")

local positionableGroup = require("modules/classes/editor/positionableGroup")

local areaTypes = { "CYLINDER", "RECTANGLE", "SHAPE" }

---Class scattered positionable group
---@class scatteredGroup : positionableGroup
---@field seed number
---@field snapToGround boolean
---@field snapToGroundOffset number
---@field lastPos Vector4
---@field baseGroup positionableGroup
---@field instanceGroup positionableGroup
---@field shapeGroup positionableGroup
---@field applyGroundNormal boolean
---@field area {rectangle: scatteredRectangleArea, cylinder: scatteredCylinderArea, shape: table[scatteredPrismArea] type: string}
---@field densityMultiplier number
local scatteredGroup = setmetatable({}, { __index = positionableGroup })

-- SECTION: "BOILERPLATE"

function scatteredGroup:new(sUI)
	local o = positionableGroup.new(self, sUI)

	o.modulePath = "modules/classes/editor/scatteredGroup"

	o.class = utils.combine(o.class, { "scatteredGroup" })
	o.quickOperations = {}
	o.icon = IconGlyphs.DiceMultipleOutline
	o.supportsSaving = false

	o.seed = 1
    o.snapToGround = false
	o.applyGroundNormal = false

	o.lastPos = nil

	o.maxPropertyWidth = nil

	o.baseGroup = positionableGroup:new(sUI)
	o.baseGroup.name = "Base"
	o.baseGroup:setParent(o)
	o.baseGroup.lockedRemove = true
	o.baseGroup.lockedRename = true

	o.instanceGroup = positionableGroup:new(sUI)
	o.instanceGroup.name = "Instances"
	o.instanceGroup:setParent(o)
	o.instanceGroup.lockedRemove = true
	o.instanceGroup.lockedRename = true

	o.shapeGroup = positionableGroup:new(sUI)
	o.shapeGroup.name = "Shape"
	o.shapeGroup:setParent(o)
	o.shapeGroup.lockedRemove = true
	o.shapeGroup.lockedRename = true

	o.snapToGroundOffset = 100

	o.area = {}
	o.area.rectangle = scatteredRectangleArea:new(o)
	o.area.cylinder = scatteredCylinderArea:new(o)
	o.area.shape = {}
	o.area.type = "CYLINDER"

	o.densityMultiplier = 1.0

	setmetatable(o, { __index = self })
   	return o
end

function scatteredGroup:load(data, silent)
	self.baseGroup.lockedRemove = false
	self.instanceGroup.lockedRemove = false
	self.shapeGroup.lockedRemove = false
	positionableGroup.load(self, data, silent)

	self.seed = data.seed
	self.snapToGround = data.snapToGround or false
	self.snapToGroundOffset = data.snapToGroundOffset or 100
	self.densityMultiplier = data.densityMultiplier or 1.0
	self.area = {}
	self.area.rectangle = scatteredRectangleArea:load(self, data.area.rectangle)
	self.area.cylinder = scatteredCylinderArea:load(self, data.area.cylinder)
	self.area.type = data.area.type


	local hasBase, hasInstances, hasShape = false, false, false
	for _, child in ipairs(self.childs) do
		if child.name == "Base" then
			hasBase = true
			self.baseGroup = child
		elseif child.name == "Instances" then
			hasInstances = true
			self.instanceGroup = child
		elseif child.name == "Shape" then 
			hasShape = true
			self.shapeGroup = child
		end
	end

	if not hasBase then
		self.baseGroup = positionableGroup:new(self.sUI)
		self.baseGroup.name = "Base"
		self.baseGroup:setParent(self)
	end

	if not hasInstances then
		self.instanceGroup = positionableGroup:new(self.sUI)
		self.instanceGroup.name = "Instances"
		self.instanceGroup:setParent(self)
	end

	if not hasShape then
		self.shapeGroup = positionableGroup:new(self.sUI)
		self.shapeGroup.name = "Shape"
		self.shapeGroup:setParent(self)
	end

	self.baseGroup.lockedRemove = true
	self.baseGroup.lockedRename = true

	self.instanceGroup.lockedRemove = true
	self.instanceGroup.lockedRename = true

	self.shapeGroup.lockedRemove = true
	self.shapeGroup.lockedRename = true

	if self.seed == -1 then
		self:reSeed()
	end
end

function scatteredGroup:serialize()
	local data = positionableGroup.serialize(self)

	data.seed = self.seed
	data.snapToGround = self.snapToGround
	data.snapToGroundOffset = self.snapToGroundOffset
	data.densityMultiplier = self.densityMultiplier
	data.area = {}
	data.area.rectangle = self.area.rectangle:serialize()
	data.area.cylinder = self.area.cylinder:serialize()
	data.area.type = self.area.type

	return data
end

function scatteredGroup:setParent(parent, index)
	self.baseGroup.lockedRemove = false
	self.instanceGroup.lockedRemove = false
	self.shapeGroup.lockedRemove = false

	positionableGroup.setParent(self, parent, index)

	self.baseGroup.lockedRemove = true
	self.instanceGroup.lockedRemove = true
	self.shapeGroup.lockedRemove = true
end

function scatteredGroup:removeChild(child)
	if child == self.baseGroup then
		self.baseGroup.lockedRemove = false
	elseif child == self.instanceGroup then
		self.instanceGroup.lockedRemove = false
	elseif child == self.shapeGroup then
		self.shapeGroup.lockedRemove = false
	end

	positionableGroup.removeChild(self, child)
end

function scatteredGroup:remove()
	self.baseGroup.lockedRemove = false
	self.instanceGroup.lockedRemove = false
	self.shapeGroup.lockedRemove = false

	positionableGroup.remove(self)
end

-- SECTION: SCATTER LOGIC

---@private
---@return Vector4
function scatteredGroup:calculatePositionRectangle()
	local offset = self.area.rectangle:getRandomInstancePositionOffset()
	return utils.addVector(offset, self.lastPos)
end

---@private
---@return Vector4
function scatteredGroup:calculatePositionCylinder()
	local offset = self.area.cylinder:getRandomInstancePositionOffset()
	return utils.addVector(offset, self.lastPos)
end

---@private
---@param prismIndex number
---@return Vector4
function scatteredGroup:calculatePositionPrism(prismIndex)
	local offset = self.area.shape[prismIndex]:getRandomInstancePositionOffset()
	return utils.addVector(offset, self.lastPos)
end

---@private
---@param prismIndex number?
---@return Vector4
function scatteredGroup:calculatePosition(prismIndex)
	if self.area.type == "CYLINDER" then
		return self:calculatePositionCylinder()
	elseif self.area.type == "RECTANGLE" then
		return self:calculatePositionRectangle()
	elseif self.area.type == "SHAPE" then
		return self:calculatePositionPrism(prismIndex)
	else
		print("Unsupported area type: " .. tostring(self.area.type))
		return self.lastPos 
	end
end

---@private
---@param scatterConfig scatteredConfig
---@return EulerAngles
function scatteredGroup:calculateRotation(scatterConfig)
	local Xmin = scatterConfig.rotation.x.min
	local Xmax = scatterConfig.rotation.x.max

	local Ymin = scatterConfig.rotation.y.min
	local Ymax = scatterConfig.rotation.y.max

	local Zmin = scatterConfig.rotation.z.min
	local Zmax = scatterConfig.rotation.z.max

	local rX = math.random(Xmin, Xmax)
	local rY = math.random(Ymin, Ymax)
	local rZ = math.random(Zmin, Zmax)

	return EulerAngles.new(rX, rY, rZ)
end

---@private
---@param scatterConfig scatteredConfig
---@return number
function scatteredGroup:calculateScale(scatterConfig)
	local min = scatterConfig.scale.min
	local max = scatterConfig.scale.max

	return math.random(min, max)
end

---@private
---@param scatterConfig scatteredConfig
---@param prismIndex number?
---@return number
function scatteredGroup:calculateElementCount(scatterConfig, prismIndex)
	local density = { min = scatterConfig.density.min,
					  max = scatterConfig.density.max }
	density.min = density.min * self.densityMultiplier
	density.max = density.max * self.densityMultiplier

	if self.area.type == "RECTANGLE" then
		return self.area.rectangle:getInstancesCount(density)
	elseif self.area.type == "CYLINDER" then
		return self.area.cylinder:getInstancesCount(density)
	elseif self.area.type == "SHAPE" then 
		return self.area.shape[prismIndex]:getInstancesCount(density)
	else
		print("Unsupported Area type: " .. tostring(self.area.type))
		return 0
	end
end

function scatteredGroup:applyRandomization(pos, recursiveParam)
	self.lastPos = pos or self.baseGroup:getPosition()
	local recursive = recursiveParam or true
	while self.instanceGroup.childs[1] do
		self.instanceGroup.childs[1]:remove()
	end
	math.randomseed(self.seed)

	local shapes = {}
	if self.area.type == "CYLINDER" then
		table.insert(shapes, self.area.cylinder)
	elseif self.area.type == "RECTANGLE" then
		table.insert(shapes, self.area.rectangle)
	elseif self.area.type == "SHAPE" then
		self:triangulate()
		shapes = self.area.shape
	end

	for si, shape in ipairs(shapes) do
		for _, child in ipairs(self.baseGroup.childs) do
			if not child.scatterConfig then
				goto continue
			end
			local elementCount = self:calculateElementCount(child.scatterConfig, si)
			for i = 1, elementCount do

				local newObjSerialized = child:serialize()
				newObjSerialized.visible = true
				newObjSerialized.hiddenByParent = false
				local newObj = require(child.modulePath):new(self.sUI)
				newObj:load(newObjSerialized, true)

				local position = self:calculatePosition(si)
				newObj:setPosition(position)

				local rotation = self:calculateRotation(child.scatterConfig)
				newObj:setRotation(rotation)

				local scaleValue = self:calculateScale(child.scatterConfig)
				local scale = { x = scaleValue,
								y = scaleValue,
								z = scaleValue }
				newObj:setScale(scale, true)

				newObj:setSilent(false)
				newObj:setVisible(true, true)
				newObj:setParent(self.instanceGroup)

				if recursive and (utils.isA(newObj, "scatteredGroup") or utils.isA(newObj, "randomizedGroup")) then
					Cron.After(0.05, function()
						newObj:applyRandomization()
					end, nil)
				end
			end
			::continue::
		end
	end
	
	if self.snapToGround then
		self:setPosition(utils.addVector(self.lastPos, Vector4.new(0, 0, self.snapToGroundOffset, 0)))
		Cron.After(0.05, function()
			self:dropToSurface(true, Vector4.new(0, 0, -1, 0), true, self.applyGroundNormal)
		end, nil)
	end
end

function scatteredGroup:reSeed()
	self.seed = math.random(0, 999999999)
	self:applyRandomization(nil, false)

	for _, child in pairs(self.instanceGroup.childs) do
		if utils.isA(child, "scatteredGroup") or utils.isA(child, "randomizedGroup") then
			child:reSeed()
		end
	end
end

-- SECTION: TRIANGULATION

local function subVec2(v1, v2)
	return { x = v1.x - v2.x, y = v1.y - v2.y }
end

local function cross(ax, ay, bx, by)
    return ax * by - ay * bx
end

local function area(poly)
    local a = 0
    for i = 1, #poly do
        local j = (i % #poly) + 1
        a = a + (poly[i].x * poly[j].y - poly[j].x * poly[i].y)
    end
    return a * 0.5
end

local function isPointInTriangle(px, py, ax, ay, bx, by, cx, cy)
    local v0x, v0y = cx - ax, cy - ay
    local v1x, v1y = bx - ax, by - ay
    local v2x, v2y = px - ax, py - ay

    local dot00 = v0x*v0x + v0y*v0y
    local dot01 = v0x*v1x + v0y*v1y
    local dot02 = v0x*v2x + v0y*v2y
    local dot11 = v1x*v1x + v1y*v1y
    local dot12 = v2x*v1x + v2y*v1y

    local invDenom = 1 / (dot00 * dot11 - dot01 * dot01)
    local u = (dot11 * dot02 - dot01 * dot12) * invDenom
    local v = (dot00 * dot12 - dot01 * dot02) * invDenom

    return u >= 0 and v >= 0 and (u + v) < 1
end

local function isConvex(prev, curr, next)
    local crossVal = cross(
        curr.x - prev.x, curr.y - prev.y,
        next.x - curr.x, next.y - curr.y
    )
    return crossVal > 0      -- assuming CCW polygon
end

function scatteredGroup:triangulate()
    self.area.shape = {}

    local h
    local verts = {}
    for _, v in ipairs(self.shapeGroup.childs) do
        if not (utils.isA(v, "spawnableElement") and v.spawnable.modulePath == "area/outlineMarker") then goto continue end

        local childPos = v:getPosition()
        table.insert(verts, { x = childPos.x, y = childPos.y })
        h = v.spawnable.height
		self.lastPos.z = childPos.z

        ::continue::
    end

    -- Ensure CCW orientation
    if area(verts) < 0 then
        local rev = {}
        for i=#verts,1,-1 do table.insert(rev, verts[i]) end
        verts = rev
    end

    while #verts > 3 do
        local earFound = false

        for i=1,#verts do
            local prev = verts[(i-2) % #verts + 1]
            local curr = verts[i]
            local next = verts[i % #verts + 1]

            if isConvex(prev, curr, next) then
                -- Check other points NOT in the triangle
                local ear = true

                for j=1,#verts do
                    if j ~= i and verts[j] ~= prev and verts[j] ~= next then
                        local p = verts[j]
                        if isPointInTriangle(
                            p.x, p.y,
                            prev.x, prev.y,
                            curr.x, curr.y,
                            next.x, next.y
                        ) then
                            ear = false
                            break
                        end
                    end
                end

                if ear then
                    -- Found an ear: output triangle
					local newPrism = scatteredPrismArea:new(self)
					newPrism.v1 = subVec2(prev, self.lastPos)
					newPrism.v2 = subVec2(curr, self.lastPos)
					newPrism.v3 = subVec2(next, self.lastPos)
					newPrism.z = h
					newPrism:calculateVolume()
                    table.insert(self.area.shape, newPrism)

                    -- Remove the ear vertex
                    table.remove(verts, i)

                    earFound = true
                    break
                end
            end
        end

        if not earFound then
            print("Ear clipping failed: polygon may be degenerate or self-intersecting.")
        end
    end

    -- Final triangle
	local newPrism = scatteredPrismArea:new(self)
	newPrism.v1 = subVec2(verts[1], self.lastPos)
	newPrism.v2 = subVec2(verts[2], self.lastPos)
	newPrism.v3 = subVec2(verts[3], self.lastPos)
	newPrism.z = h
	newPrism:calculateVolume()
	table.insert(self.area.shape, newPrism)
end

-- SECTION: UI

function scatteredGroup:getProperties()
	local properties = positionableGroup.getProperties(self)

	table.insert(properties, {
		id = "scatteredGroup",
		name = "Group Scattering",
		defaultHeader = false,
		draw = function ()
			self:drawGroupRandomization()
		end
	})

	return properties
end

function scatteredGroup:drawGroupRandomization()
	if not self.maxPropertyWidth then
		self.maxPropertyWidth = utils.getTextMaxWidth({ "Seed", "Randomization Rule", "Fixed Amount Rule", "Fixed Amount %", "Fixed Amount Total" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
	end

	if ImGui.Button("Apply Randomization") then
		history.addAction(history.getElementChange(self))
		self:applyRandomization()
	end

	style.mutedText("Seed")
	ImGui.SameLine()
	ImGui.SetCursorPosX(self.maxPropertyWidth)
	self.seed, _, finished = style.trackedIntInput(self, "##seed", self.seed, 0, 9999999999)
	if finished then
		self:applyRandomization()
	end 

	ImGui.SameLine()
	style.pushButtonNoBG(true)
	if ImGui.Button(IconGlyphs.Reload) then
		history.addAction(history.getElementChange(self))
		self:reSeed()
	end
	style.pushButtonNoBG(false)

	style.styledText("Snap to Ground")
	ImGui.SameLine()
	local snapToGround, snapToGroundChanged = style.trackedCheckbox(self, "##SnapToGround", self.snapToGround, false)
	if snapToGroundChanged then
		self.snapToGround = snapToGround
	end

	style.styledText("Apply Ground Normal")
	ImGui.SameLine()
	local applyGroundNormal, applyGroundNormalChanged = style.trackedCheckbox(self, "##applyGroundNormal", self.applyGroundNormal, false)
	if applyGroundNormalChanged then
		self.applyGroundNormal = applyGroundNormal
	end

	style.styledText("Snap Offset")
	ImGui.SameLine()
	local snapOffset, snapOffsetChanged = style.trackedDragFloat(self, "##SnapOffset", self.snapToGroundOffset, 0.1, 0.1, 1000, "%.1f")
	if snapOffsetChanged then
		self.snapToGroundOffset = snapOffset
	end

	style.styledText("Position Randomization:")
	style.mutedText("Type:")
	ImGui.SameLine()
	ImGui.PushItemWidth(120 * style.viewSize)
	local posType, posTypeChanged = style.trackedCombo(self, "##posTypeCombo", utils.indexValue(areaTypes, self.area.type) - 1, areaTypes)
	if posTypeChanged then
		self.area.type = areaTypes[posType + 1]
	end
	
	if self.area.type == "RECTANGLE" then
		self.area.rectangle:draw()
	elseif self.area.type == "CYLINDER" then
		self.area.cylinder:draw()
	end

	style.styledText("Density Multiplier")
	local densityMultiplier, densityMultiplierChanged = style.trackedDragFloat(self, "##densityMultiplier", self.densityMultiplier, 0.01, 0.01, 1000, "%.2f")
	if densityMultiplierChanged then
		self.densityMultiplier = densityMultiplier
	end
end

return scatteredGroup