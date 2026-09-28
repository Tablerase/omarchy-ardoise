import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

Item {
  id: root

  property var presets: []
  property string selectedValue: ""
  property bool hasReminder: false
  property int focusedIndex: -1
  property bool isNavFocused: false
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property color accentColor: Color.accent
  property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  property color fadeColor: Color.menu.background

  signal reminderSelected(string value, int index)
  signal clearSelected(int index)

  implicitHeight: Style.space(26)
  implicitWidth: reminderRow.implicitWidth

  function ensureVisible(idx) {
    var item = null
    if (presetRepeater && idx >= 0 && idx < presetRepeater.count) {
      item = presetRepeater.itemAt(idx)
    } else if (idx === root.presets.length && clearBtn.visible) {
      item = clearBtn
    }
    if (!item) return

    var itemLeft = item.x
    var itemRight = item.x + item.width
    if (itemLeft < reminderFlickable.contentX) {
      reminderFlickable.contentX = Math.max(0, itemLeft - Style.space(4))
    } else if (itemRight > reminderFlickable.contentX + reminderFlickable.width) {
      var maxContentX = Math.max(0, reminderFlickable.contentWidth - reminderFlickable.width)
      reminderFlickable.contentX = Math.min(maxContentX, itemRight - reminderFlickable.width + Style.space(4))
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
    id: reminderFlickable
    anchors.fill: parent
    anchors.bottomMargin: Style.space(4)
    contentWidth: reminderRow.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Behavior on contentX {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    ScrollBar.horizontal: ScrollBar {
      id: hScrollBar
      policy: reminderFlickable.contentWidth > reminderFlickable.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      implicitHeight: Style.space(3)
      contentItem: Rectangle {
        radius: height / 2
        color: Util.alpha(Color.foreground, hScrollBar.pressed ? 0.5 : (hScrollBar.hovered ? 0.35 : 0.2))
        Behavior on color { ColorAnimation { duration: 100 } }
      }
      background: Item {}
    }

    Row {
      id: reminderRow
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        id: presetRepeater
        model: root.presets

        Rectangle {
          id: presetBtn
          required property var modelData
          required property int index
          readonly property bool isSelected: root.hasReminder && (root.selectedValue === modelData.value)
          readonly property bool isBtnNavFocused: root.isNavFocused && (root.focusedIndex === index)

          implicitWidth: presetText.implicitWidth + Style.space(12)
          implicitHeight: Style.space(20)
          radius: implicitHeight / 2
          color: isSelected ? root.accentColor : (isBtnNavFocused ? Util.alpha(root.accentColor, 0.25) : Color.menu.background)
          border.color: isBtnNavFocused ? root.accentColor : (isSelected ? root.accentColor : Color.menu.border)
          border.width: isBtnNavFocused ? 1.5 : 1
          scale: isBtnNavFocused ? 1.05 : 1.0
          Behavior on scale { NumberAnimation { duration: 80 } }

          Text {
            id: presetText
            anchors.centerIn: parent
            text: presetBtn.modelData.label
            color: presetBtn.isSelected ? "white" : (presetBtn.isBtnNavFocused ? root.accentColor : root.barForeground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: presetBtn.isSelected || presetBtn.isBtnNavFocused
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var freshVal = (typeof TodoStore !== "undefined" && typeof TodoStore.computePresetReminder === "function")
                ? TodoStore.computePresetReminder(presetBtn.index)
                : presetBtn.modelData.value
              root.reminderSelected(freshVal, presetBtn.index)
            }
          }
        }
      }

      // Clear reminder pill
      Rectangle {
        id: clearBtn
        visible: root.hasReminder
        readonly property bool isClearNavFocused: root.isNavFocused && (root.focusedIndex === root.presets.length)
        implicitWidth: clearText.implicitWidth + Style.space(10)
        implicitHeight: Style.space(20)
        radius: implicitHeight / 2
        color: isClearNavFocused ? Util.alpha(root.urgentColor, 0.2) : "transparent"
        border.color: isClearNavFocused ? root.urgentColor : Color.menu.border
        border.width: isClearNavFocused ? 1.5 : 1
        scale: isClearNavFocused ? 1.05 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

        Text {
          id: clearText
          anchors.centerIn: parent
          text: "󰅖 Clear"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.clearSelected(root.presets.length)
        }
      }
    }
  }

  // Soft blur/fade edge on the left
  Rectangle {
    id: leftFadeEdge
    z: 1
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(24)
    enabled: false
    visible: opacity > 0
    opacity: (reminderFlickable.contentWidth > reminderFlickable.width && reminderFlickable.contentX > 2) ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.fadeColor }
      GradientStop { position: 1.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
    }
  }

  // Soft blur/fade edge on the right
  Rectangle {
    id: rightFadeEdge
    z: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(32)
    enabled: false
    visible: opacity > 0
    opacity: (reminderFlickable.contentWidth > reminderFlickable.width && reminderFlickable.contentX < (reminderFlickable.contentWidth - reminderFlickable.width - 2)) ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
      GradientStop { position: 1.0; color: root.fadeColor }
    }
  }
}
