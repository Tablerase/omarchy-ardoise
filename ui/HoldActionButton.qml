import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Hold-to-confirm action button designed to prevent accidental destructive
// actions (e.g. task deletion, archiving completed tasks) without resorting
// to modal confirmation dialogs.
//
// Behavior:
//   - Pressing and holding (mouse pointer or keyboard key) charges progress
//     from 0.0 to 1.0 over `holdDuration` (default: 600ms).
//   - A circular radial ring renders around the icon in `chargeColor`.
//   - When charge passes 60%, a subtle micro-shake provides tactile warning.
//   - Releasing early cancels the action and smoothly drains progress back
//     to 0.0 over `drainDuration` (default: 180ms).
//   - `triggered()` is emitted ONLY when progress reaches 1.0 (100%).
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Color.foreground
  property color hoverColor: foreground
  property color chargeColor: Color.urgent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption
  property real iconSize: Style.font.icon
  property real size: Math.max(Style.space(22), fontSize + Style.spacing.sm * 2)

  property int holdDuration: 600
  property int drainDuration: 180
  property real progress: 0.0

  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false

  signal triggered()
  signal clicked()
  signal hovered(bool isHovered)

  function startCharging() {
    if (!root.enabled) return
    if (root.holdDuration <= 0) {
      root.triggered()
      return
    }
    drainAnim.stop()
    if (root.progress >= 1.0) return
    chargeAnim.duration = Math.max(1, (1.0 - root.progress) * root.holdDuration)
    chargeAnim.restart()
  }

  function stopCharging() {
    if (chargeAnim.running) {
      chargeAnim.stop()
    }
    if (root.progress > 0.0) {
      drainAnim.duration = Math.max(1, root.progress * root.drainDuration)
      drainAnim.restart()
    }
  }

  function cancelCharging() {
    chargeAnim.stop()
    drainAnim.stop()
    root.progress = 0.0
  }

  readonly property bool isCharging: chargeAnim.running
  readonly property bool isShaking: isCharging && progress > 0.6 && progress < 1.0
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property bool _hot: (mouseArea.containsMouse || root.hasCursor) && root.enabled

  implicitWidth: root.text !== ""
    ? iconContainer.width + labelText.implicitWidth + Style.spacing.sm * 3 + (root.bordered ? 4 : 0)
    : size
  implicitHeight: size
  radius: Style.cornerRadius

  readonly property var _borderSpec: _showFocusRing
    ? Border.controlSpec("focus", hoverColor, hoverColor)
    : (_hot && bordered
      ? Border.controlSpec("hover-cursor", hoverColor, hoverColor)
      : (bordered ? Border.controlSpec("normal", foreground, Color.accent) : Border.none()))

  color: _showFocusRing
    ? Style.focusFillFor(hoverColor, hoverColor)
    : (_hot
      ? Style.hoverFillFor(hoverColor, hoverColor)
      : "transparent")
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 60 } }

  scale: root.isCharging ? 1.05 : (mouseArea.pressed ? 0.96 : 1.0)
  Behavior on scale { NumberAnimation { duration: 100 } }

  transform: Translate { id: shakeTranslate }

  SequentialAnimation {
    running: root.isShaking
    loops: Animation.Infinite
    NumberAnimation { target: shakeTranslate; property: "x"; to: -1.2; duration: 35 }
    NumberAnimation { target: shakeTranslate; property: "x"; to: 1.2; duration: 35 }
    NumberAnimation { target: shakeTranslate; property: "x"; to: -0.8; duration: 30 }
    NumberAnimation { target: shakeTranslate; property: "x"; to: 0.8; duration: 30 }
    NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 20 }
  }

  NumberAnimation {
    id: chargeAnim
    target: root
    property: "progress"
    to: 1.0
    duration: Math.max(1, (1.0 - root.progress) * root.holdDuration)
    easing.type: Easing.Linear
    onFinished: {
      if (root.progress >= 0.999) {
        root.progress = 1.0
        root.triggered()
        root.progress = 0.0
      }
    }
  }

  NumberAnimation {
    id: drainAnim
    target: root
    property: "progress"
    to: 0.0
    duration: Math.max(1, root.progress * root.drainDuration)
    easing.type: Easing.OutQuad
  }

  onProgressChanged: arcCanvas.requestPaint()
  on_HotChanged: arcCanvas.requestPaint()
  onChargeColorChanged: arcCanvas.requestPaint()

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Item {
      id: iconContainer
      width: root.size
      height: root.size

      Canvas {
        id: arcCanvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var r = Math.min(cx, cy) - Style.space(2.5)
          if (r <= 0) return

          // Faint track circle on hover/hot or while charging
          if (root._hot || root.progress > 0) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.lineWidth = 1.6
            ctx.strokeStyle = Qt.rgba(root.chargeColor.r, root.chargeColor.g, root.chargeColor.b, root.progress > 0 ? 0.35 : 0.15)
            ctx.stroke()
          }

          // Active progress arc
          if (root.progress > 0) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + root.progress * 2 * Math.PI)
            ctx.lineWidth = 2.2
            ctx.strokeStyle = root.chargeColor
            ctx.stroke()
          }
        }
      }

      Text {
        id: iconLabel
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.iconText
        color: root.enabled
          ? (root.progress > 0 ? root.chargeColor : (root._hot ? root.hoverColor : root.foreground))
          : Qt.darker(root.foreground, 2.0)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }

    Text {
      id: labelText
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.enabled
        ? (root.progress > 0 ? root.chargeColor : (root._hot ? root.hoverColor : root.foreground))
        : Qt.darker(root.foreground, 2.0)
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onContainsMouseChanged: root.hovered(containsMouse)
    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      if (root.focusable) root.forceActiveFocus()
      root.startCharging()
    }
    onReleased: root.stopCharging()
    onCanceled: root.stopCharging()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
