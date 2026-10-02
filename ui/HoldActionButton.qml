import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Button with hold-to-confirm protection.
//
// Press (or hold the bound key) for `holdDuration` ms to fire `confirmed()`;
// releasing early drains the charge and cancels. While charging, the button
// paints a bottom laser bar and a surface tint. Hosts that need the charge
// rendered on a larger surface (e.g. a whole task row) set
// `visualsEnabled: false` and bind their own visuals to `progress`.
//
// This is the single implementation of the 600ms charge pattern used by the
// row delete button, the footer clear button, and the archive permanent
// delete.
Button {
  id: root

  property int holdDuration: 600
  property color chargeColor: Color.accent
  property bool visualsEnabled: true
  // When > 0, forces a square icon-only button (PanelActionButton-like).
  property real compactSize: 0

  readonly property real progress: internal.progress
  readonly property bool charged: internal.charged

  signal confirmed()

  function startCharging() {
    if (root.holdDuration <= 0) {
      internal.charged = true
      root.confirmed()
      return
    }
    if (chargeAnim.running) return
    internal.charged = false
    drainAnim.stop()
    chargeAnim.restart()
  }

  function stopCharging() {
    chargeAnim.stop()
    if (!internal.charged && internal.progress > 0) {
      drainAnim.restart()
    }
  }

  // Keep the kit Button's computed implicit size for labeled buttons, but force
  // a square for compact icon-only buttons. Binding is restored when
  // compactSize returns to 0.
  Binding on implicitWidth { when: root.compactSize > 0; value: root.compactSize }
  Binding on implicitHeight { when: root.compactSize > 0; value: root.compactSize }

  // Writable charge state. Kept on a plain QtObject so `progress`/`charged`
  // can be exposed read-only, while the animations live on the Button root
  // (a QtObject has no default property to host them).
  QtObject {
    id: internal
    property real progress: 0.0
    property bool charged: false
  }

  NumberAnimation {
    id: chargeAnim
    target: internal
    property: "progress"
    to: 1.0
    duration: root.holdDuration
    easing.type: Easing.Linear
    onFinished: {
      if (internal.progress >= 0.999) {
        internal.charged = true
        internal.progress = 0.0
        root.confirmed()
      }
    }
  }

  NumberAnimation {
    id: drainAnim
    target: internal
    property: "progress"
    to: 0.0
    duration: 180
    easing.type: Easing.OutQuad
  }

  // Hold target. `hoverEnabled: false` lets hover fall through to the Button's
  // own mouse area (so the kit's hover visuals still work) while this overlay
  // consumes press/release so `clicked` never fires.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: false
    cursorShape: Qt.PointingHandCursor
    onPressed: root.startCharging()
    onReleased: root.stopCharging()
    onCanceled: root.stopCharging()
  }

  Rectangle {
    id: tintOverlay
    anchors.fill: parent
    radius: root.radius
    color: root.chargeColor
    opacity: root.visualsEnabled ? internal.progress * 0.16 : 0
    visible: root.visualsEnabled && internal.progress > 0
    z: 0
  }

  Rectangle {
    id: laserBar
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    height: Style.space(3)
    width: parent.width * internal.progress
    color: root.chargeColor
    radius: root.radius
    visible: root.visualsEnabled && internal.progress > 0
    z: 10
  }
}
