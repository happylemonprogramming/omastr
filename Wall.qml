import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// The Omastr wall: a Tenna-style home screen for installed Nostr apps and
// nsites. Everything on it is the user's, in the user's order; a tile's
// channel is its place counted down the wall, and the plus tile at the end
// flips to the catalog page — an app-store view of NIP-89 listings with the
// publisher's profile and whether the user follows them. Summoned via
// `omarchy-shell shell toggle lemon.omastr` (bar ostrich, or a keybind).
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

  // "wall" or "catalog"; the plus tile flips forward, Esc flips back.
  property string page: "wall"

  // Catalog state, fed by `omastr catalog --json`. The cached file renders
  // instantly on open while a fresh fetch runs behind it.
  property var apps: []
  property var filteredApps: []
  property int catalogIndex: 0
  property bool catalogFetching: false
  property string catalogError: ""

  // Two-step remove: first Delete/Enter arms (tile.id on the wall, app name
  // in the catalog), the next confirms. Any navigation disarms.
  property string pendingRemoveId: ""

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

  function cachePath() {
    return (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omastr/catalog.json"
  }

  function open(payloadJson) {
    root.opened = true
    root.page = "wall"
    root.selectedIndex = 0
    root.pendingRemoveId = ""
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
    if (root.pendingRemoveId === tile.id) {
      root.removeByName(tile.name)
      return
    }
    root.dismiss()
    Quickshell.execDetached(tile.exec)
  }

  function toggleRemoveArm(index) {
    if (index < 0 || index >= root.tiles.length) return
    var tile = root.tiles[index]
    if (root.pendingRemoveId === tile.id) root.removeByName(tile.name)
    else root.pendingRemoveId = tile.id
  }

  function removeByName(name) {
    if (removeProc.running) return
    root.pendingRemoveId = ""
    removeProc.command = [root.cli, "wall", "remove", "--purge", name]
    removeProc.running = true
  }

  function isInstalled(app) {
    for (var i = 0; i < root.tiles.length; i++) {
      var t = root.tiles[i]
      if (t.name === app.name || t.exec.indexOf(app.website) >= 0) return true
    }
    return false
  }

  // Enter/click in the catalog: install, or arm-then-remove when installed.
  function catalogPrimary(app) {
    if (!app) return
    if (root.isInstalled(app)) {
      if (root.pendingRemoveId === app.name) root.removeByName(app.name)
      else root.pendingRemoveId = app.name
    } else {
      root.installApp(app)
    }
  }

  // Resolved from this QML file's own URL (see Service.qml for why not the
  // injected manifest).
  readonly property string cli: {
    var url = Qt.resolvedUrl("bin/omastr").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  function openCatalog() {
    root.page = "catalog"
    root.catalogError = ""
    root.catalogIndex = 0
    root.pendingRemoveId = ""
    searchField.text = ""
    catalogCache.reload()
    if (!catalogProc.running) {
      root.catalogFetching = true
      catalogProc.running = true
    }
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function showWall() {
    root.page = "wall"
    root.pendingRemoveId = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function loadCatalog(raw) {
    var next = []
    try {
      var parsed = JSON.parse(raw)
      if (!Array.isArray(parsed)) return
      for (var i = 0; i < parsed.length; i++) {
        var a = parsed[i]
        if (!a || typeof a.name !== "string" || typeof a.website !== "string") continue
        next.push(a)
      }
    } catch (e) {
      return
    }
    root.apps = next
    root.updateFilter()
  }

  function updateFilter() {
    var q = searchField.text.toLowerCase()
    var out = []
    for (var i = 0; i < root.apps.length; i++) {
      var a = root.apps[i]
      if (!q
        || a.name.toLowerCase().indexOf(q) >= 0
        || (a.about || "").toLowerCase().indexOf(q) >= 0
        || (a.publisher_name || "").toLowerCase().indexOf(q) >= 0)
        out.push(a)
    }
    root.filteredApps = out
    if (root.catalogIndex >= out.length) root.catalogIndex = Math.max(0, out.length - 1)
  }

  function moveCatalog(delta) {
    if (root.filteredApps.length === 0) return
    root.pendingRemoveId = ""
    root.catalogIndex = Math.min(Math.max(root.catalogIndex + delta, 0), root.filteredApps.length - 1)
    appList.positionViewAtIndex(root.catalogIndex, ListView.Contain)
  }

  function installApp(app) {
    if (!app || installProc.running) return
    root.catalogError = ""
    installProc.command = [root.cli, "wall", "add", app.name, app.website, app.picture || ""]
    installProc.running = true
  }

  function move(delta) {
    if (root.slotCount === 0) return
    root.pendingRemoveId = ""
    root.selectedIndex = (root.selectedIndex + delta + root.slotCount) % root.slotCount
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function moveRow(delta) {
    var next = root.selectedIndex + delta * root.columns
    if (next < 0 || next >= root.slotCount) return
    root.pendingRemoveId = ""
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

  // Last fetch's cache: renders the catalog instantly while the refresh runs.
  // Not watched — the CLI replaces the file via mv, which inotify won't
  // follow; the fresh data arrives on the Process stdout instead.
  FileView {
    id: catalogCache
    path: root.cachePath()
    printErrors: false
    onLoaded: root.loadCatalog(text())
  }

  Process {
    id: catalogProc
    command: [root.cli, "catalog", "--json"]
    stdout: StdioCollector {
      id: catalogOut
      onStreamFinished: root.loadCatalog(catalogOut.text)
    }
    onExited: function(exitCode) {
      root.catalogFetching = false
      if (exitCode !== 0 && root.apps.length === 0)
        root.catalogError = "couldn't fetch the catalog — are your relays reachable?"
    }
  }

  Process {
    id: installProc
    onExited: function(exitCode) {
      if (exitCode === 0) root.showWall()
      else root.catalogError = "install failed — check the journal"
    }
  }

  // Uninstall: tile off the wall + launcher/icon gone (wall remove --purge).
  // The wall.json watch redraws whichever page is showing.
  Process {
    id: removeProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.catalogError = "remove failed — check the journal"
    }
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
          if (root.page !== "wall") {
            // Search field owns catalog keys; catch Esc if focus strays.
            if (event.key === Qt.Key_Escape) {
              root.showWall()
              event.accepted = true
            }
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.pendingRemoveId !== "") root.pendingRemoveId = ""
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
            root.toggleRemoveArm(root.selectedIndex)
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
          } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
            // The plus tile's own channel key.
            root.openCatalog()
            event.accepted = true
          }
        }
      }

      Column {
        visible: root.page === "wall"
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
            readonly property bool armed: !isPlus && tile !== null && root.pendingRemoveId === tile.id

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              radius: root.cornerRadius
              color: selected ? root.selectedBackground : "transparent"

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
                  text: isPlus ? "Add" : armed ? "remove? ⏎" : (tile ? tile.name : "")
                  color: armed ? Color.urgent : selected ? root.selectedText : root.foreground
                  opacity: isPlus ? 0.7 : 0.9
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              // Channel number, counted down the wall; "+" tunes the catalog.
              Text {
                visible: isPlus || index < 9
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Style.space(6)
                text: isPlus ? "+" : String(index + 1)
                color: selected ? root.selectedText : root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                  if (root.selectedIndex !== index) root.pendingRemoveId = ""
                  root.selectedIndex = index
                }
                onClicked: root.launchIndex(index)
              }
            }
          }
        }
      }

      // Catalog page: NIP-89 listings with the publisher's face on them.
      Column {
        visible: root.page === "catalog"
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
            text: "Catalog"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: root.catalogFetching ? "refreshing…"
              : root.apps.length === 0 ? ""
              : root.filteredApps.length === root.apps.length ? root.apps.length + " apps"
              : root.filteredApps.length + " of " + root.apps.length
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "esc → wall"
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: root.cornerRadius
          color: "transparent"
          border.width: 1
          border.color: root.border

          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            clip: true
            onTextChanged: {
              root.catalogIndex = 0
              root.pendingRemoveId = ""
              root.updateFilter()
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.pendingRemoveId !== "") root.pendingRemoveId = ""
                else root.showWall()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.moveCatalog(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveCatalog(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_PageDown) {
                root.moveCatalog(8)
                event.accepted = true
              } else if (event.key === Qt.Key_PageUp) {
                root.moveCatalog(-8)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.catalogPrimary(root.filteredApps[root.catalogIndex])
                event.accepted = true
              }
            }

            Text {
              visible: searchField.text === ""
              anchors.verticalCenter: parent.verticalCenter
              text: "Search apps…  (enter installs, esc backs out)"
              color: root.foreground
              opacity: 0.35
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Text {
          visible: root.catalogError !== ""
            || (root.apps.length === 0 && root.catalogFetching)
            || (root.apps.length > 0 && root.filteredApps.length === 0)
          text: root.catalogError !== "" ? root.catalogError
            : root.apps.length === 0 ? "Fetching the catalog from your relays…"
            : "no matches"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: appList
          width: parent.width
          height: parent.height - y
          clip: true
          spacing: Style.space(4)
          model: root.filteredApps
          interactive: contentHeight > height

          delegate: Rectangle {
            width: appList.width
            height: infoCol.implicitHeight + Style.space(20)
            radius: root.cornerRadius

            readonly property var app: modelData
            readonly property bool selected: index === root.catalogIndex
            readonly property bool installed: root.isInstalled(app)
            readonly property bool armed: installed && root.pendingRemoveId === app.name
            readonly property string npubShort:
              ((app.npub || app.pubkey || "") + "").substring(0, 12) + "…"
            // Room left of the install affordance.
            readonly property int textWidth:
              width - Style.space(10) * 2 - Style.space(44) - Style.space(12) - Style.space(88)

            color: selected ? root.selectedBackground : "transparent"

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(12)

              Item {
                width: Style.space(44)
                height: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  id: appIcon
                  anchors.fill: parent
                  visible: status === Image.Ready
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  asynchronous: true
                  sourceSize.width: width * 2
                  sourceSize.height: height * 2
                  source: app.picture || ""
                }

                Text {
                  anchors.centerIn: parent
                  visible: appIcon.status !== Image.Ready
                  text: app.name.charAt(0).toUpperCase()
                  color: selected ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(26)
                  font.bold: true
                }
              }

              Column {
                id: infoCol
                width: textWidth
                spacing: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter

                Row {
                  spacing: Style.space(6)

                  Text {
                    text: app.name
                    color: selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    visible: app.featured === true
                    text: "★"
                    color: selected ? root.selectedText : root.foreground
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    visible: installed
                    text: "· installed"
                    color: selected ? root.selectedText : root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  width: parent.width
                  text: app.website
                  color: selected ? root.selectedText : root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: app.about || ""
                  color: selected ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  topPadding: Style.space(2)

                  // Circular avatar spanning the name + npub stack; the
                  // publisher's initial stands in until the image lands.
                  Item {
                    width: Style.space(28)
                    height: Style.space(28)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                      anchors.fill: parent
                      radius: width / 2
                      color: "transparent"
                      border.width: 1
                      border.color: root.border
                      visible: pubAvatar.status !== Image.Ready

                      Text {
                        anchors.centerIn: parent
                        text: (app.publisher_name || "?").charAt(0).toUpperCase()
                        color: selected ? root.selectedText : root.foreground
                        opacity: 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    Image {
                      id: pubAvatar
                      anchors.fill: parent
                      visible: status === Image.Ready
                      fillMode: Image.PreserveAspectCrop
                      smooth: true
                      asynchronous: true
                      sourceSize.width: width * 2
                      sourceSize.height: height * 2
                      source: app.publisher_picture || ""
                      layer.enabled: true
                      layer.smooth: true
                      layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: pubAvatarMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                      }
                    }

                    Item {
                      id: pubAvatarMask
                      anchors.fill: parent
                      visible: false
                      layer.enabled: true
                      Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                      }
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                      spacing: Style.space(6)

                      Text {
                        text: (app.publisher_name || "") !== "" ? app.publisher_name : npubShort
                        color: selected ? root.selectedText : root.foreground
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        visible: app.followed === true
                        text: "✓ following"
                        color: selected ? root.selectedText : root.foreground
                        opacity: 0.85
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    Text {
                      visible: (app.publisher_name || "") !== ""
                      text: npubShort
                      color: selected ? root.selectedText : root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }

            Text {
              visible: selected
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: armed ? "sure? ⏎"
                : installed ? "remove ⏎"
                : installProc.running ? "installing…" : "install ⏎"
              color: armed ? Color.urgent : root.selectedText
              opacity: armed ? 1 : 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                onClicked: root.catalogPrimary(app)
              }
            }

            MouseArea {
              anchors.fill: parent
              anchors.rightMargin: Style.space(88)
              hoverEnabled: true
              onEntered: {
                if (root.catalogIndex !== index) root.pendingRemoveId = ""
                root.catalogIndex = index
              }
              onClicked: root.catalogIndex = index
              onDoubleClicked: root.catalogPrimary(app)
            }
          }
        }
      }
    }
  }
}
