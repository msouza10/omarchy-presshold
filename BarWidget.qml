import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui       // BarWidget, PopupCard, BarIconButton
import qs.Commons  // Color, Style tokens

// Bar icon + host for the Press & Hold toggle popup.
//
// State always comes from the real Fcitx5 config on disk, never from
// shell.json: scripts/toggle-longpress.sh is the single source of truth, so
// the icon reflects reality even if the user edited keyboard.conf by hand.
BarWidget {
  id: root
  moduleName: "omaccerts.presshold"

  readonly property string scriptPath: Qt.resolvedUrl("scripts/toggle-longpress.sh").toString().replace("file://", "")

  property bool pressHoldEnabled: false
  property bool statusKnown: false
  property bool busy: false

  function refreshStatus() {
    if (busy) return
    statusProcess.running = true
  }

  function applyResult(text) {
    var trimmed = String(text).trim()
    root.pressHoldEnabled = trimmed === "enabled"
    root.statusKnown = true
    root.busy = false
  }

  function toggle() {
    if (busy || !statusKnown) return
    busy = true
    toggleProcess.command = ["bash", root.scriptPath, root.pressHoldEnabled ? "disable" : "enable"]
    toggleProcess.running = true
  }

  Process {
    id: statusProcess
    command: ["bash", root.scriptPath, "status"]
    stdout: StdioCollector {
      id: statusOut
      onStreamFinished: root.applyResult(statusOut.text)
    }
  }

  Process {
    id: toggleProcess
    stdout: StdioCollector {
      id: toggleOut
      onStreamFinished: root.applyResult(toggleOut.text)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- Shape contract for shell.summon/hide/toggle routing: Bar's popout
  //      coordinator requires open/close/opened on the bar-widget root.
  readonly property bool opened: card.open

  function open() {
    card.open = true
  }

  function close() {
    card.open = false
  }

  IpcHandler {
    target: "omaccerts.presshold"

    function open() { root.open() }
    function close() { root.close() }
    function togglePanel() { root.opened ? root.close() : root.open() }
  }

  BarIconButton {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    text: root.pressHoldEnabled ? "ã" : "a"
    useActiveColor: root.pressHoldEnabled
    tooltipText: root.statusKnown
      ? (root.pressHoldEnabled ? "Press & Hold: On" : "Press & Hold: Off")
      : "Press & Hold: checking…"
    onPressed: function(b) { root.opened ? root.close() : root.open() }
  }

  PopupCard {
    id: card
    anchorItem: button
    bar: root.bar
    owner: root
    contentWidth: content.implicitWidth
    contentHeight: content.implicitHeight + card.verticalContentInset
    onOpenChanged: if (card.open) root.refreshStatus()

    ToggleContent {
      id: content
      anchors.fill: parent
      pressHoldEnabled: root.pressHoldEnabled
      statusKnown: root.statusKnown
      busy: root.busy
      onToggleRequested: root.toggle()
    }
  }

  Component.onCompleted: root.refreshStatus()
}
