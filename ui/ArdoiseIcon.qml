// =============================================================================
// ArdoiseIcon.qml
//
// The Ardoise task-slate mark. A Nerd Font MD glyph (Private Use Area) rendered
// through the same optical-centering technique omarchy's own bar icons use, so
// it sits on the same optical centre as the icons beside it.
//
// The glyph is a ladder rung driven by TodoStore.getArdoiseIconState():
//
//   clear     0 pending                   check_circle         foreground
//   pending   nothing time-critical       format_list_checks   foreground
//   due       due today, nothing overdue  list_status          accent
//   overdue   anything overdue            alert_circle         urgent
//
// The two extremes deliberately share a filled-circle silhouette so the mark
// keeps a stable identity while only the interior glyph and color change.
// Replaces the previous Canvas-drawn InboxIcon, whose 16px stroke weight did
// not match the 13px solid font glyphs used by every other bar widget.
// =============================================================================

import QtQuick
import qs.Commons
import "../TodoStore.js" as TodoStore

Item {
  id: root

  // The todo store whose urgency drives the ladder.
  property var store: null
  // Bar shell root, when hosted in the status bar (supplies foreground,
  // urgent and the Nerd Font family). Optional for panel/modal use.
  property var bar: null

  // Rendered glyph box in px. Defaults to omarchy's bar icon size so the
  // widget matches its neighbours without hardcoding the token.
  property int iconSize: Style.bar.iconFont
  // Force a specific rung instead of deriving one from the store.
  property string forcedKey: ""
  // Overrides the ladder color outright (e.g. the panel brand row turning
  // accent on hover). Leave undefined to let the ladder role drive the color.
  // Typed `var` on purpose: a `color` property would coerce the undefined
  // sentinel to a transparent QColor at every assignment and log a warning.
  property var colorOverride: undefined
  // Replaces only the "foreground" rung's base color, so a host surface can
  // supply its own text color while urgent/accent escalation still reads.
  property var foregroundOverride: undefined
  property var accentOverride: undefined

  readonly property var iconState: {
    var derived = TodoStore.getArdoiseIconState(root.store)
    if (root.forcedKey) {
      var forced = TodoStore.ardoiseIconStateForKey(root.forcedKey)
      if (forced) {
        return {
          key: forced.key,
          glyph: forced.glyph,
          role: forced.role,
          total: derived.total,
          overdue: derived.overdue,
          dueToday: derived.dueToday
        }
      }
    }
    return derived
  }

  readonly property color foregroundColor: root.foregroundOverride !== undefined
    ? root.foregroundOverride
    : (root.bar ? root.bar.foreground : Color.foreground)
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color accentColor: root.accentOverride !== undefined
    ? root.accentOverride
    : Color.accent
  readonly property color ladderColor: root.iconState.role === "urgent"
    ? root.urgentColor
    : (root.iconState.role === "accent" ? root.accentColor : root.foregroundColor)
  readonly property color resolvedColor: root.colorOverride !== undefined
    ? root.colorOverride
    : root.ladderColor

  readonly property string fontFamily: root.bar && root.bar.fontFamily
    ? root.bar.fontFamily
    : Style.font.family

  implicitWidth: root.iconSize
  implicitHeight: root.iconSize
  width: implicitWidth
  height: implicitHeight

  // Optical centering: MDI glyphs are not centered in their advance width, so
  // correct the horizontal painted bounds without disturbing the line box
  // (same technique as omarchy's Ui/OpticalGlyph.qml).
  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    text: root.iconState.glyph
  }

  readonly property real horizontalCorrection: glyph.implicitWidth / 2
    - (glyphMetrics.tightBoundingRect.x + glyphMetrics.tightBoundingRect.width / 2)

  Text {
    id: glyph
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.horizontalCorrection
    text: root.iconState.glyph
    textFormat: Text.PlainText
    color: root.resolvedColor
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    renderType: Text.NativeRendering

    Behavior on color {
      ColorAnimation { duration: 150 }
    }
  }
}
