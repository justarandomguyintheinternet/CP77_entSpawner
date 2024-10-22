# CP77_entSpawner

# Object Spawner - Readme

## Overview

The **Object Spawner** is a dev tool that simplifies the process of spawning in-game objects, meshes, or entities for your modding projects. With this tool, you can set up objects, save groups, and convert them into standalone AXL mods. This guide will walk you through the installation process, adding custom entities or meshes, spawning them, and converting them into AXL mods.

---

## Installation

1. Download and install the provided ZIP file. Extract the contents into a directory of your choice.

---

## Adding Custom Entities/Meshes

Depending on the type of object you want to spawn (entity or mesh), follow these steps:

### For Entities:

1. Navigate to the following directory:  
   `entSpawner\\data\\spawnables\\entity\\templates`

2. You can either:
   - Add the path to your custom entity in the existing file in this folder.
   - Or, create a new `.txt` file with your custom entity paths and save it in this folder.

### For Meshes:

1. Navigate to the following directory:  
   `entSpawner\\data\\spawnables\\mesh\\all`

2. Similar to the entity process, you can:
   - Add the path to your custom mesh in the existing file in this folder.
   - Or, create a new `.txt` file with your custom mesh paths and save it in this folder.

---

## Spawning Objects

Once your custom entities or meshes are added:

1. **Open the object spawner tool**.
2. **Select the appropriate category** (entity or mesh).
3. **Spawn the object** using the interface.
   - If desired, you can even spawn it as a **rotating mesh**.

---

## Grouping and Saving

1. **Group your objects** in the spawner.
2. **Save the group to a file**. This will prepare the objects for export into an AXL mod.

---

## Converting to Standalone AXL Mod

### Requirements:

- **WKit version 18.14.1** or newer is required.

### Steps to Convert:

1. In Game Open **Object Spawner 2.0**.
2. Go to the **"Saved" tab** in the Object Spawner and find your saved group.
3. **Click "Add to Export"** to mark the group for export.
4. Switch to the **"Export" tab** and configure the export settings:
   - Set the **sector range** and other relevant parameters for your mod.
5. **Click Export**.
6. Open **Wkit**
7. **Update your WKit scripts** using the WKit "Scripts" UI.
8. Put exported json into raw folder in your **Wkit project**. Open **Log** tab select **import_object_spawner** script and hit run. ![](https://snipboard.io/rcTWtf.jpg)
9. **Profit!**

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
