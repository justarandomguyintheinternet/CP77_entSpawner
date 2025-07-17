local style = require("modules/ui/style")
local history = require("modules/utils/history")
local utils = require("modules/utils/utils")

local lcHelper = {}

function lcHelper.getGroupedProperties(spawnable)
    return {
		name = "Light Channels",
        id = "lcGrouped",
		data = {
            selected = { true, true, true, true, true, true, true, true, true, false, false, false }
        },
		draw = function(element, entries)
            element.groupOperationData["lcGrouped"].selected = style.drawLightChannelsSelector(nil, element.groupOperationData["lcGrouped"].selected)

            if ImGui.Button("Apply to selected") then
                history.addAction(history.getMultiSelectChange(entries))

                local nApplied = 0

                for _, entry in ipairs(entries) do
                    if entry.spawnable.lightChannels ~= nil then
                        entry.spawnable.lightChannels = utils.deepcopy(element.groupOperationData["lcGrouped"].selected)
                        nApplied = nApplied + 1
                    end
                end

                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Applied light channel settings to %s nodes", nApplied)))
            end
            style.tooltip("Apply the current light channels to all selected entries.")
        end,
		entries = { spawnable }
	}
end

return lcHelper