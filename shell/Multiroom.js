// Multiroom model: parses what PipeWire and OwnTone report, builds the
// commands the service runs and turns both into the speaker list the panel
// renders. Pure functions, no I/O.
//
// Two ways to reach the speakers:
//
//   direct     PipeWire's own AirPlay (RAOP) sinks. One room: that sink becomes
//              the default output. Several rooms: a combine sink with latency
//              compensation in front of them. Timed by the host, so rooms can
//              drift apart slightly.
//   multiroom  A pipe sink feeds OwnTone, which plays to AirPlay 2 and
//              Chromecast speakers on one shared clock, like a Mac or iPhone.

var MODES = ["off", "direct", "multiroom"]

// Names of everything the plugin creates, so it can find it again after a
// shell restart and never touches anything else.
var PIPE_SINK = "omarchy_multiroom"
var COMBINE_SINK = "omarchy_multiroom_direct"
var OWNTONE_UNIT = "omarchy-multiroom-speakers-owntone"
var PIPE_NAME = "Omarchy"
var OWNTONE_PORT = 3689
// Fixed UDP ports for AirPlay 2 timing and control, so a firewall rule can
// allow them (6001/6002 are PipeWire's RAOP ports).
var CONTROL_PORT = 6003
var TIMING_PORT = 6004

// OwnTone builds that send the AirPlay user agent HomePod OS 27 expects
// carry this string; older builds get 403 Forbidden from HomePods.
var OS27_USER_AGENT = "AirPlay/999.0.0"

function normalizeMode(value) {
  var mode = String(value || "").toLowerCase()
  return MODES.indexOf(mode) >= 0 ? mode : "off"
}

function parseJson(text) {
  try { return JSON.parse(String(text || "")) } catch (e) { return null }
}

function clampPercent(value) {
  var n = Math.round(Number(value))
  return isFinite(n) ? Math.max(0, Math.min(100, n)) : 0
}

// ---- PipeWire ----------------------------------------------------------------------

// "raop_sink.Badezimmer.local.10.0.0.211.7000" → { host: "Badezimmer.local", address: "10.0.0.211" }
function parseRaopName(name) {
  var m = String(name || "").match(/^raop_sink\.(.+?)\.((?:\d{1,3}\.){3}\d{1,3}|[0-9a-fA-F:]+)\.(\d+)$/)
  return m ? { host: m[1], address: m[2], port: Number(m[3]) } : null
}

function sinkVolume(sink) {
  var channels = sink && sink.volume && typeof sink.volume === "object" ? sink.volume : {}
  var values = Object.keys(channels).map(function(key) {
    return parseInt(String(channels[key] && channels[key].value_percent || ""), 10)
  }).filter(function(v) { return isFinite(v) })
  if (values.length === 0) return null
  return clampPercent(Math.max.apply(null, values))
}

// `pactl -f json list sinks` → every sink by name.
function parseSinks(text) {
  var list = parseJson(text)
  if (!Array.isArray(list)) return []
  return list.filter(function(sink) { return sink && typeof sink.name === "string" }).map(function(sink) {
    var props = sink.properties || {}
    return {
      name: sink.name,
      description: String(props["device.description"] || sink.description || sink.name),
      state: String(sink.state || "").toLowerCase(),
      volume: sinkVolume(sink),
      muted: sink.mute === true,
      raop: sink.name.indexOf("raop_sink.") === 0
    }
  })
}

// `pactl get-sink-volume`: "Volume: front-left: 62259 /  95% / …" → 95
function parseVolumeLine(text) {
  var m = String(text || "").match(/(\d+)%/)
  return m ? Number(m[1]) : null
}

// `pactl list modules short`: "index<TAB>name<TAB>argument". Only modules
// loaded through the pulse protocol ("module-…") can be unloaded that way.
function parseModules(text) {
  return String(text || "").split("\n").map(function(line) {
    var m = line.match(/^(\d+)\t(module-[^\t]+)\t?(.*)$/)
    return m ? { index: Number(m[1]), name: m[2], argument: m[3].trim() } : null
  }).filter(function(entry) { return entry !== null })
}

// "sink_name=a sinks=b,c" → value of one key; handles "…" quoting.
function moduleArg(argument, key) {
  var re = new RegExp("(?:^|\\s)" + key + "=(\"[^\"]*\"|\\S+)")
  var m = String(argument || "").match(re)
  if (!m) return ""
  var value = m[1]
  return value.charAt(0) === "\"" ? value.slice(1, -1) : value
}

function findModules(modules, name, sinkName) {
  return (modules || []).filter(function(entry) {
    return entry.name === name && (!sinkName || moduleArg(entry.argument, "sink_name") === sinkName)
  })
}

// Quotes a module argument value; pulse module arguments take "…".
function quoteArg(value) {
  return "\"" + String(value).replace(/"/g, "") + "\""
}

// Sink properties need a second level of quoting: "device.description='…'".
function descriptionArg(description) {
  return "sink_properties=\"device.description='" + String(description).replace(/['"]/g, "") + "'\""
}

function pipeSinkArgs(fifoPath, description) {
  return ["pactl", "load-module", "module-pipe-sink",
    "file=" + quoteArg(fifoPath), "sink_name=" + PIPE_SINK,
    "format=s16le", "rate=44100", "channels=2", descriptionArg(description)]
}

function combineSinkArgs(sinkNames, description) {
  return ["pactl", "load-module", "module-combine-sink",
    "sink_name=" + COMBINE_SINK, "sinks=" + sinkNames.join(","),
    "latency_compensate=true", descriptionArg(description)]
}

// The sinks a combine module was loaded with, sorted.
function combinedSinks(module) {
  var value = moduleArg(module && module.argument, "sinks")
  return value ? value.split(",").filter(function(name) { return name !== "" }).sort() : []
}

function sameList(a, b) {
  var x = (a || []).slice().sort()
  var y = (b || []).slice().sort()
  if (x.length !== y.length) return false
  for (var i = 0; i < x.length; i++) if (x[i] !== y[i]) return false
  return true
}

// Rooms are remembered by their AirPlay name, which survives new IP
// addresses; the sink name contains the address.
function directSpeakers(sinks, selectedNames) {
  var selected = selectedNames || []
  return (sinks || []).filter(function(sink) { return sink.raop }).map(function(sink) {
    var raop = parseRaopName(sink.name) || {}
    return {
      key: sink.description,
      name: sink.description,
      sink: sink.name,
      kind: "airplay",
      address: raop.address || "",
      selected: selected.indexOf(sink.description) >= 0,
      volume: sink.volume,
      offsetMs: null,
      playing: sink.state === "running",
      needsPin: false
    }
  }).sort(byName)
}

// Where the default output should point for a set of direct rooms:
// { kind: "none" | "single" | "combine", sinks: [sink names] }.
function directTarget(speakers) {
  var sinks = (speakers || []).filter(function(speaker) { return speaker.selected && speaker.sink })
    .map(function(speaker) { return speaker.sink }).sort()
  if (sinks.length === 0) return { kind: "none", sinks: [] }
  return { kind: sinks.length === 1 ? "single" : "combine", sinks: sinks }
}

// A sink the plugin created or an AirPlay sink is no place to return to.
function isOwnSink(name) {
  var value = String(name || "")
  return value === PIPE_SINK || value === COMBINE_SINK || value.indexOf("raop_sink.") === 0
}

// ---- OwnTone -----------------------------------------------------------------------

var OUTPUT_KINDS = { "AirPlay 2": "airplay2", "AirPlay": "airplay", "AirPlay 1": "airplay", "Chromecast": "chromecast" }

// `GET /api/outputs` → speakers. Local, pipe and fifo outputs are left out:
// the plugin disables local audio and only plays to network speakers.
function parseOutputs(text) {
  var doc = parseJson(text)
  var list = doc && Array.isArray(doc.outputs) ? doc.outputs : null
  if (!list) return null
  return list.filter(function(output) {
    return output && OUTPUT_KINDS[String(output.type)] !== undefined && output.id !== undefined
  }).map(function(output) {
    return {
      key: String(output.id),
      name: String(output.name || output.id),
      sink: "",
      kind: OUTPUT_KINDS[String(output.type)],
      address: "",
      selected: output.selected === true,
      volume: typeof output.volume === "number" ? clampPercent(output.volume) : null,
      offsetMs: typeof output.offset_ms === "number" ? Math.round(output.offset_ms) : 0,
      playing: false,
      needsPin: output.needs_auth_key === true,
      requiresAuth: output.requires_auth === true
    }
  }).sort(byName)
}

function parsePlayer(text) {
  var doc = parseJson(text)
  if (!doc || typeof doc.state !== "string") return null
  return { state: doc.state, volume: typeof doc.volume === "number" ? clampPercent(doc.volume) : null }
}

// libconfuse strings: backslash and double quote need escaping.
function confString(value) {
  return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
}

// OwnTone configuration for a private instance run by the user: its own
// database, cache, log and library (holding only the pipe), no local audio,
// no MPD, reachable without password from this machine only.
function owntoneConfig(opts) {
  return [
    "# Written by Omarchy Multiroom Speakers. Changes are overwritten.",
    "general {",
    "\tuid = " + confString(opts.user),
    "\tdb_path = " + confString(opts.stateDir + "/songs3.db"),
    "\tcache_dir = " + confString(opts.stateDir + "/cache"),
    "\tlogfile = " + confString(opts.stateDir + "/owntone.log"),
    // info shows speaker sessions starting, failing and ending.
    "\tloglevel = info",
    "\ttrusted_networks = { \"localhost\" }",
    "\twebsocket_port = 0",
    "}",
    "library {",
    "\tname = \"Omarchy on %h\"",
    "\tport = " + OWNTONE_PORT,
    "\tdirectories = { " + confString(opts.libraryDir) + " }",
    "\tpipe_autostart = true",
    "}",
    "audio {",
    "\ttype = \"disabled\"",
    "}",
    "airplay_shared {",
    "\tcontrol_port = " + CONTROL_PORT,
    "\ttiming_port = " + TIMING_PORT,
    "}",
    "mpd {",
    "\tport = 0",
    "}",
    ""
  ].join("\n")
}

function owntoneStartArgs(binary, configPath) {
  return ["systemd-run", "--user", "--collect", "--quiet", "--unit=" + OWNTONE_UNIT,
    "--property=Restart=on-failure", "--property=RestartSec=3",
    binary, "-f", "-c", configPath]
}

function apiUrl(path) {
  return "http://127.0.0.1:" + OWNTONE_PORT + path
}

// ---- Shared ------------------------------------------------------------------------

// Volume a room starts with when none was set before. PipeWire's AirPlay
// sinks start at 100 %, which is the speaker's full volume.
var DEFAULT_VOLUME = 25

function roomVolume(volumes, id) {
  var value = volumes ? volumes[id] : undefined
  return typeof value === "number" && isFinite(value) ? clampPercent(value) : DEFAULT_VOLUME
}

// { id: percent } with sane values only.
function normalizeVolumes(raw) {
  var out = {}
  if (!raw || typeof raw !== "object") return out
  Object.keys(raw).slice(0, 128).forEach(function(id) {
    var value = Number(raw[id])
    if (id && isFinite(value)) out[String(id).slice(0, 128)] = clampPercent(value)
  })
  return out
}

// Rooms that are remembered but not on the network right now stay in the
// list, marked missing, so they neither vanish nor lose their place.
// known: { id: { name, kind } } as last seen.
function withMissing(speakers, rooms, known, idOf) {
  var list = (speakers || []).slice()
  ;(rooms || []).forEach(function(id) {
    if (list.some(function(speaker) { return idOf(speaker) === id })) return
    var seen = known && known[id] || {}
    list.push({
      key: id, name: seen.name || id, sink: "", kind: seen.kind || "airplay2", address: "",
      selected: true, volume: null, offsetMs: null, playing: false, needsPin: false, missing: true
    })
  })
  return list.sort(byName)
}

// Short lines for the log: what appeared, left or changed between two readings.
function speakerChanges(before, after) {
  var lines = []
  var old = {}
  ;(before || []).forEach(function(speaker) { old[speaker.key] = speaker })
  var seen = {}
  ;(after || []).forEach(function(speaker) {
    seen[speaker.key] = true
    var prev = old[speaker.key]
    var label = speaker.name + " [" + speaker.kind + "]"
    if (!prev) { lines.push("found " + label + (speaker.selected ? " selected" : "")); return }
    if (prev.kind !== speaker.kind) lines.push(speaker.name + ": " + prev.kind + " -> " + speaker.kind)
    if (prev.selected !== speaker.selected) lines.push(label + (speaker.selected ? " selected" : " deselected"))
    if (prev.volume !== speaker.volume) lines.push(label + " volume " + prev.volume + " -> " + speaker.volume)
  })
  ;(before || []).forEach(function(speaker) {
    if (!seen[speaker.key]) lines.push("lost " + speaker.name + " [" + speaker.kind + "]")
  })
  return lines
}

// By name; a speaker with AirPlay and Chromecast lists AirPlay first.
function byName(a, b) {
  var x = String(a.name).toLowerCase()
  var y = String(b.name).toLowerCase()
  if (x !== y) return x < y ? -1 : 1
  return (a.kind === "chromecast" ? 1 : 0) - (b.kind === "chromecast" ? 1 : 0)
}

function selectedCount(speakers) {
  return (speakers || []).filter(function(speaker) { return speaker.selected }).length
}

if (typeof module !== "undefined") module.exports = {
  MODES: MODES, PIPE_SINK: PIPE_SINK, COMBINE_SINK: COMBINE_SINK, OWNTONE_UNIT: OWNTONE_UNIT,
  PIPE_NAME: PIPE_NAME, OWNTONE_PORT: OWNTONE_PORT, CONTROL_PORT: CONTROL_PORT, TIMING_PORT: TIMING_PORT,
  OS27_USER_AGENT: OS27_USER_AGENT,
  normalizeMode: normalizeMode, clampPercent: clampPercent, parseRaopName: parseRaopName,
  parseSinks: parseSinks, parseModules: parseModules, parseVolumeLine: parseVolumeLine, moduleArg: moduleArg, findModules: findModules,
  pipeSinkArgs: pipeSinkArgs, combineSinkArgs: combineSinkArgs, combinedSinks: combinedSinks,
  sameList: sameList, directSpeakers: directSpeakers, directTarget: directTarget, isOwnSink: isOwnSink,
  parseOutputs: parseOutputs, parsePlayer: parsePlayer, confString: confString,
  owntoneConfig: owntoneConfig, owntoneStartArgs: owntoneStartArgs, apiUrl: apiUrl,
  selectedCount: selectedCount, DEFAULT_VOLUME: DEFAULT_VOLUME, roomVolume: roomVolume,
  normalizeVolumes: normalizeVolumes, withMissing: withMissing, speakerChanges: speakerChanges
}
