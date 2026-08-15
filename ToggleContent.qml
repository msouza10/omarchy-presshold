import QtQuick
import qs.Commons  // Color, Style tokens

// Content of the Press & Hold popup. Three internal views swapped in place
// (never a second PopupCard — Bar's popout coordinator only tracks one
// active popup per widget, so a nested popup would fight this one for
// outside-click dismissal): the toggle (default), a grid of accent-bearing
// keys, and a reorderable candidate list for whichever key was tapped.
//
// VISUAL MOCKUP ONLY (branch: visual/accent-reorder-ui): the "keys" and
// "candidates" views run on hardcoded sample data (mockCandidates) and
// reorder that in-memory copy only. Nothing here talks to Fcitx5. Wiring
// this to the real fcitx://config/addon/keyboard/longpress config happens
// after the visual design is approved, from the backend/accent-reorder
// branch built in parallel.
//
// The toggle itself is a hand-rolled Rectangle + MouseArea rather than
// QtQuick Controls' Switch: Switch imperatively overwrites its own
// `checked` property on click, which would fight the one-way binding to
// pressHoldEnabled (state always comes back from the toggle script, not
// from the control itself).
Item {
  id: content

  property bool pressHoldEnabled: false
  property bool statusKnown: false
  property bool busy: false
  signal toggleRequested()

  // "toggle" | "keys" | "candidates"
  property string view: "toggle"
  property string selectedKey: ""

  readonly property var mockCandidates: ({
    "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
    "c": ["ç", "ć", "č"],
    "d": ["ð"],
    "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
    "g": ["ğ"],
    "i": ["î", "ï", "í", "ī", "į", "ì"],
    "l": ["ł"],
    "n": ["ñ", "ń"],
    "o": ["ô", "ö", "ò", "ó", "œ", "ø"],
    "s": ["ß", "ś", "š", "ş"],
    "u": ["û", "ü", "ù", "ú", "ū"],
    "x": ["×"],
    "y": ["ÿ"],
    "z": ["ž", "ź", "ż"]
  })
  property var mockOrder: ({})

  function accentKeys() {
    var out = []
    for (var k in mockCandidates) out.push(k)
    return out
  }

  function candidatesFor(key) {
    return mockOrder[key] || mockCandidates[key] || []
  }

  function promote(key, ch) {
    var list = candidatesFor(key).slice()
    var idx = list.indexOf(ch)
    if (idx <= 0) return
    list.splice(idx, 1)
    list.unshift(ch)
    var next = {}
    for (var k in mockOrder) next[k] = mockOrder[k]
    next[key] = list
    content.mockOrder = next
  }

  function openKeyPicker() {
    content.view = "keys"
  }

  function openCandidates(key) {
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

    Column {
      width: 240
      leftPadding: content.hpad
      rightPadding: content.hpad
      topPadding: content.vpad
      bottomPadding: content.vpad
      spacing: Style.spacing.rowGap

      Row {
        width: parent.width - content.hpad * 2
        spacing: Style.spacing.md

        Text {
          width: parent.width - toggleTrack.width - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: "Press & Hold"
          color: Color.popups.text
          font.pixelSize: Style.font.body
        }

        Rectangle {
          id: toggleTrack
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          height: Style.space(20)
          radius: height / 2
          opacity: content.statusKnown && !content.busy ? 1.0 : 0.5
          color: content.pressHoldEnabled
            ? Color.accent
            : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.18)

          Rectangle {
            width: parent.height - 4
            height: parent.height - 4
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            x: content.pressHoldEnabled ? parent.width - width - 2 : 2
            color: Color.popups.background

            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }

          MouseArea {
            anchors.fill: parent
            enabled: content.statusKnown && !content.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: content.toggleRequested()
          }
        }
      }

      Text {
        width: parent.width - content.hpad * 2
        text: !content.statusKnown
          ? "Checking status…"
          : (content.pressHoldEnabled
              ? "Hold a key like 'a' to pick á à â ã…"
              : "Disabled — holding a key repeats it")
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width - content.hpad * 2
        topPadding: Style.spacing.xs

        Text {
          text: "Customize accents ›"
          color: Color.accent
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

  Component {
    id: keysView

    Column {
      width: 260
      leftPadding: content.hpad
      rightPadding: content.hpad
      topPadding: content.vpad
      bottomPadding: content.vpad
      spacing: Style.spacing.rowGap

      Row {
        width: parent.width - content.hpad * 2
        spacing: Style.spacing.sm

        Text {
          text: "‹"
          color: Color.accent
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
          font.pixelSize: Style.font.body
        }
      }

      Flow {
        width: parent.width - content.hpad * 2
        spacing: Style.spacing.xs

        Repeater {
          model: content.accentKeys()

          Rectangle {
            required property string modelData

            width: Style.space(30)
            height: Style.space(30)
            radius: Style.cornerRadius
            color: keyMouse.containsMouse
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
              : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
            border.width: 1
            border.color: keyMouse.containsMouse ? Color.accent : "transparent"

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              color: Color.popups.text
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: keyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: content.openCandidates(parent.modelData)
            }
          }
        }
      }
    }
  }

  Component {
    id: candidatesView

    Column {
      width: 260
      leftPadding: content.hpad
      rightPadding: content.hpad
      topPadding: content.vpad
      bottomPadding: content.vpad
      spacing: Style.spacing.rowGap

      Row {
        width: parent.width - content.hpad * 2
        spacing: Style.spacing.sm

        Text {
          text: "‹"
          color: Color.accent
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
          font.pixelSize: Style.font.body
        }
      }

      Flow {
        width: parent.width - content.hpad * 2
        spacing: Style.spacing.xs

        Repeater {
          model: content.candidatesFor(content.selectedKey)

          Rectangle {
            required property string modelData
            required property int index

            width: Style.space(34)
            height: Style.space(34)
            radius: Style.cornerRadius
            color: index === 0
              ? Color.accent
              : (candMouse.containsMouse
                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                  : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08))

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              color: index === 0 ? Color.popups.background : Color.popups.text
              font.pixelSize: Style.font.body
              font.bold: index === 0
            }

            Text {
              visible: index > 0
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: 1
              text: index + 1
              color: Color.muted
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: candMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: content.promote(content.selectedKey, parent.modelData)
            }
          }
        }
      }

      Text {
        width: parent.width - content.hpad * 2
        text: "Preview only — not saved yet"
        color: Color.muted
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
