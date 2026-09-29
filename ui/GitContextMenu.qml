import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool isOpen: false
  property var snapshot: null
  property var bar: null
  property int selectedMenuIndex: 0
  property real targetX: 0
  property real targetY: 0
  property alias card: card

  signal rollbackRequested(string hash)
  signal recoverRequested(string hash)
  signal copyHashRequested(string hash)
  signal closeRequested()

  readonly property var menuItems: [
    {
      id: "rollback",
      icon: "󰜉",
      label: "Rollback to snapshot",
      shortcut: "r",
      desc: "Replaces current tasks with this commit"
    },
    {
      id: "recover",
      icon: "󰅍",
      label: "Recover deleted tasks",
      shortcut: "c",
      desc: "Restores missing tasks from this commit"
    },
    {
      id: "copyHash",
      icon: "󰆏",
      label: "Copy commit hash",
      shortcut: "y",
      desc: (snapshot && snapshot.shortHash) ? snapshot.shortHash : ""
    }
  ]

  function open(snapshotData, xPos, yPos) {
    snapshot = snapshotData
    selectedMenuIndex = 0
    var menuW = card.width > 0 ? card.width : Style.space(260)
    var menuH = (card.height > 0) ? card.height : (menuContent.implicitHeight > 0 ? (menuContent.implicitHeight + card.contentTopInset + card.contentBottomInset) : Style.space(180))
    var parentW = root.parent ? root.parent.width : 400
    var parentH = root.parent ? root.parent.height : 500
    var rawX = (xPos !== undefined && !isNaN(xPos)) ? xPos : (parentW - menuW) / 2
    var rawY = (yPos !== undefined && !isNaN(yPos)) ? yPos : (parentH - menuH) / 2
    targetX = Math.max(Style.space(8), Math.min(parentW - menuW - Style.space(8), rawX))
    targetY = Math.max(Style.space(8), Math.min(parentH - menuH - Style.space(8), rawY))
    isOpen = true
  }

  function close() {
    isOpen = false
    root.closeRequested()
  }

  function triggerAction(actionId) {
    if (!snapshot) {
      close()
      return
    }
    var hash = String(snapshot.hash || "")
    if (actionId === "rollback") {
      root.rollbackRequested(hash)
    } else if (actionId === "recover") {
      root.recoverRequested(hash)
    } else if (actionId === "copyHash") {
      root.copyHashRequested(hash)
    }
    close()
  }

  function handleKey(event) {
    if (!isOpen) return false

    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      close()
      return true
    }
    if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
      event.accepted = true
      selectedMenuIndex = Math.min(menuItems.length - 1, selectedMenuIndex + 1)
      return true
    }
    if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
      event.accepted = true
      selectedMenuIndex = Math.max(0, selectedMenuIndex - 1)
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      event.accepted = true
      if (selectedMenuIndex >= 0 && selectedMenuIndex < menuItems.length) {
        triggerAction(menuItems[selectedMenuIndex].id)
      }
      return true
    }
    if (event.key === Qt.Key_R || event.text === "r") {
      event.accepted = true
      triggerAction("rollback")
      return true
    }
    if (event.key === Qt.Key_C || event.text === "c") {
      event.accepted = true
      triggerAction("recover")
      return true
    }
    if (event.key === Qt.Key_Y || event.text === "y") {
      event.accepted = true
      triggerAction("copyHash")
      return true
    }
    return true
  }

  anchors.fill: parent
  visible: isOpen

  // Click-away scrim
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: root.close()
    onWheel: function(wheel) { wheel.accepted = true }
  }

  BorderSurface {
    id: card
    x: root.targetX
    y: root.targetY
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

    // Stop mouse clicks from passing to scrim
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

        // Header: Snapshot info
        Row {
          width: parent.width
          height: Math.max(headerIcon.implicitHeight, headerColumn.implicitHeight)
          spacing: Style.space(6)

          Text {
            id: headerIcon
            anchors.verticalCenter: parent.verticalCenter
            text: "󰊢"
            color: Color.accent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Column {
            id: headerColumn
            width: parent.width - headerIcon.implicitWidth - parent.spacing
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: (root.snapshot && (root.snapshot.cleanMessage || root.snapshot.message)) ? (root.snapshot.cleanMessage || root.snapshot.message) : "Snapshot"
              color: Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.snapshot ? ("[" + (root.snapshot.deviceName || "") + "] " + (root.snapshot.shortHash || "")) : ""
              color: Color.muted
              font.family: "monospace"
              font.pixelSize: Style.font.caption * 0.8
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { width: parent.width }

        // Menu actions
        Repeater {
          model: root.menuItems

          Item {
            id: menuItem
            required property var modelData
            required property int index

            readonly property bool isSelected: root.selectedMenuIndex === index
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
              onEntered: root.selectedMenuIndex = menuItem.index
              onClicked: root.triggerAction(menuItem.modelData.id)
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
