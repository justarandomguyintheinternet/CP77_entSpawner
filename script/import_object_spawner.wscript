// Imports an entitySpawner json export
// @author keanuwheeze
// @version 0.95

//////////////// Modify this //////////////////

const inputFilePathInRawFolder = "new_project_exported.json"

///////////////////////////////////////////////

import * as Logger from 'Logger.wscript';

const header = {
  "Header": {
    "WolvenKitVersion": "8.14.1",
    "WKitJsonVersion": "0.0.8",
    "DataType": "CR2W",
  },
  "Data": {
    "Version": 195,
    "BuildVersion": 0,
    "RootChunk": {},
    "EmbeddedFiles": []
  }
}

// Helpers

const createNewFile = (type) => {
	let file = JSON.parse(JSON.stringify(header))
    file.Data.RootChunk = JSON.parse(wkit.CreateInstanceAsJSON(type))
	return file
}

const getNewSector = () => {
	let data = createNewFile("worldStreamingSector")
	data.Data.RootChunk.nodeData.Type = "WolvenKit.RED4.Archive.Buffer.worldNodeDataBuffer, WolvenKit.RED4, Version=8.13.0.0, Culture=neutral, PublicKeyToken=null"
	data.Data.RootChunk.nodeData.Data = []
	return data
}

const getNewDeviceFile = () => {
	let data = createNewFile("gameDeviceResource")
	data.Data.RootChunk.data = { "Data": { "$type": "gameDeviceResourceData", "unk1" : [], "version": 2 } }

	return data
}

const getNewPSFile = () => {
	let data = createNewFile("gamePersistentStateDataResource")
	data.Data.RootChunk.buffer = {
		"BufferId": "0",
		"Flags": 4063232,
        "Type": "WolvenKit.RED4.Archive.Buffer.RedPackage, WolvenKit.RED4, Version=8.15.1.0, Culture=neutral, PublicKeyToken=null",
        "Data": {
          "Version": 4,
          "Sections": 6,
          "CruidIndex": 0,
          "CruidDict": {},
          "Chunks": []
        }
	}

	return data
}

const getNewBlock = () => {
	return createNewFile("worldStreamingBlock")
}

const getNewWorldNodeData = () => {
	let data = { "Id": "0", "NodeIndex": 0, "Position": { "$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0 }, "Orientation": { "$type": "Quaternion", "i": 0, "j": 0, "k": 0, "r": 1 }, "Scale": { "$type": "Vector3", "X": 0, "Y": 0, "Z": 0 }, "Pivot": { "$type": "Vector3", "X": 0, "Y": 0, "Z": 0 }, "Bounds": { "$type": "Box", "Max": { "$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0 }, "Min": { "$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0 } }, "QuestPrefabRefHash": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" }, "UkHash1": { "$type": "NodeRef", "$storage": "uint64", "$value": "0" }, "CookedPrefabData": { "DepotPath": { "$type": "ResourcePath", "$storage": "uint64", "$value": "0" }, "Flags": "Default" }, "MaxStreamingDistance": 0, "UkFloat1": 0, "Uk10": 0, "Uk11": 0, "Uk12": 0, "Uk13": "0", "Uk14": "0" }
    return JSON.parse(JSON.stringify(data))
}

const deepCopy = (origin, target) => {
    for (let key in origin) {
        if (typeof origin[key] === 'object' && origin[key] !== null) {
            if (!target[key]) {
                target[key] = Array.isArray(origin[key]) ? [] : {};
            }
            deepCopy(origin[key], target[key]);
        } else {
            target[key] = origin[key];
        }
    }
}

const insertNode = (sector, node) => {
	let nodeData = getNewWorldNodeData()
	
	nodeData.NodeIndex = sector.Data.RootChunk.nodes.length
	
	// Position
	nodeData.Position.X = node.position.x
	nodeData.Position.Y = node.position.y
	nodeData.Position.Z = node.position.z
	
	// Streaming values
	nodeData.MaxStreamingDistance = node.secondaryRange
	nodeData.UkFloat1 = node.primaryRange
	nodeData.Uk10 = node.uk10
	nodeData.Uk11 = node.uk11
	
	// Pivot
	nodeData.Pivot.X = node.position.x
	nodeData.Pivot.Y = node.position.y
	nodeData.Pivot.Z = node.position.z
	
	// Bounds
	nodeData.Bounds.Max.X = node.position.x
	nodeData.Bounds.Max.Y = node.position.y
	nodeData.Bounds.Max.Z = node.position.z

	nodeData.Bounds.Min.X = node.position.x
	nodeData.Bounds.Min.Y = node.position.y
	nodeData.Bounds.Min.Z = node.position.z

	// Scale
	nodeData.Scale.X = node.scale.x
	nodeData.Scale.Y = node.scale.y
	nodeData.Scale.Z = node.scale.z
	
	// Rotation
	nodeData.Orientation.i = node.rotation.i
	nodeData.Orientation.j = node.rotation.j
	nodeData.Orientation.k = node.rotation.k
	nodeData.Orientation.r = node.rotation.r
	
	// NodeRef
	if (node.nodeRef !== undefined && node.nodeRef !== "") {
		nodeData.QuestPrefabRefHash.$storage = "string"
		nodeData.QuestPrefabRefHash.$value = node.nodeRef
		sector.Data.RootChunk.nodeRefs.push({
			"$type": "NodeRef",
			"$storage": "string",
			"$value": node.nodeRef
		})
	} else {
		nodeData.QuestPrefabRefHash.$value = wkit.HashString(JSON.stringify(nodeData), "fnv1a64").toString()
	}

	sector.Data.RootChunk.nodeData.Data.push(nodeData)
	
	let worldNode = JSON.parse(wkit.CreateInstanceAsJSON(node.type))
	
	sortInstanceData(node.data)
	deepCopy(node.data, worldNode)

	// Debug name for wkit
	worldNode.debugName.$value = node.name || ""

	sector.Data.RootChunk.nodes.push({HandleId : sector.Data.RootChunk.nodes.length.toString() , Data : worldNode})
}

const createSectorFromData = (data) => {
	let sector = getNewSector()
	sector.Data.RootChunk.category = data.category
	sector.Data.RootChunk.level = data.level
	sector.Data.RootChunk.variantIndices = [0]
	sector.Data.RootChunk.version = 62
	
	return sector
}

const addSectorToBlock = (block, info, root) => {
	let descriptor = JSON.parse(wkit.CreateInstanceAsJSON("worldStreamingSectorDescriptor"))
	descriptor.category = info.category
	descriptor.level = info.level
	descriptor.numNodeRanges = 1
	
	descriptor.streamingBox.Max.X = info.max.x
	descriptor.streamingBox.Max.Y = info.max.y
	descriptor.streamingBox.Max.Z = info.max.z
	
	descriptor.streamingBox.Min.X = info.min.x
	descriptor.streamingBox.Min.Y = info.min.y
	descriptor.streamingBox.Min.Z = info.min.z
	
	descriptor.data.DepotPath.$storage = "string"
	descriptor.data.DepotPath.$value = `${root}/sectors/${info.name}.streamingsector`
	
	block.Data.RootChunk.descriptors.push(descriptor)
}

const sortInstanceData = (data) => {
	if (data["instanceData"]) {
		const instanceDataSorted = []

		for (const dictKey in data["instanceData"]["Data"]["buffer"]["Data"]["CruidDict"]) {
			for (const dataEntry of data["instanceData"]["Data"]["buffer"]["Data"]["Chunks"]) {
				if (dataEntry["id"] === data["instanceData"]["Data"]["buffer"]["Data"]["CruidDict"][dictKey]) {
					instanceDataSorted.push(dataEntry)
				}
			}
		}

		data["instanceData"]["Data"]["buffer"]["Data"]["Chunks"] = instanceDataSorted
	}
}

//TODO: Put these in a list
// BufferID - Flags - Type - Data

const reorderJSONByType = (data) => {
    if (Array.isArray(data)) {
        return data.map(reorderJSONByType)
    } else if (data !== null && typeof data === "object") {
        const reordered = {};
        const keys = Object.keys(data);

        if (keys.includes("$type")) {
            reordered["$type"] = data["$type"];
        }
		if (keys.includes("ShapeType")) {
            reordered["ShapeType"] = data["ShapeType"];
        }
        if (keys.includes("BufferId")) {
            reordered["BufferId"] = data["BufferId"];
        }
        if (keys.includes("Flags")) {
            reordered["Flags"] = data["Flags"];
        }
        if (keys.includes("Type")) {
            reordered["Type"] = data["Type"];
        }

        for (let key of keys) {
            if (key !== "$type" && key !== "ShapeType" && key !== "Type" && key !== "BufferId" && key !== "Flags") {
                reordered[key] = reorderJSONByType(data[key]);
            }
        }

        return reordered;
    } else {
        return data;
    }
}

// Main import logic
export function RunEntitySpawnerImport(filePath = inputFilePathInRawFolder, calledFromExternal = false) {
	if (!calledFromExternal && (!filePath || !wkit.FileExistsInRaw(filePath))) {
		return;
	}
	
	Logger.Success(`Starting to import ${filePath}`);
	let data = JSON.parse(wkit.LoadRawJsonFromProject(inputFilePathInRawFolder, "json"))

	data = reorderJSONByType(data)

	if (data == null) {
		Logger.Error(`File ${inputFilePathInRawFolder} does not exist / wrong format!`)
	} else {
		let block = getNewBlock()

		data.sectors.forEach((entry) => {
			addSectorToBlock(block, entry, data.name)
			let sector = createSectorFromData(entry)

			entry.nodes.forEach((node) => {
				insertNode(sector, node)
			})

			wkit.SaveToProject(`${data.name}/sectors/${entry.name}.streamingsector`, wkit.JsonToCR2W(JSON.stringify(sector)))
		})

		let devices = getNewDeviceFile()

		for (const [hash, device] of Object.entries(data.devices)) {
			devices.Data.RootChunk.data.Data.unk1.push({
				"$type": "gameDeviceResourceData_Cls1",
				"children": device.children,
				"className": {
					"$type": "CName",
					"$storage": "string",
					"$value": device.className
				},
				"hash": device.hash,
				"nodePosition": {
					"$type": "Vector3",
					"X": device.nodePosition.x,
					"Y": device.nodePosition.y,
					"Z": device.nodePosition.z
				},
				"parents": device.parents
			})
		}
		wkit.SaveToProject(`${data.name}/custom_devices.devices`, wkit.JsonToCR2W(JSON.stringify(devices)))

		let ps = getNewPSFile()
		let index = 0
		for (const [_, entry] of Object.entries(data.psEntries)) {
			ps.Data.RootChunk.buffer.Data.Chunks.push(entry.instanceData)
			ps.Data.RootChunk.buffer.Data.CruidDict[index.toString()] = entry.PSID
			index++
		}
		wkit.SaveToProject(`${data.name}/custom_devices.psrep`, wkit.JsonToCR2W(JSON.stringify(ps)))

		let xl = {
			streaming: {
				blocks: [
					`${data.name}/all.streamingblock`
				]
			},
			resource: {
				patch : {
					[`${data.name}/custom_devices.devices`] : [
						"base\\worlds\\03_night_city\\_compiled\\default\\03_night_city.devices"
					],
					[`${data.name}/custom_devices.psrep`] : [
						"base\\worlds\\03_night_city\\_compiled\\default\\03_night_city.psrep"
					]
				}
			}
		}
		wkit.SaveToResources(`${data.name}.xl`, wkit.JsonToYaml(JSON.stringify(xl)))
		wkit.SaveToProject(`${data.name}/all.streamingblock`, wkit.JsonToCR2W(JSON.stringify(block)))

		Logger.Success("Import finished.")
	}
}

RunEntitySpawnerImport();