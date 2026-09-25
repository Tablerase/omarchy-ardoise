// =============================================================================
// InboxIcon.qml
//
// Scalable vector inbox tray icon for the Omarchy status bar.
// Inspired by the Canvas 2D rendering technique in OmaTasks (crmne.todoist)
// by Carmine Paolino (https://github.com/crmne/omatasks) — MIT License.
// =============================================================================

import QtQuick
import qs.Commons

Item {
  id: root

  property color color: Color.foreground
  implicitWidth: Style.space(16)
  implicitHeight: Style.space(16)

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      var s = width / 24
      ctx.reset()
      ctx.scale(s, s)
      ctx.strokeStyle = root.color
      ctx.lineWidth = 1.75
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // Outer inbox tray
      ctx.beginPath()
      ctx.moveTo(4, 4)
      ctx.lineTo(20, 4)
      ctx.lineTo(22, 17)
      ctx.lineTo(21, 20)
      ctx.lineTo(3, 20)
      ctx.lineTo(2, 17)
      ctx.closePath()
      ctx.stroke()

      // Front cutout notch
      ctx.beginPath()
      ctx.moveTo(2.8, 13.5)
      ctx.lineTo(7.5, 13.5)
      ctx.lineTo(9.5, 16.5)
      ctx.lineTo(14.5, 16.5)
      ctx.lineTo(16.5, 13.5)
      ctx.lineTo(21.2, 13.5)
      ctx.stroke()
    }

    Connections {
      target: root
      function onColorChanged() { canvas.requestPaint() }
      function onWidthChanged() { canvas.requestPaint() }
      function onHeightChanged() { canvas.requestPaint() }
    }
  }
}
