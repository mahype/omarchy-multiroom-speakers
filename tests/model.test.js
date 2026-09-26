// Run with: node --test tests/
const assert = require("assert")
const test = require("node:test")

const Model = require("../shell/Model.js")

const de = Model.strings("de_DE")
const en = Model.strings("en_US")

const speakers = [
  { key: "1", name: "Bad", kind: "airplay2", selected: true, volume: 40, playing: false, needsPin: false },
  { key: "2", name: "KEF", kind: "chromecast", selected: false, volume: 50, playing: false, needsPin: false },
  { key: "3", name: "TV", kind: "airplay2", selected: false, volume: null, playing: false, needsPin: true }
]
const state = (change) => Object.assign(Model.emptyState(), { mode: "multiroom", speakers: speakers }, change)

test("summaries name mode and rooms", () => {
  assert.strictEqual(Model.summary(Model.emptyState(), de), "Aus")
  assert.strictEqual(Model.summary(state(), de), "Multiroom · 1 Raum")
  assert.strictEqual(Model.summary(state({ mode: "direct", speakers: [] }), en), "Direct · No room selected")
  assert.strictEqual(Model.summary(state({ starting: true }), en), "Multiroom · Starting OwnTone…")
  assert.strictEqual(Model.summary(state({ problem: "raop-missing" }), de), "Multiroom · " + de.raopMissing)
  assert.strictEqual(Model.roomsText(3, de), "3 Räume")
})

test("speaker subtitles", () => {
  assert.strictEqual(Model.subtitle(speakers[0], de), "AirPlay 2")
  assert.strictEqual(Model.subtitle(speakers[1], en), "Chromecast")
  assert.strictEqual(Model.subtitle(speakers[2], de), "AirPlay 2 · Kopplung nötig")
  assert.strictEqual(Model.subtitle(Object.assign({}, speakers[0], { missing: true }), de), "AirPlay 2 · nicht im Netz gefunden")
  assert.strictEqual(Model.subtitle(Object.assign({}, speakers[0], { failed: true }), en), "AirPlay 2 · connection failed")
  assert.strictEqual(Model.subtitle(Object.assign({}, speakers[0], { kind: "airplay", playing: true }), en),
    "AirPlay · playing")
})

test("bar text, glyph and attention", () => {
  assert.strictEqual(Model.barText(state()), "1")
  assert.strictEqual(Model.barText(Model.emptyState()), "")
  assert.strictEqual(Model.barText(state({ problem: "owntone-failed" })), "")
  assert.notStrictEqual(Model.glyph("off"), Model.glyph("multiroom"))
  assert.ok(Model.needsAttention(state({ owntoneOld: true })))
  assert.ok(Model.needsAttention(state({ problem: "owntone-missing" })))
  assert.ok(!Model.needsAttention(state()))
  assert.ok(Model.needsAttention(state(), "Command failed"))
  assert.ok(Model.needsAttention(state({ speakers: [Object.assign({}, speakers[0], { failed: true })] })))
  assert.ok(!Model.needsAttention(state({ speakers: [Object.assign({}, speakers[0], { missing: true, failed: true })] })))
  assert.ok(!Model.needsAttention(Object.assign(Model.emptyState(), { problem: "raop-missing" })))
})

test("tooltip lists the playing rooms", () => {
  const text = Model.tooltip(state(), "", de)
  assert.ok(text.startsWith("Multiroom: Multiroom · 1 Raum"))
  assert.ok(text.includes("\nBad\n"))
  assert.ok(text.endsWith(de.leftClick))
})

test("speakers by name and optimistic patches", () => {
  assert.strictEqual(Model.speakerByName(speakers, "kef").key, "2")
  assert.strictEqual(Model.speakerByName(speakers, "3").name, "TV")
  assert.strictEqual(Model.speakerByName(speakers, "Küche"), null)
  const twins = [{ key: "c", name: "KEF", kind: "chromecast" }, { key: "a", name: "KEF", kind: "airplay2" }]
  assert.strictEqual(Model.speakerByName(twins, "KEF").key, "a")
  const patched = Model.patchSpeakers(speakers, "2", { selected: true })
  assert.strictEqual(patched[1].selected, true)
  assert.strictEqual(speakers[1].selected, false)
})

test("a speaker with AirPlay and Chromecast is one device", () => {
  const list = [
    { key: "a", name: "KEF", kind: "airplay2", selected: false },
    { key: "c", name: "KEF", kind: "chromecast", selected: false },
    { key: "b", name: "Bad", kind: "airplay2", selected: true }
  ]
  const devices = Model.groupSpeakers(list, {})
  assert.deepStrictEqual(devices.map((d) => d.name), ["KEF", "Bad"])
  assert.strictEqual(devices[0].key, "a")
  assert.deepStrictEqual(devices[0].variants,
    [{ key: "a", kind: "airplay2", missing: false }, { key: "c", kind: "chromecast", missing: false }])
  assert.strictEqual(Model.groupSpeakers(list, { KEF: "chromecast" })[0].key, "c")
  // The connection that plays wins over the preference.
  const playing = list.map((s) => s.key === "a" ? Object.assign({}, s, { selected: true }) : s)
  assert.strictEqual(Model.groupSpeakers(playing, { KEF: "chromecast" })[0].key, "a")
  assert.strictEqual(devices[1].variants.length, 1)
})

test("a connection that is gone stays selectable", () => {
  // A KEF playing over Chromecast stops announcing AirPlay.
  const list = [{ key: "c", name: "KEF", kind: "chromecast", selected: true }]
  const devices = Model.groupSpeakers(list, { KEF: "chromecast" }, { KEF: { airplay2: "a", chromecast: "c" } })
  assert.deepStrictEqual(devices[0].variants, [
    { key: "a", kind: "airplay2", missing: true },
    { key: "c", kind: "chromecast", missing: false }
  ])
  assert.strictEqual(devices[0].key, "c")
})

test("hints for rooms that do not play", () => {
  const mac = { name: "Mac mini", family: "mac", selected: true, failed: true }
  assert.strictEqual(Model.connectHint(mac, "multiroom", de), de.macHint)
  assert.strictEqual(Model.connectHint(Object.assign({}, mac, { failed: false }), "multiroom", de), "")
  // Direct mode cannot see refusals; a chosen Mac gets the hint at once.
  assert.strictEqual(Model.connectHint(Object.assign({}, mac, { failed: false }), "direct", de), de.macSilentHint)
  const pod = { name: "Bad", family: "homepod", selected: true, failed: true }
  assert.ok(Model.connectHint(pod, "multiroom", de).startsWith("Bad hat die Verbindung abgelehnt. In der Home-App"))
  assert.ok(Model.connectHint({ name: "KEF", family: "", failed: true }, "multiroom", en).startsWith("KEF refused"))
  assert.strictEqual(Model.connectHint({ name: "KEF", family: "", failed: true, missing: true }, "multiroom", en), "")
})
