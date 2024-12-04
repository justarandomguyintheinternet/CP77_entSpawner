# CP77_entSpawner

# Object Spawner - Readme

## Overview

- Object Spawner is a dev tool that simplifies the process of spawning in-game objects (Entities), meshes, lights, collisions and more, for your modding projects. With this tool, you can set up objects, save groups, and convert them into standalone AXL mods. This guide will walk you through the installation process, adding custom entities or meshes, spawning them, and converting them into AXL mods
- By default Object Spawner is capable of spawning any entity, mesh, decal, effect and sound which is already part of the game
- Object Spawner tries to stay as close as possible to the way the engine handles the game world, thus each type of object (Mesh, entity, light, etc.) directly corresponds to a type of `worldNode`

---

## Installation

1. Download and install the provided ZIP file. Extract the contents into the base game directory.

---

## Spawning Objects

1. **Open the object spawner tool**.
2. **Select the appropriate category** (Such as entity, mesh, collision, deco).
3. **Select the specific type of object** E.g. for the `Mesh` category you can select between normal mesh, rotating mesh, cloth mesh and dynamic mesh
4. **Spawn the object** using the interface.

---

## Grouping and Saving

1. **Group your objects** in the spawner.
2. **Save the group to a file**. This will prepare the objects for export into an AXL mod.
- Hint: Each saved group will later correspond to one individual streamingsector

---

## Converting to Standalone AXL Mod

### Requirements:

- **WKit version 18.14.1** or newer is required.

### Steps to Convert:

#### 1. Exporting from Object Spawner
1. In Game Open **Object Spawner 2.0**.
2. Go to the **"Saved" tab** in the Object Spawner and find your saved group(s).
3. **Click "Add to Export"** to mark the group(s) for export.
4. Switch to the **"Export" tab** and configure the export settings:
   - Set the **sector range** and other relevant parameters for your mod.
   - The **sector range** should be at least as big as the smallest individual streaming range of an object (Better to go big)
5. **Click Export**.

#### 2. Importing in WKit
1. Open **Wkit**
2. **Update your WKit scripts** using the WKit "Scripts" UI.
3. Put exported json into raw folder in your **Wkit project**.
4. Go to `Tools -> Script Manager`
5. Double click `import_object_spawner` (Yes to Create local copy)
6. Replace `new_project_exported.json` with the name of your exported file placed in raw
7. Click `Run` in the script
8. **Profit!**

---

## Adding Custom Entities/Meshes

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

## Additional Notes

- **Initial Setup**: Most of the setup steps, such as adding custom paths and configuring WKit, are only needed the first time you use the tool. Afterward, the process will be streamlined and much quicker.
- **Rotating Mesh**: If you want to spawn rotating meshes, make sure to select that option in the spawner interface.

---

## Troubleshooting

- **WKit Version**: Ensure you have the correct version of **WKit (18.14.1 or newer)** to avoid compatibility issues when exporting.
- **Script Updates**: If you experience any issues with the spawner, double-check that you have updated your scripts in WKit.
- **File Import**: Make sure you import the correct exported file when converting the saved group to an AXL mod.
- ![Update scripts](https://snipboard.io/pAOlYn.jpg) **Check Step 7**

---

## Conclusion

The Object Spawner tool is designed to simplify modding workflows by streamlining object spawning and export processes. With just a few steps, you can create interactive in-game objects and convert them into AXL mods for standalone use. While the process may seem detailed, most of the steps only require a one-time setup. Enjoy your modding!

---

### Contact & Support

If you encounter any issues or have questions about the Object Spawner, please refer to the support documentation or reach out to the community for assistance.

---
