local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local config = require("modules/utils/config")

---@class category
---@field name string
---@field icon string
---@field headerOpen boolean
---@field favorites favorite[]
---@field grouped boolean
---@field favoritesUI favoritesUI
---@field fileName string
---@field openPopup boolean
---@field editName string
local category = {}

function category:new(fUI)
	local o = {}

	o.name = "New Category"
	o.icon = ""
	o.headerOpen = false
	o.favorites = {}
	o.grouped = false

    o.favoritesUI = fUI
	o.fileName = ""
	o.openPopup = false
	o.editName = ""

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during save()
function category:load(data, fileName)
	self:setName(data.name)
	self.headerOpen = data.headerOpen
    self.icon = data.icon
	self.fileName = fileName
	self.grouped = data.grouped

	for _, favoriteData in pairs(data.favorites) do
		local favorite = require("modules/classes/favorites/favorite"):new(self.favoritesUI)
		favorite:load(favoriteData)
		self:addFavorite(favorite)
	end
end

function category:setName(name)
	self.name = name
	self.editName = name
end

function category:generateFileName()
	self.fileName = utils.createFileName(self.name) .. "_" .. tostring(os.time()) .. ".json"
end

function category:addFavorite(favorite)
	table.insert(self.favorites, favorite)
	favorite:setCategory(self)

	self:save()
end

function category:removeFavorite(favorite)
	for key, data in pairs(self.favorites) do
		if data == favorite then
			table.remove(self.favorites, key)
			break
		end
	end

	self:save()
end

function category:isNameDuplicate(name)
	local found = 0

	for _, favorite in pairs(self.favorites) do
		if favorite.name == name and found < 2 then
			found = found + 1
			if found == 2 then
				return true
			end
		end
	end

	return false
end

function category:drawEditPopup()
	if ImGui.BeginPopupContextItem("##editCategory" .. self.fileName) then
        -- Edit name
        style.setNextItemWidth(200)
        if self.openPopup then
            self.openPopup = false
            ImGui.SetKeyboardFocusHere()
        end
        self.editName, changed = ImGui.InputTextWithHint("##name", "Name...", self.editName, 100)
        if ImGui.IsItemDeactivatedAfterEdit() then
			if not self.favoritesUI.categories[self.editName] then
				self.favoritesUI.updateCategoryName(self.name, self.editName)
				self.name = self.editName
				self:save()
			else
				self.editName = self.name
			end
		end
		if self.name ~= self.editName and self.favoritesUI.categories[self.editName] then
			ImGui.SameLine()
            style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
            style.tooltip("Category with this name already exists.")
		end

		ImGui.Separator()

		-- Confirm / delete
		style.pushButtonNoBG(true)
		if ImGui.Button(IconGlyphs.CheckCircleOutline) then
			ImGui.CloseCurrentPopup()
		end
		style.pushButtonNoBG(false)

		style.pushButtonNoBG(true)
		ImGui.SameLine()
		ImGui.Button(IconGlyphs.Delete)
		if ImGui.BeginPopupContextItem("Delete Category?", ImGuiPopupFlags.MouseButtonLeft) then
			style.mutedText("Are you sure you want to delete this category?")
			if ImGui.Button("Confirm") then
				ImGui.CloseCurrentPopup()
				self:delete()
			end
			ImGui.SameLine()
			if ImGui.Button("Cancle") then
				ImGui.CloseCurrentPopup()
			end
			ImGui.EndPopup()
		end

		style.pushButtonNoBG(false)
		ImGui.EndPopup()
    end

    if self.openPopup then
        ImGui.OpenPopup("##editCategory" .. self.fileName)
    end
end

function category:drawSideButtons()
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

    -- Right side buttons
    local settingsX, _ = ImGui.CalcTextSize(IconGlyphs.FileTreeOutline)
    local groupX, _ = ImGui.CalcTextSize(IconGlyphs.CogOutline)
	local totalX = settingsX + groupX + ImGui.GetStyle().ItemSpacing.x
    local scrollBarAddition = ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0
    local cursorX = ImGui.GetWindowWidth() - totalX - ImGui.GetStyle().CellPadding.x / 2 - scrollBarAddition + ImGui.GetScrollX()
    ImGui.SetCursorPosX(cursorX)

	local grouped = self.grouped
	style.pushStyleColor(not grouped, ImGuiCol.Text, style.mutedColor)
	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(IconGlyphs.FileTreeOutline) then
		self.grouped = not self.grouped
		self:save()
	end
	style.popStyleColor(not grouped)
	style.tooltip("Group by tags")

	ImGui.SameLine()
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(IconGlyphs.CogOutline) then
		self.openPopup = true
	end
end

---@param context {padding: number, row: number, depth: number}
function category:draw(context)
	self.favoritesUI.pushRow(context)

	ImGui.PushID(context.row)

	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4 * style.viewSize, context.padding * 2 + style.viewSize)

    self.headerOpen, changed = ImGui.Selectable("##category" .. context.row, self.headerOpen, ImGuiSelectableFlags.SpanAllColumns + ImGuiSelectableFlags.AllowOverlap)
	if changed then
		self:save()
	end
	context.row = context.row + 1

	ImGui.SameLine()
	ImGui.PushStyleColor(ImGuiCol.Button, 0)
	ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
	ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
	ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 1 * style.viewSize)

	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(self.headerOpen and IconGlyphs.MenuDownOutline or IconGlyphs.MenuRightOutline) then
		self.headerOpen = not self.headerOpen
		self:save()
	end
	ImGui.SameLine()
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

	self:drawEditPopup()
end

function category:serialize()
	local data = {
		name = self.name,
		icon = self.icon,
		headerOpen = self.headerOpen,
		grouped = self.grouped,
		favorites = {}
	}

	for _, favorite in pairs(self.favorites) do
		table.insert(data.favorites, favorite:serialize())
	end

	return data
end

function category:save()
	local data = self:serialize()

	config.saveFile("data/favorite/" .. self.fileName, data)
end

function category:delete()
	os.remove("data/favorite/" .. self.fileName)
	self.favoritesUI.categories[self.name] = nil
end

return category