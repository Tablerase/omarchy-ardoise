// =============================================================================
// Chip.qml
//
// Reusable compact pill/badge component inspired by OmaTasks.
// Supports icons, elided text, subtle background tint, tooltips,
// and optional remove button without any layout recursion loops.
// =============================================================================

import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color chipColor: Color.accent
  property color textColor: chipColor
  property real bgAlpha: 0.12
  property real borderAlpha: 0.35
  property bool removable: false
  property real maximumWidth: Style.space(130)
  property string fontFamily: Style.font.family
  property real fontSize: Style.space(8.5)

  signal clicked()
  signal removed()

  implicitHeight: Style.space(18)
  implicitWidth: Math.min(maximumWidth, (iconLabel.visible ? (iconLabel.implicitWidth + Style.space(4)) : 0) + textLabel.implicitWidth + Style.space(14) + (removable ? Style.space(16) : 0))
  height: implicitHeight
  radius: implicitHeight / 2

  color: chipHover.hovered ? Util.alpha(root.chipColor, root.bgAlpha + 0.08) : Util.alpha(root.chipColor, root.bgAlpha)
  border.color: Util.alpha(root.chipColor, root.borderAlpha)
  border.width: 1

  Text {
    id: iconLabel
    visible: root.iconText.length > 0
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    verticalAlignment: Text.AlignVCenter
    text: root.iconText
    color: root.textColor
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
    color: root.textColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: true
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
    cursorShape: Qt.PointingHandCursor
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
