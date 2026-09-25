import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string keyText: ""
  property color badgeColor: Color.accent
  property color badgeBg: Util.alpha(badgeColor, 0.15)
  property color borderColor: badgeColor
  property real fontSize: Style.space(9)
  property real horizontalPadding: Style.space(8)
  property real verticalPadding: Style.space(2)

  implicitWidth: keyLabel.implicitWidth + horizontalPadding
  implicitHeight: Math.max(Style.space(18), keyLabel.implicitHeight + verticalPadding * 2)
  radius: Style.space(4)
  color: badgeBg
  border.color: borderColor
  border.width: 1

  Text {
    id: keyLabel
    anchors.centerIn: parent
    text: root.keyText
    color: root.badgeColor
    font.family: "monospace"
    font.pixelSize: root.fontSize
    font.bold: true
  }
}
