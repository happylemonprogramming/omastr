import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omastr bar chip: the ostrich. Left click toggles the wall overlay,
// right click opens a status check in a floating terminal.
//
// The badge is fed by a file, not by in-process state: any Omastr piece
// (notifications daemon, signer host) writes a number to
// ~/.local/state/omastr/badge and the chip picks it up on the file watch.
// That keeps the daemons decoupled from the shell process entirely.
BarWidget {
  id: root
  moduleName: "lemon.omastr"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property int badgeCount: 0

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omastr/badge"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var n = parseInt(String(text()).trim(), 10)
      root.badgeCount = isNaN(n) || n < 0 ? 0 : n
    }
    // A deleted badge file must clear the count, not freeze the last one.
    onLoadFailed: root.badgeCount = 0
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Omastr"
    iconComponent: Component {
      OstrichIcon {
        anchors.centerIn: parent
        iconSize: Style.bar.iconCanvas
        color: button.foreground
        badgeColor: root.bar ? root.bar.urgent : Color.urgent
        badgeTextColor: Color.background
        badgeCount: root.badgeCount
      }
    }
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton)
        root.bar.run("omarchy-launch-floating-terminal-with-presentation "
          + Qt.resolvedUrl("bin/omastr").toString().replace("file://", "") + " status --network")
      else
        root.bar.run("omarchy-shell shell toggle lemon.omastr")
    }
  }
}
