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
  readonly property string reorderScriptPath: Qt.resolvedUrl("scripts/reorder-candidates.py").toString().replace("file://", "")
  // Absolute path, not "python3": on systems with mise/pyenv-style shims
  // ahead of /usr/bin in PATH, a bare "python3" resolves to a shim build
  // that lacks python-dbus (an Arch/Omarchy system package, not something
  // a user-level Python install would ever have), and --keys/promote fail
  // with a silent ModuleNotFoundError on stderr no one is watching.
  readonly property string systemPython3: "/usr/bin/python3"

  property bool pressHoldEnabled: false
  property bool statusKnown: false
  property bool busy: false

  // Accent candidates, always fetched fresh from Fcitx5 -- never persisted
  // in shell.json or held stale across popup sessions. Empty until the
  // first --keys fetch (triggered by opening the key picker) completes.
  property var accentCandidates: ({})
  property bool candidatesKnown: false
  property bool candidatesBusy: false
  property bool reorderBusy: false

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

  function refreshCandidates() {
    if (candidatesBusy) return
    candidatesBusy = true
    keysProcess.running = true
  }

  function promote(key, candidate) {
    if (reorderBusy) return
    reorderBusy = true
    promoteProcess.command = [root.systemPython3, root.reorderScriptPath, key, candidate]
    promoteProcess.running = true
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

  // "<key> <c1> <c2> ..." per line -> { key: [c1, c2, ...] }
  Process {
    id: keysProcess
    command: [root.systemPython3, root.reorderScriptPath, "--keys"]
    stdout: StdioCollector {
      id: keysOut
      onStreamFinished: {
        var next = {}
        var lines = keysOut.text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          var parts = line.split(" ")
          next[parts[0]] = parts.slice(1)
        }
        root.accentCandidates = next
        root.candidatesKnown = true
        root.candidatesBusy = false
      }
    }
  }

  // Re-fetches just the promoted key's line from source of truth rather
  // than trusting the client-side splice: same "state always comes from
  // reality" rule refreshStatus() follows for the on/off toggle above.
  Process {
    id: promoteProcess
    stdout: StdioCollector {
      id: promoteOut
      onStreamFinished: {
        root.reorderBusy = false
        root.refreshCandidates()
      }
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
    // Both axes must add the card's own chrome. PopupCard exposes
    // verticalContentInset but no horizontal counterpart, so the width is
    // computed the same way by hand: without it the card is sized to the raw
    // content width, then insets the content holder by padding+border on each
    // side, squeezing the content and clipping whatever sits flush right (the
    // toggle switch, the last key in a row).
    readonly property real horizontalContentInset: card.padding * 2
      + Border.left(card.borderSpec) + Border.right(card.borderSpec)

    contentWidth: content.implicitWidth + card.horizontalContentInset
    contentHeight: content.implicitHeight + card.verticalContentInset
    // Reopening lands on the toggle, not wherever the last session was left:
    // the sub-views are a detour, and the popup's primary job is the on/off
    // state. Reset on close rather than open so the swap isn't visible.
    onOpenChanged: {
      if (card.open) root.refreshStatus()
      else content.view = "toggle"
    }

    ToggleContent {
      id: content
      anchors.fill: parent
      pressHoldEnabled: root.pressHoldEnabled
      statusKnown: root.statusKnown
      busy: root.busy
      accentCandidates: root.accentCandidates
      candidatesKnown: root.candidatesKnown
      candidatesBusy: root.candidatesBusy
      reorderBusy: root.reorderBusy
      onToggleRequested: root.toggle()
      onKeyPickerRequested: root.refreshCandidates()
      onPromoteRequested: function(key, ch) { root.promote(key, ch) }
    }
  }

  Component.onCompleted: root.refreshStatus()
}
