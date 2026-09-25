import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

ToolTip {
  id: root

  property string description: ""
  property string shortcut: ""
  property bool autoParse: true

  property color panelForeground: Color.tooltip.text
  property color panelBackground: Color.tooltip.background
  property color panelBorder: Color.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall
  property color shortcutColor: Color.accent

  readonly property var parsedInfo: {
    var desc = root.description.length > 0 ? root.description : root.text
    if (root.shortcut.length > 0) {
      return { desc: desc, shortcut: root.shortcut }
    }
    if (root.autoParse && desc.length > 0) {
      var m = desc.trim().match(/^(.*?)\s*\(([^()]+)\)$/)
      if (m && m[2]) {
        return { desc: m[1].trim(), shortcut: m[2].trim() }
      }
    }
    return { desc: desc, shortcut: "" }
  }

  readonly property string effectiveDesc: parsedInfo.desc
  readonly property string effectiveShortcut: parsedInfo.shortcut

  readonly property var panelBorderSpec: Border.localOrSurfaceSpec("tooltip", "border", panelBorder, Color.tooltip.border, Style.normalBorderWidth)

  delay: 400
  padding: 0

  background: BorderSurface {
    color: root.panelBackground
    borderSpec: root.panelBorderSpec
    radius: Style.cornerRadius
  }

  contentItem: Column {
    spacing: Style.space(4)
    topPadding: Border.top(root.panelBorderSpec) + Style.spacing.controlPaddingY
    bottomPadding: Border.bottom(root.panelBorderSpec) + Style.spacing.controlPaddingY
    leftPadding: Border.left(root.panelBorderSpec) + Style.spacing.controlPaddingX
    rightPadding: Border.right(root.panelBorderSpec) + Style.spacing.controlPaddingX

    Text {
      id: descText
      visible: root.effectiveDesc.length > 0
      anchors.horizontalCenter: parent.horizontalCenter
      horizontalAlignment: Text.AlignHCenter
      text: root.effectiveDesc
      color: root.panelForeground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    Row {
      id: shortcutRow
      visible: root.effectiveShortcut.length > 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)

      Repeater {
        model: root.effectiveShortcut.length > 0 ? root.effectiveShortcut.split(" / ") : []

        Row {
          required property string modelData
          required property int index
          spacing: Style.space(4)

          Text {
            visible: index > 0
            text: "/"
            color: Color.muted
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.fontFamily
            font.pixelSize: Style.space(9)
          }

          KeyBadge {
            keyText: modelData.trim()
            badgeColor: root.shortcutColor
          }
        }
      }
    }
  }
}
