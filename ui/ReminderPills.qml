import QtQuick
import qs.Commons
import "../TodoStore.js" as TodoStore

Row {
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

  signal reminderSelected(string value, int index)
  signal clearSelected(int index)

  spacing: Style.space(4)

  Repeater {
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
