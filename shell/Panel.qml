import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup. Holds no speaker state of its own — everything comes from the
// service; this file only decides what to show and forwards actions.
Panel {
  id: root
  moduleName: "io.github.mahype.omarchy-multiroom-speakers"
  ipcTarget: moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property var strings: Model.strings(Qt.locale().name)
  readonly property var state: service ? service.state : Model.emptyState()
  readonly property string mode: state.mode
  readonly property bool switching: service ? service.switching : false
  // One row per device; AirPlay and Chromecast of one speaker share it.
  readonly property var devices: Model.groupSpeakers(state.speakers, state.via)

  // Only one device is expanded at a time; nothing stays expanded between
  // opens. Kept by name: the key changes with the connection.
  property string expandedKey: ""
  // Text field with focus; the key catcher leaves typing alone meanwhile.
  property var focusedField: null

  function toggleExpanded(key) { expandedKey = expandedKey === key ? "" : key }

  function expandByName(name) {
    var speaker = Model.speakerByName(state.speakers, name)
    if (!speaker) return false
    expandedKey = speaker.name
    return true
  }

  function open() {
    controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    controller.hide()
  }

  onOpenedChanged: {
    if (service) service.watching = opened
    if (opened) {
      panelFlick.contentY = 0
      if (service) service.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      expandedKey = ""
      focusedField = null
    }
  }

  onModeChanged: expandedKey = ""

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.focusedField !== null
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: scrollBar; policy: ScrollBar.AsNeeded }

        Column {
          id: column
          // Keep the switches clear of the scrollbar when the list scrolls.
          width: panelFlick.width - (panelFlick.interactive ? scrollBar.width + Style.space(8) : 0)
          spacing: Style.space(12)

          // ---------- Header: title · summary ----------
          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.strings.title
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            HintText {
              bar: root.bar
              width: parent.width
              text: Model.summary(root.state, root.strings)
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Mode ----------
          ButtonGroup {
            options: [
              { value: "off", label: root.strings.modes.off },
              { value: "direct", label: root.strings.modes.direct },
              { value: "multiroom", label: root.strings.modes.multiroom }
            ]
            value: root.mode
            enabled: !root.switching
            opacity: enabled ? 1 : 0.5
            focusable: false
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(value) { if (root.service) root.service.setMode(value) }
          }

          HintText {
            bar: root.bar
            width: parent.width
            text: root.strings.modeHints[root.mode] || ""
          }

          // ---------- Feedback ----------
          HintText {
            bar: root.bar
            readonly property string problem: Model.problemText(root.state, root.strings)
            readonly property bool isError: problem !== "" || (root.service !== null && root.service.error !== "")
            visible: text !== ""
            width: parent.width
            text: problem || (root.service ? (root.service.error || root.service.statusMessage) : "")
            color: isError ? root.bar.urgent : root.bar.foreground
            opacity: isError ? 1 : 0.6
          }

          HintText {
            bar: root.bar
            visible: root.mode === "multiroom" && root.state.owntoneOld === true
            width: parent.width
            text: root.strings.owntoneOld
            color: root.bar.urgent
            opacity: 1
          }

          // ---------- Speakers ----------
          Column {
            visible: root.mode !== "off" && root.devices.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: root.strings.speakers; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Repeater {
              model: root.devices
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(10)

                PanelSeparator { visible: index > 0; foreground: root.bar.foreground; opacity: 0.5 }

                SpeakerRow {
                  width: parent.width
                  bar: root.bar
                  service: root.service
                  speaker: modelData
                  mode: root.mode
                  expanded: root.expandedKey === modelData.name
                  onExpandToggled: root.toggleExpanded(modelData.name)
                  onFieldFocus: function(field) { root.focusedField = field }
                }
              }
            }
          }

          HintText {
            bar: root.bar
            visible: root.mode !== "off" && root.state.speakers.length === 0 && root.state.problem === ""
              && (root.service === null || root.service.statusMessage === "")
            width: parent.width
            text: root.strings.noSpeakers
          }
        }
      }
    }
  }
}
