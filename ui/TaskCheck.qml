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

  scale: 1.0
  Behavior on scale {
    NumberAnimation { duration: 140; easing.type: Easing.OutBack }
  }

  SequentialAnimation {
    id: popAnimation
    NumberAnimation { target: root; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "scale"; to: 1.0; duration: 140; easing.type: Easing.OutBack }
  }

  onCheckedChanged: {
    if (root.checked) {
      popAnimation.restart()
    }
  }

  color: checkMouse.containsMouse
    ? (root.checked ? Color.menu.selectedBackground : Util.alpha(root.accentColor, 0.15))
    : (root.checked
        ? Util.alpha(root.accentColor, 0.14)
        : (root.isOverdue
            ? Util.alpha(root.urgentColor, 0.12)
            : (root.isDueToday ? Util.alpha(root.accentColor, 0.10) : "transparent")))

  Behavior on color { ColorAnimation { duration: 150 } }

  border.color: root.checked
    ? root.accentColor
    : (root.isOverdue ? root.urgentColor : (root.isDueToday ? root.accentColor : Color.muted))
  border.width: (root.isOverdue || root.isDueToday || root.checked) ? 1.5 : 1

  Behavior on border.color { ColorAnimation { duration: 150 } }

  Text {
    anchors.centerIn: parent
    text: "✓"
    color: root.accentColor
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.space(11)
    font.bold: true
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    opacity: root.checked ? 1.0 : 0.0
    scale: root.checked ? 1.0 : 0.2

    Behavior on opacity {
      NumberAnimation { duration: 120 }
    }
    Behavior on scale {
      NumberAnimation { duration: 180; easing.type: Easing.OutBack }
    }
  }

  MouseArea {
    id: checkMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
