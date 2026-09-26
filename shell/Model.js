// Pure display and localization helpers. I/O belongs in Service.qml.

var STRINGS = {
  en: {
    title: "Multiroom",
    modes: { off: "Off", direct: "Direct", multiroom: "Multiroom" },
    modeHints: {
      off: "Sound stays on this computer.",
      direct: "PipeWire streams to each room itself. Several rooms are combined into one output; they can drift apart slightly.",
      multiroom: "OwnTone plays to AirPlay 2 and Chromecast speakers on one clock, like a Mac or iPhone. About two seconds of delay."
    },
    speakers: "SPEAKERS", noRoom: "No room selected", oneRoom: "1 room", rooms: "%1 rooms",
    searching: "Looking for speakers…", noSpeakers: "No speakers found yet.",
    starting: "Starting OwnTone…",
    raopMissing: "PipeWire cannot stream to AirPlay yet. Install pipewire-zeroconf: sudo pacman -S pipewire-zeroconf",
    owntoneMissing: "OwnTone is not installed. See the README: tools/build-owntone.sh builds it.",
    owntoneFailed: "OwnTone does not start. Its log: %1",
    owntoneOld: "HomePods with HomePod OS 27 refuse this OwnTone build. tools/build-owntone.sh builds a current one.",
    commandFailed: "Command failed",
    volume: "Volume", offset: "Delay", connection: "Connection", offsetHint: "Delays this room against the others.",
    pin: "PIN", pinHint: "%1 shows a PIN. Enter it here to pair.", pair: "Pair",
    kinds: { airplay: "AirPlay", airplay2: "AirPlay 2", chromecast: "Chromecast" },
    playing: "playing", needsPin: "needs pairing",
    missing: "not found on the network", failed: "connection failed",
    connectFailed: "%1 refused the connection. Details in owntone.log.",
    leftClick: "Click: open multiroom controls"
  },
  de: {
    title: "Multiroom",
    modes: { off: "Aus", direct: "Direkt", multiroom: "Multiroom" },
    modeHints: {
      off: "Der Ton bleibt auf diesem Computer.",
      direct: "PipeWire sendet selbst an jeden Raum. Mehrere Räume werden zu einem Ausgang zusammengefasst; sie können leicht auseinanderlaufen.",
      multiroom: "OwnTone spielt auf AirPlay-2- und Chromecast-Lautsprechern mit einer gemeinsamen Uhr, wie ein Mac oder iPhone. Etwa zwei Sekunden Verzögerung."
    },
    speakers: "LAUTSPRECHER", noRoom: "Kein Raum gewählt", oneRoom: "1 Raum", rooms: "%1 Räume",
    searching: "Suche Lautsprecher…", noSpeakers: "Noch keine Lautsprecher gefunden.",
    starting: "Starte OwnTone…",
    raopMissing: "PipeWire kann noch nicht an AirPlay senden. Installiere pipewire-zeroconf: sudo pacman -S pipewire-zeroconf",
    owntoneMissing: "OwnTone ist nicht installiert. Siehe README: tools/build-owntone.sh baut es.",
    owntoneFailed: "OwnTone startet nicht. Sein Log: %1",
    owntoneOld: "HomePods mit HomePod OS 27 lehnen diese OwnTone-Version ab. tools/build-owntone.sh baut eine aktuelle.",
    commandFailed: "Befehl fehlgeschlagen",
    volume: "Lautstärke", offset: "Verzögerung", connection: "Verbindung", offsetHint: "Verzögert diesen Raum gegenüber den anderen.",
    pin: "PIN", pinHint: "%1 zeigt eine PIN an. Gib sie hier ein, um zu koppeln.", pair: "Koppeln",
    kinds: { airplay: "AirPlay", airplay2: "AirPlay 2", chromecast: "Chromecast" },
    playing: "spielt", needsPin: "Kopplung nötig",
    missing: "nicht im Netz gefunden", failed: "Verbindung fehlgeschlagen",
    connectFailed: "%1 hat die Verbindung abgelehnt. Details in owntone.log.",
    leftClick: "Klick: Multiroom-Steuerung öffnen"
  }
}

// English by default; German when the system locale is German (Qt.locale().name).
function strings(localeName) {
  return isGerman(localeName) ? STRINGS.de : STRINGS.en
}

function isGerman(localeName) {
  return String(localeName || "").toLowerCase().indexOf("de") === 0
}

function emptyState() {
  return { mode: "off", speakers: [], problem: "", owntoneOld: false, starting: false, logPath: "", via: {} }
}

function selectedCount(speakers) {
  return (speakers || []).filter(function(speaker) { return speaker.selected }).length
}

function roomsText(count, s) {
  if (count === 0) return s.noRoom
  return count === 1 ? s.oneRoom : s.rooms.replace("%1", String(count))
}

function problemText(state, s) {
  if (!state) return ""
  switch (state.problem) {
  case "raop-missing": return s.raopMissing
  case "owntone-missing": return s.owntoneMissing
  case "owntone-failed": return s.owntoneFailed.replace("%1", state.logPath || "")
  default: return ""
  }
}

// "Multiroom · 3 rooms", "Direct · No room selected", "Off"
function summary(state, s) {
  var mode = state ? state.mode : "off"
  if (mode === "off") return s.modes.off
  if (state.problem) return s.modes[mode] + " · " + problemText(state, s)
  if (state.starting) return s.modes[mode] + " · " + s.starting
  return s.modes[mode] + " · " + roomsText(selectedCount(state.speakers), s)
}

// "AirPlay 2 · 40 %", "AirPlay · playing", "Chromecast · needs pairing"
function subtitle(speaker, s) {
  if (!speaker) return ""
  var parts = [s.kinds[speaker.kind] || speaker.kind]
  if (speaker.missing) parts.push(s.missing)
  else if (speaker.failed) parts.push(s.failed)
  else if (speaker.needsPin) parts.push(s.needsPin)
  if (speaker.playing) parts.push(s.playing)
  return parts.join(" · ")
}

// Something is wrong: a problem with PipeWire or OwnTone, a room that
// refused or lost its connection, or a failed command. Rooms that are merely
// away (standby) are not an error.
function needsAttention(state, error) {
  if (!state || state.mode === "off") return false
  if (state.problem !== "" || state.owntoneOld === true || !!error) return true
  return (state.speakers || []).some(function(speaker) { return speaker.failed === true && !speaker.missing })
}

// nf-md-speaker_off / speaker / speaker_multiple
function glyph(mode) {
  if (mode === "direct") return String.fromCodePoint(0xF04C3)
  if (mode === "multiroom") return String.fromCodePoint(0xF0D38)
  return String.fromCodePoint(0xF04C4)
}

// Number of rooms next to the icon while a mode is on.
function barText(state) {
  if (!state || state.mode === "off" || state.problem) return ""
  var count = selectedCount(state.speakers)
  return count > 0 ? String(count) : ""
}

function tooltip(state, error, s) {
  var lines = [s.title + ": " + summary(state, s)]
  var names = (state && state.mode !== "off" ? state.speakers : []).filter(function(speaker) { return speaker.selected })
    .map(function(speaker) { return speaker.name })
  if (names.length > 0) lines.push(names.join(", "))
  if (state && state.mode === "multiroom" && state.owntoneOld) lines.push(s.owntoneOld)
  if (error) lines.push(error)
  lines.push(s.leftClick)
  return lines.join("\n")
}

// A speaker by name or key. Speakers that offer AirPlay and Chromecast under
// one name are found as AirPlay.
function speakerByName(speakers, name) {
  var wanted = String(name || "").trim().toLowerCase()
  var found = (speakers || []).filter(function(speaker) {
    return speaker.name.toLowerCase() === wanted || speaker.key.toLowerCase() === wanted
  })
  var airplay = found.filter(function(speaker) { return speaker.kind !== "chromecast" })
  return airplay.length > 0 ? airplay[0] : (found.length > 0 ? found[0] : null)
}

// One row per device: a speaker reachable over AirPlay and Chromecast under
// one name is one device with two connections. The row shows the connection
// that plays, else the preferred one (via: { name: kind }), else AirPlay.
function groupSpeakers(speakers, via) {
  var order = []
  var byName = {}
  ;(speakers || []).forEach(function(speaker) {
    if (!byName[speaker.name]) { byName[speaker.name] = []; order.push(speaker.name) }
    byName[speaker.name].push(speaker)
  })
  return order.map(function(name) {
    var variants = byName[name]
    var chosen = variants.filter(function(v) { return v.selected && !v.missing })[0]
      || variants.filter(function(v) { return via && via[name] === v.kind })[0]
      || variants.filter(function(v) { return v.kind !== "chromecast" })[0]
      || variants[0]
    return Object.assign({}, chosen, {
      variants: variants.map(function(v) { return { key: v.key, kind: v.kind } })
    })
  })
}

// Expected state of a command before PipeWire or OwnTone confirm it.
function patchSpeakers(speakers, key, change) {
  return (speakers || []).map(function(speaker) {
    return speaker.key === key ? Object.assign({}, speaker, change) : speaker
  })
}

if (typeof module !== "undefined") module.exports = {
  STRINGS: STRINGS, strings: strings, isGerman: isGerman, emptyState: emptyState,
  selectedCount: selectedCount, roomsText: roomsText, problemText: problemText, summary: summary,
  subtitle: subtitle, needsAttention: needsAttention, glyph: glyph, barText: barText, tooltip: tooltip,
  speakerByName: speakerByName, patchSpeakers: patchSpeakers, groupSpeakers: groupSpeakers
}
