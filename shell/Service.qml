import QtQuick
import Quickshell
import Quickshell.Io
import "Multiroom.js" as Multiroom
import "Model.js" as Model

// Owner of all multiroom state. Mounted once per session; the bar widget and
// the panel reach it through `bar.shell.serviceFor(...)` and call only the
// action functions below.
//
// Modes:
//   off        nothing of the plugin runs; the previous output is restored.
//   direct     PipeWire's AirPlay sinks (module-raop-discover); one room is
//              used directly, several go through a combine sink.
//   multiroom  a pipe sink feeds a private OwnTone instance (transient systemd
//              user unit), which plays to AirPlay 2 and Chromecast speakers in
//              sync.
//
// Everything the plugin creates carries a fixed name (see Multiroom.js), so it
// is found again after a shell restart and nothing else is touched. External
// programs are always called with argument arrays, never through a shell.
//
// What the plugin does and what the speakers answer is written to
// plugin.log next to OwnTone's own log, for finding out why a room stayed
// silent.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string user: Quickshell.env("USER")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy-multiroom-speakers"
  readonly property string configPath: configDir + "/config.json"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy-multiroom-speakers"
  readonly property string libraryDir: stateDir + "/library"
  readonly property string fifoPath: libraryDir + "/" + Multiroom.PIPE_NAME
  readonly property string owntoneConfPath: stateDir + "/owntone.conf"
  readonly property string logPath: stateDir + "/owntone.log"
  readonly property string pluginLogPath: stateDir + "/plugin.log"
  // Where tools/build-owntone.sh installs a current OwnTone.
  readonly property string builtOwntone: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share"))
    + "/omarchy-multiroom-speakers/owntone/sbin/owntone"
  readonly property var strings: Model.strings(Qt.locale().name)

  // How long remembered rooms are awaited after a mode switch.
  readonly property int restoreWindow: 25000
  // Speakers need a moment to end a session before another sender connects.
  readonly property int handoverDelay: 2000
  // A room that dropped out is selected again this often, this far apart.
  readonly property int retryLimit: 3
  readonly property int retryGap: 20000

  // ---- State the panel reads ----------------------------------------------------

  // { mode, speakers, problem, owntoneOld, starting, logPath }
  property var state: Model.emptyState()
  readonly property string mode: config.mode
  readonly property bool ready: loaded
  property string error: ""
  property string statusMessage: ""
  // True while a mode switch runs; the mode buttons wait meanwhile.
  property bool switching: false
  // Set by the panel while it is open; polls faster then.
  property bool watching: false
  // OwnTone binary from the widget settings; empty means "find it".
  property string owntoneSetting: ""

  property bool loaded: false
  property var config: normalizeConfig(null)
  property var speakers: []
  property string problem: ""
  property bool owntoneOld: false
  property bool starting: false
  property string owntoneBinary: ""
  // Bumped on every mode switch; answers from an earlier mode are dropped.
  property int epoch: 0
  property int owntoneFailures: 0
  // After a mode switch the remembered rooms are selected again once they
  // have been found, or when discovery had enough time.
  property real restoreUntil: 0
  // First answer of the OwnTone API since it started.
  property real owntoneReadyAt: 0
  // Multiroom: the default output moves to the pipe once the rooms are set,
  // so no sound reaches OwnTone while it still sorts out its speakers.
  property bool pipePending: false
  // Direct: AirPlay sinks seen in the last reading. A new sink starts at
  // 100 % and gets the room's volume before it plays.
  property var seenSinks: ({})
  // Volume per AirPlay sink in the last reading; a volume is only taken over
  // as the room's volume once it held still for two readings.
  property var sinkVolumes: ({})
  // One reading and one change of the output at a time; overlapping ones
  // raced each other and loaded the combine sink twice.
  property bool polling: false
  property real pollStarted: 0
  property bool applying: false
  property bool applyAgain: false
  property bool applySwitch: false
  // Per room: { reason, at } of the last failure, { count, at } of retries.
  property var failures: ({})
  property var retries: ({})

  onWatchingChanged: if (watching) pollTimer.restart()
  // A one-off error message fades; lasting problems are shown per room.
  onErrorChanged: if (error) errorTimer.restart()
  onOwntoneSettingChanged: owntoneBinary = ""

  function publish() {
    var now = Date.now()
    var shown = speakers.map(function(speaker) {
      return failures[speaker.key] && !speaker.missing ? Object.assign({}, speaker, { failed: true }) : speaker
    })
    Object.keys(holds).forEach(function(key) {
      if (holds[key].until > now) shown = Model.patchSpeakers(shown, key, holds[key].change)
    })
    state = {
      mode: config.mode, speakers: config.mode === "off" ? [] : shown, problem: problem,
      owntoneOld: owntoneOld, starting: starting, logPath: logPath,
      via: config.mode === "multiroom" ? config.multiroom.via : ({})
    }
  }

  // ---- Log ------------------------------------------------------------------------------

  property var logLines: []
  property bool logDirty: false
  property bool logLoaded: false

  function log(text) {
    logLines = logLines.concat([new Date().toISOString() + " [" + config.mode + "] " + text]).slice(-3000)
    logDirty = true
  }

  function flushLog() {
    if (!logDirty || !logLoaded) return
    pluginLog.setText(logLines.join("\n") + "\n")
    logDirty = false
  }

  // ---- Optimistic updates -----------------------------------------------------------

  // Speaker changes stay on screen until the next reading after they settled.
  property var holds: ({})

  function hold(key, change) {
    var next = Object.assign({}, holds)
    next[key] = { change: Object.assign({}, holds[key] ? holds[key].change : {}, change), until: Date.now() + 3000 }
    holds = next
    publish()
  }

  function held(key) {
    return holds[key] && holds[key].until > Date.now()
  }

  // ---- Settings -------------------------------------------------------------------

  function names(list) {
    var seen = {}
    return (Array.isArray(list) ? list : []).map(function(value) { return String(value || "").trim() })
      .filter(function(value) {
        if (value === "" || seen[value]) return false
        seen[value] = true
        return true
      }).slice(0, 64)
  }

  function normalizeKnown(raw) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    Object.keys(raw).slice(0, 128).forEach(function(id) {
      var entry = raw[id]
      if (entry && typeof entry === "object")
        out[id] = { name: String(entry.name || id).slice(0, 128), kind: String(entry.kind || "airplay2").slice(0, 16) }
    })
    return out
  }

  // Preferred connection per device name: { name: "airplay2" | "chromecast" | … }
  function normalizeVia(raw) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    Object.keys(raw).slice(0, 128).forEach(function(name) {
      var kind = String(raw[name] || "")
      if (["airplay", "airplay2", "chromecast"].indexOf(kind) >= 0) out[String(name).slice(0, 128)] = kind
    })
    return out
  }

  function normalizeConfig(raw) {
    var value = raw && typeof raw === "object" ? raw : {}
    var direct = value.direct && typeof value.direct === "object" ? value.direct : {}
    var multi = value.multiroom && typeof value.multiroom === "object" ? value.multiroom : {}
    return {
      version: 1,
      mode: Multiroom.normalizeMode(value.mode),
      direct: { rooms: names(direct.rooms), volumes: Multiroom.normalizeVolumes(direct.volumes) },
      multiroom: {
        rooms: names(multi.rooms), volumes: Multiroom.normalizeVolumes(multi.volumes),
        known: normalizeKnown(multi.known), via: normalizeVia(multi.via)
      },
      returnSink: String(value.returnSink || "").slice(0, 256)
    }
  }

  function saveConfig(change) {
    var next = normalizeConfig(Object.assign({}, config, change))
    config = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
    publish()
  }

  function saveDirect(change) { saveConfig({ direct: Object.assign({}, config.direct, change) }) }
  function saveMulti(change) { saveConfig({ multiroom: Object.assign({}, config.multiroom, change) }) }

  function setFailure(key, reason) {
    var next = Object.assign({}, failures)
    if (reason) next[key] = { reason: reason, at: Date.now() }
    else delete next[key]
    failures = next
  }

  // ---- Commands ---------------------------------------------------------------------

  property var queue: []
  property var current: null

  // One external program at a time; callback(exitCode, stdout).
  function run(argv, callback) {
    queue = queue.concat([{ argv: argv, callback: callback || null }])
    pump()
  }

  function pump() {
    if (runner.running || queue.length === 0) return
    current = queue[0]
    queue = queue.slice(1)
    runner.command = current.argv
    runner.running = true
  }

  // Readings and probes run all the time; only commands that change
  // something are logged, together with their result.
  function quiet(argv) {
    var tool = argv[0]
    if (["test", "grep", "true", "install", "cat"].indexOf(tool) >= 0) return true
    if (tool === "pactl") return ["list", "get-default-sink", "get-sink-volume", "-f"].indexOf(argv[1]) >= 0
    if (tool === "systemctl") return argv.indexOf("is-active") >= 0
    if (tool === "curl") return true
    return false
  }

  // OwnTone's JSON API; callback(ok, body, status).
  function api(method, path, body, callback) {
    var argv = ["curl", "-s", "-m", "5", "-X", method, "-w", "\n%{http_code}"]
    if (body !== null && body !== undefined) argv = argv.concat(["-H", "Content-Type: application/json", "--data", JSON.stringify(body)])
    run(argv.concat([Multiroom.apiUrl(path)]), function(code, out) {
      var text = String(out || "")
      var cut = text.lastIndexOf("\n")
      var status = Number(text.slice(cut + 1))
      var ok = code === 0 && status >= 200 && status < 300
      if (method !== "GET") log("api " + method + " " + path + (body ? " " + JSON.stringify(body) : "") + " -> " + (code === 0 ? status : "curl " + code))
      if (callback) callback(ok, cut >= 0 ? text.slice(0, cut) : "", status)
    })
  }

  // Runs `step` only while the mode it was started for is still current.
  function guard(step) {
    var started = epoch
    return function(a, b, c) { if (started === epoch) step(a, b, c) }
  }

  // One pending delayed step at a time (mode switches are serialized).
  function later(ms, step) {
    delayTimer.step = step
    delayTimer.interval = ms
    delayTimer.restart()
  }

  // ---- Default output ---------------------------------------------------------------

  function setDefault(sink, callback) {
    run(["pactl", "set-default-sink", sink], function(code) { if (callback) callback(code === 0) })
  }

  // Back to the output that was in use before a mode was switched on.
  function restoreDefault(callback) {
    run(["pactl", "get-default-sink"], function(code, out) {
      var current = String(out || "").trim()
      var target = config.returnSink
      if (!Multiroom.isOwnSink(current) || !target || Multiroom.isOwnSink(target)) { if (callback) callback(); return }
      log("default output back to " + target)
      setDefault(target, function() { if (callback) callback() })
    })
  }

  function rememberDefault(callback) {
    run(["pactl", "get-default-sink"], function(code, out) {
      var current = String(out || "").trim()
      if (code === 0 && current && !Multiroom.isOwnSink(current)) saveConfig({ returnSink: current })
      if (callback) callback()
    })
  }

  // ---- Modes --------------------------------------------------------------------------

  function setMode(value) {
    var next = Multiroom.normalizeMode(value)
    if (switching || next === config.mode) return next === config.mode
    var previous = config.mode
    log("mode " + previous + " -> " + next)
    epoch += 1
    switching = true
    error = ""
    problem = ""
    owntoneOld = false
    starting = false
    speakers = []
    holds = ({})
    failures = ({})
    retries = ({})
    sinkVolumes = ({})
    polling = false
    saveConfig({ mode: next })
    var finish = function() {
      switching = false
      publish()
      pollTimer.restart()
    }
    var enter = function() {
      if (next === "direct") setupDirect(finish)
      else if (next === "multiroom") setupMultiroom(finish)
      else restoreDefault(finish)
    }
    var leave = function() {
      teardown(previous === "off" ? "" : previous, function() {
        // The speakers still hold the old session for a moment.
        if (previous !== "off" && next !== "off") later(handoverDelay, enter)
        else enter()
      })
    }
    if (previous === "off") rememberDefault(leave)
    else leave()
    return true
  }

  // Removes what a mode created. Called with "" it still cleans up leftovers.
  function teardown(previous, callback) {
    run(["pactl", "list", "modules", "short"], function(code, out) {
      var modules = Multiroom.parseModules(out)
      var remove = Multiroom.findModules(modules, "module-combine-sink", Multiroom.COMBINE_SINK)
        .concat(Multiroom.findModules(modules, "module-pipe-sink", Multiroom.PIPE_SINK))
      if (previous === "direct") remove = remove.concat(Multiroom.findModules(modules, "module-raop-discover"))
      var unload = function() {
        remove.forEach(function(entry) { run(["pactl", "unload-module", String(entry.index)]) })
        run(["true"], function() { if (callback) callback() })
      }
      // Move the default away first, so no stream is left on a vanishing sink;
      // OwnTone stops before its pipe goes away.
      restoreDefault(function() {
        if (previous === "multiroom" || previous === "") stopOwntone(unload)
        else unload()
      })
    })
  }

  // ---- Direct: PipeWire RAOP ----------------------------------------------------------

  function setupDirect(callback) {
    restoreUntil = Date.now() + restoreWindow
    seenSinks = ({})
    ensureRaop(guard(function() {
      statusMessage = strings.searching
      // Discovery needs a moment before the first sinks appear.
      discoveryTimer.restart()
      if (callback) callback()
    }))
  }

  function ensureRaop(callback) {
    run(["pactl", "list", "modules", "short"], function(code, out) {
      if (Multiroom.findModules(Multiroom.parseModules(out), "module-raop-discover").length > 0) { callback(0); return }
      run(["pactl", "load-module", "module-raop-discover"], function(loadCode) {
        problem = loadCode === 0 ? "" : "raop-missing"
        publish()
        callback(loadCode)
      })
    })
  }

  function directVolume(name) {
    return Multiroom.roomVolume(config.direct.volumes, name)
  }

  function pollDirect(done) {
    run(["pactl", "list", "modules", "short"], function(code, out) {
      var modules = Multiroom.parseModules(out)
      if (Multiroom.findModules(modules, "module-raop-discover").length === 0) {
        log("AirPlay discovery module missing, loading it again")
        ensureRaop(function() { done() })
        return
      }
      run(["pactl", "-f", "json", "list", "sinks"], function(sinkCode, sinkOut) {
        if (config.mode !== "direct") { done(); return }
        var found = Multiroom.directSpeakers(Multiroom.parseSinks(sinkOut), config.direct.rooms)
        var previous = seenSinks
        var lastVolumes = sinkVolumes
        var seen = {}
        var volumes = {}
        var learned = null
        found.forEach(function(speaker) {
          seen[speaker.sink] = true
          volumes[speaker.sink] = speaker.volume
          if (!speaker.selected) return
          if (!previous[speaker.sink]) {
            // New sink: PipeWire starts it at 100 %; the room's volume first.
            var volume = directVolume(speaker.name)
            log("new AirPlay sink for " + speaker.name + " (" + speaker.address + "), volume " + volume + " %")
            run(["pactl", "set-sink-volume", speaker.sink, volume + "%"])
            speaker.volume = volume
            volumes[speaker.sink] = volume
          } else if (typeof speaker.volume === "number" && speaker.volume === lastVolumes[speaker.sink]
                     && speaker.volume !== directVolume(speaker.name) && !held(speaker.key)) {
            // Changed elsewhere (volume keys, audio panel) and settled: remember it.
            learned = learned || Object.assign({}, config.direct.volumes)
            learned[speaker.name] = speaker.volume
            log("volume of " + speaker.name + " changed elsewhere: " + speaker.volume + " %")
          }
        })
        seenSinks = seen
        sinkVolumes = volumes
        if (learned) saveDirect({ volumes: learned })
        var list = Multiroom.withMissing(found, config.direct.rooms, null, function(s) { return s.name })
        Multiroom.speakerChanges(speakers, list).forEach(function(line) { log(line) })
        speakers = list
        if (found.length > 0) statusMessage = ""
        publish()
        // A room that appears or disappears changes the combine sink.
        var target = Multiroom.directTarget(found)
        var combine = Multiroom.findModules(modules, "module-combine-sink", Multiroom.COMBINE_SINK)
        var outdated = target.kind === "combine"
          ? combine.length !== 1 || !Multiroom.sameList(Multiroom.combinedSinks(combine[0]), target.sinks)
          : combine.length > 0
        if (restoreDue(found, config.direct.rooms, function(s) { return s.name }, null)) {
          restoreUntil = 0
          log("rooms restored: " + (config.direct.rooms.join(", ") || "none"))
          applyDirect(true)
        } else if (outdated && restoreUntil === 0 && !applying) {
          applyDirect(false)
        }
        done()
      })
    })
  }

  // Points the default output at the selected rooms. `switchOutput` is false
  // when only the combine sink has to follow the available rooms.
  function applyDirect(switchOutput) {
    if (applying) {
      applyAgain = true
      applySwitch = applySwitch || switchOutput
      return
    }
    applying = true
    var target = Multiroom.directTarget(speakers)
    var finished = function() {
      applying = false
      if (!applyAgain) return
      var again = applySwitch
      applyAgain = false
      applySwitch = false
      applyDirect(again)
    }
    run(["pactl", "list", "modules", "short"], function(code, out) {
      if (config.mode !== "direct") { finished(); return }
      var modules = Multiroom.parseModules(out)
      var combine = Multiroom.findModules(modules, "module-combine-sink", Multiroom.COMBINE_SINK)
      var keep = target.kind === "combine" && combine.length === 1
        && Multiroom.sameList(Multiroom.combinedSinks(combine[0]), target.sinks)
      var unload = function(next) {
        if (keep) { next(); return }
        combine.forEach(function(entry) { run(["pactl", "unload-module", String(entry.index)]) })
        run(["true"], next)
      }
      log("direct output: " + target.kind + (target.sinks.length ? " " + target.sinks.join(", ") : ""))
      if (target.kind === "none") {
        restoreDefault(function() { unload(finished) })
      } else if (target.kind === "single") {
        setDefault(target.sinks[0], function() { unload(finished) })
      } else {
        unload(function() {
          var point = function() {
            if (switchOutput || combine.length > 0) setDefault(Multiroom.COMBINE_SINK, finished)
            else finished()
          }
          if (keep) { point(); return }
          run(Multiroom.combineSinkArgs(target.sinks, "AirPlay " + strings.modes.direct), function(loadCode) {
            if (loadCode !== 0) error = strings.commandFailed
            run(["pactl", "set-sink-volume", Multiroom.COMBINE_SINK, "100%"], point)
          })
        })
      }
    })
  }

  // ---- Multiroom: OwnTone ------------------------------------------------------------

  function setupMultiroom(callback) {
    starting = true
    publish()
    findOwntone(guard(function(binary) {
      if (!binary) {
        log("no OwnTone binary found")
        problem = "owntone-missing"
        starting = false
        publish()
        if (callback) callback()
        return
      }
      // Builds without the HomePod OS 27 user agent are refused by HomePods.
      run(["grep", "-qaF", Multiroom.OS27_USER_AGENT, binary], guard(function(grepCode) {
        owntoneOld = grepCode !== 0
        log("OwnTone " + binary + (owntoneOld ? " (too old for HomePod OS 27)" : ""))
        run(["install", "-d", "-m", "700", stateDir, libraryDir, stateDir + "/cache"], guard(function() {
          var text = Multiroom.owntoneConfig({ user: user, stateDir: stateDir, libraryDir: libraryDir })
          run(["cat", owntoneConfPath], guard(function(catCode, current) {
            // A running OwnTone with an older config is restarted.
            var changed = catCode !== 0 || current !== text
            if (changed) owntoneConf.setText(text)
            var start = function() {
              ensurePipe(guard(function() {
                restoreUntil = Date.now() + restoreWindow
                owntoneReadyAt = 0
                owntoneFailures = 0
                pipePending = true
                ensureOwntone(function() { if (callback) callback() })
              }))
            }
            if (changed && catCode === 0) {
              log("OwnTone config changed, restarting OwnTone")
              stopOwntone(guard(start))
            } else {
              start()
            }
          }))
        }))
      }))
    }))
  }

  // The binary from the settings, else a current build from
  // tools/build-owntone.sh, else the packaged one.
  function findOwntone(callback) {
    if (owntoneBinary) { callback(owntoneBinary); return }
    var candidates = [owntoneSetting, builtOwntone, "/usr/bin/owntone", "/usr/sbin/owntone", "/usr/local/sbin/owntone"]
      .filter(function(path) { return path && path.charAt(0) === "/" })
    function next(index) {
      if (index >= candidates.length) { callback(""); return }
      run(["test", "-x", candidates[index]], function(code) {
        if (code === 0) {
          owntoneBinary = candidates[index]
          callback(owntoneBinary)
        } else {
          next(index + 1)
        }
      })
    }
    next(0)
  }

  function ensurePipe(callback) {
    run(["pactl", "list", "modules", "short"], function(code, out) {
      if (Multiroom.findModules(Multiroom.parseModules(out), "module-pipe-sink", Multiroom.PIPE_SINK).length > 0) { callback(); return }
      run(Multiroom.pipeSinkArgs(fifoPath, strings.title + " (OwnTone)"), function(loadCode) {
        if (loadCode !== 0) error = strings.commandFailed
        run(["pactl", "set-sink-volume", Multiroom.PIPE_SINK, "100%"], function() { callback() })
      })
    })
  }

  function ensureOwntone(callback) {
    run(["systemctl", "--user", "is-active", Multiroom.OWNTONE_UNIT], function(code, out) {
      var active = String(out || "").trim()
      if (active === "active" || active === "activating") { callback(); return }
      // No sound may reach the pipe while OwnTone starts: it would start
      // playing at once, on the speakers from its database and as AirPlay 1,
      // before they show up as AirPlay 2. reselect() moves the sound back.
      restoreDefault(function() { startOwntone(callback) })
    })
  }

  // OwnTone 29.3 aborts when it is terminated while it reads the pipe
  // (double free in the pipe watcher). Stopping playback first avoids that.
  function stopOwntone(callback) {
    run(["systemctl", "--user", "is-active", Multiroom.OWNTONE_UNIT], function(code, out) {
      if (String(out || "").trim() !== "active") { callback(); return }
      api("PUT", "/api/player/stop", null, function() {
        run(["systemctl", "--user", "stop", Multiroom.OWNTONE_UNIT], function() { callback() })
      })
    })
  }

  function startOwntone(callback) {
    run(["systemctl", "--user", "reset-failed", Multiroom.OWNTONE_UNIT], function() {
      run(Multiroom.owntoneStartArgs(owntoneBinary, owntoneConfPath), function(startCode) {
        if (startCode !== 0) problem = "owntone-failed"
        publish()
        callback()
      })
    })
  }

  // ---- Volume keys in multiroom mode --------------------------------------------

  // The pipe carries the sound at full level; turning it down would only
  // hand the speakers a weaker signal. Volume keys change the pipe sink, so
  // each change becomes a step of OwnTone's master volume (all rooms keep
  // their balance) and the pipe goes back to 100 %.
  property bool pipeVolumeBusy: false

  function checkPipeVolume() {
    if (config.mode !== "multiroom" || pipeVolumeBusy) return
    pipeVolumeBusy = true
    run(["pactl", "get-sink-volume", Multiroom.PIPE_SINK], function(code, out) {
      var level = code === 0 ? Multiroom.parseVolumeLine(out) : null
      if (level === null || level === 100) { pipeVolumeBusy = false; return }
      var step = level - 100
      log("volume key: pipe at " + level + " %, master " + (step > 0 ? "+" : "") + step)
      api("PUT", "/api/player/volume?step=" + step, null, function() {
        run(["pactl", "set-sink-volume", Multiroom.PIPE_SINK, "100%"], function() {
          pipeVolumeBusy = false
          pollTimer.restart()
        })
      })
    })
  }

  // Direct mode with several rooms: the combine sink would only weaken the
  // signal as well. A change of it moves each room's own volume instead.
  function checkCombineVolume() {
    if (config.mode !== "direct" || pipeVolumeBusy) return
    pipeVolumeBusy = true
    run(["pactl", "get-sink-volume", Multiroom.COMBINE_SINK], function(code, out) {
      var level = code === 0 ? Multiroom.parseVolumeLine(out) : null
      if (level === null || level === 100) { pipeVolumeBusy = false; return }
      var step = level - 100
      var volumes = Object.assign({}, config.direct.volumes)
      var rooms = speakers.filter(function(s) { return s.selected && s.sink })
      log("volume key: combined output at " + level + " %, rooms " + (step > 0 ? "+" : "") + step)
      rooms.forEach(function(room) {
        var next = Multiroom.clampPercent(directVolume(room.name) + step)
        volumes[room.name] = next
        hold(room.key, { volume: next })
        run(["pactl", "set-sink-volume", room.sink, next + "%"])
      })
      saveDirect({ volumes: volumes })
      run(["pactl", "set-sink-volume", Multiroom.COMBINE_SINK, "100%"], function() {
        pipeVolumeBusy = false
      })
    })
  }

  function checkVolumes() {
    if (config.mode === "multiroom") checkPipeVolume()
    else if (config.mode === "direct") checkCombineVolume()
  }

  function multiVolume(key) {
    return Multiroom.roomVolume(config.multiroom.volumes, key)
  }

  function pollMultiroom(done) {
    run(["pactl", "list", "modules", "short"], function(code, out) {
      // PipeWire restarted: the pipe sink has to come back.
      if (Multiroom.findModules(Multiroom.parseModules(out), "module-pipe-sink", Multiroom.PIPE_SINK).length === 0) {
        log("pipe sink missing, loading it again")
        ensurePipe(guard(function() { if (!pipePending) setDefault(Multiroom.PIPE_SINK) }))
      }
      api("GET", "/api/outputs", null, function(ok, body) {
        if (config.mode !== "multiroom") { done(); return }
        var found = ok ? Multiroom.parseOutputs(body) : null
        if (found === null) { owntoneDown(); done(); return }
        if (owntoneReadyAt === 0) {
          owntoneReadyAt = Date.now()
          log("OwnTone answers")
        }
        owntoneFailures = 0
        starting = false
        if (problem === "owntone-failed") problem = ""
        rememberKnown(found)
        noticeDropouts(found)
        var list = Multiroom.withMissing(found, config.multiroom.rooms, config.multiroom.known, function(s) { return s.key })
        Multiroom.speakerChanges(speakers, list).forEach(function(line) { log(line) })
        speakers = list
        statusMessage = found.length === 0 ? strings.searching : ""
        publish()
        if (restoreDue(found, config.multiroom.rooms, function(s) { return s.key }, config.multiroom.known)) reselect(found)
        else if (restoreUntil === 0) retryDropped(found)
        done()
      })
    })
  }

  // Names and kinds of the chosen rooms, so they can be shown while away.
  function rememberKnown(found) {
    var known = config.multiroom.known
    var changed = false
    var next = {}
    config.multiroom.rooms.forEach(function(key) {
      var speaker = null
      for (var i = 0; i < found.length; i++) if (found[i].key === key) speaker = found[i]
      next[key] = speaker ? { name: speaker.name, kind: speaker.kind } : (known[key] || { name: key, kind: "airplay2" })
      if (!known[key] || known[key].name !== next[key].name || known[key].kind !== next[key].kind) changed = true
    })
    if (changed || Object.keys(known).length !== Object.keys(next).length) saveMulti({ known: next })
  }

  // A chosen room that OwnTone deselected on its own lost its session.
  function noticeDropouts(found) {
    if (restoreUntil !== 0) return
    found.forEach(function(speaker) {
      var wanted = config.multiroom.rooms.indexOf(speaker.key) >= 0
      var before = null
      for (var i = 0; i < speakers.length; i++) if (speakers[i].key === speaker.key) before = speakers[i]
      if (wanted && before && before.selected && !before.missing && !speaker.selected && !held(speaker.key)) {
        log("dropped: " + speaker.name + " [" + speaker.kind + "], see owntone.log")
        setFailure(speaker.key, "dropped")
      }
      if (speaker.selected && failures[speaker.key]) setFailure(speaker.key, "")
    })
  }

  // Chosen rooms that are around but not playing are asked again, a few
  // times and not too often, so a speaker that woke up joins by itself.
  function retryDropped(found) {
    var now = Date.now()
    found.forEach(function(speaker) {
      if (config.multiroom.rooms.indexOf(speaker.key) < 0 || speaker.selected || held(speaker.key)) return
      var entry = retries[speaker.key] || { count: 0, at: 0 }
      if (entry.count >= retryLimit || now - entry.at < retryGap) return
      var next = Object.assign({}, retries)
      next[speaker.key] = { count: entry.count + 1, at: now }
      retries = next
      log("retry " + (entry.count + 1) + "/" + retryLimit + ": " + speaker.name)
      selectOutput(speaker, true)
    })
  }

  function owntoneDown() {
    owntoneFailures += 1
    if (owntoneFailures === 1 || owntoneFailures % 10 === 0) log("OwnTone API not answering (" + owntoneFailures + ")")
    if (!owntoneBinary) return
    run(["systemctl", "--user", "is-active", Multiroom.OWNTONE_UNIT], guard(function(code, out) {
      var active = String(out || "").trim()
      if (active !== "active" && active !== "activating") {
        // Gone or failed: start it again, but give up after a few tries.
        log("OwnTone unit " + (active || "gone"))
        if (owntoneFailures > 4) { problem = "owntone-failed"; starting = false; publish(); return }
        owntoneReadyAt = 0
        restoreUntil = Date.now() + restoreWindow
        pipePending = true
        ensureOwntone(function() {})
      } else if (owntoneFailures > 10) {
        problem = "owntone-failed"
        starting = false
        publish()
      }
    }))
  }

  // True once every remembered room was found, or the wait is over. OwnTone
  // first lists a speaker as AirPlay 1 and switches it to AirPlay 2 a few
  // seconds later; selecting it before that starts an AirPlay 1 session,
  // which HomePods refuse. So a room last seen as AirPlay 2 has to show up as
  // AirPlay 2 again.
  function restoreDue(list, rooms, idOf, known) {
    if (restoreUntil === 0) return false
    if (Date.now() > restoreUntil) return true
    if (known && (owntoneReadyAt === 0 || Date.now() - owntoneReadyAt < 3000)) return false
    return rooms.every(function(id) {
      var speaker = null
      for (var i = 0; i < list.length; i++) if (idOf(list[i]) === id) speaker = list[i]
      if (!speaker) return false
      return !known || !known[id] || known[id].kind !== "airplay2" || speaker.kind === "airplay2"
    })
  }

  // After OwnTone started, the rooms of the last session play again; then
  // the sound moves to the pipe.
  function reselect(found) {
    restoreUntil = 0
    // Of a speaker remembered as AirPlay and as Chromecast, AirPlay plays.
    var present = found.filter(function(speaker) { return config.multiroom.rooms.indexOf(speaker.key) >= 0 })
    var wanted = present.filter(function(speaker) {
      return speaker.kind !== "chromecast" || !present.some(function(other) {
        return other.name === speaker.name && other.kind !== "chromecast"
      })
    }).map(function(speaker) { return speaker.key })
    var dropped = present.filter(function(speaker) { return wanted.indexOf(speaker.key) < 0 })
    if (dropped.length > 0) saveMulti({ rooms: config.multiroom.rooms.filter(function(key) {
      return !dropped.some(function(speaker) { return speaker.key === key })
    }) })
    log("rooms restored: " + (wanted.map(function(key) {
      var s = found.filter(function(x) { return x.key === key })[0]
      return s.name + " [" + s.kind + "]"
    }).join(", ") || "none"))
    var done = guard(function() {
      pipePending = false
      setDefault(Multiroom.PIPE_SINK)
      pollTimer.restart()
    })
    api("PUT", "/api/outputs/set", { outputs: wanted }, guard(function() {
      wanted.forEach(function(key) {
        api("PUT", "/api/outputs/" + encodeURIComponent(key), { volume: multiVolume(key) })
      })
      run(["true"], done)
    }))
  }

  // ---- Speaker actions ----------------------------------------------------------------

  function speaker(key) {
    for (var i = 0; i < speakers.length; i++) if (speakers[i].key === key) return speakers[i]
    return null
  }

  function selectOutput(target, on) {
    var body = on ? { selected: true, volume: multiVolume(target.key) } : { selected: false }
    api("PUT", "/api/outputs/" + encodeURIComponent(target.key), body, guard(function(ok) {
      if (on && !ok) {
        // OwnTone answers 400 when the speaker refused the session.
        setFailure(target.key, "refused")
        error = strings.connectFailed.replace("%1", target.name)
        log("refused: " + target.name + " [" + target.kind + "], see owntone.log")
      } else if (ok) {
        setFailure(target.key, "")
      }
      pollTimer.restart()
    }))
  }

  function setSelected(key, on) {
    var target = speaker(key)
    if (!target || switching) return false
    error = ""
    log((on ? "select " : "deselect ") + target.name + " [" + target.kind + "]")
    hold(key, { selected: !!on })
    if (config.mode === "direct") {
      var rooms = config.direct.rooms.filter(function(name) { return name !== key })
      if (on) rooms.push(key)
      saveDirect({ rooms: rooms })
      speakers = Model.patchSpeakers(speakers, key, { selected: !!on })
      if (target.missing && !on) { speakers = speakers.filter(function(s) { return s.key !== key }); publish(); return true }
      // The room's volume before any sound reaches it.
      if (on && target.sink) {
        run(["pactl", "set-sink-volume", target.sink, directVolume(target.name) + "%"])
        hold(key, { volume: directVolume(target.name) })
      }
      applyDirect(true)
      return true
    }
    if (config.mode === "multiroom") {
      // One device, one session: AirPlay and Chromecast of the same speaker
      // exclude each other.
      var twins = on ? speakers.filter(function(s) {
        return s.key !== key && s.name === target.name && (s.selected || config.multiroom.rooms.indexOf(s.key) >= 0)
      }) : []
      var ids = config.multiroom.rooms.filter(function(id) {
        return id !== key && !twins.some(function(t) { return t.key === id })
      })
      if (on) ids.push(key)
      saveMulti({ rooms: ids })
      var next = Object.assign({}, retries)
      delete next[key]
      retries = next
      setFailure(key, "")
      if (target.missing) { speakers = speakers.filter(function(s) { return s.key !== key }); publish(); return true }
      twins.forEach(function(twin) {
        log("deselect " + twin.name + " [" + twin.kind + "] (same device)")
        hold(twin.key, { selected: false })
        if (!twin.missing) selectOutput(twin, false)
      })
      if (on) hold(key, { volume: multiVolume(key) })
      selectOutput(target, !!on)
      return true
    }
    return false
  }

  // Picks how a device is reached (AirPlay or Chromecast). A playing device
  // switches over right away.
  function setVariant(name, kind) {
    var variants = speakers.filter(function(s) { return s.name === name })
    var target = variants.filter(function(s) { return s.kind === kind })[0]
    if (config.mode !== "multiroom" || !target) return false
    var via = Object.assign({}, config.multiroom.via)
    via[name] = kind
    saveMulti({ via: via })
    log("connection of " + name + ": " + kind)
    var playing = variants.some(function(s) { return s.key !== target.key && (s.selected || config.multiroom.rooms.indexOf(s.key) >= 0) })
    if (playing) setSelected(target.key, true)
    return true
  }

  function toggle(key) {
    var target = speaker(key)
    return target ? setSelected(key, !target.selected) : false
  }

  function setVolume(key, value) {
    var target = speaker(key)
    var volume = Multiroom.clampPercent(value)
    if (!target || target.missing) return false
    hold(key, { volume: volume })
    log("volume " + target.name + " " + volume + " %")
    if (config.mode === "direct") {
      var volumes = Object.assign({}, config.direct.volumes)
      volumes[target.name] = volume
      saveDirect({ volumes: volumes })
      run(["pactl", "set-sink-volume", target.sink, volume + "%"], function(code) {
        if (code !== 0) error = strings.commandFailed
      })
      return true
    }
    if (config.mode === "multiroom") {
      var multi = Object.assign({}, config.multiroom.volumes)
      multi[key] = volume
      saveMulti({ volumes: multi })
      api("PUT", "/api/outputs/" + encodeURIComponent(key), { volume: volume }, function(ok) {
        if (!ok) error = strings.commandFailed
      })
      return true
    }
    return false
  }

  // Positive values delay the room (OwnTone accepts -2000 … 2000 ms).
  function setOffset(key, value) {
    var offset = Math.max(-2000, Math.min(2000, Math.round(Number(value) || 0)))
    if (config.mode !== "multiroom" || !speaker(key)) return false
    hold(key, { offsetMs: offset })
    api("PUT", "/api/outputs/" + encodeURIComponent(key), { offset_ms: offset }, function(ok) {
      if (!ok) error = strings.commandFailed
    })
    return true
  }

  // Apple TVs show a PIN when OwnTone asks to pair.
  function sendPin(key, pin) {
    var value = String(pin || "").replace(/\D/g, "")
    if (config.mode !== "multiroom" || !speaker(key) || value === "") return false
    api("PUT", "/api/outputs/" + encodeURIComponent(key), { pin: value }, function(ok) {
      error = ok ? "" : strings.commandFailed
      pollTimer.restart()
    })
    return true
  }

  function refresh() {
    // A reading that hangs for long is not waited for forever.
    if (polling && Date.now() - pollStarted < 15000) return
    if (config.mode !== "direct" && config.mode !== "multiroom") return
    polling = true
    pollStarted = Date.now()
    var done = function() { polling = false }
    if (config.mode === "direct") pollDirect(done)
    else pollMultiroom(done)
  }

  // Brings the mode from config.json back after a shell or PipeWire restart.
  function resume() {
    epoch += 1
    log("shell started, resuming " + config.mode)
    if (config.mode === "direct") setupDirect(function() {})
    else if (config.mode === "multiroom") setupMultiroom(function() {})
    else teardown("", function() {})
  }

  // ---- Plumbing -----------------------------------------------------------------------------

  Process {
    id: runner
    stdout: StdioCollector { id: runnerOut; waitForEnd: true }
    stderr: StdioCollector { id: runnerErr; waitForEnd: true }
    onExited: function(exitCode) {
      var done = root.current
      root.current = null
      if (done && !root.quiet(done.argv)) {
        var err = String(runnerErr.text || "").trim().replace(/\s+/g, " ").slice(0, 300)
        root.log("$ " + done.argv.join(" ") + " -> " + exitCode + (err ? " (" + err + ")" : ""))
      }
      if (done && done.callback) done.callback(exitCode, runnerOut.text)
      Qt.callLater(root.pump)
    }
  }

  Timer {
    id: pollTimer
    // Fast while the panel is open or remembered rooms are awaited.
    interval: root.watching || root.restoreUntil > 0 ? 1500 : 8000
    repeat: true
    running: root.loaded && root.config.mode !== "off" && !root.switching
    onTriggered: {
      // Drop settled optimistic changes, then read the real state.
      var now = Date.now()
      var kept = {}
      Object.keys(root.holds).forEach(function(key) { if (root.holds[key].until > now) kept[key] = root.holds[key] })
      root.holds = kept
      root.refresh()
    }
  }

  // RAOP discovery takes a few seconds to announce the first speakers.
  // Sink changes (volume keys, audio panel) while a mode is on.
  Process {
    id: sinkEvents
    command: ["pactl", "subscribe"]
    running: root.loaded && root.config.mode !== "off" && !root.switching
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("'change' on sink #") >= 0) pipeVolumeTimer.restart()
      }
    }
  }

  Timer {
    id: errorTimer
    interval: 20000
    onTriggered: root.error = ""
  }

  // Volume keys repeat; one check after the burst.
  Timer {
    id: pipeVolumeTimer
    interval: 150
    onTriggered: root.checkVolumes()
  }

  Timer {
    id: discoveryTimer
    interval: 1500
    onTriggered: root.refresh()
  }

  Timer {
    id: delayTimer
    property var step: null
    onTriggered: {
      var run = step
      step = null
      if (run) run()
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.logDirty
    onTriggered: root.flushLog()
  }

  // FileView does not create parent directories.
  Process {
    id: dirProc
    command: ["install", "-d", "-m", "700", root.configDir, root.stateDir]
    running: true
    onExited: {
      pluginLog.reload()
      configFile.reload()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    printErrors: false
    onLoaded: {
      if (root.loaded) return
      var parsed = null
      try { parsed = JSON.parse(text()) } catch (e) { parsed = null }
      root.config = root.normalizeConfig(parsed)
      root.loaded = true
      root.publish()
      root.resume()
    }
    onLoadFailed: {
      if (root.loaded) return
      root.config = root.normalizeConfig(null)
      root.loaded = true
      root.publish()
    }
  }

  FileView {
    id: owntoneConf
    path: root.owntoneConfPath
    printErrors: false
    // OwnTone starts right after the write and must read the new file.
    blockWrites: true
  }

  // Earlier sessions are kept; the newest lines win when the log is full.
  FileView {
    id: pluginLog
    path: root.pluginLogPath
    printErrors: false
    onLoaded: {
      if (root.logLoaded) return
      var earlier = String(text() || "").split("\n").filter(function(line) { return line !== "" })
      root.logLines = earlier.concat(root.logLines).slice(-3000)
      root.logLoaded = true
      root.logDirty = true
    }
    onLoadFailed: {
      root.logLoaded = true
      root.logDirty = true
    }
  }
}
