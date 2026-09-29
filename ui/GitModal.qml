import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../GitSync.js" as GitSync
import "../TodoStore.js" as TodoStore

Rectangle {
  id: root

  property bool isOpen: false
  property var bar: null
  property var barWidget: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground

  property string deviceName: root.barWidget ? String(root.barWidget.deviceName || "") : "omarchy"
  property var snapshots: (root.barWidget && root.barWidget.gitSnapshots) ? root.barWidget.gitSnapshots : []
  property int selectedIndex: 0
  property int activeTab: 0 // 0: Snapshots & Rollback, 1: Sync Settings
  property int syncFocusIndex: 0 // 0: remoteField, 1: saveRemoteBtn, 2: syncNowBtn
  property string snapshotSection: "snapshots" // "snapshots" | "actions"
  property int actionButtonIndex: 0 // 0: rollback, 1: recover
  property alias contextMenu: contextMenu

  readonly property var selectedSnapshot: (root.snapshots && root.snapshots.length > root.selectedIndex)
    ? root.snapshots[root.selectedIndex]
    : null

  signal closeRequested()

  onActiveTabChanged: {
    if (contextMenu) contextMenu.close()
    if (activeTab === 0) {
      root.snapshotSection = "snapshots"
      root.actionButtonIndex = 0
      root.ensureSnapshotVisible()
    } else {
      root.syncFocusIndex = 0
    }
    root.forceActiveFocus()
  }

  function open() {
    isOpen = true
    activeTab = 0
    snapshotSection = "snapshots"
    actionButtonIndex = 0
    selectedIndex = 0
    syncFocusIndex = 0
    if (contextMenu) contextMenu.close()
    if (root.barWidget && typeof root.barWidget.refreshGitHistory === "function") {
      root.barWidget.refreshGitHistory(true)
    }
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function close() {
    if (contextMenu && contextMenu.isOpen) {
      contextMenu.close()
      return
    }
    isOpen = false
    root.closeRequested()
  }

  function openContextMenuForSelected() {
    if (!root.selectedSnapshot) return
    var targetY = Style.space(80)
    if (snapshotList && root.selectedIndex >= 0 && root.selectedIndex < snapshotList.count) {
      var item = snapshotList.itemAtIndex(root.selectedIndex)
      if (item) {
        var mapped = item.mapToItem(root, item.width - Style.space(200), item.height / 2)
        contextMenu.open(root.selectedSnapshot, mapped.x, mapped.y)
        return
      }
    }
    contextMenu.open(root.selectedSnapshot, (root.width - Style.space(260)) / 2, Style.space(100))
  }

  function toggle() {
    if (isOpen) close()
    else open()
  }

  onIsOpenChanged: {
    if (isOpen) {
      if (root.barWidget && typeof root.barWidget.refreshGitHistory === "function") {
        root.barWidget.refreshGitHistory(true)
      }
      Qt.callLater(function() { root.forceActiveFocus() })
    }
  }

  anchors.fill: parent
  visible: isOpen
  z: 999
  color: {
    var base = (Color.popups && Color.popups.background) ? Color.popups.background : Color.background
    return Qt.rgba(base.r, base.g, base.b, 1.0)
  }
  radius: Style.cornerRadius
  focus: true

  function ensureSnapshotVisible() {
    if (snapshotList && root.selectedIndex >= 0 && root.selectedIndex < snapshotList.count) {
      snapshotList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
    if (root.snapshots && root.selectedIndex >= root.snapshots.length - 5) {
      if (root.barWidget && typeof root.barWidget.loadMoreGitHistory === "function") {
        root.barWidget.loadMoreGitHistory()
      }
    }
  }

  // Unconditional mouse event blocker — prevents hover/click bleed-through to items below
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: function(mouse) { root.forceActiveFocus() }
    onWheel: function(wheel) { wheel.accepted = true }
    z: -1
  }

  Keys.onEscapePressed: function(event) {
    event.accepted = true
    root.close()
  }

  function handleKey(event) {
    if (contextMenu && contextMenu.isOpen) {
      if (contextMenu.handleKey(event)) return true
    }

    if (event.key === Qt.Key_Escape || event.text === "q" || event.text === "u") {
      event.accepted = true
      root.close()
      return
    }

    // Tab switching with 1, 2
    if (event.key === Qt.Key_1 || event.text === "1") {
      event.accepted = true
      root.activeTab = 0
      return
    }
    if (event.key === Qt.Key_2 || event.text === "2") {
      event.accepted = true
      root.activeTab = 1
      return
    }

    if (root.activeTab === 0) {
      // Tab / Shift+Tab section transitions in Tab 0
      if (event.key === Qt.Key_Tab) {
        event.accepted = true
        if (root.snapshotSection === "snapshots") {
          root.snapshotSection = "actions"
          root.actionButtonIndex = 0
        } else {
          if (root.actionButtonIndex === 0) {
            root.actionButtonIndex = 1
          } else {
            root.snapshotSection = "snapshots"
          }
        }
        return
      }
      if (event.key === Qt.Key_Backtab) {
        event.accepted = true
        if (root.snapshotSection === "actions") {
          if (root.actionButtonIndex === 1) {
            root.actionButtonIndex = 0
          } else {
            root.snapshotSection = "snapshots"
          }
        } else {
          root.snapshotSection = "actions"
          root.actionButtonIndex = 1
        }
        return
      }

      if (root.snapshotSection === "snapshots") {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
          event.accepted = true
          if (root.snapshots && root.snapshots.length > 0) {
            if (root.selectedIndex < root.snapshots.length - 1) {
              root.selectedIndex++
              root.ensureSnapshotVisible()
            } else {
              root.snapshotSection = "actions"
              root.actionButtonIndex = 0
            }
          }
          return
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          if (root.snapshots && root.snapshots.length > 0) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.key === Qt.Key_L || event.text === "l") {
          event.accepted = true
          root.activeTab = 1
          return
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier || event.text === "G")) {
          event.accepted = true
          if (root.snapshots && root.snapshots.length > 0) {
            root.selectedIndex = root.snapshots.length - 1
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.key === Qt.Key_G || event.text === "g") {
          event.accepted = true
          if (root.snapshots && root.snapshots.length > 0) {
            root.selectedIndex = 0
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.key === Qt.Key_M || event.text === "m" || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Menu) {
          event.accepted = true
          if (root.selectedSnapshot) {
            root.openContextMenuForSelected()
          }
          return
        }
        if (event.key === Qt.Key_R || event.text === "r") {
          event.accepted = true
          if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.rollbackToCommit === "function") {
            root.barWidget.rollbackToCommit(root.selectedSnapshot.hash)
          }
          return
        }
        if (event.key === Qt.Key_C || event.text === "c") {
          event.accepted = true
          if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.recoverFromCommit === "function") {
            root.barWidget.recoverFromCommit(root.selectedSnapshot.hash)
          }
          return
        }
      } else { // snapshotSection === "actions"
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left || event.text === "h") {
          event.accepted = true
          root.actionButtonIndex = 0
          return
        }
        if (event.key === Qt.Key_L || event.key === Qt.Key_Right || event.text === "l") {
          event.accepted = true
          root.actionButtonIndex = 1
          return
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          root.snapshotSection = "snapshots"
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          event.accepted = true
          if (root.actionButtonIndex === 0) {
            rollbackBtn.clicked()
          } else {
            recoverBtn.clicked()
          }
          return
        }
        if (event.key === Qt.Key_R || event.text === "r") {
          event.accepted = true
          rollbackBtn.clicked()
          return
        }
        if (event.key === Qt.Key_C || event.text === "c") {
          event.accepted = true
          recoverBtn.clicked()
          return
        }
      }
    } else if (root.activeTab === 1) {
      if (event.key === Qt.Key_Tab) {
        event.accepted = true
        root.syncFocusIndex = (root.syncFocusIndex + 1) % 3
        return
      }
      if (event.key === Qt.Key_Backtab) {
        event.accepted = true
        root.syncFocusIndex = (root.syncFocusIndex + 2) % 3
        return
      }
      if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
        event.accepted = true
        if (root.syncFocusIndex === 0) {
          root.syncFocusIndex = 1
        }
        return
      }
      if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
        event.accepted = true
        if (root.syncFocusIndex > 0) {
          root.syncFocusIndex = 0
        }
        return
      }
      if (event.key === Qt.Key_L || event.key === Qt.Key_Right || event.text === "l") {
        event.accepted = true
        if (root.syncFocusIndex === 1) {
          root.syncFocusIndex = 2
        }
        return
      }
      if (event.key === Qt.Key_H || event.key === Qt.Key_Left || event.text === "h") {
        event.accepted = true
        if (root.syncFocusIndex === 2) {
          root.syncFocusIndex = 1
        } else {
          root.activeTab = 0
        }
        return
      }
      if (event.key === Qt.Key_I || event.key === Qt.Key_A || event.text === "i" || event.text === "a" || event.text === "/") {
        if (root.syncFocusIndex === 0) {
          event.accepted = true
          remoteField.forceActiveFocus()
          return
        }
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        event.accepted = true
        if (root.syncFocusIndex === 0) {
          remoteField.forceActiveFocus()
        } else if (root.syncFocusIndex === 1) {
          saveRemoteBtn.clicked()
        } else if (root.syncFocusIndex === 2) {
          syncNowBtn.clicked()
        }
        return
      }
      if (event.text === "s" || event.key === Qt.Key_S) {
        event.accepted = true
        syncNowBtn.clicked()
        return
      }
      if (root.syncFocusIndex === 0 && event.text && event.text.length === 1 && !event.modifiers && event.text !== "j" && event.text !== "k" && event.text !== "h" && event.text !== "l") {
        event.accepted = true
        remoteField.forceActiveFocus()
        remoteField.text += event.text
        remoteField.cursorPosition = remoteField.text.length
        return
      }
    }
    return false
  }

  Keys.onPressed: function(event) {
    handleKey(event)
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    // Modal Header
    Item {
      width: parent.width
      implicitHeight: Math.max(headerLeft.implicitHeight, closeBtn.implicitHeight)

      Row {
        id: headerLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰊢"
          color: Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            text: "Git Snapshots & Undo"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            text: "Device: [" + root.deviceName + "] • " + (root.snapshots.length) + " snapshots"
            color: Util.alpha(root.barForeground, 0.7)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Close Button
      PanelActionButton {
        id: closeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(24)
        iconText: "󰅖"
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: Color.muted
        hoverColor: root.bar ? root.bar.urgent : Color.urgent
        tooltipText: ""
        onClicked: root.close()

        HoverHandler { id: closeBtnHover }
        ShortcutToolTip {
          visible: closeBtnHover.hovered
          description: "Close"
          shortcut: "Esc"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }
      }
    }

    // Tabs Header — matching HelpModal separator style
    Row {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: [
          { label: "Snapshots", shortcut: "1" },
          { label: "Sync & Remote", shortcut: "2" }
        ]

        Item {
          required property var modelData
          required property int index

          readonly property bool isActive: root.activeTab === index
          implicitWidth: tabRow.implicitWidth + Style.space(16)
          implicitHeight: tabRow.implicitHeight + Style.space(10)

          Row {
            id: tabRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: isActive ? root.barForeground : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: isActive
            }

            KeyBadge {
              anchors.verticalCenter: parent.verticalCenter
              keyText: modelData.shortcut
            }
          }

          // Active underline accent
          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1.5
            color: isActive ? Color.accent : Util.alpha(Color.muted, 0.2)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.activeTab = index
              root.forceActiveFocus()
            }
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // Tab 0: Snapshots List & Rollback
    Item {
      visible: root.activeTab === 0
      width: parent.width
      height: parent.height - y - Style.space(8)

      Column {
        anchors.fill: parent
        spacing: Style.space(6)

        // Snapshot Virtualized List
        Item {
          id: listContainer
          width: parent.width
          height: parent.height - actionRow.implicitHeight - Style.space(10)

          ListView {
            id: snapshotList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(4)
            model: root.snapshots
            currentIndex: root.selectedIndex

            ScrollBar.vertical: ScrollBar {
              policy: snapshotList.contentHeight > snapshotList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            onAtYEndChanged: {
              if (atYEnd && root.barWidget && typeof root.barWidget.loadMoreGitHistory === "function") {
                root.barWidget.loadMoreGitHistory()
              }
            }

            delegate: Rectangle {
              id: snapshotItem
              required property var modelData
              required property int index

              readonly property bool isSelected: root.selectedIndex === index
              readonly property bool isLocalDevice: String(modelData.deviceName || "").toLowerCase() === String(root.deviceName).toLowerCase()

              width: snapshotList.width
              implicitHeight: itemLayout.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: isSelected
                ? Util.alpha(Color.accent, 0.14)
                : (itemHover.containsMouse ? Color.menu.selectedBackground : Color.menu.selectedBackground)
              border.color: isSelected ? Color.accent : Color.menu.border
              border.width: isSelected ? 1.5 : 1

              MouseArea {
                id: itemHover
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                onClicked: function(mouse) {
                  root.selectedIndex = snapshotItem.index
                  root.snapshotSection = "snapshots"
                  root.forceActiveFocus()
                  if (mouse.button === Qt.RightButton) {
                    var pos = mapToItem(root, mouse.x, mouse.y)
                    contextMenu.open(snapshotItem.modelData, pos.x, pos.y)
                  }
                }
              }

              Row {
                id: itemLayout
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(8)

                // Device Tag Badge
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: devLabel.implicitWidth + Style.space(8)
                  implicitHeight: devLabel.implicitHeight + Style.space(4)
                  radius: Style.cornerRadius * 0.5
                  color: snapshotItem.isLocalDevice ? Util.alpha(Color.accent, 0.25) : Util.alpha(Color.muted, 0.2)

                  Text {
                    id: devLabel
                    anchors.centerIn: parent
                    text: (snapshotItem.modelData && snapshotItem.modelData.deviceName) ? snapshotItem.modelData.deviceName : "unknown"
                    color: snapshotItem.isLocalDevice ? Color.accent : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.85
                    font.bold: true
                  }
                }

                // Message and relative date
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - devLabel.parent.width - (countBadge.visible ? countBadge.width : 0) - (moreBtn.visible ? moreBtn.width : 0) - Style.space(28)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: (snapshotItem.modelData && (snapshotItem.modelData.cleanMessage || snapshotItem.modelData.message)) ? (snapshotItem.modelData.cleanMessage || snapshotItem.modelData.message) : ""
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Row {
                    spacing: Style.space(6)
                    Text {
                      text: (snapshotItem.modelData && snapshotItem.modelData.shortHash) ? snapshotItem.modelData.shortHash : ""
                      color: Color.muted
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption * 0.8
                    }
                    Text {
                      text: "• " + ((snapshotItem.modelData && snapshotItem.modelData.timestamp) ? GitSync.formatRelativeTime(snapshotItem.modelData.timestamp) : "")
                      color: Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.8
                    }
                  }
                }

                // Task Count Badge
                Rectangle {
                  id: countBadge
                  anchors.verticalCenter: parent.verticalCenter
                  visible: Boolean(snapshotItem.modelData && snapshotItem.modelData.pendingCount !== undefined)
                  implicitWidth: countText.implicitWidth + Style.space(6)
                  implicitHeight: countText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius * 0.4
                  color: Util.alpha(Color.muted, 0.15)

                  Text {
                    id: countText
                    anchors.centerIn: parent
                    text: (snapshotItem.modelData && snapshotItem.modelData.pendingCount !== undefined ? snapshotItem.modelData.pendingCount : "") + " pending"
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.8
                  }
                }

                // More options button (contextual menu trigger)
                PanelActionButton {
                  id: moreBtn
                  anchors.verticalCenter: parent.verticalCenter
                  visible: itemHover.containsMouse || snapshotItem.isSelected
                  size: Style.space(22)
                  iconText: "󰇙"
                  fontSize: Style.font.caption
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  foreground: Color.muted
                  hoverColor: Color.accent
                  tooltipText: "Snapshot options"
                  onClicked: {
                    root.selectedIndex = snapshotItem.index
                    root.snapshotSection = "snapshots"
                    var pos = mapToItem(root, width / 2, height)
                    contextMenu.open(snapshotItem.modelData, pos.x - Style.space(200), pos.y)
                  }
                }
              }
            }
          }

          // Empty state
          Text {
            anchors.centerIn: parent
            visible: !root.snapshots || root.snapshots.length === 0
            text: "No git snapshots found. Add or edit tasks to create snapshots."
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // Actions Row
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: rollbackBtn
            text: "Rollback"
            enabled: Boolean(root.selectedSnapshot)
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 0) && (root.snapshotSection === "actions") && (root.actionButtonIndex === 0)
            onClicked: {
              if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.rollbackToCommit === "function") {
                root.barWidget.rollbackToCommit(root.selectedSnapshot.hash)
                root.forceActiveFocus()
              }
            }

            HoverHandler { id: rollbackBtnHover }
            ShortcutToolTip {
              visible: rollbackBtnHover.hovered
              description: "Rollback to snapshot"
              shortcut: "r"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Button {
            id: recoverBtn
            text: "Recover Deleted"
            enabled: Boolean(root.selectedSnapshot)
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 0) && (root.snapshotSection === "actions") && (root.actionButtonIndex === 1)
            onClicked: {
              if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.recoverFromCommit === "function") {
                root.barWidget.recoverFromCommit(root.selectedSnapshot.hash)
                root.forceActiveFocus()
              }
            }

            HoverHandler { id: recoverBtnHover }
            ShortcutToolTip {
              visible: recoverBtnHover.hovered
              description: "Recover deleted tasks from snapshot"
              shortcut: "c"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }
        }
      }
    }

    // Tab 1: Sync & Remote Settings
    Item {
      visible: root.activeTab === 1
      width: parent.width
      height: parent.height - y - Style.space(8)

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        Text {
          text: "Remote Repository (GitHub / GitLab)"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: remoteField
          width: parent.width
          placeholderText: "git@github.com:username/ardoise-data.git"
          placeholderTextColor: Color.muted
          text: root.barWidget ? String(root.barWidget.remoteUrl || "") : ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.barForeground
          selectByMouse: true
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          topPadding: Style.space(8)
          bottomPadding: Style.space(8)

          background: BorderSurface {
            readonly property bool isNavFocused: (root.activeTab === 1) && (root.syncFocusIndex === 0) && !remoteField.activeFocus
            color: remoteField.activeFocus
              ? Util.alpha(Color.accent, 0.08)
              : Style.controlFill(false, remoteField.hovered, root.barForeground, Color.accent)
            borderSpec: remoteField.activeFocus
              ? Border.flat(Color.accent, 2)
              : (isNavFocused
                  ? Border.flat(Color.accent, 1)
                  : (remoteField.hovered ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent)
                                         : Border.controlSpec("normal", root.barForeground, Color.accent)))
            radius: Style.cornerRadius
          }

          onActiveFocusChanged: {
            if (activeFocus) {
              root.syncFocusIndex = 0
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            remoteField.focus = false
            root.syncFocusIndex = 0
            root.forceActiveFocus()
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              event.accepted = true
              remoteField.focus = false
              root.syncFocusIndex = 0
              root.forceActiveFocus()
              return
            }
          }

          Keys.onDownPressed: function(event) {
            event.accepted = true
            remoteField.focus = false
            root.syncFocusIndex = 1
            root.forceActiveFocus()
          }

          Keys.onTabPressed: function(event) {
            event.accepted = true
            remoteField.focus = false
            root.syncFocusIndex = 1
            root.forceActiveFocus()
          }

          Keys.onReturnPressed: function(event) {
            event.accepted = true
            if (root.barWidget && typeof root.barWidget.setRemoteUrl === "function") {
              root.barWidget.setRemoteUrl(remoteField.text)
            }
            remoteField.focus = false
            root.syncFocusIndex = 1
            root.forceActiveFocus()
          }
          Keys.onEnterPressed: function(event) {
            event.accepted = true
            if (root.barWidget && typeof root.barWidget.setRemoteUrl === "function") {
              root.barWidget.setRemoteUrl(remoteField.text)
            }
            remoteField.focus = false
            root.syncFocusIndex = 1
            root.forceActiveFocus()
          }
        }

        Row {
          spacing: Style.space(8)

          Button {
            id: saveRemoteBtn
            text: "Save Remote"
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 1) && (root.syncFocusIndex === 1)
            onClicked: {
              if (root.barWidget && typeof root.barWidget.setRemoteUrl === "function") {
                root.barWidget.setRemoteUrl(remoteField.text)
              }
              root.forceActiveFocus()
            }

            HoverHandler { id: saveRemoteHover }
            ShortcutToolTip {
              visible: saveRemoteHover.hovered
              description: "Save remote repository URL"
              shortcut: "Enter"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Button {
            id: syncNowBtn
            text: "Sync Now"
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 1) && (root.syncFocusIndex === 2)
            onClicked: {
              if (root.barWidget && typeof root.barWidget.syncWithRemote === "function") {
                root.barWidget.syncWithRemote()
              }
              root.forceActiveFocus()
            }

            HoverHandler { id: syncNowHover }
            ShortcutToolTip {
              visible: syncNowHover.hovered
              description: "Synchronize with remote repository"
              shortcut: "Enter / s"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }
        }

        // Sync Status Message
        Rectangle {
          width: parent.width
          implicitHeight: statusRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius * 0.6
          color: Color.menu.selectedBackground
          border.width: 1
          border.color: Color.menu.border

          Row {
            id: statusRow
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰁯"
              color: (root.barWidget && root.barWidget.gitSyncStatus === "error") ? Color.error : Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              id: statusText
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(24)
              text: (root.barWidget && root.barWidget.gitSyncMessage)
                ? root.barWidget.gitSyncMessage
                : "Auto-sync runs in background every 1 hour (3-way merge on divergence)."
              color: (root.barWidget && root.barWidget.gitSyncStatus === "error") ? Color.error : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 0.9
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  GitContextMenu {
    id: contextMenu
    bar: root.bar
    z: 1000
    onRollbackRequested: function(hash) {
      if (root.barWidget && typeof root.barWidget.rollbackToCommit === "function") {
        root.barWidget.rollbackToCommit(hash)
      }
      root.forceActiveFocus()
    }
    onRecoverRequested: function(hash) {
      if (root.barWidget && typeof root.barWidget.recoverFromCommit === "function") {
        root.barWidget.recoverFromCommit(hash)
      }
      root.forceActiveFocus()
    }
    onCopyHashRequested: function(hash) {
      Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(hash) + " | wl-copy"])
      root.forceActiveFocus()
    }
    onCloseRequested: {
      root.forceActiveFocus()
    }
  }
}
