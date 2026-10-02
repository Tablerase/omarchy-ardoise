import QtQuick
import qs.Commons
import qs.Ui

// Contextual menu for the focused task, opened with K.
//
// Rendering only: selection and key handling live in PanelLogic.js, because
// PanelKeyCatcher routes j/k/Enter/Space/x/Esc through the panel state machine
// before any printable key reaches the menu. This component is a non-modal
// overlay, so it must never take focus.
Item {
  id: root

  property bool isOpen: false
  property var items: []
  property int selectedIndex: 0
  property real anchorX: 0
  property real anchorY: 0
  property string title: ""
  property string meta: ""
  property var bar: null
  property alias card: card

  signal itemActivated(string actionId)
  signal closeRequested()

  // The card is clamped inside the panel (and therefore the monitor) with an
  // 8px margin, preferring the right of the focused row and flipping left
  // when there is no room. Both are QML bindings so they track the card's
  // resolved size, the anchor, and the panel size.
  function clampedX() {
    var menuW = card.width > 0 ? card.width : Style.space(260)
    var parentW = root.parent ? root.parent.width : menuW
    var m = Style.space(8)
    var x = root.anchorX + Style.space(6)
    if (x + menuW + m > parentW) x = root.anchorX - menuW - Style.space(6)
    return Math.max(m, Math.min(parentW - menuW - m, x))
  }

  function clampedY() {
    var menuH = card.implicitHeight > 0 ? card.implicitHeight : Style.space(220)
    var parentH = root.parent ? root.parent.height : menuH
    var m = Style.space(8)
    return Math.max(m, Math.min(parentH - menuH - m, root.anchorY - menuH / 2))
  }

  anchors.fill: parent
  visible: isOpen
  z: 900

  // Click-away scrim. It also swallows wheel events so the list behind cannot
  // scroll while the menu is open.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: root.closeRequested()
    onWheel: function(wheel) { wheel.accepted = true }
  }

  BorderSurface {
    id: card
    x: root.clampedX()
    y: root.clampedY()
    width: Style.space(260)
    implicitHeight: card.contentTopInset + card.contentBottomInset + menuContent.implicitHeight
    height: implicitHeight
    color: {
      var base = (Color.popups && Color.popups.background) ? Color.popups.background : Color.background
      return Qt.rgba(base.r, base.g, base.b, 0.98)
    }
    borderSpec: Border.flat(Color.accent, 1.5)
    radius: Style.cornerRadius
    padding: Style.space(8)

    // Stop clicks inside the card from reaching the scrim.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onWheel: function(wheel) { wheel.accepted = true }
    }

    Item {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset

      Column {
        id: menuContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(4)

        // Header: focused task context
        Column {
          width: parent.width
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: root.title
            color: Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: root.meta.length > 0
            text: root.meta
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption * 0.8
            elide: Text.ElideRight
          }
        }

        PanelSeparator { width: parent.width }

        Repeater {
          model: root.items

          Item {
            id: menuItem
            required property var modelData
            required property int index

            readonly property bool isSelected: root.selectedIndex === index
            width: parent.width
            implicitHeight: Style.space(38)
            height: implicitHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius * 0.5
              color: menuItem.isSelected
                ? Util.alpha(Color.accent, 0.16)
                : (itemMouse.containsMouse ? Color.menu.selectedBackground : "transparent")
              border.color: menuItem.isSelected ? Color.accent : "transparent"
              border.width: menuItem.isSelected ? 1 : 0
            }

            MouseArea {
              id: itemMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = menuItem.index
              onClicked: root.itemActivated(String(menuItem.modelData.id || ""))
            }

            Item {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)

              Row {
                id: itemLeft
                anchors.left: parent.left
                anchors.right: keyBadge.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  id: itemIcon
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(menuItem.modelData.icon || "")
                  color: menuItem.isSelected ? Color.accent : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - itemIcon.implicitWidth - parent.spacing
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: String(menuItem.modelData.label || "")
                    color: menuItem.isSelected ? Color.accent : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: menuItem.isSelected
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: Boolean(menuItem.modelData.desc)
                    text: String(menuItem.modelData.desc || "")
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.8
                    elide: Text.ElideRight
                  }
                }
              }

              KeyBadge {
                id: keyBadge
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                keyText: String(menuItem.modelData.shortcut || "")
              }
            }
          }
        }
      }
    }
  }
}
