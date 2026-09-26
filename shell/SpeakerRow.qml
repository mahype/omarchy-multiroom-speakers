import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A device: switch and volume always in view. Unfolded (multiroom) it shows
// how the device is reached — AirPlay or Chromecast, when it offers both —,
// the delay against the other rooms and pairing.
Column {
  id: row

  property QtObject bar: null
  property var service: null
  // A device from Model.groupSpeakers(): a speaker plus its `variants`.
  property var speaker: null
  property string mode: "off"
  property bool expanded: false
  signal expandToggled()
  signal fieldFocus(var field)

  readonly property var strings: Model.strings(Qt.locale().name)
  readonly property bool present: speaker !== null && speaker.missing !== true
  readonly property bool hasVariants: speaker !== null && speaker.variants && speaker.variants.length > 1
  readonly property bool expandable: present && mode === "multiroom"

  spacing: Style.space(8)

  RowHeader {
    width: parent.width
    bar: row.bar
    name: row.speaker ? row.speaker.name : ""
    subtitle: Model.subtitle(row.speaker, row.strings)
    on: row.speaker ? row.speaker.selected === true : false
    // nf-md-cast_audio for Chromecast, nf-md-speaker otherwise
    glyph: String.fromCodePoint(row.speaker && row.speaker.kind === "chromecast" ? 0xF101E : 0xF04C3)
    expandable: row.expandable
    expanded: row.expanded
    // A remembered room that is away can still be switched off.
    opacity: row.present ? 1 : 0.45
    onExpandToggled: row.expandToggled()
    onSwitchToggled: if (row.service) row.service.toggle(row.speaker.key)
  }

  // Volume of every device, also of those not playing right now.
  SliderRow {
    visible: row.present && typeof row.speaker.volume === "number"
    x: Style.space(38)
    width: parent.width - x
    opacity: row.speaker && row.speaker.selected ? 1 : 0.5
    bar: row.bar
    glyph: String.fromCodePoint(0xF057E)  // volume-high
    value: row.speaker && typeof row.speaker.volume === "number" ? row.speaker.volume : 0
    onCommitted: function(v) { row.service.setVolume(row.speaker.key, v) }
  }

  Column {
    visible: row.expanded && row.expandable
    x: Style.space(38)
    width: parent.width - x
    spacing: Style.space(10)

    // AirPlay or Chromecast for a device that offers both.
    Column {
      visible: row.hasVariants
      width: parent.width
      spacing: Style.space(4)

      HintText {
        bar: row.bar
        text: row.strings.connection
        font.pixelSize: Style.font.caption
      }

      ButtonGroup {
        options: row.hasVariants ? row.speaker.variants.map(function(v) {
          return { value: v.kind, label: row.strings.kinds[v.kind] || v.kind }
        }) : []
        value: row.speaker ? row.speaker.kind : ""
        focusable: false
        foreground: row.bar.foreground
        fontFamily: row.bar.fontFamily
        fontSize: Style.font.bodySmall
        onChanged: function(value) { if (row.service) row.service.setVariant(row.speaker.name, value) }
      }

      HintText {
        visible: row.speaker !== null && row.speaker.kind === "chromecast"
        bar: row.bar
        width: parent.width
        text: row.strings.castHint
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      HintText {
        bar: row.bar
        text: row.strings.offset
        font.pixelSize: Style.font.caption
      }

      SliderRow {
        width: parent.width
        bar: row.bar
        glyph: String.fromCodePoint(0xF051F)  // timer-sand
        minimum: -1000
        maximum: 1000
        step: 25
        unit: " ms"
        value: row.speaker && typeof row.speaker.offsetMs === "number" ? row.speaker.offsetMs : 0
        onCommitted: function(v) { row.service.setOffset(row.speaker.key, v) }
      }

      HintText {
        bar: row.bar
        width: parent.width
        text: row.strings.offsetHint
        font.pixelSize: Style.font.caption
      }
    }

    HintText {
      visible: row.speaker !== null && row.speaker.needsPin === true
      bar: row.bar
      width: parent.width
      text: row.strings.pinHint.replace("%1", row.speaker ? row.speaker.name : "")
    }

    Item {
      visible: row.speaker !== null && row.speaker.needsPin === true
      width: parent.width
      implicitHeight: pinField.implicitHeight

      TextField {
        id: pinField
        anchors.left: parent.left
        anchors.right: pinButton.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: row.strings.pin
        font.family: row.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        foreground: row.bar.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        onActiveFocusChanged: row.fieldFocus(activeFocus ? pinField : null)
        onAccepted: pinButton.send()
      }

      Button {
        id: pinButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.strings.pair
        foreground: row.bar.foreground
        fontFamily: row.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        enabled: pinField.text.trim() !== ""
        function send() {
          if (!enabled) return
          if (row.service.sendPin(row.speaker.key, pinField.text)) pinField.text = ""
        }
        onClicked: send()
      }
    }
  }
}
