import QtQuick
import qs.Commons  // Color, Style, Border tokens
import qs.Ui       // Button, ToggleSwitch — the shell's own themed controls

// Content of the Press & Hold popup. Three internal views swapped in place
// (never a second PopupCard — Bar's popout coordinator only tracks one
// active popup per widget, so a nested popup would fight this one for
// outside-click dismissal): the toggle (default), a keyboard-shaped picker
// for which key to customize, and a reorderable candidate list for whichever
// key was tapped.
//
// Each view's root is a plain Item with explicit implicitWidth/implicitHeight
// (never the Column directly — Column's implicitWidth is computed by the
// positioner and is read-only; assigning it is a hard QML error, and without
// it PopupCard, which sizes the real popup window from content.implicitWidth,
// falls back to a stale/wrong size and clips the view). The Column inside
// just handles layout at a fixed inner width.
//
// The key picker and candidate chips are built from Button/ToggleSwitch and
// the same Style.controlFill/Border.controlSpec state tokens those controls
// use internally, rather than hand-rolled Rectangles with hardcoded alpha
// values -- that mismatch (no real hover/press feedback, colors that don't
// track the theme) is what made this view look bolted-on next to the rest
// of the bar.
//
// accentCandidates/candidatesKnown/candidatesBusy/reorderBusy and the
// keyPickerRequested/promoteRequested signals are owned by BarWidget, which
// talks to scripts/reorder-candidates.py over Fcitx5's D-Bus config -- same
// "state always comes from reality, never cached in shell.json" rule as
// pressHoldEnabled below. This view only renders whatever BarWidget last
// fetched and asks for a refetch/promote; it holds no candidate state itself.
Item {
  id: content

  property bool pressHoldEnabled: false
  property bool statusKnown: false
  property bool busy: false
  signal toggleRequested()

  // key -> ordered list of candidate chars, as last fetched from Fcitx5.
  // Fcitx5's longpress table covers far more than the US keyboard's letter
  // keys (uppercase entries, digits, punctuation, and whole non-Latin
  // scripts bundled in from other installed layouts) -- see keysView below
  // for how that full set maps onto "a drawing of a keyboard".
  property var accentCandidates: ({})
  property bool candidatesKnown: false
  property bool candidatesBusy: false
  property bool reorderBusy: false
  signal keyPickerRequested()
  signal promoteRequested(string key, string candidate)

  // "toggle" | "keys" | "candidates"
  property string view: "toggle"
  property string selectedKey: ""

  // A US keyboard, laid out the way one physically is: `k` is the unshifted
  // legend, `s` the shifted one, `w` the key's width in key units (1 = a
  // normal letter key), `indent` the row's stagger, also in key units.
  //
  // Carrying both legends is what lets the Shift key be real rather than
  // decorative -- Fcitx5's uppercase entries (A → À Á Â) and its
  // shifted-symbol ones (! → ¡, $ → ¢ € £) then live under the key the user
  // would actually press for them, instead of being flattened into one
  // undifferentiated overflow list. Whatever Fcitx5 lists that no US key can
  // reach -- Cyrillic, Hebrew, Arabic -- falls through to the "Other scripts"
  // strip below the board, so nothing from --keys becomes unreachable.
  readonly property var keyRows: [
    { indent: 0, keys: [
      { k: "1", s: "!" }, { k: "2", s: "@" }, { k: "3", s: "#" }, { k: "4", s: "$" },
      { k: "5", s: "%" }, { k: "6", s: "^" }, { k: "7", s: "&" }, { k: "8", s: "*" },
      { k: "9", s: "(" }, { k: "0", s: ")" }, { k: "-", s: "_" }, { k: "=", s: "+" }
    ] },
    { indent: 0, keys: [
      { k: "q", s: "Q" }, { k: "w", s: "W" }, { k: "e", s: "E" }, { k: "r", s: "R" },
      { k: "t", s: "T" }, { k: "y", s: "Y" }, { k: "u", s: "U" }, { k: "i", s: "I" },
      { k: "o", s: "O" }, { k: "p", s: "P" }, { k: "[", s: "{" }, { k: "]", s: "}" }
    ] },
    { indent: 0.5, keys: [
      { k: "a", s: "A" }, { k: "s", s: "S" }, { k: "d", s: "D" }, { k: "f", s: "F" },
      { k: "g", s: "G" }, { k: "h", s: "H" }, { k: "j", s: "J" }, { k: "k", s: "K" },
      { k: "l", s: "L" }, { k: ";", s: ":" }, { k: "'", s: "\"" }
    ] },
    { indent: 0, keys: [
      { role: "shift", w: 1.5 },
      { k: "z", s: "Z" }, { k: "x", s: "X" }, { k: "c", s: "C" }, { k: "v", s: "V" },
      { k: "b", s: "B" }, { k: "n", s: "N" }, { k: "m", s: "M" },
      { k: ",", s: "<" }, { k: ".", s: ">" }, { k: "/", s: "?" }
    ] },
    { indent: 3, keys: [{ role: "space", w: 6 }] }
  ]

  // Total width of the board in key units, from its widest row -- the row
  // the layout has to be able to fit.
  readonly property real boardUnits: {
    var widest = 0
    for (var r = 0; r < content.keyRows.length; r++) {
      var row = content.keyRows[r]
      var units = row.indent
      for (var i = 0; i < row.keys.length; i++) units += (row.keys[i].w || 1)
      if (units > widest) widest = units
    }
    return widest
  }

  function accentKeys() {
    var out = []
    for (var k in content.accentCandidates) out.push(k)
    return out
  }

  function candidatesFor(key) {
    return content.accentCandidates[key] || []
  }

  function hasCandidates(key) {
    return content.candidatesFor(key).length > 0
  }

  // Every legend the board can reach, in either shift state. Derived from
  // keyRows rather than spelled out again, so adding a key to the layout
  // automatically stops it from also showing up in the overflow strip.
  function boardChars() {
    var set = ({})
    for (var r = 0; r < content.keyRows.length; r++) {
      var keys = content.keyRows[r].keys
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].k) set[keys[i].k] = true
        if (keys[i].s) set[keys[i].s] = true
      }
    }
    return set
  }

  // Everything Fcitx5 offers that no key on the board can reach -- in
  // practice the other scripts it ships entries for. Sorted so the strip
  // doesn't reshuffle across fetches.
  function otherKeys() {
    var board = content.boardChars()
    var out = []
    for (var k in content.accentCandidates) {
      if (!board[k]) out.push(k)
    }
    out.sort()
    return out
  }

  function promote(key, ch) {
    if (content.reorderBusy) return
    content.promoteRequested(key, ch)
  }

  function openKeyPicker() {
    content.view = "keys"
    content.keyPickerRequested()
  }

  function openCandidates(key) {
    if (!content.hasCandidates(key)) return
    content.selectedKey = key
    content.view = "candidates"
  }

  function backToKeys() {
    content.view = "keys"
  }

  function backToToggle() {
    content.view = "toggle"
  }

  readonly property int hpad: Style.spacing.md
  readonly property int vpad: Style.spacing.sm

  implicitWidth: viewLoader.item ? viewLoader.item.implicitWidth : 240
  implicitHeight: viewLoader.item ? viewLoader.item.implicitHeight : 40

  Loader {
    id: viewLoader
    sourceComponent: content.view === "keys"
      ? keysView
      : content.view === "candidates" ? candidatesView : toggleView
  }

  Component {
    id: toggleView

    Item {
      readonly property int innerWidth: 300
      implicitWidth: innerWidth
      implicitHeight: col.implicitHeight + content.vpad * 2

      Column {
        id: col
        x: content.hpad
        y: content.vpad
        width: parent.innerWidth - content.hpad * 2
        spacing: Style.spacing.rowGap

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Text {
            width: parent.width - toggleSwitch.width - Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "Press & Hold"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ToggleSwitch {
            id: toggleSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: content.pressHoldEnabled
            busy: content.busy
            // Blocked entirely until the first status fetch lands, so an
            // eager click before we know the real state can't send the
            // toggle the wrong way. Once known, `busy` alone gates further
            // clicks while keeping hover/cursor alive (see ToggleSwitch's
            // own doc comment) -- state comes back from the toggle script,
            // not from the switch optimistically flipping itself.
            interactive: content.statusKnown
            opacity: content.statusKnown ? 1.0 : 0.5
            onToggled: content.toggleRequested()
          }
        }

        Text {
          width: parent.width
          text: !content.statusKnown
            ? "Checking status…"
            : (content.pressHoldEnabled
                ? "Hold a key like 'a' to pick á à â ã…"
                : "Disabled — holding a key repeats it")
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Row {
          width: parent.width
          topPadding: Style.spacing.xs

          Text {
            text: "Customize accents ›"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall

            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: content.openKeyPicker()
            }
          }
        }
      }
    }
  }

  Component {
    id: keysView

    // `id` on the root, not `viewLoader.item`: children reference an
    // ancestor's id directly, resolved once the whole component's object
    // tree exists. `viewLoader.item` is only set by the Loader *after* it
    // finishes building this very tree, so a descendant binding on it reads
    // null the first time it evaluates (and per QML's warn-and-continue
    // policy, keeps silently re-throwing the same TypeError to the log on
    // every subsequent open instead of a single loud failure).
    Item {
      id: keysRoot

      // Shift is a real state, not a decoration: it swaps every legend to
      // its shifted twin and looks the candidates up for that character.
      // Resets on each visit so arriving here always starts from the plain
      // keyboard, the same reason the popup itself resets to the toggle view.
      property bool shifted: false

      readonly property int keyW: Style.space(26)
      readonly property int keyH: Style.space(32)
      readonly property int keyGap: Style.spacing.xs
      // The overflow strip's caps: a size down from the board's, since they
      // are an appendix to it and carry a single legend rather than two.
      readonly property int strayKeyW: Style.space(22)
      readonly property int strayKeyH: Style.space(24)
      // Travel of the keycap, and how far it floats up under the cursor. Both
      // are deliberately tiny -- this is a low-profile board, so the whole
      // gesture is a couple of pixels, not a deep throw.
      readonly property int keyTravel: Style.space(3)
      readonly property int hoverFloat: Style.space(1)
      // Deck padding: the case the keys are seated in.
      readonly property int deckPad: Style.spacing.sm

      // A key `units` wide spans that many keycaps *plus* the gaps it swallows
      // between them, so a 1.5u Shift lines up on the same grid as the 1u keys
      // beside it instead of drifting a gap-width off.
      function unitWidth(units) {
        return Math.round(keyW * units + keyGap * (units - 1))
      }

      readonly property int boardWidth: unitWidth(content.boardUnits)
      readonly property int innerWidth: boardWidth + deckPad * 2 + content.hpad * 2

      implicitWidth: innerWidth
      implicitHeight: col.implicitHeight + content.vpad * 2

      Column {
        id: col
        x: content.hpad
        y: content.vpad
        width: parent.innerWidth - content.hpad * 2
        spacing: Style.spacing.rowGap

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            text: "‹"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: content.backToToggle()
            }
          }

          Text {
            text: "Choose a key"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Text {
          visible: !content.candidatesKnown
          width: parent.width
          text: content.candidatesBusy ? "Loading…" : "Nothing to show yet"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // The deck: the case the keys sit in. Without it the rows read as
        // three loose strips of buttons; with it they read as one object.
        Rectangle {
          id: deck
          visible: content.candidatesKnown
          width: parent.width
          height: rows.implicitHeight + keysRoot.deckPad * 2
          radius: Style.cornerRadius
          color: Util.alpha(Color.popups.text, 0.03)
          border.color: Util.alpha(Color.popups.text, 0.09)
          border.width: 1

          Column {
            id: rows
            x: keysRoot.deckPad
            y: keysRoot.deckPad
            spacing: keysRoot.keyGap

            Repeater {
              model: content.keyRows

              Row {
                id: keyRow
                required property var modelData

                x: keysRoot.unitWidth(modelData.indent + 1) - keysRoot.keyW
                spacing: keysRoot.keyGap

                Repeater {
                  model: keyRow.modelData.keys

                  KeyCap {
                    id: keySlot
                    required property var modelData

                    readonly property string role: modelData.role || "key"
                    // The literal character, not its upper-case form: with
                    // Shift live, "q" and "Q" are two different entries with
                    // two different candidate lists, and printing both as "Q"
                    // the way a real keycap does would make it impossible to
                    // tell which one is being edited.
                    readonly property string keyChar: keysRoot.shifted
                      ? (modelData.s || "")
                      : (modelData.k || "")

                    units: modelData.w || 1
                    // Shift is a modifier, not a character: it stays live
                    // whether or not the board has candidates to show, since
                    // its whole job is to reveal the ones on the other layer.
                    available: role === "shift" || content.hasCandidates(keyChar)
                    armed: role === "shift" && keysRoot.shifted
                    // The arrow is what the physical key is marked with, and
                    // the word "Shift" doesn't fit a 1.5u cap anyway.
                    legend: role === "shift" ? "⇧" : (role === "space" ? "" : keyChar)
                    sub: role === "key" ? (content.candidatesFor(keyChar)[0] || "") : ""

                    foreground: Color.popups.text
                    unitSize: keysRoot.keyW
                    keyHeight: keysRoot.keyH
                    gap: keysRoot.keyGap
                    travelDepth: keysRoot.keyTravel
                    hoverLift: keysRoot.hoverFloat

                    onActivated: {
                      if (role === "shift") keysRoot.shifted = !keysRoot.shifted
                      else content.openCandidates(keyChar)
                    }
                  }
                }
              }
            }
          }
        }

        // What the board can't reach: Fcitx5 ships long-press entries for
        // scripts a US keyboard has no key for at all. Same keycaps as the
        // board so the two read as one kit, but a size down and with no deck
        // under them -- as bordered chips they out-shouted the keyboard they
        // were supposed to be an appendix to.
        Column {
          visible: content.candidatesKnown && content.otherKeys().length > 0
          width: parent.width
          spacing: Style.spacing.xs
          topPadding: Style.spacing.sm

          Text {
            text: "Other scripts"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.xs

            Repeater {
              model: content.otherKeys()

              KeyCap {
                required property string modelData

                legend: modelData
                unitSize: keysRoot.strayKeyW
                keyHeight: keysRoot.strayKeyH
                gap: keysRoot.keyGap
                travelDepth: keysRoot.keyTravel
                hoverLift: keysRoot.hoverFloat
                foreground: Color.popups.text
                onActivated: content.openCandidates(modelData)
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: candidatesView

    Item {
      readonly property int innerWidth: 320
      implicitWidth: innerWidth
      implicitHeight: col.implicitHeight + content.vpad * 2

      Column {
        id: col
        x: content.hpad
        y: content.vpad
        width: parent.innerWidth - content.hpad * 2
        spacing: Style.spacing.rowGap

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            text: "‹"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: content.backToKeys()
            }
          }

          Text {
            text: "Tap to move to front — “" + content.selectedKey + "”"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: content.candidatesFor(content.selectedKey)

            // Keycaps here too, not chips: the candidates are characters on
            // the same keyboard the previous view drew, so they get the same
            // object. The position rides the cap's sub line rather than a
            // corner badge, which on a cap this size overlapped the very
            // glyph it was labelling.
            KeyCap {
              required property string modelData
              required property int index

              legend: modelData
              sub: String(index + 1)
              subColor: Color.muted
              // The armed look marks the current default -- the same "this
              // one is engaged" language Shift uses on the board.
              armed: index === 0
              unitSize: Style.space(30)
              keyHeight: Style.space(36)
              legendSize: Style.font.title
              opacity: content.reorderBusy ? 0.5 : 1.0
              onActivated: content.promote(content.selectedKey, modelData)
            }
          }
        }

        Text {
          width: parent.width
          text: content.reorderBusy ? "Saving…" : "Tap a character to make it the default"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
