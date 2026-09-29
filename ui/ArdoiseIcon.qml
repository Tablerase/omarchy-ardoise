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
//   overdue   anything overdue            timer_alert          warning
//
// The colour ramp is the severity channel: foreground -> accent -> warning.
// Red (urgent) is deliberately NOT a rung colour - it stays reserved for real
// error surfaces, so an orange task is late, and a red task is broken.
//
// Replaces the previous Canvas-drawn InboxIcon, whose 16px stroke weight did
// not match the 13px solid font glyphs used by every other bar widget.
// =============================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../TodoStore.js" as TodoStore

Item {
  id: root

  // The todo store whose urgency drives the ladder.
  property var store: null
  // Bar shell root, when hosted in the status bar (supplies foreground and the
  // Nerd Font family). Optional for panel/modal use.
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
  // supply its own text color while escalation still reads.
  property var foregroundOverride: undefined
  property var accentOverride: undefined
  property var warningOverride: undefined

  // ---- Warning colour -----------------------------------------------------
  // Omarchy has no warning role: Color.qml only parses accent, urgent (the
  // theme's `red`), muted and color0/4/7/8, and ignores the `yellow` key every
  // theme ships. The ladder needs a third, softer severity step, so the
  // theme's own `yellow` is read directly.
  //
  // `yellow` is preferred over `orange` because several themes' orange is a
  // coral/salmon that collides with urgent red (catppuccin orange #f6b6ab vs
  // red #f38ba8; catppuccin-latte orange #d84e2b vs red #d20f39).
  readonly property string themeDir: Color.currentThemePath
  property string themeYellow: ""
  readonly property string themeName: Quickshell.env("HOME")
    + "/.local/state/omarchy/current/theme.name"

  // omarchy-theme-set swaps the theme by `rm -rf current/theme` followed by
  // `mv next-theme current/theme`, so a FileView watching colors.toml loses
  // its inode and goes deaf. theme.name is a regular file *outside* the
  // swapped directory and is rewritten in place last, so it is the reliable
  // change signal; it then re-reads colors.toml.
  FileView {
    id: themeNameFile
    path: root.themeName
    watchChanges: true
    printErrors: false
    onLoaded: colorsFile.reload()
    // `text()` is stale inside the change signal, so route through reload() and
    // parse fresh content in onLoaded (same pattern as Color.qml's userShellFile).
    onFileChanged: reload()
  }

  FileView {
    id: colorsFile
    path: root.themeDir + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.themeYellow = root.parseYellow(text())
    // Keep the last good value rather than flashing the hardcoded default.
    onLoadFailed: { }
  }

  function parseYellow(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*yellow\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) return match[1]
    }
    return ""
  }

  // Resolution order: explicit host override -> user theme `bar.warning` ->
  // the active theme's own `yellow` -> amber fallback.
  readonly property color warningColor: root.warningOverride !== undefined
    ? root.warningOverride
    : Color.pick("bar.warning", root.themeYellow
        ? root.themeYellow
        : "#df8e1d")

  readonly property var iconState: {
    var derived = TodoStore.getArdoiseIconState(root.store)
    if (root.forcedKey) {
      var forced = TodoStore.ardoiseIconStateForKey(root.forcedKey)
      if (forced) {
        return {
          key: forced.key,
          glyph: forced.glyph,
          role: forced.role,
          count: derived.count,
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
  readonly property color ladderColor: {
    if (root.iconState.role === "warning") return root.warningColor
    if (root.iconState.role === "urgent") return root.urgentColor
    if (root.iconState.role === "accent") return root.accentColor
    return root.foregroundColor
  }
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
