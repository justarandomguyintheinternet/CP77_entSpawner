# World Builder

## Overview

- World Builder is a modding tool for Cyberpunk 2077, which is focused on allowing for additions to the game-world, in a native way that is as close as possible to the game.
- By default World Builder has [access to all game-resources](https://app.gitbook.com/o/-MP5ijqI11FeeX7c8-N8/s/4gzcGtLrr90pVjAWVdTc/modding-guides/world-editing/object-spawner/supported-nodes) (E.g. Entities, Meshes, Decals, Sounds...), additionally any custom resources can be made available for spawning.
- World Builder's also allows for more "Meta" type additions, such as reflection probes, area nodes (E.g. for interior audio muffling), community nodes (NPC groups that can be configured based on time of day) and much more.
- World Builder tries to stay as close as possible to the way the engine handles the game world, thus each type of object (Mesh, entity, light, etc.) directly corresponds to a type of `worldNode`

---

## Installation
- [Installation guide on the wiki](https://app.gitbook.com/o/-MP5ijqI11FeeX7c8-N8/s/4gzcGtLrr90pVjAWVdTc/modding-guides/world-editing/object-spawner/installation)

---
## Wiki
- A wide range of guides, explaining everything from installation, over basic usage, to specific features can be found on the modding Wiki:
# [World Builder Wiki](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner)

---

## Spawning Objects

- [Wiki section](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner/ui-tabs-explained/tab-spawn-new)
1. **Open the world builder tool**.
2. **Select the appropriate category** (Such as entity, mesh, collision, deco).
3. **Select the specific type of object** E.g. for the `Mesh` category you can select between normal mesh, rotating mesh, cloth mesh and dynamic mesh
4. **Spawn the object** using the interface.

---

## Grouping and Saving

1. **Group your objects** in the interface, `Spawned` tab.
2. **Save the group to a file**. This will prepare the objects for export into an AXL mod.
- Hint: Each saved group will later correspond to one individual streamingsector

---

## Converting to Standalone AXL Mod

- See the [Guide on the wiki](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/exporting-from-object-spawner)

---

## Adding Custom Entities/Meshes

- [Wiki Guide](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner/features-and-guides/adding-custom-resources-props)
- Generally, you can make any type of custom resource (Like material files for decals, or particle files) available by creating a `.txt` file in the corresponding `entSpawner\\data\\spawnables\\...` folder
- In the following the exact steps for meshes and entities will be explained

### For Entities:

1. Navigate to the following directory:  
   `entSpawner\\data\\spawnables\\entity\\templates`
2. Create a new `.txt` file with your custom entity paths and save it in this folder.

### For Meshes:

1. Navigate to the following directory:  
   `entSpawner\\data\\spawnables\\mesh\\all`
2. Create a new `.txt` file with your custom mesh paths and save it in this folder.

---

## Troubleshooting

- Ensure you have the latest version of the tool, as well as the latest version of all the requirements
- In case of issues with the UI, deleting `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\entSpawner\data\config.json` might help
- Custom entity or mesh is lacking appearances? Read up on [cache exclusions](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/object-spawner/features-and-guides/adding-custom-resources-props#cache-exclusions)

## Contact and Support
- For feature requests / questions and troubleshooting, either use:
   - GitHub issues
   - Ask on the [Cyberpunk 2077 Modding Community](https://discord.gg/redmodding) discord server, in the `#world-editing` channel
   - DM `keanuwheeze` via discord
- For troubleshooting, provide the following:
   - What is not working
   - What would you expect to happen
   - When does the bug occur (Ideally step by step on how you can recreate the bug)
   - `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\entSpawner\entSpawner.log` file
   - Build file, if bug is related to specifc build (Found in `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\entSpawner\data\objects`)
   - Game version, tool version, requirements versions
   - Any images or videos of the bug
