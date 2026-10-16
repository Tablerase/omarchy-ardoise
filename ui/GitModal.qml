import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
  readonly property color secondaryText: TodoStore.getReadableSecondary(root.color, Color.muted, root.barForeground)

  property string deviceName: root.barWidget ? String(root.barWidget.deviceName || "") : "omarchy"
  property var snapshots: (root.barWidget && root.barWidget.gitSnapshots) ? root.barWidget.gitSnapshots : []
  property int selectedIndex: 0
  property int activeTab: 0 // 0: Snapshots & Rollback, 1: Sync Settings
  property int syncFocusIndex: 0 // 0: remoteField, 1: autoCreateRemoteBtn, 2: saveRemoteBtn, 3: syncNowBtn
  property string snapshotSection: "snapshots" // "snapshots" | "preview" | "actions"
  property int previewIndex: 0
  property int actionButtonIndex: 0 // 0: rollback, 1: recover
  property alias contextMenu: contextMenu

  // Snapshot search filter state
  property bool searchActive: false
  property string searchQuery: ""

  // Filtered view: live-computed subset of snapshots matching searchQuery
  readonly property var filteredSnapshots: GitSync.filterSnapshots(root.snapshots, root.searchQuery)

  readonly property var selectedSnapshot: (root.filteredSnapshots && root.filteredSnapshots.length > root.selectedIndex)
    ? root.filteredSnapshots[root.selectedIndex]
    : null

  readonly property var previewDiff: (root.barWidget && root.barWidget.inspectedSnapshotDiff) ? root.barWidget.inspectedSnapshotDiff : null
  readonly property var inspectedTasks: (root.previewDiff && Array.isArray(root.previewDiff.tasks))
    ? root.previewDiff.tasks
    : ((root.barWidget && root.barWidget.inspectedSnapshotTasks) ? root.barWidget.inspectedSnapshotTasks : [])
  readonly property var previewTasks: root.inspectedTasks
  readonly property var selectedPreviewTask: (root.inspectedTasks && root.inspectedTasks.length > root.previewIndex)
    ? root.inspectedTasks[root.previewIndex]
    : null

  onSelectedSnapshotChanged: {
    root.previewIndex = 0
    if (root.barWidget && typeof root.barWidget.inspectSnapshot === "function") {
      root.barWidget.inspectSnapshot(root.selectedSnapshot ? root.selectedSnapshot.hash : "")
    }
  }

  signal closeRequested()

  onActiveTabChanged: {
    if (contextMenu) contextMenu.close()
    if (activeTab === 0) {
      root.snapshotSection = "snapshots"
      root.previewIndex = 0
      root.actionButtonIndex = 0
      root.ensureSnapshotVisible()
    } else {
      root.syncFocusIndex = 0
    }
    // Close search when switching away from Tab 0
    root.searchActive = false
    root.searchQuery = ""
    root.forceActiveFocus()
  }

  function open() {
    isOpen = true
    activeTab = 0
    snapshotSection = "snapshots"
    previewIndex = 0
    actionButtonIndex = 0
    selectedIndex = 0
    syncFocusIndex = 0
    searchActive = false
    searchQuery = ""
    if (contextMenu) contextMenu.close()
    if (root.barWidget && typeof root.barWidget.refreshGitHistory === "function") {
      root.barWidget.refreshGitHistory(true)
    }
    if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.inspectSnapshot === "function") {
      root.barWidget.inspectSnapshot(root.selectedSnapshot.hash)
    }
    Qt.callLater(function() { root.forceActiveFocus() })
  }

  function activateSearch() {
    searchActive = true
    Qt.callLater(function() {
      if (typeof searchField !== "undefined" && searchField) {
        searchField.forceActiveFocus()
        searchField.selectAll()
      }
    })
  }

  function closeSearch() {
    searchActive = false
    searchQuery = ""
    if (typeof searchField !== "undefined" && searchField) {
      searchField.text = ""
    }
    selectedIndex = 0
    root.forceActiveFocus()
  }

  function clearSearchText() {
    searchQuery = ""
    if (typeof searchField !== "undefined" && searchField) {
      searchField.text = ""
    }
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
    if (snapshotList && snapshotList.currentItem) {
      var mapped = snapshotList.currentItem.mapToItem(root, snapshotList.currentItem.width - Style.space(270), snapshotList.currentItem.height / 2)
      contextMenu.open(root.selectedSnapshot, mapped.x, mapped.y)
      return
    }
    contextMenu.open(root.selectedSnapshot, (root.width - Style.space(260)) / 2, Math.max(Style.space(60), (root.height - Style.space(200)) / 2))
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
    } else {
      if (root.barWidget && typeof root.barWidget.inspectSnapshot === "function") {
        root.barWidget.inspectSnapshot("")
      }
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
    // Only trigger lazy-load when not filtering (filtered results are a subset of loaded snapshots)
    if (!root.searchActive && root.snapshots && root.selectedIndex >= root.snapshots.length - 5) {
      if (root.barWidget && typeof root.barWidget.loadMoreGitHistory === "function") {
        root.barWidget.loadMoreGitHistory()
      }
    }
  }

  function ensurePreviewVisible() {
    if (inspectedTaskList && root.previewIndex >= 0 && root.previewIndex < inspectedTaskList.count) {
      inspectedTaskList.positionViewAtIndex(root.previewIndex, ListView.Contain)
    }
  }

  // Unconditional mouse event blocker to prevent hover/click bleed-through to items below
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
      // Two-stage escape: close search first if active, then dismiss modal
      if (root.searchActive) {
        root.closeSearch()
      } else {
        root.close()
      }
      return
    }

    // Activate snapshot search via / or Ctrl+F (Tab 0 only)
    if (root.activeTab === 0 && !root.searchActive) {
      if (event.text === "/" || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F)) {
        event.accepted = true
        root.activateSearch()
        return
      }
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
      // Tab / Shift+Tab section transitions in Tab 0: snapshots -> preview -> actions
      if (event.key === Qt.Key_Tab) {
        event.accepted = true
        if (root.snapshotSection === "snapshots") {
          if (root.previewTasks && root.previewTasks.length > 0) {
            root.snapshotSection = "preview"
            root.previewIndex = 0
            root.ensurePreviewVisible()
          } else {
            root.snapshotSection = "actions"
            root.actionButtonIndex = 0
          }
        } else if (root.snapshotSection === "preview") {
          root.snapshotSection = "actions"
          root.actionButtonIndex = 0
        } else {
          if (root.actionButtonIndex === 0) {
            root.actionButtonIndex = 1
          } else {
            root.snapshotSection = "snapshots"
            root.ensureSnapshotVisible()
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
            if (root.previewTasks && root.previewTasks.length > 0) {
              root.snapshotSection = "preview"
              root.previewIndex = Math.min(root.previewIndex, root.previewTasks.length - 1)
              root.ensurePreviewVisible()
            } else {
              root.snapshotSection = "snapshots"
              root.ensureSnapshotVisible()
            }
          }
        } else if (root.snapshotSection === "preview") {
          root.snapshotSection = "snapshots"
          root.ensureSnapshotVisible()
        } else {
          root.snapshotSection = "actions"
          root.actionButtonIndex = 1
        }
        return
      }

      if (root.snapshotSection === "snapshots") {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
          event.accepted = true
          if (root.filteredSnapshots && root.filteredSnapshots.length > 0) {
            if (root.selectedIndex < root.filteredSnapshots.length - 1) {
              root.selectedIndex++
              root.ensureSnapshotVisible()
            } else {
              if (root.previewTasks && root.previewTasks.length > 0) {
                root.snapshotSection = "preview"
                root.previewIndex = 0
                root.ensurePreviewVisible()
              } else {
                root.snapshotSection = "actions"
                root.actionButtonIndex = 0
              }
            }
          }
          return
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          if (root.filteredSnapshots && root.filteredSnapshots.length > 0) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            root.ensureSnapshotVisible()
          }
          return
        }
        // Suppress tab-switch via l when search is active (/ and Ctrl+F handles that UX)
        if ((event.key === Qt.Key_L || event.text === "l") && !root.searchActive) {
          event.accepted = true
          root.activeTab = 1
          return
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier || event.text === "G")) {
          event.accepted = true
          if (root.filteredSnapshots && root.filteredSnapshots.length > 0) {
            root.selectedIndex = root.filteredSnapshots.length - 1
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.key === Qt.Key_G || event.text === "g") {
          event.accepted = true
          if (root.filteredSnapshots && root.filteredSnapshots.length > 0) {
            root.selectedIndex = 0
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.text === "K" || (event.key === Qt.Key_K && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Menu) {
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
      } else if (root.snapshotSection === "preview") {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down || event.text === "j") {
          event.accepted = true
          if (root.previewTasks && root.previewTasks.length > 0) {
            if (root.previewIndex < root.previewTasks.length - 1) {
              root.previewIndex++
              root.ensurePreviewVisible()
            } else {
              root.snapshotSection = "actions"
              root.actionButtonIndex = 0
            }
          }
          return
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          if (root.previewIndex > 0) {
            root.previewIndex--
            root.ensurePreviewVisible()
          } else {
            root.snapshotSection = "snapshots"
            root.ensureSnapshotVisible()
          }
          return
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier || event.text === "G")) {
          event.accepted = true
          if (root.previewTasks && root.previewTasks.length > 0) {
            root.previewIndex = root.previewTasks.length - 1
            root.ensurePreviewVisible()
          }
          return
        }
        if (event.key === Qt.Key_G || event.text === "g") {
          event.accepted = true
          if (root.previewTasks && root.previewTasks.length > 0) {
            root.previewIndex = 0
            root.ensurePreviewVisible()
          }
          return
        }
        if ((event.key === Qt.Key_L || event.text === "l") && !root.searchActive) {
          event.accepted = true
          root.activeTab = 1
          return
        }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left || event.text === "h") {
          event.accepted = true
          root.snapshotSection = "snapshots"
          root.ensureSnapshotVisible()
          return
        }
        if (event.key === Qt.Key_Y || event.text === "y") {
          event.accepted = true
          if (root.selectedPreviewTask && root.selectedPreviewTask.title) {
            root.copyTaskTitle(root.selectedPreviewTask.title)
          }
          return
        }
        if (event.key === Qt.Key_C || event.text === "c") {
          event.accepted = true
          if (root.selectedPreviewTask && (root.selectedPreviewTask.isMissing || root.selectedPreviewTask.diffStatus === "removed") && root.barWidget && typeof root.barWidget.recoverSingleTask === "function") {
            root.barWidget.recoverSingleTask(root.selectedPreviewTask)
          } else if (root.selectedSnapshot && root.barWidget && typeof root.barWidget.recoverFromCommit === "function") {
            root.barWidget.recoverFromCommit(root.selectedSnapshot.hash)
          }
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          event.accepted = true
          if (root.selectedPreviewTask && (root.selectedPreviewTask.isMissing || root.selectedPreviewTask.diffStatus === "removed") && root.barWidget && typeof root.barWidget.recoverSingleTask === "function") {
            root.barWidget.recoverSingleTask(root.selectedPreviewTask)
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
          if (root.previewTasks && root.previewTasks.length > 0) {
            root.snapshotSection = "preview"
            root.previewIndex = root.previewTasks.length - 1
            root.ensurePreviewVisible()
          } else {
            root.snapshotSection = "snapshots"
            root.ensureSnapshotVisible()
          }
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
        root.syncFocusIndex = (root.syncFocusIndex + 1) % 4
        return
      }
      if (event.key === Qt.Key_Backtab) {
        event.accepted = true
        root.syncFocusIndex = (root.syncFocusIndex + 3) % 4
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
        } else if (root.syncFocusIndex === 2) {
          root.syncFocusIndex = 3
        }
        return
      }
      if (event.key === Qt.Key_H || event.key === Qt.Key_Left || event.text === "h") {
        event.accepted = true
        if (root.syncFocusIndex === 3) {
          root.syncFocusIndex = 2
        } else if (root.syncFocusIndex === 2) {
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
          autoCreateRemoteBtn.clicked()
        } else if (root.syncFocusIndex === 2) {
          saveRemoteBtn.clicked()
        } else if (root.syncFocusIndex === 3) {
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
            text: "Git Snapshots \u0026 Undo"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            text: root.searchActive && root.searchQuery.trim().length > 0
              ? ("Device: [" + root.deviceName + "] • " + root.filteredSnapshots.length + " / " + root.snapshots.length + " snapshots")
              : ("Device: [" + root.deviceName + "] • " + root.snapshots.length + " snapshots")
            color: Util.alpha(root.barForeground, 0.7)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Header right-action buttons
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        // Search Button (Tab 0 only)
        PanelActionButton {
          id: searchBtn
          visible: root.activeTab === 0
          size: Style.space(24)
          iconText: "󰍉"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.searchActive ? Color.accent : Color.muted
          hoverColor: Color.accent
          tooltipText: ""
          onClicked: {
            if (root.searchActive) {
              root.closeSearch()
            } else {
              root.activateSearch()
            }
          }

          HoverHandler { id: searchBtnHover }
          ShortcutToolTip {
            visible: searchBtnHover.hovered
            description: "Search snapshots"
            shortcut: "/ or Ctrl+F"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        // Close Button
        PanelActionButton {
          id: closeBtn
          size: Style.space(24)
          iconText: "󰅖"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.secondaryText
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
    }

    // Tabs Header matching HelpModal separator style
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
              color: isActive ? root.barForeground : root.secondaryText
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

        // Snapshot Failure Warning Banner (conditional: only visible when background snapshot fails)
        Rectangle {
          id: snapshotWarningBanner
          visible: Boolean(root.barWidget && root.barWidget.gitSnapshotWarning)
          width: parent.width
          implicitHeight: warningLayout.implicitHeight + Style.space(12)
          radius: Style.cornerRadius * 0.6
          color: Util.alpha(Color.warning, 0.12)
          border.width: 1
          border.color: Util.alpha(Color.warning, 0.45)

          Row {
            id: warningLayout
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰀦"
              color: Color.warning
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 1.2
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(24) - (signingFixBtn.visible ? signingFixBtn.implicitWidth + Style.space(8) : 0) - retryBtn.implicitWidth - Style.space(16)
              text: (root.barWidget && root.barWidget.gitSnapshotWarning) ? root.barWidget.gitSnapshotWarning : ""
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 0.9
              wrapMode: Text.WordWrap
            }

            Button {
              id: signingFixBtn
              visible: Boolean(root.barWidget && root.barWidget.gitSnapshotWarning && root.barWidget.gitSnapshotWarning.indexOf("signing") !== -1)
              anchors.verticalCenter: parent.verticalCenter
              text: "Disable Signing"
              fontSize: Style.font.caption * 0.85
              bordered: true
              onClicked: {
                if (root.barWidget && typeof root.barWidget.disableLocalSigning === "function") {
                  root.barWidget.disableLocalSigning()
                }
              }
            }

            PanelActionButton {
              id: retryBtn
              anchors.verticalCenter: parent.verticalCenter
              size: Style.space(24)
              iconText: "󰑐"
              fontSize: Style.font.caption
              tooltipText: "Retry snapshot"
              onClicked: {
                if (root.barWidget && typeof root.barWidget.triggerAutoCommit === "function") {
                  root.barWidget.triggerAutoCommit("Manual retry snapshot")
                }
              }
            }
          }
        }

        // Snapshot Search Row (expandable via / or Ctrl+F or searchBtn)
        Row {
          id: snapshotSearchRow
          visible: root.searchActive
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: searchField
            width: parent.width - closeSnapshotSearchBtn.implicitWidth - Style.space(6)
            placeholderText: "Search snapshots by message, device, hash, author..."
            font.pixelSize: Style.font.caption
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            text: root.searchQuery
            color: root.barForeground
            onTextChanged: {
              root.searchQuery = text
              root.selectedIndex = 0
            }
            background: BorderSurface {
              color: searchField.activeFocus
                ? Util.alpha(Color.accent, 0.08)
                : Style.controlFill(false, searchField.hovered, root.barForeground, Color.accent)
              borderSpec: searchField.activeFocus
                ? Border.flat(Color.accent, 2)
                : (searchField.hovered
                    ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent)
                    : Border.controlSpec("normal", root.barForeground, Color.accent))
              radius: Style.cornerRadius
            }

            Keys.onPressed: function(event) {
              if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                event.accepted = true
                searchField.selectAll()
              }
            }

            Keys.onEscapePressed: function(event) {
              event.accepted = true
              if (searchField.text.length > 0) {
                searchField.text = ""
                root.searchQuery = ""
                root.selectedIndex = 0
              } else {
                root.closeSearch()
              }
            }

            Keys.onReturnPressed: function(event) {
              event.accepted = true
              if (root.filteredSnapshots.length > 0) {
                root.snapshotSection = "snapshots"
                root.selectedIndex = 0
                root.forceActiveFocus()
                root.ensureSnapshotVisible()
              }
            }
            Keys.onEnterPressed: function(event) {
              event.accepted = true
              if (root.filteredSnapshots.length > 0) {
                root.snapshotSection = "snapshots"
                root.selectedIndex = 0
                root.forceActiveFocus()
                root.ensureSnapshotVisible()
              }
            }

            Keys.onDownPressed: function(event) {
              event.accepted = true
              if (root.filteredSnapshots.length > 0) {
                root.snapshotSection = "snapshots"
                root.selectedIndex = 0
                root.forceActiveFocus()
                root.ensureSnapshotVisible()
              }
            }
          }

          PanelActionButton {
            id: closeSnapshotSearchBtn
            size: Style.space(24)
            iconText: "󰅖"
            fontSize: Style.font.caption
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            foreground: root.secondaryText
            hoverColor: Color.accent
            tooltipText: ""
            onClicked: root.closeSearch()

            HoverHandler { id: closeSearchBtnHover }
            ShortcutToolTip {
              visible: closeSearchBtnHover.hovered
              description: "Close search"
              shortcut: "Esc"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }
        }

        // Snapshot Virtualized List
        Item {
          id: listContainer
          width: parent.width
          height: parent.height - actionRow.implicitHeight - (snapshotSearchRow.visible ? snapshotSearchRow.implicitHeight + Style.space(6) : 0) - (previewBox.visible ? previewBox.height + Style.space(6) : 0) - (snapshotWarningBanner.visible ? snapshotWarningBanner.implicitHeight + Style.space(6) : 0) - Style.space(10)

          ListView {
            id: snapshotList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(4)
            model: root.filteredSnapshots
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
                : (itemHover.containsMouse ? Color.menu.selectedBackground : "transparent")
              border.color: isSelected ? Color.accent : (itemHover.containsMouse ? Color.menu.border : "transparent")
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
                    var pos = itemHover.mapToItem(root, mouse.x, mouse.y)
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
                  color: snapshotItem.isLocalDevice ? Util.alpha(Color.accent, 0.25) : Util.alpha(root.secondaryText, 0.2)

                  Text {
                    id: devLabel
                    anchors.centerIn: parent
                    text: (snapshotItem.modelData && snapshotItem.modelData.deviceName) ? snapshotItem.modelData.deviceName : "unknown"
                    color: snapshotItem.isLocalDevice ? Color.accent : root.secondaryText
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
                      color: root.secondaryText
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption * 0.8
                    }
                    Text {
                      text: "• " + ((snapshotItem.modelData && snapshotItem.modelData.timestamp) ? GitSync.formatRelativeTime(snapshotItem.modelData.timestamp) : "")
                      color: root.secondaryText
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
                  color: Util.alpha(root.secondaryText, 0.15)

                  Text {
                    id: countText
                    anchors.centerIn: parent
                    text: (snapshotItem.modelData && snapshotItem.modelData.pendingCount !== undefined ? snapshotItem.modelData.pendingCount : "") + " pending"
                    color: root.secondaryText
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
                  foreground: root.secondaryText
                  hoverColor: Color.accent
                  tooltipText: "Snapshot options"
                  onClicked: {
                    root.selectedIndex = snapshotItem.index
                    root.snapshotSection = "snapshots"
                    var pos = moreBtn.mapToItem(root, moreBtn.width / 2, moreBtn.height)
                    contextMenu.open(snapshotItem.modelData, pos.x - Style.space(200), pos.y)
                  }
                }
              }
            }
          }

          // Empty state: no snapshots at all
          Text {
            anchors.centerIn: parent
            visible: !root.snapshots || root.snapshots.length === 0
            text: "No git snapshots found. Add or edit tasks to create snapshots."
            color: root.secondaryText
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          // Empty search results state
          Column {
            anchors.centerIn: parent
            visible: root.snapshots && root.snapshots.length > 0 && root.searchActive && root.filteredSnapshots.length === 0
            spacing: Style.space(4)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰍉 No snapshots matching \"" + root.searchQuery + "\""
              color: root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Press Esc to clear or adjust search"
              color: Util.alpha(root.secondaryText, 0.75)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 0.85
            }
          }
        }

        // Local Snapshot Task Preview Box & Diff Visualisation
        Rectangle {
          id: previewBox
          visible: root.isOpen && Boolean(root.selectedSnapshot)
          width: parent.width
          height: visible ? Style.space(120) : 0
          radius: Style.cornerRadius
          color: Util.alpha(Color.menu.background, 0.95)
          border.color: (root.snapshotSection === "preview") ? Color.accent : Util.alpha(root.secondaryText, 0.4)
          border.width: (root.snapshotSection === "preview") ? 1.5 : 1
          clip: true

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(4)

            // Header
            Row {
              id: previewHeader
              width: parent.width
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰈙"
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Snapshot Tasks (" + (root.previewTasks ? root.previewTasks.length : 0) + ")"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption * 0.95
                font.bold: true
              }

              // Diff Summary Pills
              Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: Boolean(root.previewDiff && root.previewDiff.hasChanges)
                spacing: Style.space(4)

                Rectangle {
                  visible: Boolean(root.previewDiff && root.previewDiff.summary && root.previewDiff.summary.added > 0)
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: addDiffText.implicitWidth + Style.space(6)
                  implicitHeight: addDiffText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius * 0.3
                  color: Util.alpha(Color.accent, 0.2)

                  Text {
                    id: addDiffText
                    anchors.centerIn: parent
                    text: "+" + (root.previewDiff && root.previewDiff.summary ? root.previewDiff.summary.added : 0) + " added"
                    color: Color.accent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.75
                    font.bold: true
                  }
                }

                Rectangle {
                  visible: Boolean(root.previewDiff && root.previewDiff.summary && root.previewDiff.summary.removed > 0)
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: remDiffText.implicitWidth + Style.space(6)
                  implicitHeight: remDiffText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius * 0.3
                  color: Util.alpha(Color.urgent, 0.2)

                  Text {
                    id: remDiffText
                    anchors.centerIn: parent
                    text: "-" + (root.previewDiff && root.previewDiff.summary ? root.previewDiff.summary.removed : 0) + " deleted"
                    color: Color.urgent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.75
                    font.bold: true
                  }
                }

                Rectangle {
                  visible: Boolean(root.previewDiff && root.previewDiff.summary && root.previewDiff.summary.completed > 0)
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: compDiffText.implicitWidth + Style.space(6)
                  implicitHeight: compDiffText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius * 0.3
                  color: Util.alpha(root.secondaryText, 0.2)

                  Text {
                    id: compDiffText
                    anchors.centerIn: parent
                    text: (root.previewDiff && root.previewDiff.summary ? root.previewDiff.summary.completed : 0) + " done"
                    color: root.secondaryText
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.75
                  }
                }

                Rectangle {
                  visible: Boolean(root.previewDiff && root.previewDiff.summary && root.previewDiff.summary.modified > 0)
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: modDiffText.implicitWidth + Style.space(6)
                  implicitHeight: modDiffText.implicitHeight + Style.space(2)
                  radius: Style.cornerRadius * 0.3
                  color: Util.alpha(Color.accent, 0.15)

                  Text {
                    id: modDiffText
                    anchors.centerIn: parent
                    text: (root.previewDiff && root.previewDiff.summary ? root.previewDiff.summary.modified : 0) + " changed"
                    color: Color.accent
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.75
                  }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Boolean(root.selectedSnapshot && root.selectedSnapshot.shortHash)
                text: "• " + (root.selectedSnapshot ? root.selectedSnapshot.shortHash : "")
                color: root.secondaryText
                font.family: "monospace"
                font.pixelSize: Style.font.caption * 0.8
              }

              // Navigation hint
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: (root.snapshotSection === "preview")
                text: "• j/k nav  c recover  y copy"
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption * 0.75
              }
            }

            // Task List
            ListView {
              id: inspectedTaskList
              width: parent.width
              height: parent.height - previewHeader.implicitHeight - Style.space(4)
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              spacing: Style.space(2)
              model: root.inspectedTasks
              currentIndex: root.previewIndex

              ScrollBar.vertical: ScrollBar {
                policy: inspectedTaskList.contentHeight > inspectedTaskList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
              }

              delegate: Rectangle {
                id: taskItemDelegate
                required property var modelData
                required property int index

                readonly property bool isCurrent: (root.snapshotSection === "preview") && (root.previewIndex === index)
                readonly property bool isMissingFromStore: Boolean(modelData.isMissing)
                readonly property string status: modelData.diffStatus || "unchanged"

                width: inspectedTaskList.width
                implicitHeight: taskRow.implicitHeight + Style.space(4)
                radius: Style.cornerRadius * 0.4
                color: isCurrent
                  ? Util.alpha(Color.accent, 0.16)
                  : (taskDelegateHover.containsMouse ? Util.alpha(Color.menu.selectedBackground, 0.7) : "transparent")
                border.color: isCurrent ? Color.accent : "transparent"
                border.width: 1

                MouseArea {
                  id: taskDelegateHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    root.snapshotSection = "preview"
                    root.previewIndex = taskItemDelegate.index
                    root.forceActiveFocus()
                  }
                }

                Row {
                  id: taskRow
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(6)

                  // Status Icon
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: taskItemDelegate.status === "removed"
                      ? "󰍴"
                      : (taskItemDelegate.status === "added"
                          ? "󰐕"
                          : (taskItemDelegate.modelData.done ? "󰄲" : "󰄱"))
                    color: taskItemDelegate.status === "removed"
                      ? Color.urgent
                      : (taskItemDelegate.status === "added"
                          ? Color.accent
                          : (taskItemDelegate.modelData.done
                              ? root.secondaryText
                              : (taskItemDelegate.isMissingFromStore ? Color.accent : root.barForeground)))
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.85
                    font.bold: taskItemDelegate.status === "removed" || taskItemDelegate.status === "added"
                  }

                  // Diff Status Badge
                  Rectangle {
                    id: diffBadge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: taskItemDelegate.status !== "unchanged"
                    implicitWidth: diffBadgeText.implicitWidth + Style.space(6)
                    implicitHeight: diffBadgeText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius * 0.3
                    color: taskItemDelegate.status === "removed"
                      ? Util.alpha(Color.urgent, 0.22)
                      : (taskItemDelegate.status === "added"
                          ? Util.alpha(Color.accent, 0.22)
                          : Util.alpha(root.secondaryText, 0.18))

                    Text {
                      id: diffBadgeText
                      anchors.centerIn: parent
                      text: taskItemDelegate.status === "removed"
                        ? "- Deleted"
                        : (taskItemDelegate.status === "added"
                            ? "+ Added"
                            : (taskItemDelegate.status === "completed"
                                ? "Done"
                                : (taskItemDelegate.status === "reopened"
                                    ? "Reopened"
                                    : "Modified")))
                      color: taskItemDelegate.status === "removed"
                        ? Color.urgent
                        : (taskItemDelegate.status === "added" ? Color.accent : root.secondaryText)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.72
                      font.bold: taskItemDelegate.status === "removed" || taskItemDelegate.status === "added"
                    }
                  }

                  // Profile tag badge
                  Rectangle {
                    id: profBadge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Boolean(taskItemDelegate.modelData.profile && taskItemDelegate.modelData.profile !== "personal")
                    implicitWidth: profText.implicitWidth + Style.space(6)
                    implicitHeight: profText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius * 0.3
                    color: Util.alpha(root.secondaryText, 0.18)

                    Text {
                      id: profText
                      anchors.centerIn: parent
                      text: taskItemDelegate.modelData.profile || ""
                      color: root.secondaryText
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.72
                    }
                  }

                  // Task Title
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Style.space(40), parent.width - (diffBadge.visible ? diffBadge.implicitWidth + Style.space(6) : 0) - (profBadge.visible ? profBadge.implicitWidth + Style.space(6) : 0) - (recoverBadge.visible ? recoverBadge.implicitWidth + Style.space(6) : 0) - Style.space(24))
                    text: taskItemDelegate.modelData.title || ""
                    color: taskItemDelegate.status === "removed"
                      ? Color.urgent
                      : (taskItemDelegate.modelData.done ? root.secondaryText : root.barForeground)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.85
                    font.strikeout: taskItemDelegate.status === "removed"
                    elide: Text.ElideRight
                  }

                  // Recoverable Badge
                  Rectangle {
                    id: recoverBadge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: taskItemDelegate.isMissingFromStore || taskItemDelegate.status === "removed"
                    implicitWidth: recText.implicitWidth + Style.space(6)
                    implicitHeight: recText.implicitHeight + Style.space(2)
                    radius: Style.cornerRadius * 0.3
                    color: Util.alpha(Color.accent, 0.2)

                    Text {
                      id: recText
                      anchors.centerIn: parent
                      text: "+ Recoverable"
                      color: Color.accent
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.72
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.barWidget && typeof root.barWidget.recoverSingleTask === "function") {
                          root.barWidget.recoverSingleTask(taskItemDelegate.modelData)
                          root.forceActiveFocus()
                        }
                      }
                    }
                  }
                }
              }
            }

            // Empty state for snapshot with 0 tasks
            Item {
              visible: root.previewTasks.length === 0
              width: parent.width
              height: parent.height - previewHeader.implicitHeight - Style.space(4)

              Text {
                anchors.centerIn: parent
                text: "No active tasks recorded in this snapshot"
                color: root.secondaryText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption * 0.85
              }
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
          text: "Remote Repository (GitHub, GitLab, or any Git remote)"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: remoteField
          width: parent.width
          placeholderText: "git@github.com:... or git@gitlab.com:... or custom Git URL"
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
            id: autoCreateRemoteBtn
            text: "󰊤 Create GitHub Repo"
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 1) && (root.syncFocusIndex === 1)
            onClicked: {
              if (root.barWidget && typeof root.barWidget.autoSetupGitRemote === "function") {
                root.barWidget.autoSetupGitRemote(remoteField.text)
              }
              root.forceActiveFocus()
            }

            HoverHandler { id: autoCreateHover }
            ShortcutToolTip {
              visible: autoCreateHover.hovered
              description: "Optional 1-click private repo setup via gh CLI; or enter any Git URL above"
              shortcut: "Enter"
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }
          }

          Button {
            id: saveRemoteBtn
            text: "Save Remote"
            fontSize: Style.font.caption
            bordered: true
            hasCursor: (root.activeTab === 1) && (root.syncFocusIndex === 2)
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
            hasCursor: (root.activeTab === 1) && (root.syncFocusIndex === 3)
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
          border.color: Util.alpha(root.secondaryText, 0.3)

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
              color: (root.barWidget && root.barWidget.gitSyncStatus === "error") ? Color.error : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 0.9
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  property string pendingCopyHash: ""
  property string pendingCopyTitle: ""

  Process {
    id: copyHashProc
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      copyHashProc.write(root.pendingCopyHash)
      copyHashProc.stdinEnabled = false
    }
    onExited: function(code) {
      if (code === 0 && root.pendingCopyHash) {
        Quickshell.execDetached(["notify-send", "-a", "Ardoise", "-i", "edit-copy", "Commit hash copied", root.pendingCopyHash.slice(0, 7)])
      }
    }
  }

  function copyHash(hash) {
    if (!hash) return
    Quickshell.clipboardText = String(hash)
    root.pendingCopyHash = String(hash)
    if (copyHashProc.running) {
      copyHashProc.running = false
    }
    copyHashProc.stdinEnabled = true
    copyHashProc.running = true
  }

  Process {
    id: copyTitleProc
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      copyTitleProc.write(root.pendingCopyTitle)
      copyTitleProc.stdinEnabled = false
    }
    onExited: function(code) {
      if (code === 0 && root.pendingCopyTitle) {
        Quickshell.execDetached(["notify-send", "-a", "Ardoise", "-i", "edit-copy", "Task title copied", root.pendingCopyTitle.substring(0, 40)])
      }
    }
  }

  function copyTaskTitle(title) {
    if (!title) return
    Quickshell.clipboardText = String(title)
    root.pendingCopyTitle = String(title)
    if (copyTitleProc.running) {
      copyTitleProc.running = false
    }
    copyTitleProc.stdinEnabled = true
    copyTitleProc.running = true
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
      root.copyHash(hash)
      root.forceActiveFocus()
    }
    onCloseRequested: {
      root.forceActiveFocus()
    }
  }
}
