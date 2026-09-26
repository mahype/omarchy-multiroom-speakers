import QtQuick
import qs.Commons
import qs.Ui

// Icon · slider · value. Commits on release.
Item {
  id: sRow
  property QtObject bar: null
  property string glyph: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 100
  property real step: 5
  property string unit: " %"
  signal committed(real value)

  implicitHeight: slider.implicitHeight

  Text {
    id: icon
    // Fixed width, so sliders with different icons line up.
    width: Style.space(18)
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: sRow.glyph
    color: sRow.bar.foreground
    font.family: sRow.bar.fontFamily
    font.pixelSize: Style.font.body
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }

  PanelSlider {
    id: slider
    bar: sRow.bar
    minimum: sRow.minimum
    maximum: sRow.maximum
    step: sRow.step
    integer: true
    value: sRow.value
    anchors.left: icon.right
    anchors.leftMargin: Style.space(10)
    anchors.right: valueText.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    onReleased: function(v) { sRow.committed(v) }
  }

  // The mouse wheel scrolls the panel instead of turning the volume up while
  // passing over a slider. Clicks and drags still reach the slider.
  MouseArea {
    anchors.fill: slider
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      var view = sRow.scrollView()
      if (!view) return
      var delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
      var bottom = Math.max(0, view.contentHeight - view.height)
      view.contentY = Math.max(0, Math.min(bottom, view.contentY - delta))
    }
  }

  function scrollView() {
    for (var item = sRow.parent; item; item = item.parent)
      if (item.contentY !== undefined && item.flickableDirection !== undefined) return item
    return null
  }

  Text {
    id: valueText
    textFormat: Text.PlainText
    text: Math.round(slider.liveValue) + sRow.unit
    color: sRow.bar.foreground
    font.family: sRow.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    width: Style.space(64)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
}
