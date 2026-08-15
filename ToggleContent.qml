import QtQuick
import qs.Commons  // Color, Style tokens

// Content of the Press & Hold popup — a label, a status line, and a custom
// pill toggle. Card chrome (background, border, outside-click dismiss) is
// provided by the PopupCard host in BarWidget.qml; this is content-only.
//
// The toggle is a hand-rolled Rectangle + MouseArea rather than QtQuick
// Controls' Switch: Switch imperatively overwrites its own `checked`
// property on click, which would fight the one-way binding to
// pressHoldEnabled (state always comes back from the toggle script, not
// from the control itself).
Item {
  id: content

  property bool pressHoldEnabled: false
  property bool statusKnown: false
  property bool busy: false
  signal toggleRequested()

  readonly property int hpad: Style.spacing.md
  readonly property int vpad: Style.spacing.sm

  implicitWidth: 240
  implicitHeight: col.implicitHeight + vpad * 2

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: content.hpad
    anchors.rightMargin: content.hpad
    y: content.vpad
    spacing: Style.spacing.rowGap

    Row {
      width: parent.width
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
      width: parent.width
      text: !content.statusKnown
        ? "Checking status…"
        : (content.pressHoldEnabled
            ? "Hold a key like 'a' to pick á à â ã…"
            : "Disabled — holding a key repeats it")
      color: Color.muted
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
