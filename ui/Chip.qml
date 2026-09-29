// =============================================================================
// Chip.qml
//
// Reusable compact pill/badge component inspired by OmaTasks.
// Supports icons, elided text, subtle background tint, tooltips,
// and optional remove button without any layout recursion loops.
//
// Variants:
//   - "default": Standard rounded pill capsule with accent tint
//   - "time": Squircle ticket badge (Style.space(4)) reacting to urgency states
//             (overdue amber warning with 󱫌, due-today accent with 󰥔, future)
//   - "location": Codebase/repo pill capsule with monospace code font,
//                 accent git/folder glyph, and developer code surface
//   - "tag": Clean category/profile tag pill
// =============================================================================

import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string variant: "default" // "default" | "time" | "location" | "tag"
  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color chipColor: Color.accent
  property color textColor: chipColor
  property color iconColor: textColor
  property real bgAlpha: 0.12
  property real borderAlpha: 0.35
  property bool removable: false
  property real maximumWidth: Style.space(130)
  property string fontFamily: Style.font.family
  property real fontSize: Style.space(8.5)

  property real cornerRadius: -1
  readonly property real effectiveRadius: cornerRadius >= 0
    ? cornerRadius
    : (variant === "time" ? Style.space(4) : implicitHeight / 2)

  property bool isMonospace: variant === "location"
  property bool isOverdue: false
  property bool isDueToday: false
  property bool isDone: false
  property color warningColor: "#df8e1d"
  property color accentColor: Color.accent

  signal clicked()
  signal removed()

  readonly property string effectiveIconText: {
    if (root.iconText.length > 0) return root.iconText
    if (variant === "time") return isOverdue ? "󱫌" : "󰥔"
    if (variant === "location") return "󰊤"
    return ""
  }

  readonly property color resolvedIconColor: {
    if (isDone) return Color.muted
    if (variant === "time") {
      if (isOverdue) return root.warningColor
      return root.accentColor
    }
    if (variant === "location") return root.accentColor
    return (root.iconColor !== root.textColor) ? root.iconColor : root.textColor
  }

  readonly property color resolvedTextColor: {
    if (isDone) return Color.muted
    if (variant === "time") {
      if (isOverdue) return root.warningColor
      if (isDueToday) return root.accentColor
      return root.accentColor
    }
    if (variant === "location") {
      return (root.textColor !== root.chipColor) ? root.textColor : Color.muted
    }
    return root.textColor
  }

  implicitHeight: Style.space(18)
  implicitWidth: Math.min(maximumWidth, (iconLabel.visible ? (iconLabel.implicitWidth + Style.space(4)) : 0) + textLabel.implicitWidth + Style.space(14) + (removable ? Style.space(16) : 0))
  height: implicitHeight
  radius: effectiveRadius

  color: {
    if (isDone) {
      return Util.alpha(Color.muted, 0.08)
    }
    if (variant === "time") {
      if (isOverdue) {
        return chipHover.hovered ? Util.alpha(root.warningColor, 0.24) : Util.alpha(root.warningColor, 0.14)
      }
      if (isDueToday) {
        return chipHover.hovered ? Util.alpha(root.accentColor, 0.22) : Util.alpha(root.accentColor, 0.14)
      }
      return chipHover.hovered ? Util.alpha(root.accentColor, 0.15) : Util.alpha(root.accentColor, 0.08)
    }
    if (variant === "location") {
      return chipHover.hovered ? Util.alpha(root.accentColor, 0.15) : Color.menu.selectedBackground
    }
    return chipHover.hovered ? Util.alpha(root.chipColor, root.bgAlpha + 0.08) : Util.alpha(root.chipColor, root.bgAlpha)
  }

  border.color: {
    if (isDone) {
      return Util.alpha(Color.muted, 0.2)
    }
    if (variant === "time") {
      if (isOverdue) {
        return Util.alpha(root.warningColor, chipHover.hovered ? 0.7 : 0.45)
      }
      if (isDueToday) {
        return Util.alpha(root.accentColor, chipHover.hovered ? 0.7 : 0.4)
      }
      return Util.alpha(root.accentColor, chipHover.hovered ? 0.45 : 0.22)
    }
    if (variant === "location") {
      return chipHover.hovered ? root.accentColor : Util.alpha(root.accentColor, 0.22)
    }
    return Util.alpha(root.chipColor, root.borderAlpha)
  }

  border.width: (variant === "time" && (isOverdue || isDueToday)) ? 1.5 : 1

  Text {
    id: iconLabel
    visible: root.effectiveIconText.length > 0
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    verticalAlignment: Text.AlignVCenter
    text: root.effectiveIconText
    color: root.resolvedIconColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Text {
    id: textLabel
    visible: root.text.length > 0
    anchors.left: iconLabel.visible ? iconLabel.right : parent.left
    anchors.leftMargin: iconLabel.visible ? Style.space(3) : Style.space(6)
    anchors.right: removeBtn.visible ? removeBtn.left : parent.right
    anchors.rightMargin: removeBtn.visible ? Style.space(3) : Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    verticalAlignment: Text.AlignVCenter
    text: root.text
    color: root.resolvedTextColor
    font.family: root.isMonospace ? "monospace" : root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: variant === "time" || (!root.isMonospace && variant !== "location")
    elide: Text.ElideRight
  }

  // Optional Remove action button
  Item {
    id: removeBtn
    visible: root.removable
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(14)
    height: Style.space(14)

    Text {
      anchors.centerIn: parent
      text: "󰅖"
      color: removeHover.hovered ? Color.urgent : Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.space(9)
    }

    MouseArea {
      id: removeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.removed()
    }

    HoverHandler {
      id: removeHover
    }
  }

  MouseArea {
    id: chipMouse
    anchors.left: parent.left
    anchors.right: removeBtn.visible ? removeBtn.left : parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    hoverEnabled: true
    cursorShape: (root.variant === "location" || root.variant === "time") ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  HoverHandler {
    id: chipHover
  }

  PanelToolTip {
    visible: (chipHover.hovered || (removeHover && removeHover.hovered)) && (root.tooltipText.length > 0 || textLabel.truncated)
    text: root.tooltipText.length > 0 ? root.tooltipText : root.text
    fontFamily: root.fontFamily
  }
}
