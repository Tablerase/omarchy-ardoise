import QtQuick
import qs.Commons

Rectangle {
  id: root

  property bool checked: false
  property bool isOverdue: false
  property bool isDueToday: false
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  property color accentColor: Color.accent

  signal clicked()

  implicitWidth: Style.space(20)
  implicitHeight: Style.space(20)
  width: implicitWidth
  height: implicitHeight
  radius: width / 2

  color: checkMouse.containsMouse
    ? (root.checked ? Color.menu.selectedBackground : Util.alpha(root.accentColor, 0.15))
    : (root.checked
        ? "transparent"
        : (root.isOverdue
            ? Util.alpha(root.urgentColor, 0.12)
            : (root.isDueToday ? Util.alpha(root.accentColor, 0.10) : "transparent")))

  border.color: root.checked
    ? Color.muted
    : (root.isOverdue ? root.urgentColor : (root.isDueToday ? root.accentColor : Color.muted))
  border.width: (root.isOverdue || root.isDueToday) && !root.checked ? 1.5 : 1

  Text {
    anchors.centerIn: parent
    text: root.checked ? "✓" : ""
    color: Color.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.space(11)
    font.bold: true
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: checkMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
