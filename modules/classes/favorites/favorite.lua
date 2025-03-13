local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local editor = require("modules/utils/editor/editor")

---@class favorite
---@field name string
---@field tags table
---@field data positionable
---@field category category?
---@field icon string
---@field favoritesUI favoritesUI
local favorite = {}

---@param fUI favoritesUI
---@return favorite
function favorite:new(fUI)
	local o = {}

	o.name = "New Favorite"
    o.tags = {}
    o.data = nil
    o.category = nil
    o.icon = ""

    o.favoritesUI = fUI

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during serialize()
function favorite:load(data)
	self.name = data.name
    self.tags = data.tags
    self.data = data.data
    self.icon = data.icon
end

function favorite:setCategory(category)
    self.category = category
end

function favorite:isMatch(stringFilter, tagFilter)
    if not self.name:lower():match(stringFilter:lower()) then return false end

    if utils.tableLength(self.tags) == 0 then return not settings.favoritesTagsAND or utils.tableLength(tagFilter) == 0 end

    for tag, _ in pairs(tagFilter) do
        if self.tags[tag] and not settings.favoritesTagsAND then return true end
        if not self.tags[tag] and settings.favoritesTagsAND then
            return false
        end
    end

    return settings.favoritesTagsAND
end

function favorite:drawSideButtons()
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

    -- Right side buttons
    local settingsX, _ = ImGui.CalcTextSize(IconGlyphs.CogOutline)
	local totalX = settingsX + ImGui.GetStyle().ItemSpacing.x
    local scrollBarAddition = ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0
    local cursorX = ImGui.GetWindowWidth() - totalX - ImGui.GetStyle().CellPadding.x / 2 - scrollBarAddition + ImGui.GetScrollX()
    ImGui.SetCursorPosX(cursorX)

	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(IconGlyphs.CogOutline) then
		self.favoritesUI.openPopup = true
        self.favoritesUI.popupItem = self
	end
end

function favorite:draw(context)
    self.favoritesUI.pushRow(context)

	ImGui.PushID(context.row)

	ImGui.SetCursorPosX((context.depth) * 17 * style.viewSize)
	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4 * style.viewSize, context.padding * 2 + style.viewSize)

    if ImGui.Selectable("##favorite" .. context.row, false, ImGuiSelectableFlags.SpanAllColumns + ImGuiSelectableFlags.AllowOverlap) then
        self.favoritesUI.spawnUI.spawnNew({ data = self.data }, require(self.data.modulePath), true)
    elseif ImGui.IsMouseDragging(0, 0.6) and not self.favoritesUI.spawnUI.dragging and ImGui.IsItemHovered() then
        self.favoritesUI.spawnUI.dragging = true
        self.favoritesUI.spawnUI.dragData = { data = self.data, name = self.name }
    elseif not ImGui.IsMouseDragging(0, 0.6) and self.favoritesUI.spawnUI.dragging then
        if not ImGui.IsItemHovered() then
            local ray = editor.getScreenToWorldRay()
            self.favoritesUI.spawnUI.popupSpawnHit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), true)

            spawnUI.dragData.lastSpawned = spawnUI.spawnNew(self.favoritesUI.spawnUI.dragData, require(self.data.modulePath), true)
        end

        self.favoritesUI.spawnUI.dragging = false
        self.favoritesUI.spawnUI.dragData = nil
        self.favoritesUI.spawnUI.popupSpawnHit = nil
    end

	context.row = context.row + 1

	ImGui.SameLine()
	ImGui.PushStyleColor(ImGuiCol.Button, 0)
	ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
	ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
	ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 1 * style.viewSize)

	ImGui.SetNextItemAllowOverlap()
	if self.icon ~= "" then
		ImGui.AlignTextToFramePadding()
		ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * style.viewSize)
		ImGui.Text(IconGlyphs[self.icon])
	end
	ImGui.SameLine()
	ImGui.AlignTextToFramePadding()
	ImGui.SetNextItemAllowOverlap()
	ImGui.Text(self.name)

	ImGui.SameLine()
	self:drawSideButtons()

	ImGui.PopStyleColor(2)
	ImGui.PopStyleVar(3)

	ImGui.PopID()
end

function favorite:serialize()
	local data = {
		name = self.name,
        tags = self.tags,
        data = self.data,
        icon = self.icon
	}

	return data
end

return favorite