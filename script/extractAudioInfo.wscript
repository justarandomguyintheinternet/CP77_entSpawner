import * as Logger from 'Logger.wscript';

const extractSettingsInfo = (settings) => {
    return {
    	onEnter : settings.Data.EventsOnEnter.map((event) => event.event["$value"]),
        onActive : settings.Data.EventsOnActive.map((event) => event.event["$value"]),
        onExit : settings.Data.EventsOnExit.map((event) => event.event["$value"]),
        parameters : settings.Data.Parameters.map((parameter) => parameter.name["$value"]),
        reverb : settings.Data.Reverb["$value"]
    }
}

const extractSignpostInfo = (signpost) => {
    return {
        enter : signpost.enterSignpost["$value"],
        exit : signpost.exitSignpost["$value"]
    }
}

let staticData = {
    onEnter : new Map(),
    onActive : new Map(),
    onExit : new Map(),
    parameters : new Map(),
    reverb : new Map()
}
let ambientData = {
    onEnter : new Map(),
    onActive : new Map(),
    onExit : new Map(),
    parameters : new Map(),
    reverb : new Map()
}
let staticMetadata = new Map()
let ambientMetadata = new Map()
let ambientQuad = new Map()
let signposts = {
    enter : new Map(),
    exit : new Map()
}

let doneSectors = ""
let nDone = 0
let saveInterval = 100

const save = (ambientData, staticData, staticMetadata, ambientMetadata, signposts, ambientQuad) => {
    wkit.SaveToRaw(`ambientData.json`, JSON.stringify({
        onEnter: Array.from(ambientData.onEnter.keys()),
        onActive: Array.from(ambientData.onActive.keys()),
        onExit: Array.from(ambientData.onExit.keys()),
        parameters: Array.from(ambientData.parameters.keys()),
        reverb: Array.from(ambientData.reverb.keys())
    }))

    wkit.SaveToRaw(`staticData.json`, JSON.stringify({
        onEnter: Array.from(staticData.onEnter.keys()),
        onActive: Array.from(staticData.onActive.keys()),
        onExit: Array.from(staticData.onExit.keys()),
        parameters: Array.from(staticData.parameters.keys()),
        reverb: Array.from(staticData.reverb.keys())
    }))

    wkit.SaveToRaw(`staticMetadata.json`, JSON.stringify(Array.from(staticMetadata.entries()).map(([metadata, events]) => ({metadata, events}))))
    wkit.SaveToRaw(`ambientMetadata.json`, JSON.stringify(Array.from(ambientMetadata.entries()).map(([metadata, events]) => ({metadata, events}))))
    wkit.SaveToRaw(`ambientQuad.json`, JSON.stringify(Array.from(ambientQuad.entries()).map(([_, events]) => ({events}))))
    wkit.SaveToRaw(`signposts.json`, JSON.stringify({
        enter: Array.from(signposts.enter.keys()),
        exit: Array.from(signposts.exit.keys())
    }))
}

let skip = JSON.parse(wkit.LoadRawJsonFromProject("skip.txt", "json"))

for (const file of wkit.GetArchiveFiles()) { // [wkit.GetFileFromArchive("base\\worlds\\03_night_city\\_compiled\\default\\exterior_-12_10_0_1.streamingsector", OpenAs.GameFile)]
    if (file && !skip.includes(file.Name) && file.Extension === ".streamingsector" && !file.Name.includes("navigation")) {
        Logger.Info(`Processing ${file.Name}`)
        try {
            let sector = JSON.parse(wkit.GameFileToJson(wkit.GetFileFromBase(file.Name)))

            if (sector && sector.Data) {
                let nodes = sector.Data.RootChunk.nodes
                let staticAudio = nodes.filter((node) => node.Data && node.Data["$type"] && node.Data["$type"] == "worldStaticSoundEmitterNode")
                let ambientNodes = nodes.filter((node) => node.Data && node.Data["$type"] && node.Data["$type"] == "worldAmbientAreaNode")
                let signpostNodes = nodes.filter((node) => node.Data && node.Data["$type"] && node.Data["$type"] == "worldAudioSignpostTriggerNode")
        
                staticAudio.forEach(node => {
                    if (node.Data && node.Data.Settings) {
                        let info = extractSettingsInfo(node.Data.Settings)
                    
                        info.onEnter.forEach((data) => {
                            staticData.onEnter.set(data, staticData.onEnter.get(data) + 1 || 1)
                        })
                        info.onActive.forEach((data) => {
                            staticData.onActive.set(data, staticData.onActive.get(data) + 1 || 1)
                        })
                        info.onExit.forEach((data) => {
                            staticData.onExit.set(data, staticData.onExit.get(data) + 1 || 1)
                        })
                        info.parameters.forEach((data) => {
                            staticData.parameters.set(data, staticData.parameters.get(data) + 1 || 1)
                        })
                        staticData.reverb.set(info.reverb, staticData.reverb.get(info.reverb) + 1 || 1)
            
                        if (node.Data.emitterMetadataName["$value"] !== "None") {
                            let names = staticMetadata.get(node.Data.emitterMetadataName["$value"]) || []
                            staticMetadata.set(node.Data.emitterMetadataName["$value"], names.concat(info.onActive))
                        }
                    }
                })
        
                signpostNodes.forEach((node) => {
                    let info = extractSignpostInfo(node.Data)
                    signposts.enter.set(info.enter, signposts.enter.get(info.enter) + 1 || 1)
                    signposts.exit.set(info.exit, signposts.exit.get(info.exit) + 1 || 1)
                })
        
                ambientNodes.forEach(node => {
                    node.Data.notifiers.forEach(trigger => {
                        if (trigger && trigger.Data && trigger.Data["$type"] === "audioAmbientAreaNotifier" && trigger.Data.Settings) {
                            let info = extractSettingsInfo(trigger.Data.Settings)
                        
                            info.onEnter.forEach((data) => {
                                ambientData.onEnter.set(data, ambientData.onEnter.get(data) + 1 || 1)
                            })
                            info.onActive.forEach((data) => {
                                ambientData.onActive.set(data, ambientData.onActive.get(data) + 1 || 1)
        
                            })
                            info.onExit.forEach((data) => {
                                ambientData.onExit.set(data, ambientData.onExit.get(data) + 1 || 1)
                            })
                            info.parameters.forEach((data) => {
                                ambientData.parameters.set(data, ambientData.parameters.get(data) + 1 || 1)
                            })
                            ambientData.reverb.set(info.reverb, ambientData.reverb.get(info.reverb) + 1 || 1)
        
                            if (trigger.Data.Settings.Data.quadSettings && trigger.Data.Settings.Data.quadSettings.Events && trigger.Data.Settings.Data.quadSettings.Events.Elements) {
                                let events = trigger.Data.Settings.Data.quadSettings.Events.Elements.map((element) => element.event["$value"])
                                ambientQuad.set(events.join(","), events)
                            }
        
                            if (trigger.Data.Settings.Data.MetadataParent["$value"] !== "None") {
                                let names = ambientMetadata.get(trigger.Data.Settings.Data.MetadataParent["$value"]) || []
                                ambientMetadata.set(trigger.Data.Settings.Data.MetadataParent["$value"], names.concat(info.onActive))
                            }
                        }
                    });
                })
            }
    
            doneSectors += file.Name + "\n"
            nDone += 1
    
            if (doneSectors.length % saveInterval === 0) {
                wkit.SaveToRaw(`doneSectors.txt`, doneSectors)
                save(ambientData, staticData, staticMetadata, ambientMetadata, signposts, ambientQuad)
                Logger.Info(`Done ${nDone} sectors, last sector: ${file.Name}`)
            }
        } catch(err) {
			Logger.Error(`Cannot open sector ${file.Name}`)
        }
    }
}

wkit.SaveToRaw(`doneSectors.txt`, doneSectors)
save(ambientData, staticData, staticMetadata, ambientMetadata, signposts, ambientQuad)
Logger.Info(`Done ${nDone} sectors`)