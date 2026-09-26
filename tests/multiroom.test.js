// Run with: node --test tests/
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const test = require("node:test")

const M = require("../shell/Multiroom.js")

const fixture = (name) => fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")

test("modes fall back to off", () => {
  assert.strictEqual(M.normalizeMode("Multiroom"), "multiroom")
  assert.strictEqual(M.normalizeMode("direct"), "direct")
  assert.strictEqual(M.normalizeMode("loud"), "off")
  assert.strictEqual(M.normalizeMode(null), "off")
})

test("RAOP sink names carry host and address", () => {
  assert.deepStrictEqual(M.parseRaopName("raop_sink.Badezimmer.local.10.0.0.211.7000"),
    { host: "Badezimmer.local", address: "10.0.0.211", port: 7000 })
  assert.deepStrictEqual(M.parseRaopName("raop_sink.localhost.local.10.0.0.55.38941"),
    { host: "localhost.local", address: "10.0.0.55", port: 38941 })
  assert.strictEqual(M.parseRaopName("alsa_output.usb"), null)
})

test("sinks from pactl JSON", () => {
  const sinks = M.parseSinks(fixture("sinks.json"))
  const bad = sinks.find((sink) => sink.name.startsWith("raop_sink.Badezimmer"))
  assert.strictEqual(bad.description, "Badezimmer")
  assert.strictEqual(bad.raop, true)
  assert.strictEqual(bad.volume, 100)
  const pipe = sinks.find((sink) => sink.name === M.PIPE_SINK)
  assert.strictEqual(pipe.raop, false)
  assert.deepStrictEqual(M.parseSinks("not json"), [])
})

test("modules from pactl short listing", () => {
  const modules = M.parseModules(fixture("modules-short.txt"))
  assert.ok(modules.every((entry) => entry.name.startsWith("module-")))
  assert.strictEqual(M.findModules(modules, "module-raop-discover").length, 1)
  const pipe = M.findModules(modules, "module-pipe-sink", M.PIPE_SINK)
  assert.strictEqual(pipe.length, 1)
  assert.strictEqual(pipe[0].index, 536870917)
  assert.strictEqual(M.findModules(modules, "module-pipe-sink", "other").length, 0)
  const combine = M.findModules(modules, "module-combine-sink", M.COMBINE_SINK)
  assert.deepStrictEqual(M.combinedSinks(combine[0]),
    ["raop_sink.Badezimmer.local.10.0.0.211.7000", "raop_sink.KEF.local.10.0.0.64.7000"])
})

test("module arguments are read with and without quotes", () => {
  assert.strictEqual(M.moduleArg('file="/a b/c" sink_name=x', "file"), "/a b/c")
  assert.strictEqual(M.moduleArg('file="/a b/c" sink_name=x', "sink_name"), "x")
  assert.strictEqual(M.moduleArg("sinks=a,b", "sink_name"), "")
})

test("load-module arguments quote paths and descriptions", () => {
  const pipe = M.pipeSinkArgs("/home/a b/Omarchy", "Multiroom (OwnTone)")
  assert.ok(pipe.includes('file="/home/a b/Omarchy"'))
  assert.ok(pipe.includes("sink_name=" + M.PIPE_SINK))
  assert.ok(pipe.includes("sink_properties=\"device.description='Multiroom (OwnTone)'\""))
  const combine = M.combineSinkArgs(["a", "b"], "AirPlay's \"Direct\"")
  assert.ok(combine.includes("sinks=a,b"))
  assert.ok(combine.includes("latency_compensate=true"))
  assert.ok(combine.includes("sink_properties=\"device.description='AirPlays Direct'\""))
})

test("direct speakers are remembered by name", () => {
  const sinks = [
    { name: "raop_sink.KEF.local.10.0.0.64.7000", description: "KEF", state: "running", volume: 40, raop: true },
    { name: "raop_sink.Bad.local.10.0.0.2.7000", description: "Bad", state: "suspended", volume: 100, raop: true },
    { name: "alsa_output.usb", description: "USB", state: "idle", volume: 50, raop: false }
  ]
  const speakers = M.directSpeakers(sinks, ["KEF"])
  assert.deepStrictEqual(speakers.map((s) => s.name), ["Bad", "KEF"])
  assert.strictEqual(speakers[1].selected, true)
  assert.strictEqual(speakers[1].playing, true)
  assert.strictEqual(speakers[1].address, "10.0.0.64")
  assert.deepStrictEqual(M.directTarget(speakers), { kind: "single", sinks: ["raop_sink.KEF.local.10.0.0.64.7000"] })
  assert.deepStrictEqual(M.directTarget(M.directSpeakers(sinks, [])), { kind: "none", sinks: [] })
  assert.strictEqual(M.directTarget(M.directSpeakers(sinks, ["KEF", "Bad"])).kind, "combine")
})

test("own sinks are never restored as the previous output", () => {
  assert.ok(M.isOwnSink(M.PIPE_SINK))
  assert.ok(M.isOwnSink(M.COMBINE_SINK))
  assert.ok(M.isOwnSink("raop_sink.KEF.local.10.0.0.64.7000"))
  assert.ok(!M.isOwnSink("alsa_output.usb-Generic_USB_Audio-00.HiFi__SPDIF__sink"))
})

test("OwnTone outputs from the API", () => {
  const outputs = M.parseOutputs(fixture("outputs.json"))
  assert.ok(outputs.length >= 2)
  assert.ok(outputs.every((o) => ["airplay", "airplay2", "chromecast"].includes(o.kind)))
  const kef = outputs.filter((o) => o.name === "KEF").map((o) => o.kind)
  assert.deepStrictEqual(kef, ["airplay2", "chromecast"])
  const local = M.parseOutputs(JSON.stringify({ outputs: [
    { id: "0", name: "Computer", type: "ALSA", selected: true },
    { id: "9", name: "TV", type: "AirPlay 2", selected: true, volume: 30, offset_ms: -50, needs_auth_key: true }
  ] }))
  assert.deepStrictEqual(local.map((o) => o.key), ["9"])
  assert.strictEqual(local[0].offsetMs, -50)
  assert.strictEqual(local[0].needsPin, true)
  assert.strictEqual(M.parseOutputs("<html>"), null)
})

test("the OwnTone config is private and escaped", () => {
  const conf = M.owntoneConfig({ user: "user", stateDir: '/home/s "x"/state', libraryDir: "/home/s/lib" })
  assert.ok(conf.includes('uid = "user"'))
  assert.ok(conf.includes('db_path = "/home/s \\"x\\"/state/songs3.db"'))
  assert.ok(conf.includes('directories = { "/home/s/lib" }'))
  assert.ok(conf.includes('type = "disabled"'))
  assert.ok(conf.includes('trusted_networks = { "localhost" }'))
  assert.ok(conf.includes("timing_port = " + M.TIMING_PORT))
  assert.ok(conf.includes("port = 0"))
  const args = M.owntoneStartArgs("/usr/bin/owntone", "/tmp/o.conf")
  assert.deepStrictEqual(args.slice(-4), ["/usr/bin/owntone", "-f", "-c", "/tmp/o.conf"])
  assert.ok(args.includes("--unit=" + M.OWNTONE_UNIT))
})

test("rooms start at a safe volume", () => {
  assert.strictEqual(M.roomVolume({}, "KEF"), M.DEFAULT_VOLUME)
  assert.strictEqual(M.roomVolume({ KEF: 40 }, "KEF"), 40)
  assert.deepStrictEqual(M.normalizeVolumes({ KEF: "140", Bad: "x", Kueche: 12.4 }), { KEF: 100, Kueche: 12 })
  assert.ok(M.DEFAULT_VOLUME <= 30)
})

test("remembered rooms that are away stay in the list", () => {
  const found = [{ key: "1", name: "Bad", kind: "airplay2", selected: true, sink: "s1" }]
  const list = M.withMissing(found, ["1", "2"], { 2: { name: "Soundbar", kind: "chromecast" } }, (s) => s.key)
  assert.deepStrictEqual(list.map((s) => s.name), ["Bad", "Soundbar"])
  assert.strictEqual(list[1].missing, true)
  assert.strictEqual(list[1].kind, "chromecast")
  // Missing rooms have no sink and never reach the default output.
  assert.deepStrictEqual(M.directTarget(list), { kind: "single", sinks: ["s1"] })
})

test("speaker changes read like a log", () => {
  const before = [
    { key: "1", name: "Bad", kind: "airplay", selected: false, volume: 50 },
    { key: "2", name: "KEF", kind: "airplay2", selected: true, volume: 30 }
  ]
  const after = [
    { key: "1", name: "Bad", kind: "airplay2", selected: true, volume: 25 },
    { key: "3", name: "TV", kind: "airplay2", selected: false, volume: 50 }
  ]
  assert.deepStrictEqual(M.speakerChanges(before, after), [
    "Bad: airplay -> airplay2",
    "Bad [airplay2] selected",
    "Bad [airplay2] volume 50 -> 25",
    "found TV [airplay2]",
    "lost KEF [airplay2]"
  ])
})

test("sink volume lines", () => {
  assert.strictEqual(M.parseVolumeLine("Volume: front-left: 62259 /  95% / -1.34 dB,   front-right: 62259 /  95% / -1.34 dB"), 95)
  assert.strictEqual(M.parseVolumeLine("Volume: front-left: 68811 / 105% / 1.27 dB"), 105)
  assert.strictEqual(M.parseVolumeLine("Failed"), null)
})
