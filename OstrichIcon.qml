import QtQuick
import QtQuick.Effects

// The Omastr ostrich, tinted to whatever color the surface wants.
//
// Same recipe as the shell's symbolic tray icons (and Omostrich's bar chip):
// a white-on-transparent raster of the SVG underneath, fully colorized by a
// MultiEffect on top. If the effect ever fails to render, the white fallback
// still reads as a light mark instead of a black blob. The badge dot is the
// Tailscale-widget pattern: a small filled circle in the top-right corner.
Item {
  id: root

  property real iconSize: 16
  property color color: "#ffffff"
  property color badgeColor: "#e05555"
  property color badgeTextColor: "#000000"
  property int badgeCount: 0

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: silhouette
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    smooth: true
    sourceSize.width: Math.round(root.iconSize * 2)
    sourceSize.height: Math.round(root.iconSize * 2)
    source: Qt.resolvedUrl("assets/ostrich.svg")
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: silhouette
    source: silhouette
    visible: silhouette.status === Image.Ready
    colorization: 1.0
    colorizationColor: root.color
  }

  Rectangle {
    visible: root.badgeCount > 0
    width: Math.max(7, parent.width * 0.46)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: -parent.height * 0.06
    anchors.rightMargin: -parent.width * 0.06

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.badgeCount > 9 ? "9+" : String(root.badgeCount)
      color: root.badgeTextColor
      font.pixelSize: Math.max(6, parent.height * (root.badgeCount > 9 ? 0.5 : 0.72))
      font.bold: true
    }
  }
}
