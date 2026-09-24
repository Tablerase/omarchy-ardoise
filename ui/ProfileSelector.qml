import QtQuick
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

Item {
  id: root

  property var profiles: []
  property string selectedProfile: ""
  property int focusedIndex: -1
  property bool isNavFocused: false
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property color accentColor: Color.accent

  signal profileSelected(string profileName, int index)

  implicitHeight: Style.space(22)

  function ensureVisible(idx) {
    if (!profileRepeater || idx < 0 || idx >= profileRepeater.count) return
    var item = profileRepeater.itemAt(idx)
    if (!item) return
    var itemLeft = item.x
    var itemRight = item.x + item.width
    if (itemLeft < profileFlickable.contentX) {
      profileFlickable.contentX = Math.max(0, itemLeft - Style.space(4))
    } else if (itemRight > profileFlickable.contentX + profileFlickable.width) {
      var maxContentX = Math.max(0, profileFlickable.contentWidth - profileFlickable.width)
      profileFlickable.contentX = Math.min(maxContentX, itemRight - profileFlickable.width + Style.space(4))
    }
  }

  onFocusedIndexChanged: {
    if (focusedIndex >= 0) {
      ensureVisible(focusedIndex)
    }
  }

  onIsNavFocusedChanged: {
    if (isNavFocused && focusedIndex >= 0) {
      ensureVisible(focusedIndex)
    }
  }

  Flickable {
    id: profileFlickable
    anchors.fill: parent
    contentWidth: profileRow.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Behavior on contentX {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Row {
      id: profileRow
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        id: profileRepeater
        model: root.profiles

        Rectangle {
          id: profileBtn
          required property string modelData
          required property int index
          readonly property bool isSelected: root.selectedProfile === modelData
          readonly property bool isBtnNavFocused: root.isNavFocused && (root.focusedIndex === index)

          implicitWidth: pillContent.implicitWidth + Style.space(12)
          implicitHeight: Style.space(20)
          radius: implicitHeight / 2
          color: isSelected ? root.accentColor : (isBtnNavFocused ? Util.alpha(root.accentColor, 0.25) : Color.menu.background)
          border.color: isBtnNavFocused ? root.accentColor : (isSelected ? root.accentColor : Color.menu.border)
          border.width: isBtnNavFocused ? 1.5 : 1
          scale: isBtnNavFocused ? 1.05 : 1.0
          Behavior on scale { NumberAnimation { duration: 80 } }

          Row {
            id: pillContent
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: TodoStore.getProfileGlyph(profileBtn.modelData)
              color: profileBtn.isSelected ? "white" : (profileBtn.isBtnNavFocused ? root.accentColor : Color.muted)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: profileText
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, Style.space(80))
              text: profileBtn.modelData
              color: profileBtn.isSelected ? "white" : (profileBtn.isBtnNavFocused ? root.accentColor : root.barForeground)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: profileBtn.isSelected || profileBtn.isBtnNavFocused
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.profileSelected(profileBtn.modelData, profileBtn.index)
              root.ensureVisible(profileBtn.index)
            }
          }

          HoverHandler {
            id: profileHover
          }

          PanelToolTip {
            visible: profileHover.hovered && profileText.truncated
            text: profileBtn.modelData
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }
      }
    }
  }
}
