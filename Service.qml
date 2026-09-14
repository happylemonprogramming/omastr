import QtQuick
import Quickshell
import Quickshell.Io

// lemon.omastr service entry point.
//
// On shell startup, check whether the keyring-backed identity is configured;
// if not, nudge once per session with a notification whose click opens the
// setup wizard in a floating terminal. (Running `omastr` also migrates any
// pre-rename omarchy-nostr key/config to the new name.)
//
// The notifications daemon phase will extend this file to spawn and babysit
// the daemon (clipboard-watcher pattern: setpriv --pdeathsig TERM + restart
// timer).
Item {
  id: root

  property var shell: null
  property var manifest: null

  // Resolved from this QML file's own location rather than the injected
  // manifest: injected properties arrive *after* creation, and starting a
  // Process from a property-change handler races the command binding's
  // re-evaluation (QProcess then launches with the stale, empty path).
  readonly property string cli: {
    var url = Qt.resolvedUrl("bin/omastr").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  PersistentProperties {
    id: persisted
    reloadableId: "lemon-omastr"
    property bool promptedSetup: false
  }

  Component.onCompleted: statusProc.running = true

  Process {
    id: statusProc
    command: [root.cli, "status", "--quiet"]
    onExited: function(exitCode) {
      if (exitCode === 0 || persisted.promptedSetup) return
      persisted.promptedSetup = true
      Quickshell.execDetached([
        "omarchy-notification-send",
        "-g", "󰌆",
        "-u", "normal",
        "Omastr",
        "Set up your Nostr identity to enable signing, notifications, and the wall.",
        "--exec", "omarchy-launch-floating-terminal-with-presentation", root.cli, "setup"
      ])
    }
  }
}
