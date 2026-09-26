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
    volume: "Volume", offset: "Delay", connection: "Connection",
    macHint: "Macs accept AirPlay only from devices with the same Apple ID. On the Mac, open System Settings → General → AirDrop & Handoff, turn on AirPlay Receiver and set \"Allow AirPlay for\" to \"Anyone on the same network\". Then enter the code the Mac shows here.",
    macSilentHint: "If nothing plays: Macs accept AirPlay only from devices with the same Apple ID. On the Mac, set System Settings → General → AirDrop & Handoff → \"Allow AirPlay for\" to \"Anyone on the same network\".",
    homeHint: "%1 refused the connection. In the Home app, open Home Settings → Speakers & TV and allow access for \"Anyone on the same network\".",
    refusedHint: "%1 refused the connection. Is it switched on and open for AirPlay? Details in owntone.log.",
    dismiss: "Dismiss",
    pairFirst: "Switch %1 on to pair: it then shows a code, which you enter here. Needed once.",
    tvHint: "%1 shows a four-digit code on the TV when it is first connected. Enter it here to pair. No code? In the Home app, open Home Settings → Speakers & TV and allow access for \"Anyone on the same network\".",
    castHint: "OwnTone does not keep Chromecast in sync with AirPlay rooms; it plays about two seconds later. Use AirPlay for multiroom.",
    waitingFor: "switching, waiting for %1", offsetHint: "Delays this room against the others.",
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
    volume: "Lautstärke", offset: "Verzögerung", connection: "Verbindung",
    macHint: "Macs nehmen AirPlay nur von Geräten mit derselben Apple-ID an. Am Mac unter Systemeinstellungen → Allgemein → AirDrop & Handoff „AirPlay-Empfänger“ einschalten und „AirPlay erlauben für“ auf „Jeder im selben Netzwerk“ stellen. Den Code, den der Mac dann zeigt, hier eingeben.",
    macSilentHint: "Falls nichts zu hören ist: Macs nehmen AirPlay nur von Geräten mit derselben Apple-ID an. Am Mac unter Systemeinstellungen → Allgemein → AirDrop & Handoff „AirPlay erlauben für“ auf „Jeder im selben Netzwerk“ stellen.",
    homeHint: "%1 hat die Verbindung abgelehnt. In der Home-App unter Home-Einstellungen → Lautsprecher & TV den Zugriff für „Jeder im selben Netzwerk“ erlauben.",
    refusedHint: "%1 hat die Verbindung abgelehnt. Ist das Gerät eingeschaltet und für AirPlay freigegeben? Details in owntone.log.",
    dismiss: "Ausblenden",
    pairFirst: "Zum Koppeln %1 einschalten: Dann erscheint ein Code, den du hier eingibst. Nur einmal nötig.",
    tvHint: "%1 zeigt beim ersten Verbinden einen vierstelligen Code auf dem Fernseher. Gib ihn hier ein, um zu koppeln. Kein Code? In der Home-App unter Home-Einstellungen → Lautsprecher & TV den Zugriff für „Jeder im selben Netzwerk“ erlauben.",
    castHint: "OwnTone hält Chromecast nicht synchron mit den AirPlay-Räumen, es spielt etwa zwei Sekunden später. Für Multiroom AirPlay nehmen.",
    waitingFor: "wechselt, warte auf %1", offsetHint: "Verzögert diesen Raum gegenüber den anderen.",
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
  return { mode: "off", speakers: [], problem: "", owntoneOld: false, starting: false, logPath: "", via: {}, variants: {} }
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
  else if (speaker.needsPin || speaker.unpaired) parts.push(s.needsPin)
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

// What to do about a room that does not play, shown under its row. Direct
// mode cannot tell a refusal, so a chosen Mac gets the hint right away.
// `refused` is a failure the user dismissed: the hint stays for when the row
// is unfolded again.
function connectHint(speaker, mode, s) {
  if (!speaker || speaker.missing) return ""
  var failed = speaker.failed === true || speaker.refused === true
  if (speaker.family === "mac" && (failed || (mode === "direct" && speaker.selected)))
    return failed ? s.macHint : s.macSilentHint
  if (!failed) return ""
  // Apple TVs pair with a code on the TV screen.
  if (speaker.family === "appletv") return s.tvHint.replace("%1", speaker.name)
  if (speaker.family === "homepod") return s.homeHint.replace("%1", speaker.name)
  return s.refusedHint.replace("%1", speaker.name)
}

// One row per device: a speaker reachable over AirPlay and Chromecast under
// one name is one device with two connections. The row shows the connection
// that plays, else the preferred one (via: { name: kind }), else AirPlay.
// variants: { name: { kind: key } } of connections seen before; one that is
// gone right now (a KEF playing over Chromecast stops announcing AirPlay)
// stays selectable, marked missing.
function groupSpeakers(speakers, via, known) {
  var order = []
  var byName = {}
  ;(speakers || []).forEach(function(speaker) {
    if (!byName[speaker.name]) { byName[speaker.name] = []; order.push(speaker.name) }
    byName[speaker.name].push(speaker)
  })
  return order.map(function(name) {
    var list = byName[name]
    var chosen = list.filter(function(v) { return v.selected && !v.missing })[0]
      || list.filter(function(v) { return via && via[name] === v.kind })[0]
      || list.filter(function(v) { return v.kind !== "chromecast" })[0]
      || list[0]
    var options = list.map(function(v) { return { key: v.key, kind: v.kind, missing: v.missing === true } })
    var seen = known && known[name] || {}
    Object.keys(seen).forEach(function(kind) {
      if (!options.some(function(o) { return o.kind === kind }))
        options.push({ key: seen[kind], kind: kind, missing: true })
    })
    options.sort(function(a, b) { return (a.kind === "chromecast" ? 1 : 0) - (b.kind === "chromecast" ? 1 : 0) })
    return Object.assign({}, chosen, { variants: options })
  }).sort(function(a, b) {
    // Playing devices first, the rest after them, each by name.
    var x = active(a) ? 0 : 1
    var y = active(b) ? 0 : 1
    if (x !== y) return x - y
    var n = a.name.toLowerCase()
    var m = b.name.toLowerCase()
    return n < m ? -1 : (n > m ? 1 : 0)
  })
}

// A device that is chosen and around; a refused one waiting for a fix too.
function active(device) {
  return device.selected === true && device.missing !== true || device.failed === true
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
  speakerByName: speakerByName, patchSpeakers: patchSpeakers, groupSpeakers: groupSpeakers,
  connectHint: connectHint
}
