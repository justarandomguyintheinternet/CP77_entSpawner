---Shared `DeviceOperationsContainer` data: paths, the class catalogues the quick setup builds its UI
---from.
---
---The container lives on the PS chunk of any device whose controller derives from
---`ScriptableDeviceComponentPS`, and ships null on effectively every device. It holds two arrays:
---`operations` (named effects) and `triggers` (conditions that run them by name). A trigger reaches
---an operation only through an exact, case-sensitive CName match, which is why the quick setup makes
---that reference a dropdown rather than a text field.
---
---Field schemas below are read from the RTTI dump, and the enum member lists are the RED JSON values
---(enums serialize as their member name, verified against shipped entities such as
---`ep1\gameplay\devices\lighting\industrial\spotlight\spotlight_maelstrom.ent`).
---@class deviceOperations
local deviceOperations = {}

local transformAnimations = require("modules/utils/data/transformAnimations")
local builder = require("modules/utils/game/entityBuilder")
local redValue = require("modules/utils/data/redValue")

deviceOperations.BASE_PS_CLASS = "ScriptableDeviceComponentPS"
deviceOperations.CONTAINER_CLASS = "DeviceOperationsContainer"
deviceOperations.OPERATION_BASE_CLASS = "DeviceOperationBase"
deviceOperations.TRIGGER_BASE_CLASS = "DeviceOperationsTrigger"
deviceOperations.EXECUTION_CLASS = "OperationExecutionData"
deviceOperations.SOUND_COMPONENT_CLASS = "gameaudioSoundComponent"
deviceOperations.EFFECT_COMPONENT_CLASS = "entEffectSpawnerComponent"
---The only controller that carries custom actions. It has no subclasses, so the Toggle custom action
---operation and the Custom action ID trigger are dead on every other device.
deviceOperations.GENERIC_PS_CLASS = "GenericDeviceControllerPS"
deviceOperations.ANIMATOR_COMPONENT_CLASSES = { "gameTransformAnimatorComponent", "gameRootTransformAnimatorComponent" }
---Components that carry both a `.mesh` and a `meshAppearance`, i.e. the ones an entity-wide
---appearance switch can land on. `entPhysicalMeshComponent` derives from `entMeshComponent`, and the
---cloth / morph-target components are left out: they carry a `meshAppearance` but take their
---geometry from another resource, so there is no appearance list to read.
deviceOperations.MESH_COMPONENT_CLASSES = { "entMeshComponent", "entSkinnedMeshComponent", "entPhysicalDestructionComponent" }

deviceOperations.CONTAINER_PATH = { "persistentState", "Data", "deviceOperationsSetup" }
deviceOperations.CONTAINER_DATA_PATH = { "persistentState", "Data", "deviceOperationsSetup", "Data" }
deviceOperations.OPERATIONS_PATH = { "persistentState", "Data", "deviceOperationsSetup", "Data", "operations" }
deviceOperations.TRIGGERS_PATH = { "persistentState", "Data", "deviceOperationsSetup", "Data", "triggers" }
deviceOperations.CUSTOM_ACTIONS_PATH = { "persistentState", "Data", "genericDeviceActionsSetup", "customActions", "actions" }

---Enum member names, in declaration order. RED JSON stores the name, not the ordinal.
deviceOperations.ENUMS = {
    EEffectOperationType = { "START", "STOP", "BRAKE_LOOP" },
    EDeviceStatus = { "DISABLED", "UNPOWERED", "OFF", "ON", "INVALID" },
    EDoorStatus = { "SEALED", "LOCKED", "CLOSED", "OPENED" },
    EComparisonOperator = { "Equal", "NotEqual", "More", "MoreOrEqual", "Less", "LessOrEqual" },
    ETriggerOperationType = { "ENTER", "EXIT" },
    EComponentOperation = { "Enable", "Disable" },
    EMathOperationType = { "Add", "Set" },
    DeviceStimType = { "Distract", "VisualDistract", "Explosion", "VentilationAreaEffect", "None" },
    EItemOperationType = { "ADD", "REMOVE" },
    EWorkspotOperationType = { "ENTER", "LEAVE" },
    ETransformAnimationOperationType = { "PLAY", "PAUSE", "RESET", "SKIP" },
    -- Four members, not the two the operation's own docs suggest: `Device.OnPlayBink` maps PAUSE
    -- and RESUME onto `BinkComponent.Pause(true/false)`.
    EBinkOperationType = { "PLAY", "STOP", "PAUSE", "RESUME" },
    ECLSForcedState = { "DEFAULT", "ForcedON", "ForcedOFF" },
    EPriority = { "VeryLow", "Low", "Medium", "High", "VeryHigh", "Absolute" },
    gameinteractionsEInteractionEventType = { "EIET_activate", "EIET_deactivate" }
}

-- Field schemas ---------------------------------------------------------------------------------
--
-- `path` is relative to the operation's / trigger data's own `Data` table. `kind` picks the widget:
-- cname | noderef | tweakdbid | bool | int | float | enum (with `enum`) | class (with `base`).
-- A `list` describes a repeated struct: the quick setup draws its entries as a table, one row each.
--
-- Two optional keys turn a free-text field into a dropdown, which is the whole point of this panel:
-- every one of these names is matched exactly and fails silently when it is wrong.
--   `selector`  -- "component" | "meshAppearance" | "animation" | "vfx" | "event" |
--                  "customAction" | "interactionTag" | "deviceAction", resolved against the live
--                  entity (or the shipped audio metadata) by the provider functions further down.
--   `records`   -- a TweakDB record class whose IDs fill the dropdown, for `tweakdbid` fields.
-- Both keep `allowCustom` on, so a name the entity does not carry yet is still typeable.
-- `componentFilter` narrows a "component" selector to components of one class.

deviceOperations.OPERATION_TYPES = {
    {
        class = "PlaySoundDeviceOperation", label = "Play sound",
        hint = "Plays or stops a WWise event. The entity needs a gameaudioSoundComponent for this to route anywhere.",
        list = {
            path = { "SFXs" }, itemClass = "SSFXOperationData", label = "Sounds", singular = "sound",
            fields = {
                { path = { "sfxName" }, label = "WWise event", kind = "cname", selector = "event", width = 260 },
                { path = { "operationType" }, label = "Action", kind = "enum", enum = "EEffectOperationType", width = 100 }
            }
        }
    },
    {
        class = "PlayEffectDeviceOperation", label = "Play effect (VFX)",
        hint = "Starts or stops a particle effect already registered on the entity, by name.",
        list = {
            path = { "VFXs" }, itemClass = "SVFXOperationData", label = "Effects", singular = "effect",
            fields = {
                { path = { "vfxName" }, label = "Effect name", kind = "cname", selector = "vfx", width = 90 },
                { path = { "operationType" }, label = "Action", kind = "enum", enum = "EEffectOperationType", width = 100 },
                { path = { "shouldPersist" }, label = "Persist", kind = "bool" },
                { path = { "size" }, label = "Size", kind = "float", width = 60 },
                { path = { "nodeRef" }, label = "Node ref", kind = "noderef" }
            }
        }
    },
    {
        class = "ToggleComponentsDeviceOperation", label = "Toggle components",
        hint = "Enables or disables named components on this entity.",
        list = {
            path = { "components" }, itemClass = "SComponentOperationData", label = "Components", singular = "component",
            fields = {
                { path = { "componentName" }, label = "Component", kind = "cname", selector = "component", width = 220 },
                { path = { "operationType" }, label = "Action", kind = "enum", enum = "EComponentOperation", width = 80 }
            }
        }
    },
    {
        class = "PlayTransformAnimationDeviceOperation", label = "Transform animation",
        hint = "Plays, pauses or resets a transform animation on the entity.",
        list = {
            path = { "transformAnimations" }, itemClass = "STransformAnimationData", label = "Animations", singular = "animation",
            fields = {
                { path = { "animationName" }, label = "Animation", kind = "cname", selector = "animation", width = 140 },
                { path = { "operationType" }, label = "Action", kind = "enum", enum = "ETransformAnimationOperationType", width = 80 },
                { path = { "playData", "looping" }, label = "Looping", kind = "bool" },
                { path = { "playData", "timeScale" }, label = "Time scale", kind = "float" },
                { path = { "playData", "timesPlayed" }, label = "Repeats", kind = "int",
                  hint = "Ignored while Looping is on." }
            }
        }
    },
    {
        class = "MeshAppearanceDeviceOperation", label = "Mesh appearance",
        hint = "Switches the mesh appearance of the entity.",
        fields = {
            { path = { "meshesAppearence" }, label = "Appearance", kind = "cname", selector = "meshAppearance", width = 240,
              -- Hints render through `ImGui.Text`, which does not wrap, so they are broken by hand.
              hint = "A mesh appearance, i.e. one defined inside a component's .mesh -- not an entity appearance.\n"
                  .. "The name goes to every mesh component at once, and only the ones whose .mesh owns an\n"
                  .. "appearance by that name change -- so this list is the union over the entity's meshes." }
        }
    },
    {
        class = "FactsDeviceOperation", label = "Set quest fact",
        hint = "Writes a global quest fact. This is the supported way to reach another device: it reads the fact with a Fact trigger. Facts persist in the save and are shared with every other mod, so prefix them.",
        list = {
            path = { "facts" }, itemClass = "SFactOperationData", label = "Facts", singular = "fact",
            fields = {
                { path = { "factName" }, label = "Fact", kind = "cname", width = 240 },
                { path = { "factValue" }, label = "Value", kind = "int" },
                { path = { "operationType" }, label = "Mode", kind = "enum", enum = "EMathOperationType", width = 60 }
            }
        }
    },
    {
        class = "StimDeviceOperation", label = "Broadcast stimulus",
        hint = "Broadcasts a distraction stimulus that NPC AI reacts to.",
        list = {
            path = { "stims" }, itemClass = "SStimOperationData", label = "Stimuli", singular = "stimulus",
            fields = {
                { path = { "stimType" }, label = "Type", kind = "enum", enum = "DeviceStimType" },
                { path = { "operationType" }, label = "Action", kind = "enum", enum = "EEffectOperationType", width = 100 },
                { path = { "radius" }, label = "Radius", kind = "float" },
                { path = { "lifeTime" }, label = "Lifetime", kind = "float" },
                { path = { "nodeRef" }, label = "Node ref", kind = "noderef" }
            }
        }
    },
    {
        class = "ApplyStatusEffectDeviceOperation", label = "Apply status effect",
        list = {
            path = { "statusEffects" }, itemClass = "SStatusEffectOperationData", label = "Effects", singular = "effect",
            fields = {
                { path = { "effect", "statusEffect" }, label = "Status effect", kind = "tweakdbid", records = "gamedataStatusEffect_Record", width = 300 },
                { path = { "range" }, label = "Range", kind = "float" },
                { path = { "duration" }, label = "Duration", kind = "float" }
            }
        }
    },
    {
        class = "ApplyDamageDeviceOperation", label = "Apply damage",
        list = {
            path = { "damages" }, itemClass = "SDamageOperationData", label = "Damages", singular = "damage",
            fields = {
                { path = { "damageType" }, label = "Damage type", kind = "tweakdbid", records = "gamedataAttack_Record", width = 300,
                  hint = "An Attack record: the operation feeds it to TweakDBInterface.GetAttackRecord." },
                { path = { "range" }, label = "Range", kind = "float" }
            }
        }
    },
    {
        class = "ItemsDeviceOperation", label = "Grant / remove items",
        list = {
            path = { "items" }, itemClass = "SInventoryOperationData", label = "Items", singular = "item",
            fields = {
                { path = { "itemName" }, label = "Item", kind = "tweakdbid", records = "gamedataItem_Record", width = 300 },
                { path = { "quantity" }, label = "Quantity", kind = "int" },
                { path = { "operationType" }, label = "Mode", kind = "enum", enum = "EItemOperationType", width = 80 }
            }
        }
    },
    {
        class = "SetMessageDeviceOperation", label = "Set LCD screen message",
        hint = "One of only two operations that reach another node, and it is hardcoded to LcdScreenControllerPS.",
        fields = {
            { path = { "targetRef" }, label = "Target node", kind = "noderef" },
            { path = { "messageRecordID" }, label = "Message record", kind = "tweakdbid", records = "gamedataScreenMessageData_Record", width = 280 },
            { path = { "replaceTextWithCustomNumber" }, label = "Use number", kind = "bool" },
            { path = { "customNumber" }, label = "Number", kind = "int" }
        }
    },
    {
        class = "TeleportDeviceOperation", label = "Teleport",
        fields = {
            { path = { "teleport", "nodeRef" }, label = "Destination", kind = "noderef" }
        }
    },
    {
        class = "TeleportNodetoSlotOperation", label = "Teleport node to slot",
        hint = "The other operation that reaches another node, and it only ever moves an object onto a slot.",
        fields = {
            { path = { "gameObjectRef" }, label = "Object node", kind = "noderef" },
            { path = { "slotName" }, label = "Slot", kind = "cname", width = 240 }
        }
    },
    {
        class = "PlayerWokrspotDeviceOperation", label = "Player workspot",
        hint = "Engine spelling: PlayerWokrspot.",
        fields = {
            { path = { "playerWorkspot", "componentName" }, label = "Component", kind = "cname", selector = "component", width = 220 },
            { path = { "playerWorkspot", "operationType" }, label = "Action", kind = "enum", enum = "EWorkspotOperationType" },
            { path = { "playerWorkspot", "freeCamera" }, label = "Free camera", kind = "bool" }
        }
    },
    {
        class = "PlayBinkDeviceOperation", label = "Play Bink video",
        hint = "The video path itself is a resource token this panel cannot author; set `bink.binkPath` under Entity Instance Data.",
        fields = {
            { path = { "bink", "componentName" }, label = "Component", kind = "cname", selector = "component",
              componentFilter = "gameBinkComponent", width = 220 },
            { path = { "bink", "operationType" }, label = "Action", kind = "enum", enum = "EBinkOperationType" },
            { path = { "bink", "loop" }, label = "Loop", kind = "bool" }
        }
    },
    {
        class = "ToggleCustomActionDeviceOperation", label = "Toggle custom action",
        hint = "Shows or hides one of the device's own custom actions. It only flips `isEnabled` on an entry that already exists in the controller's customActions array -- it cannot create one, and it does nothing at all on a controller other than GenericDeviceController.",
        fields = {
            { path = { "customActionID" }, label = "Action ID", kind = "cname", selector = "customAction", width = 240 },
            { path = { "enabled" }, label = "Enabled", kind = "bool" }
        }
    },
    {
        class = "ToggleOffMeshConnectionsDeviceOperation", label = "Toggle navmesh links",
        fields = {
            { path = { "enable" }, label = "Enable", kind = "bool" },
            { path = { "affectsPlayer" }, label = "Player", kind = "bool" },
            { path = { "affectsNPCs" }, label = "NPCs", kind = "bool" }
        }
    },
    {
        class = "RequestCLSStateChangeDeviceOperation", label = "Crowd lighting state",
        fields = {
            { path = { "state" }, label = "State", kind = "enum", enum = "ECLSForcedState" },
            { path = { "priority" }, label = "Priority", kind = "enum", enum = "EPriority" },
            { path = { "sourceName" }, label = "Source", kind = "cname", width = 240 },
            { path = { "removePreviousRequests" }, label = "Replace previous", kind = "bool" }
        }
    },
    {
        class = "GenericDeviceOperation", label = "Generic (combination)",
        hint = "Carries every payload at once. Too broad for this panel: edit its arrays under Entity Instance Data.",
        deferToInstanceData = true
    }
}

deviceOperations.TRIGGER_TYPES = {
    {
        class = "BaseStateOperationsTrigger", dataClass = "BaseStateOperationTriggerData",
        label = "Device state changes",
        hint = "Fires on a change into the chosen state, not on every evaluation.",
        fields = {
            { path = { "state" }, label = "State", kind = "enum", enum = "EDeviceStatus" }
        }
    },
    {
        class = "DoorStateOperationsTrigger", dataClass = "DoorStateOperationTriggerData",
        label = "Door state changes",
        hint = "Fires on a change into the chosen state, not on every evaluation.",
        fields = {
            { path = { "state" }, label = "State", kind = "enum", enum = "EDoorStatus" }
        }
    },
    {
        class = "ActivatorOperationsTrigger", dataClass = "ActivatorOperationTriggerData",
        label = "Device activated",
        -- Not an on-load trigger, despite the class name. Its only call site is
        -- `GenericDevice.OnActivateDevice(evt: ref<ActivateDevice>)`, so it fires when the device
        -- *receives* an ActivateDevice action -- from a quest node, a master device driving its
        -- slaves, or the player performing it -- and never on any other controller. Nothing in the
        -- container fires at spawn; a `Device state changes` trigger on ON is the closest thing.
        hint = "Fires when the device receives an ActivateDevice action, from a quest, a master device or the player. Only GenericDeviceController raises it, and it does not fire on load.",
        fields = {}
    },
    {
        class = "FactOperationsTrigger", dataClass = "FactOperationTriggerData",
        label = "Quest fact changes",
        hint = "The supported way for one device to react to another: the other device writes the fact with a Set quest fact operation.",
        fields = {
            { path = { "factName" }, label = "Fact", kind = "cname", width = 240 },
            { path = { "comparisionType" }, label = "Compare", kind = "enum", enum = "EComparisonOperator" },
            { path = { "factValue" }, label = "Value", kind = "int" }
        }
    },
    {
        class = "DeviceActionOperationsTrigger", dataClass = "DeviceActionOperationTriggerData",
        label = "Device action performed",
        hint = "Fires on any action the device performs -- interaction, quickhack or quest -- matched on the action's class name only; the action instance carries nothing.",
        fields = {
            -- `selector = "deviceAction"` narrows the picker to the actions this controller can
            -- actually raise. The base stays the real one: the picker's own toggle falls back to it.
            { path = { "action" }, label = "Action class", kind = "class", base = "ScriptableDeviceAction",
              selector = "deviceAction", required = true }
        }
    },
    {
        class = "CustomActionOperationsTriggers", dataClass = "CustomActionOperationTriggerData",
        label = "Custom action ID",
        hint = "Fires when the player performs one of the device's own custom actions. Only GenericDeviceController carries those, so this trigger never fires on any other controller.",
        fields = {
            { path = { "actionID" }, label = "Action ID", kind = "cname", selector = "customAction", width = 240 }
        }
    },
    {
        class = "TriggerVolumeOperationsTrigger", dataClass = "TriggerVolumeOperationTriggerData",
        label = "Trigger volume enter / exit",
        fields = {
            { path = { "componentName" }, label = "Component", kind = "cname", selector = "component",
              -- Two unrelated branches raise the area events this listens for: the physical trigger
              -- components (`entTriggerComponent` is a *subclass* of `entPhysicalTriggerComponent`,
              -- not the base) and the static area shapes.
              componentFilter = { "entPhysicalTriggerComponent", "gameStaticAreaShapeComponent" }, width = 220,
              hint = "The trigger component whose enter / exit event this listens for. Matched by name against the component that fired." },
            { path = { "operationType" }, label = "Direction", kind = "enum", enum = "ETriggerOperationType" },
            { path = { "isActivatorPlayer" }, label = "Player", kind = "bool" },
            { path = { "isActivatorNPC" }, label = "NPC", kind = "bool" },
            { path = { "canNPCBeDead" }, label = "Dead NPC counts", kind = "bool" }
        }
    },
    {
        class = "InteractionAreaOperationsTrigger", dataClass = "InteractionAreaOperationTriggerData",
        label = "Interaction area enter / exit",
        hint = "Listens to the entity's own gameinteractionsComponent, which most devices already carry -- so this is a proximity trigger that needs no trigger volume. The tag names one of the layers in the component's .interaction descriptor.",
        fields = {
            { path = { "areaTag" }, label = "Area tag", kind = "cname", selector = "interactionTag", width = 240 },
            { path = { "operationType" }, label = "Direction", kind = "enum", enum = "gameinteractionsEInteractionEventType" },
            { path = { "isActivatorPlayer" }, label = "Player", kind = "bool" },
            { path = { "isActivatorNPC" }, label = "NPC", kind = "bool" }
        }
    },
    {
        class = "SensesOperationsTrigger", dataClass = "SensesOperationTriggerData",
        label = "Sensed (seen / heard)",
        fields = {
            { path = { "attitudeGroup" }, label = "Attitude group", kind = "cname", width = 240 },
            { path = { "operationType" }, label = "Direction", kind = "enum", enum = "ETriggerOperationType" },
            { path = { "isActivatorPlayer" }, label = "Player", kind = "bool" },
            { path = { "isActivatorNPC" }, label = "NPC", kind = "bool" }
        }
    },
    {
        class = "HitOperationsTrigger", dataClass = "HitOperationTriggerData",
        label = "Damaged",
        hint = "Fires when health drops below the given percentage.",
        fields = {
            { path = { "healthPercentage" }, label = "Health %", kind = "float" },
            { path = { "bullets" }, label = "Bullets", kind = "bool" },
            { path = { "explosions" }, label = "Explosions", kind = "bool" },
            { path = { "melee" }, label = "Melee", kind = "bool" },
            { path = { "isAttackerPlayer" }, label = "Player", kind = "bool" },
            { path = { "isAttackerNPC" }, label = "NPC", kind = "bool" }
        }
    },
    {
        class = "FocusModeOperationsTrigger", dataClass = "FocusModeOperationTriggerData",
        label = "Scanner (focus mode)",
        fields = {
            { path = { "operationType" }, label = "Direction", kind = "enum", enum = "ETriggerOperationType" },
            { path = { "isLookedAt" }, label = "Looked at", kind = "bool" }
        }
    }
}

---@param class string
---@return table?
function deviceOperations.getOperationType(class)
    for _, entry in ipairs(deviceOperations.OPERATION_TYPES) do
        if entry.class == class then return entry end
    end
    return nil
end

---@param class string
---@return table?
function deviceOperations.getTriggerType(class)
    for _, entry in ipairs(deviceOperations.TRIGGER_TYPES) do
        if entry.class == class then return entry end
    end
    return nil
end

---@param class string
---@return string
function deviceOperations.getOperationLabel(class)
    local entry = deviceOperations.getOperationType(class)
    return entry and entry.label or tostring(class)
end

---@param class string
---@return string
function deviceOperations.getTriggerLabel(class)
    local entry = deviceOperations.getTriggerType(class)
    return entry and entry.label or tostring(class)
end

-- Templates -------------------------------------------------------------------------------------

---Ready-made setups. Each returns `{ operations = {...}, triggers = {...} }` as plain descriptors,
---which the popup turns into real objects; keeping them declarative means the templates cannot drift
---from the schemas above.
deviceOperations.TEMPLATES = {
    {
        id = "soundOnOff",
        label = "Sound on ON / OFF",
        description = "The wiki's fan example: one WWise event started when the device turns on and stopped when it turns off.",
        needsSoundComponent = true,
        build = function (prefix)
            prefix = prefix ~= "" and prefix or "sound"
            local startName, stopName = prefix .. "_start", prefix .. "_stop"
            return {
                operations = {
                    { class = "PlaySoundDeviceOperation", name = startName,
                      set = { { path = { "SFXs" }, listItem = "SSFXOperationData",
                                values = { { path = { "operationType" }, value = "START" } } } } },
                    { class = "PlaySoundDeviceOperation", name = stopName,
                      set = { { path = { "SFXs" }, listItem = "SSFXOperationData",
                                values = { { path = { "operationType" }, value = "STOP" } } } } }
                },
                triggers = {
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "ON" } }, runs = { startName } },
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "OFF" } }, runs = { stopName } }
                }
            }
        end
    },
    {
        id = "vfxOnOff",
        label = "VFX on ON / OFF",
        description = "Starts a named effect when the device turns on and stops it when it turns off.",
        build = function (prefix)
            prefix = prefix ~= "" and prefix or "vfx"
            local startName, stopName = prefix .. "_start", prefix .. "_stop"
            return {
                operations = {
                    { class = "PlayEffectDeviceOperation", name = startName,
                      set = { { path = { "VFXs" }, listItem = "SVFXOperationData",
                                values = { { path = { "operationType" }, value = "START" } } } } },
                    { class = "PlayEffectDeviceOperation", name = stopName,
                      set = { { path = { "VFXs" }, listItem = "SVFXOperationData",
                                values = { { path = { "operationType" }, value = "STOP" } } } } }
                },
                triggers = {
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "ON" } }, runs = { startName } },
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "OFF" } }, runs = { stopName } }
                }
            }
        end
    },
    {
        id = "meshAppearanceOnOff",
        label = "Mesh appearance on ON / OFF",
        description = "Switches the mesh appearance when the device turns on and when it turns off. Pick both appearances afterwards.\n"
            .. "The mesh turns invisible unless its .mesh keeps every appearance loaded (forceLoadAllAppearances).",
        build = function (prefix)
            prefix = prefix ~= "" and prefix or "mesh"
            local onName, offName = prefix .. "_on", prefix .. "_off"
            return {
                operations = {
                    { class = "MeshAppearanceDeviceOperation", name = onName },
                    { class = "MeshAppearanceDeviceOperation", name = offName }
                },
                triggers = {
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "ON" } }, runs = { onName } },
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "OFF" } }, runs = { offName } }
                }
            }
        end
    },
    {
        id = "factRelay",
        label = "Write a quest fact on ON",
        description = "Sets a fact when the device turns on. Another device reads it with a Quest fact trigger, which is the only supported way to make one device affect another.",
        build = function (prefix)
            prefix = prefix ~= "" and prefix or "device"
            local name = prefix .. "_broadcast"
            return {
                operations = {
                    { class = "FactsDeviceOperation", name = name,
                      set = { { path = { "facts" }, listItem = "SFactOperationData",
                                values = {
                                    { path = { "factName" }, value = redValue.cName(prefix .. "_is_on") },
                                    { path = { "factValue" }, value = 1 },
                                    { path = { "operationType" }, value = "Set" }
                                } } } }
                },
                triggers = {
                    { class = "BaseStateOperationsTrigger", values = { { path = { "state" }, value = "ON" } }, runs = { name } }
                }
            }
        end
    }
}

-- Validation ------------------------------------------------------------------------------------

---An operation name with its whitespace folded into underscores.
---
---A trigger reaches an operation only through an exact CName match, so a space makes a name nothing
---can ever reference -- and typing one is the easiest slip to make, because the name reads as a
---label. Converted rather than refused: the intent behind `fan look off` is not in doubt, and a
---field that quietly rejects the keystroke would be harder to understand than one that shows what
---it stored. Runs are collapsed, and the ends trimmed, so no name gains a leading or doubled `_`.
---@param name string?
---@return string
function deviceOperations.sanitizeOperationName(name)
    return (tostring(name or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("%s+", "_"))
end

---@param name string
---@return string? problem
function deviceOperations.checkOperationName(name)
    if name == "" then
        return "Empty name: no trigger can reference this operation."
    end
    if name:find("%s") then
        -- The wiki's headline failure: the trigger fires, the name never matches, and nothing is logged.
        return "Contains whitespace. The match is exact, so this operation will never run."
    end
    return nil
end

---Cross-reference the two arrays.
---@param operationNames string[] Names in `operations` order
---@param referencedNames table<string, boolean> Names any trigger asks for
---@return table<string, boolean> unused Operations nothing references
---@return table<string, boolean> orphans References with no matching operation
---@return table<string, number> duplicates Names carried by more than one operation
function deviceOperations.crossReference(operationNames, referencedNames)
    local counts, unused, orphans, duplicates = {}, {}, {}, {}

    for _, name in ipairs(operationNames) do
        counts[name] = (counts[name] or 0) + 1
    end

    for name, count in pairs(counts) do
        if not referencedNames[name] then unused[name] = true end
        -- Not a fault: `Execute` runs *every* operation whose name matches, so sharing a name is how
        -- one trigger fans out to several operations. Surfaced as information, not a warning.
        if count > 1 then duplicates[name] = count end
    end

    for name, _ in pairs(referencedNames) do
        if not counts[name] then orphans[name] = true end
    end

    return unused, orphans, duplicates
end

---@param spawnable table entity spawnable
---@return boolean
function deviceOperations.hasSoundComponent(spawnable)
    for _, component in pairs(spawnable.defaultComponentData or {}) do
        if type(component) == "table" and component["$type"] == deviceOperations.SOUND_COMPONENT_CLASS then
            return true
        end
    end
    return false
end

-- Selector sources --------------------------------------------------------------------------------
--
-- Everything a device operation names -- a component, a clip, an effect, a sound -- is matched
-- exactly at runtime and does nothing at all when it is wrong, with no log line. The values are
-- therefore read back off the thing being edited rather than typed.
--
-- The **live entity** is the source, not `defaultComponentData`: that table holds only the PS
-- controller until something forces a full instance-data load, so a list built from it is empty on a
-- freshly spawned device. The converted data is kept as a fallback for the window between a project
-- load and the entity being up.

---Does `className` derive from `baseName` (or equal it)?
---@param className string?
---@param baseName string?
---@return boolean
function deviceOperations.classDerivesFrom(className, baseName)
    if type(className) ~= "string" or className == "" then return false end
    if type(baseName) ~= "string" or baseName == "" then return false end
    if className == baseName then return true end

    local derives = false
    pcall(function ()
        local class = Reflection.GetClass(className)
        while class do
            if class:GetName().value == baseName then
                derives = true
                return
            end
            class = class:GetParent()
        end
    end)

    return derives
end

---@param spawnable table? entity spawnable
---@return table? components The live component list, or nil when the entity is not up
local function getLiveComponents(spawnable)
    if type(spawnable) ~= "table" or type(spawnable.getEntity) ~= "function" then return nil end

    local entityRef = spawnable:getEntity()
    if not entityRef then return nil end

    local components = nil
    if not pcall(function () components = entityRef:GetComponents() end) then return nil end

    return components
end

---@param names string[]
---@return string[] names The same list, sorted case-insensitively
local function sortedNames(names)
    table.sort(names, function (a, b) return a:lower() < b:lower() end)
    return names
end

---@param filter string|string[]|nil
---@return string[] classes Normalized to a list, empty when there is no filter
local function filterClasses(filter)
    if type(filter) == "string" then return { filter } end
    if type(filter) == "table" then return filter end

    return {}
end

---A readable name for a component filter, for the "this entity has none" note.
---@param filter string|string[]|nil
---@return string
function deviceOperations.describeComponentFilter(filter)
    return table.concat(filterClasses(filter), " or ")
end

---Component names on the entity, and the class each name resolves to.
---
---The class is carried alongside because the name alone does not say what a component is: a device
---routinely holds a dozen of them with names like `mesh1`, `trigger` or `audio`, and a field that
---only accepts one kind -- the Bink component, the trigger area component -- silently does nothing
---when the name picked is the wrong sort of thing. Showing the class turns that into something the
---author can see before they commit to a name.
---@param spawnable table entity spawnable
---@param filter string|string[]|nil Only components deriving from this class (or any of these)
---@return string[] names Sorted case-insensitively
---@return table<string, string> classes name -> RTTI class name
function deviceOperations.getComponents(spawnable, filter)
    local names, seen, componentClasses = {}, {}, {}
    local classes = filterClasses(filter)

    local function add(name, className)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        seen[name] = true
        table.insert(names, name)
        if type(className) == "string" and className ~= "" then
            componentClasses[name] = className
        end
    end

    local components = getLiveComponents(spawnable)

    if components then
        for _, component in pairs(components) do
            local matches = #classes == 0

            for _, class in ipairs(classes) do
                local ok, isA = pcall(function () return component:IsA(class) end)
                if ok and isA then
                    matches = true
                    break
                end
            end

            if matches then
                -- Read apart, so a component whose class cannot be read is still listed under its
                -- name rather than dropped out of the picker entirely.
                local componentName, className = nil, nil
                pcall(function () componentName = component.name.value end)
                pcall(function () className = component:GetClassName().value end)

                add(componentName, className)
            end
        end

        return sortedNames(names), componentClasses
    end

    for _, component in pairs(type(spawnable) == "table" and spawnable.defaultComponentData or {}) do
        if type(component) == "table" and type(component.name) == "table" then
            local matches = #classes == 0

            for _, class in ipairs(classes) do
                if deviceOperations.classDerivesFrom(component["$type"], class) then
                    matches = true
                    break
                end
            end

            if matches then
                add(tostring(component.name["$value"] or ""), component["$type"])
            end
        end
    end

    return sortedNames(names), componentClasses
end

---Transform animation clip names, from the entity's animator component.
---@param spawnable table entity spawnable
---@return string[]
function deviceOperations.getAnimationNames(spawnable)
    local names, seen = {}, {}

    local function add(name)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        seen[name] = true
        table.insert(names, name)
    end

    local components = getLiveComponents(spawnable)

    if components then
        for _, component in pairs(components) do
            for _, animatorClass in ipairs(deviceOperations.ANIMATOR_COMPONENT_CLASSES) do
                local ok, isA = pcall(function () return component:IsA(animatorClass) end)

                if ok and isA then
                    pcall(function ()
                        for _, definition in pairs(component.animations) do
                            add(definition.name.value)
                        end
                    end)
                    break
                end
            end
        end

        if #names > 0 then return sortedNames(names) end
    end

    -- Converted instance data, for the frames before the entity is up. `listDefinitionNames` reads
    -- the same array in its JSON shape, so the Motion panel and this one cannot disagree.
    local componentID = transformAnimations.findAnimatorComponentID(spawnable)

    if componentID then
        local source = (spawnable.instanceDataChanges or {})[componentID]
            or (spawnable.defaultComponentData or {})[componentID]

        for _, name in ipairs(transformAnimations.listDefinitionNames(type(source) == "table" and source.animations or nil)) do
            add(name)
        end
    end

    return sortedNames(names)
end

---Effect names registered on the entity's effect spawner components.
---
---`PlayEffectDeviceOperation` reaches these through `GameObjectEffectHelper.StartEffectEvent`, which
---looks the name up in exactly this list. (It also has a `vfxResource` path that spawns a resource
---directly, but that field is a resource token this panel does not author.)
---@param spawnable table entity spawnable
---@return string[]
function deviceOperations.getEffectNames(spawnable)
    local names, seen = {}, {}

    local function add(name)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        seen[name] = true
        table.insert(names, name)
    end

    local components = getLiveComponents(spawnable)

    if components then
        for _, component in pairs(components) do
            local ok, isA = pcall(function ()
                return component:IsA(deviceOperations.EFFECT_COMPONENT_CLASS)
            end)

            if ok and isA then
                pcall(function ()
                    for _, descriptor in pairs(component.effectDescs) do
                        add(descriptor.effectName.value)
                    end
                end)
            end
        end

        return sortedNames(names)
    end

    for _, component in pairs(type(spawnable) == "table" and spawnable.defaultComponentData or {}) do
        if type(component) == "table" and component["$type"] == deviceOperations.EFFECT_COMPONENT_CLASS then
            for _, descriptor in ipairs(type(component.effectDescs) == "table" and component.effectDescs or {}) do
                local descriptorData = type(descriptor) == "table" and descriptor.Data or descriptor
                if type(descriptorData) == "table" then
                    add(redValue.readCName(descriptorData.effectName))
                end
            end
        end
    end

    return sortedNames(names)
end

---Resolved mesh references, so rebuilding the picker's list costs a table lookup rather than a
---`ResRef` round trip per component per frame. Keyed by hash string or depot path, whichever the
---component gave; `false` marks a reference that never resolved.
---@type table<string, table|false>
local meshRefCache = {}

---@param hash any? A `raRef` hash, from a live component
---@param path string? A depot path, from converted instance data
---@return table? ref `{ key, path, resRef }`
local function resolveMeshRef(hash, path)
    local lookup = (type(path) == "string" and path ~= "") and path or (hash and tostring(hash) or nil)
    if not lookup then return nil end

    local cached = meshRefCache[lookup]
    if cached ~= nil then return cached or nil end

    local resRef = nil

    if type(path) == "string" and path ~= "" then
        pcall(function () resRef = ResRef.FromString(path) end)
    else
        pcall(function ()
            resRef = ResRef.FromHash(hash)
            path = resRef:ToString()
        end)
    end

    if not resRef then
        meshRefCache[lookup] = false
        return nil
    end

    local hasPath = type(path) == "string" and path ~= ""
    local ref = {
        -- A mesh whose hash resolves to no readable path still loads by hash, so the hash stays the
        -- key then -- it just cannot share the persistent, path-keyed appearance cache.
        key = hasPath and path or lookup,
        path = hasPath and path or nil,
        resRef = resRef
    }

    meshRefCache[lookup] = ref

    return ref
end

---The mesh components on the entity, as `{ name, key, path, resRef }` records.
---@param spawnable table entity spawnable
---@return table[]
local function getMeshSources(spawnable)
    local sources = {}

    local function add(name, hash, path)
        local ref = resolveMeshRef(hash, path)
        if not ref then return end

        table.insert(sources, {
            name = type(name) == "string" and name or "",
            key = ref.key,
            path = ref.path,
            resRef = ref.resRef
        })
    end

    local components = getLiveComponents(spawnable)

    if components then
        for _, component in pairs(components) do
            for _, meshClass in ipairs(deviceOperations.MESH_COMPONENT_CLASSES) do
                local ok, isA = pcall(function () return component:IsA(meshClass) end)

                if ok and isA then
                    -- The name is only the annotation on the appearances this mesh offers, so a
                    -- component that will not give one still contributes its appearance list.
                    local componentName, meshHash = nil, nil
                    pcall(function () componentName = component.name.value end)
                    pcall(function () meshHash = component.mesh.hash end)

                    add(componentName, meshHash, nil)
                    break
                end
            end
        end

        return sources
    end

    for _, component in pairs(type(spawnable) == "table" and spawnable.defaultComponentData or {}) do
        if type(component) == "table" and type(component.mesh) == "table" then
            local isMesh = false

            for _, meshClass in ipairs(deviceOperations.MESH_COMPONENT_CLASSES) do
                if deviceOperations.classDerivesFrom(component["$type"], meshClass) then
                    isMesh = true
                    break
                end
            end

            -- Only the readable form: a `uint64` storage holds the hash as a JSON number, which is
            -- not a path and would load nothing if handed to `ResRef.FromString`. The live entity
            -- covers that case, and this branch only runs before it is up.
            if isMesh and type(component.mesh.DepotPath) == "table"
                and tostring(component.mesh.DepotPath["$storage"] or "string") == "string" then
                add(
                    type(component.name) == "table" and tostring(component.name["$value"] or "") or "",
                    nil,
                    tostring(component.mesh.DepotPath["$value"] or "")
                )
            end
        end
    end

    return sources
end

---Every mesh appearance this entity's components can be switched to.
---
---`MeshAppearanceDeviceOperation` queues one `entAppearanceEvent` with no `componentName`, so the
---name reaches every mesh component at once and only the ones whose `.mesh` owns an appearance by
---that name react. The vocabulary is therefore the union over the entity's meshes, not one mesh's
---list -- and a name only some of them carry is a legitimate authoring choice, which is why the
---owning components are reported alongside rather than used to narrow the list.
---
---Reading it means loading each `.mesh`, which is asynchronous: the first frames return whatever is
---cached already and `pending` true, and the list fills in as the loads land.
---@param spawnable table entity spawnable
---@return string[] names Sorted case-insensitively
---@return table<string, string[]> owners appearance name -> the components offering it
---@return boolean pending At least one mesh is still loading
---@return number meshCount How many mesh components were found
function deviceOperations.getMeshAppearanceNames(spawnable)
    local names, seen, owners = {}, {}, {}
    local pending = false
    local sources = getMeshSources(spawnable)

    for _, source in ipairs(sources) do
        local apps = builder.getMeshAppearances(source.key, source.path, source.resRef)

        if not apps then
            pending = true
        else
            for _, app in ipairs(apps) do
                if type(app) == "string" and app ~= "" then
                    if not seen[app] then
                        seen[app] = true
                        table.insert(names, app)
                        owners[app] = {}
                    end

                    if source.name ~= "" then
                        table.insert(owners[app], source.name)
                    end
                end
            end
        end
    end

    return sortedNames(names), owners, pending, #sources
end

---The custom action IDs this device declares.
---
---There is no shared vocabulary for these: each is invented by whoever authored the device, in
---`GenericDeviceControllerPS.genericDeviceActionsSetup.customActions.actions[].actionID`. A sweep of
---all 21,661 shipped `.ent` files found only 175 devices carrying any, with ~105 distinct names, and
---the same concept spelled several ways across them (`Take`/`take`, `Loot`/`loot`/`LootID`,
---`quickhack`/`Quickhack`) -- which is the proof that no convention exists to guess from. The list
---has to come off the device being edited.
---@param entries table[]? The `customActions.actions` array in its converted JSON form
---@return string[]
function deviceOperations.readCustomActionIDs(entries)
    local names, seen = {}, {}

    for _, entry in ipairs(type(entries) == "table" and entries or {}) do
        local action = type(entry) == "table" and (entry.Data or entry) or nil
        local name = type(action) == "table" and redValue.readCName(action.actionID) or ""

        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end

    return sortedNames(names)
end

---Every TweakDB ID of one record class, sorted.
---
---Cached per class and built lazily: `gamedataItem_Record` alone is tens of thousands of rows, and
---the search dropdown clips what it draws, so the cost is paid once when a picker is first shown.
---@type table<string, string[]>
local recordNameCache = {}

---@param recordClass string e.g. `gamedataItem_Record`
---@return string[]
function deviceOperations.getRecordNames(recordClass)
    if type(recordClass) ~= "string" or recordClass == "" then return {} end

    local cached = recordNameCache[recordClass]
    if cached then return cached end

    local names = {}
    pcall(function ()
        for _, record in pairs(TweakDB:GetRecords(recordClass)) do
            local id = record:GetID().value
            if type(id) == "string" and id ~= "" then
                table.insert(names, id)
            end
        end
    end)

    table.sort(names)
    recordNameCache[recordClass] = names

    return names
end

---Drops the cached record lists and mesh appearance lists, so a TweakDB or archive reload is
---picked up.
function deviceOperations.invalidate()
    recordNameCache = {}
    builder.invalidateMeshAppearances()
    meshRefCache = {}
end

return deviceOperations
