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

  readonly property var selectedSnapshot: (root.snapshots && root.snapshots.length > root.selectedIndex)
    ? root.snapshots[root.selectedIndex]
    : null

  signal closeRequested()

  function open() {
    isOpen = true
    activeTab = 0
    selectedIndex = 0
    if (root.barWidget && typeof root.barWidget.refreshGitHistory === "function") {
      root.barWidget.refreshGitHistory()
    }
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function close() {
    isOpen = false
    root.closeRequested()
  }

  function toggle() {
    if (isOpen) close()
    else open()
  }

  onIsOpenChanged: {
    if (isOpen) {
      if (root.barWidget && typeof root.barWidget.refreshGitHistory === "function") {
        root.barWidget.refreshGitHistory()
      }
      Qt.callLater(function() { root.forceActiveFocus() })
    }
  }

  anchors.fill: parent
  visible: isOpen
  z: 999
  color: Util.alpha(Color.popups.background, 0.96)
  radius: Style.cornerRadius
  focus: true

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

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      root.close()
      return
    }

    // Tab switching with 1 and 2
    if (event.key === Qt.Key_1) {
      event.accepted = true
      root.activeTab = 0
      return
    }
    if (event.key === Qt.Key_2) {
      event.accepted = true
      root.activeTab = 1
      return
    }

    if (root.activeTab === 0) {
      if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
        event.accepted = true
        if (root.snapshots && root.snapshots.length > 0) {
          root.selectedIndex = Math.min(root.snapshots.length - 1, root.selectedIndex + 1)
        }
        return
      }
      if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
        event.accepted = true
        if (root.snapshots && root.snapshots.length > 0) {
          root.selectedIndex = Math.max(0, root.selectedIndex - 1)
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
    }
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
            color: Color.muted
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

        // Snapshot Flickable List
        Flickable {
          id: snapshotFlickable
          width: parent.width
          height: parent.height - actionRow.implicitHeight - Style.space(10)
          contentWidth: width
          contentHeight: snapshotCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ScrollBar.vertical: ScrollBar {
            policy: snapshotCol.implicitHeight > snapshotFlickable.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          }

          Column {
            id: snapshotCol
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.snapshots

              Rectangle {
                id: snapshotItem
                required property var modelData
                required property int index

                readonly property bool isSelected: root.selectedIndex === index
                readonly property bool isLocalDevice: String(modelData.deviceName || "").toLowerCase() === String(root.deviceName).toLowerCase()

                width: snapshotCol.width
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
                  hoverEnabled: true
                  onClicked: {
                    root.selectedIndex = snapshotItem.index
                    root.forceActiveFocus()
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
                      text: snapshotItem.modelData.deviceName || "unknown"
                      color: snapshotItem.isLocalDevice ? Color.accent : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      font.bold: true
                    }
                  }

                  // Message and relative date
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - devLabel.parent.width - countBadge.width - Style.space(24)
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: snapshotItem.modelData.cleanMessage || snapshotItem.modelData.message || ""
                      color: root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Row {
                      spacing: Style.space(6)
                      Text {
                        text: snapshotItem.modelData.shortHash
                        color: Color.muted
                        font.family: Style.font.monospace
                        font.pixelSize: Style.font.caption * 0.8
                      }
                      Text {
                        text: "• " + GitSync.formatRelativeTime(snapshotItem.modelData.timestamp)
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
                    visible: snapshotItem.modelData.pendingCount !== undefined
                    implicitWidth: countText.implicitWidth + Style.space(6)
                    implicitHeight: countText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius * 0.4
                    color: Util.alpha(Color.muted, 0.15)

                    Text {
                      id: countText
                      anchors.centerIn: parent
                      text: (snapshotItem.modelData.pendingCount !== undefined ? snapshotItem.modelData.pendingCount : "") + " pending"
                      color: Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.8
                    }
                  }
                }
              }
            }

            // Empty state
            Text {
              visible: !root.snapshots || root.snapshots.length === 0
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "No git snapshots found. Add or edit tasks to create snapshots."
              color: Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              topPadding: Style.space(20)
            }
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
            color: Style.controlFill(remoteField.activeFocus, remoteField.hovered, root.barForeground, Color.accent)
            borderSpec: Border.controlSpec(
              remoteField.activeFocus ? "focus" : (remoteField.hovered ? "hover-cursor" : "normal"),
              root.barForeground,
              Color.accent
            )
            radius: Style.cornerRadius
          }

          Keys.onEscapePressed: function(event) {
            event.accepted = true
            remoteField.focus = false
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
            onClicked: {
              if (root.barWidget && typeof root.barWidget.setRemoteUrl === "function") {
                root.barWidget.setRemoteUrl(remoteField.text)
              }
            }
          }

          Button {
            id: syncNowBtn
            text: "Sync Now"
            fontSize: Style.font.caption
            bordered: true
            onClicked: {
              if (root.barWidget && typeof root.barWidget.syncWithRemote === "function") {
                root.barWidget.syncWithRemote()
              }
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
}
