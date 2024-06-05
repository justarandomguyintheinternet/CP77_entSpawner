local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local object = require("modules/classes/object")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local drag = require("modules/utils/dragHelper")

---Class for handling the hierarchical structure and base UI, wraps a spawnable object
---@class object
---@field public name string
---@field public parent group?
---@field public type string
---@field public newName string
---@field public selectedGroup integer
---@field public color table
---@field public box table {x: number, y: number}
---@field public id integer
---@field public headerOpen boolean
---@field public autoLoad boolean
---@field public loadRange number
---@field public isAutoLoaded boolean
---@field public spawnable spawnable
---@field public sUI spawnedUI
---@field public spawnableHeaderOpen boolean
---@field public beingTargeted boolean
---@field public targetable boolean
---@field public beingDragged boolean
---@field public hovered boolean
object = {}

---@param sUI spawnedUI
---@return object
function object:new(sUI)
	local o = {}

    o.name = "" -- Base stuff
    o.parent = nil

    o.type = "object" -- Visual stuff
    o.newName = ""
    o.selectedGroup = -1
    o.color = {0, 50, 255}
    o.box = {x = 650, y = 282}
    o.id = math.random(1, 1000000000) -- Id for imgui child rng gods bls have mercy
    o.headerOpen = settings.headerState
    o.spawnableHeaderOpen = false

    o.autoLoad = false
	o.loadRange = settings.autoSpawnRange
    o.isAutoLoaded = false

    o.spawnable = nil

    o.sUI = sUI

    o.beingTargeted = false
    o.targetable = true
    o.beingDragged = false
    o.hovered = false

	self.__index = self
   	return setmetatable(o, self)
end

function object:spawn()
    self.spawnable:spawn()
end

function object:update()
    self.spawnable:update()
end

function object:despawn()
    self.spawnable:despawn()
end

function object:getPosition()
    return self.spawnable.position
end

---@param position Vector4
function object:setPosition(position)
    self.spawnable.position = position
    self:update()
end

function object:getRotation()
    return self.spawnable.rotation
end

-- Group system functions

---Generate valid name from path or if no path given current name
---@param path string?
function object:generateName(path)
    local text = path or self.name
    if string.find(self.name, "\\") then
        self.name = text:match("\\[^\\]*$") -- Everything after last \
    end
    self.name = self.name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    self.name = utils.createFileName(self.name)
end

---Update file name to new given
---@param name string
function object:rename(name)
    name = self.spawnable:generateName(name)
    os.rename("data/objects/" .. self.name .. ".json", "data/objects/" .. name .. ".json")
    self.name = name
    self.sUI.spawner.baseUI.savedUI.reload()
end

---Return the object data for internal object format saving
---@return table {name, type, headerOpen, autoLoad, loadRange, spawnable}
function object:getState()
    self.name = self.spawnable:generateName(self.name)

    return {
        name = self.name,
        type = self.type,
        headerOpen = self.headerOpen,
        spawnableHeaderOpen = self.spawnableHeaderOpen,
        autoLoad = self.autoLoad,
        loadRange = self.loadRange,
        spawnable = self.spawnable:save()
    }
end

---Either save to file or return self as table to parent
---@return table?
function object:save()
    if self.parent == nil then
        local state = self:getState()

        config.tryCreateConfig("data/objects/" .. state.name .. ".json", state)
        config.saveFile("data/objects/" .. state.name .. ".json", state)
        self.sUI.spawner.baseUI.savedUI.reload()
    else
        return self:getState()
    end
end

---Load object data from table, same format as what
---@see object.getState returns
function object:load(data)
    self.name = data.name
    self.headerOpen = data.headerOpen
    self.autoLoad = data.autoLoad
    self.loadRange = data.loadRange
    self.spawnableHeaderOpen = data.spawnableHeaderOpen or true

    self.spawnable = require("modules/classes/spawn/" .. data.spawnable.modulePath):new()
    self.spawnable.object = self
    self.spawnable:loadSpawnData(data.spawnable, ToVector4(data.spawnable.position), ToEulerAngles(data.spawnable.rotation))
end

function object:tryMainDraw()
    if self.parent == nil then
        self:draw()
    end
end

function object:handleDrag()
	local hovered = ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenBlockedByActiveItem)

	if hovered and not self.hovered then
		drag.draggableHoveredIn(self)
	elseif not hovered and self.hovered then
		drag.draggableHoveredOut(self)
	end

	self.hovered = hovered
end

---Callback for when this object gets dropped into another one
function object:dropIn(target)
    if target.type == "group" then
        self:setSelectedGroupByPath(target:getOwnPath())
        self:moveToSelectedGroup()
    elseif target.type == "object" then
        local path = self:addGroupToParent(self.name .. "_group")
        self:setSelectedGroupByPath(path)
        self:moveToSelectedGroup()

        target:setSelectedGroupByPath(path)
        target:moveToSelectedGroup()
    end
end

function object:draw()
    if self.parent ~= nil then
		ImGui.Indent(35)
	end

    ImGui.PushID(tostring(self.name .. self.id))
    ImGui.SetNextItemOpen(self.headerOpen)

    if self.beingDragged then ImGui.PushStyleColor(ImGuiCol.Header, 1, 0, 0, 0.5) end
	if self.beingTargeted then ImGui.PushStyleColor(ImGuiCol.Header, 0, 1, 0, 0.5) end
    self.headerOpen = ImGui.CollapsingHeader(self.name)
	if self.beingDragged or self.beingTargeted then ImGui.PopStyleColor() end

    self:handleDrag()

    local hovered = self.spawnable.isHovered
    self.spawnable:resetVisualizerStates()
    self.spawnable:setIsHovered(ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenBlockedByActiveItem))

    if self.headerOpen then
        CPS.colorBegin("Border", self.color)
        CPS.colorBegin("Separator", self.color)

        local h = 6 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().WindowPadding.y + 4 * ImGui.GetStyle().ItemSpacing.y + 7 * ImGui.GetStyle().ItemSpacing.y
        h = h + self.spawnable:getExtraHeight()
        ImGui.BeginChild("obj_" .. tostring(self.name .. self.id), self.box.x, h, true)

        if not self.isAutoLoaded then
            ImGui.SetNextItemWidth(300)
            self.newName = ImGui.InputTextWithHint('##Name', 'New Name...', self.newName, 100)
            if ImGui.IsItemDeactivatedAfterEdit() then
                self:rename(self.newName)
                self:saveAfterMove()
                self.newName = ""
            end

            ImGui.SameLine()

            if ImGui.Button("Copy Data to Clipboard") then
                ImGui.SetClipboardText(self.spawnable.spawnData)
            end
            style.tooltip(self.spawnable.spawnData)
        else
			ImGui.Text(tostring(self.name .. " | AUTOSPAWNED"))
		end

        -- ImGui.Text(tostring("Spawned: " .. tostring(self.spawnable:isSpawned()):upper()))

        self:drawGroup()

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        self.spawnable:draw()

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        if CPS.CPButton("Spawn") then
            if self.spawnable:isSpawned() then
                self.spawnable:respawn()
            else
                self.spawnable:spawn()
            end
        end
        ImGui.SameLine()
        if CPS.CPButton("Despawn") then
            self:despawn()
        end
        ImGui.SameLine()
        if CPS.CPButton("Clone") then
            local clone = object:new(self.sUI)
            local rot = EulerAngles.new(self.spawnable.rotation.roll, self.spawnable.rotation.pitch, self.spawnable.rotation.yaw)
            local pos = Vector4.new(self.spawnable.position.x, self.spawnable.position.y, self.spawnable.position.z, 0)

            clone.spawnable = require("modules/classes/spawn/" .. self.spawnable.modulePath):new(clone)
            clone.spawnable:loadSpawnData(self.spawnable:save(), pos, rot)

            clone.name = self.name .. " Clone"

            clone:spawn()
            table.insert(self.sUI.elements, clone)
            if self.parent ~= nil then
                clone.parent = self.parent
                table.insert(self.parent.childs, clone)
            end
        end
        ImGui.SameLine()
        if CPS.CPButton("Remove") then
            self:despawn()
            if self.parent ~= nil then
                utils.removeItem(self.parent.childs, self)
                ---TODO: Figure out what to do here
                -- self.parent:saveAfterMove()
            end
            utils.removeItem(self.sUI.elements, self)
        end
        ImGui.SameLine()
        if CPS.CPButton("Make Favorite") then
            self.sUI.spawner.baseUI.favUI.createNewFav(self)
        end
        ImGui.SameLine()
        if self.parent == nil then
            if CPS.CPButton("Save to file") then
                self:save()
                self.sUI.spawner.baseUI.savedUI.files[self.name] = nil
            end
        end

        ImGui.EndChild()

        CPS.colorEnd(2)
    end
    ImGui.PopID()

    self.spawnable:updateIsHovered(hovered)

    if self.parent ~= nil then
		ImGui.Unindent(35)
	else
		ImGui.Separator()
	end
end

function object:drawGroup()
    local gs = {} -- Get list of all paths for dropdown
    for _, g in pairs(self.sUI.groups) do
        table.insert(gs, g.name)
    end

    if self.selectedGroup == -1 then -- If first call get the current path and make it selected
        self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
    end

    ImGui.SetNextItemWidth(300)
    self.selectedGroup = ImGui.Combo("##movetogroup", self.selectedGroup, gs, #gs)

    ImGui.SameLine()

    if ImGui.Button("Move to group", 150, 0) then
        if self:verifyMove(self.sUI.groups[self.selectedGroup + 1].tab) then -- Dont move inside same group
           self:moveToSelectedGroup()
        end
    end
end

function object:setSelectedGroupByPath(path)
    self.sUI.getGroups()

    local i = 0
    for _, group in pairs(self.sUI.groups) do
        if group.name == path then
            self.selectedGroup = i
            break
        end
        i = i + 1
    end
end

function object:moveToSelectedGroup()
    if self.selectedGroup ~= 0 then
        if self.parent == nil then
            os.remove("data/objects/" .. self.name .. ".json")
            self.sUI.spawner.baseUI.savedUI.reload()
        end
        if self.parent ~= nil then
            utils.removeItem(self.parent.childs, self)
        end
        self.parent = self.sUI.groups[self.selectedGroup + 1].tab
        table.insert(self.sUI.groups[self.selectedGroup + 1].tab.childs, self)
        self:saveAfterMove()
    else
        if self.parent ~= nil then
            utils.removeItem(self.parent.childs, self)
            self.parent:saveAfterMove()
        end

        self.parent = nil
        self:save()
    end
end

function object:addGroupToParent(name)
    local g = require("modules/classes/spawn/group"):new(self.sUI)
    g.name = utils.createFileName(name)

    g.parent = nil
    if self.parent then
        g.parent = self.parent
        table.insert(self.parent.childs, g)
    end
    table.insert(self.sUI.elements, g)

    return g:getOwnPath()
end

function object:addObjectToParent(spawnable, name, headerOpen)
    local o = object:new(self.sUI)
    o.spawnable = spawnable
    o.spawnable:spawn()
    o.parent = self.parent
    o.name = name
    o.headerOpen = headerOpen

    if self.parent then
        table.insert(self.parent.childs, o)
    end

    table.insert(self.sUI.elements, o)
end

function object:verifyMove(to)
	local allowed = true

	if to == self.parent then
		allowed = false
	end

	return allowed
end

function object:saveAfterMove()
	-- if self.parent == nil then
	-- 	for _, file in pairs(dir("data/objects")) do
	-- 		if file.name:match("^.+(%..+)$") == ".json" then
	-- 			if file.name == self.name .. ".json" then
	-- 				self:save()
	-- 			end
	-- 		end
	-- 	end
	-- else
	-- 	self.parent:saveAfterMove()
	-- end
end

function object:getOwnPath(first)
    if self.parent == nil then
        if first then
            return "-- No group --"
        else
            return self.name
        end
    else
        if first then
            return self.parent:getOwnPath()
        else
            return tostring(self.parent:getOwnPath() .. "/" .. self.name)
        end
    end
end

function object:getHeight(y)
	if self.headerOpen then
		return y + self.box.y + 32
	else
	    return y + 28
    end
end

function object:getWidth(x)
    if self.headerOpen then
        return math.max(x, x + 35)
    else
        return x
    end
end

return object