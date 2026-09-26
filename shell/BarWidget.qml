import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.mahype.omarchy-multiroom-speakers"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var state: service ? service.state : Model.emptyState()
  readonly property bool on: state.mode !== "off"
  // Red only when something went wrong.
  readonly property bool attention: Model.needsAttention(state, service ? service.error : "")
  readonly property var strings: Model.strings(Qt.locale().name)
  readonly property string countText: setting("showRoomsInBar", true) === true ? Model.barText(state) : ""
  readonly property string glyph: Model.glyph(state.mode)
  readonly property var anchorButton: countText !== "" ? textButton : iconButton
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function applySettings() {
    if (service) service.owntoneSetting = String(setting("owntoneBinary", "") || "").trim()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.anchorButton
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function tooltip() {
    return Model.tooltip(state, service ? service.error : "", strings)
  }

  implicitWidth: anchorButton.implicitWidth
  implicitHeight: anchorButton.implicitHeight
  onBarChanged: injectPanel()
  onServiceChanged: { injectPanel(); applySettings() }
  onSettingsChanged: { injectPanel(); applySettings() }
  onAnchorButtonChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens the panel with one speaker unfolded, e.g. for a keybinding.
    function expand(name: string): string {
      if (!panelLoader.item) return "unavailable"
      root.open()
      return panelLoader.item.expandByName(name) ? "ok" : "unknown"
    }
    // Switches the mode: "off", "direct" or "multiroom".
    function mode(name: string): string {
      if (!root.service) return "unavailable"
      var value = String(name || "").toLowerCase()
      if (["off", "direct", "multiroom"].indexOf(value) < 0) return "invalid"
      return root.service.setMode(value) ? "ok" : "busy"
    }
    // Current mode and the selected rooms, e.g. "multiroom: Bad, Küche".
    function status(): string {
      if (!root.service) return "unavailable"
      var rooms = root.state.speakers.filter(function(s) { return s.selected }).map(function(s) { return s.name })
      return root.state.mode + (rooms.length > 0 ? ": " + rooms.join(", ") : "")
    }
    // Adds or removes a room by name: state is "on", "off" or "toggle".
    function room(name: string, state: string): string {
      if (!root.service) return "unavailable"
      var speaker = Model.speakerByName(root.state.speakers, name)
      if (!speaker) return "unknown"
      if (state === "toggle") return root.service.toggle(speaker.key) ? "ok" : "unavailable"
      if (state !== "on" && state !== "off") return "invalid"
      return root.service.setSelected(speaker.key, state === "on") ? "ok" : "unavailable"
    }
  }

  WidgetButton {
    id: textButton
    anchors.fill: parent
    visible: root.countText !== ""
    bar: root.bar
    text: root.glyph + " " + root.countText
    active: root.attention
    tooltipText: root.tooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    visible: root.countText === ""
    bar: root.bar
    text: root.glyph
    active: root.attention
    tooltipText: root.tooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

}
