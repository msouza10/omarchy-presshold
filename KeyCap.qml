import QtQuick
import qs.Commons  // Color, Style, Util tokens

// One stylized low-profile mechanical keycap.
//
// Deliberately not photoreal: no bevels, gradients or drop shadows. A fixed
// housing plate the size of the whole slot, with the cap resting a few pixels
// above it so the sliver of housing left showing reads as the switch body.
// Pressing drops the cap onto the housing; releasing springs it back. The
// travel alone carries the impression.
//
// All chrome comes from the shared Style.controlFill / Style.controlBorder
// state tokens -- the same ones qs.Ui's Button paints itself with -- so a
// keycap tracks the active Omarchy theme exactly like every other control in
// the shell rather than carrying its own hardcoded palette.
//
// Used both for the keyboard drawing and for the overflow strip of keys no
// US keyboard can reach, so the two read as the same kind of object instead
// of the strip looking like a louder, unrelated set of chips.
Item {
  id: root

  // What the cap prints. `sub` is the small accent preview under the legend
  // (the character long-press would offer first); empty means none.
  property string legend: ""
  property string sub: ""

  // Width in key units: 1 is a letter key, 1.5 a Shift, 6 a space bar.
  property real units: 1

  // Live keys are interactive and fully painted. A dead one keeps its shape
  // but goes flat and dim -- it is still part of the drawing of a keyboard,
  // it just has nothing to customize.
  property bool available: true

  // Persistent "on" look, for a modifier that stays engaged (Shift).
  property bool armed: false

  property color foreground: Color.popups.text

  // The sub line defaults to accent because its usual job is previewing an
  // accent. A caller printing something incidental there -- a position
  // number, say -- turns it down instead of competing with the legend.
  property color subColor: Color.accent

  // Geometry. Defaults stand alone so a caller that just wants a keycap
  // doesn't have to describe a whole keyboard first.
  property int unitSize: Style.space(26)
  property int keyHeight: Style.space(32)
  property int gap: Style.spacing.xs
  property int travelDepth: Style.space(3)
  property int hoverLift: Style.space(1)

  // Legends are set in the shell's own font (Style.font.family resolves the
  // fontconfig alias `omarchy font set` writes, so it follows the user's
  // choice). It happens to be monospaced, which is what a keycap wants:
  // every legend gets the same advance width, so a row of them sits on one
  // rhythm instead of "i" rattling around in a cap sized for "w".
  property string fontFamily: Style.font.family
  // Two steps apart on the type scale, not one: at neighbouring sizes the
  // accent preview competes with the character it belongs to instead of
  // reading as its subtitle.
  property real legendSize: Style.font.body
  property real subSize: Style.font.caption

  signal activated()

  readonly property bool hot: available && mouse.containsMouse

  // A cap `units` wide spans that many keycaps *plus* the gaps it swallows
  // between them, so a 1.5u Shift stays on the same grid as the 1u keys
  // beside it instead of drifting a gap-width off.
  width: Math.round(unitSize * units + gap * (units - 1))
  height: keyHeight

  // 0 at rest, 1 bottomed out. Driven by the two animations below rather
  // than by a Behavior on the pressed state: a quick tap releases the mouse
  // before a Behavior would have finished travelling, so the cap snapped
  // back from halfway and the press read as nothing happening at all. Here
  // the release waits for the descent to land first.
  property real travel: 0
  property bool held: false

  // Under the cursor the cap floats up a hair -- the only idle motion, and
  // what makes the board feel like it has keys rather than cells.
  property real rise: hot && travel === 0 ? hoverLift : 0
  Behavior on rise { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

  NumberAnimation {
    id: pressDown
    target: root
    property: "travel"
    to: 1
    duration: 55
    easing.type: Easing.OutCubic
    onFinished: if (!root.held) pressUp.restart()
  }

  NumberAnimation {
    id: pressUp
    target: root
    property: "travel"
    to: 0
    duration: 160
    // Overshoots a hair past rest on the way up, which is what sells it as
    // a spring rather than a slide.
    easing.type: Easing.OutBack
    easing.overshoot: 2.2
  }

  Rectangle {
    id: housing
    anchors.fill: parent
    radius: Style.cornerRadius
    visible: root.available
    color: Util.alpha(root.foreground, 0.06)
    border.color: Util.alpha(root.foreground, 0.10)
    border.width: 1
  }

  Rectangle {
    id: cap
    width: parent.width
    height: parent.height - root.travelDepth
    y: root.travelDepth * root.travel - root.rise
    radius: Style.cornerRadius
    color: root.armed
      ? Style.selectedFillFor(root.foreground, Color.accent)
      : root.available
        ? Style.controlFill(false, root.hot, root.foreground, Color.accent)
        : "transparent"
    border.color: root.armed
      ? Color.accent
      : root.available
        ? Style.controlBorder(false, root.hot, root.foreground, Color.accent)
        : Util.alpha(root.foreground, 0.10)
    border.width: root.available ? Style.controlBorderWidth(false, root.hot) : 1

    Behavior on color { ColorAnimation { duration: 100 } }

    // Both legends carry an explicit line box rather than relying on the
    // font's natural line height, which is generous enough that two stacked
    // lines fill a 1u cap edge to edge and read as crowded. Boxing each line
    // to just over its own pixel size and centering the glyph inside gives
    // the pair a predictable height, and leaves real margin above and below
    // whatever font the user has set.
    Column {
      anchors.centerIn: parent
      spacing: 0

      Text {
        visible: root.legend !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        height: Math.round(root.legendSize * 1.15)
        verticalAlignment: Text.AlignVCenter
        text: root.legend
        color: root.armed
          ? Color.accent
          : root.available ? root.foreground : Util.alpha(root.foreground, 0.30)
        font.family: root.fontFamily
        font.pixelSize: root.legendSize
        font.bold: root.available
      }

      Text {
        visible: root.sub !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        height: Math.round(root.subSize * 1.1)
        verticalAlignment: Text.AlignVCenter
        text: root.sub
        color: root.subColor
        font.family: root.fontFamily
        font.pixelSize: root.subSize
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.available
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: {
      root.held = true
      pressUp.stop()
      pressDown.restart()
    }
    onReleased: {
      root.held = false
      if (!pressDown.running) pressUp.restart()
    }
    onCanceled: {
      root.held = false
      if (!pressDown.running) pressUp.restart()
    }
    onClicked: root.activated()
  }
}
