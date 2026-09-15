import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// The Omastr wall: a Tenna-style home screen for installed Nostr apps and
// nsites. Everything on it is the user's, in the user's order; a tile's
// channel is its place counted down the wall, and the plus tile at the end
// opens the catalog. Summoned via `omarchy-shell shell toggle lemon.omastr`
// (bar ostrich, or a keybind).
//
// Tiles are read from ~/.config/omastr/wall.json — a JSON array of
//   { "id": string, "name": string, "icon": path-or-url|null, "exec": [argv] }
// written by the installers (`omastr` CLI / catalog). The overlay only draws
// and launches; it never writes the file.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property int selectedIndex: 0
  property var tiles: []

  // Shares the [menu] surface tokens so themes that style the menu style us.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int cellSize: Style.space(120)
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(440), panel.height - Style.gapsOut * 2)
  property int columns: Math.max(1, Math.floor((cardWidth - contentMargin * 2) / cellSize))

  // Tiles plus the trailing plus-tile; selection indexes into this.
  readonly property int slotCount: tiles.length + 1

  function configPath() {
    return (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omastr/wall.json"
  }

  function open(payloadJson) {
    root.opened = true
    root.selectedIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lemon.omastr")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadWall(raw) {
    var next = []
    try {
      var parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) {
        for (var i = 0; i < parsed.length; i++) {
          var t = parsed[i]
          if (!t || typeof t.name !== "string" || !Array.isArray(t.exec) || t.exec.length === 0) continue
          next.push({
            id: String(t.id || t.name),
            name: t.name,
            icon: typeof t.icon === "string" && t.icon !== "" ? t.icon : null,
            exec: t.exec.map(String)
          })
        }
      }
    } catch (e) {
      // A malformed wall draws as empty rather than wedging the overlay.
    }
    root.tiles = next
    if (root.selectedIndex >= root.slotCount) root.selectedIndex = root.slotCount - 1
  }

  function iconSource(icon) {
    if (!icon) return ""
    if (icon.indexOf("/") === 0) return "file://" + icon
    return icon
  }

  function launchIndex(index) {
    if (index === root.tiles.length) {
      root.openCatalog()
      return
    }
    if (index < 0 || index >= root.tiles.length) return
    var tile = root.tiles[index]
    root.dismiss()
    Quickshell.execDetached(tile.exec)
  }

  // Resolved from this QML file's own URL (see Service.qml for why not the
  // injected manifest).
  readonly property string cli: {
    var url = Qt.resolvedUrl("bin/omastr").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  function openCatalog() {
    root.dismiss()
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation", root.cli, "catalog"
    ])
  }

  function move(delta) {
    if (root.slotCount === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.slotCount) % root.slotCount
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function moveRow(delta) {
    var next = root.selectedIndex + delta * root.columns
    if (next < 0 || next >= root.slotCount) return
    root.selectedIndex = next
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  FileView {
    path: root.configPath()
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadWall(text())
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omastr-wall"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveRow(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveRow(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launchIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            // Tune straight to a channel, counted down the wall.
            root.launchIndex(event.key - Qt.Key_1)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Row {
          width: parent.width
          spacing: Style.spacing.md

          OstrichIcon {
            iconSize: Style.font.title
            color: root.foreground
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "Omastr"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.tiles.length === 0 ? "nothing on the wall yet"
              : root.tiles.length === 1 ? "1 channel" : root.tiles.length + " channels"
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        GridView {
          id: grid
          width: parent.width
          height: parent.height - y
          clip: true
          cellWidth: root.cellSize
          cellHeight: root.cellSize
          model: root.slotCount
          interactive: contentHeight > height

          delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            readonly property bool isPlus: index === root.tiles.length
            readonly property var tile: isPlus ? null : root.tiles[index]
            readonly property bool selected: index === root.selectedIndex

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              radius: root.cornerRadius
              color: selected ? root.selectedBackground : "transparent"
              border.width: isPlus ? 1 : 0
              border.color: root.border

              Column {
                anchors.centerIn: parent
                spacing: Style.space(8)

                Item {
                  width: Style.space(52)
                  height: Style.space(52)
                  anchors.horizontalCenter: parent.horizontalCenter

                  Image {
                    anchors.fill: parent
                    visible: !isPlus && tile && tile.icon !== null && status === Image.Ready
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    source: isPlus || !tile ? "" : root.iconSource(tile.icon)
                  }

                  // Plus mark, or fallback initial for a tile with no icon.
                  Text {
                    anchors.centerIn: parent
                    visible: isPlus || !tile || tile.icon === null
                    text: isPlus ? "+" : (tile ? tile.name.charAt(0).toUpperCase() : "")
                    color: selected ? root.selectedText : root.foreground
                    opacity: isPlus ? 0.7 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(34)
                    font.bold: !isPlus
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: grid.cellWidth - Style.space(20)
                  text: isPlus ? "Add" : (tile ? tile.name : "")
                  color: selected ? root.selectedText : root.foreground
                  opacity: isPlus ? 0.7 : 0.9
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              // Channel number, counted down the wall.
              Text {
                visible: !isPlus && index < 9
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Style.space(6)
                text: String(index + 1)
                color: selected ? root.selectedText : root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.selectedIndex = index
                onClicked: root.launchIndex(index)
              }
            }
          }
        }
      }
    }
  }
}
