import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore

Item {
  id: root

  property var bar: null
  property var barWidget: null
  property var store: barWidget ? barWidget.store : TodoStore.defaultStore()
  readonly property var todos: store ? (store.todos || []) : []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  readonly property var profiles: store ? (store.profiles || ["personal", "work"]) : ["personal", "work"]
  readonly property var visibleProfiles: TodoStore.getSortedProfiles(root.store, true, root.currentFilter)

  readonly property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color cardBackground: Color.popups.background

  property string currentFilter: "all"
  property var expandedTaskId: -1
  property bool addingProfile: false
  property string shortcutState: "active"
  property string detectedShortcut: "SUPER + SHIFT + T"
  property bool shortcutRegistered: false
  property string moduleName: "tablerase.ardoise"
  property var descArea: null

  onVisibleChanged: {
    if (!visible) {
      savePendingNotes()
      expandedTaskId = -1
    }
  }

  readonly property var filteredTodos: TodoStore.getFilteredTodos(root.store, root.currentFilter)
  readonly property int filteredPendingCount: TodoStore.getPendingCount(root.store, root.currentFilter)
  readonly property var reminderPresets: TodoStore.getReminderPresets()
  readonly property bool activeFocusBlocked: Boolean((newTodoField && newTodoField.activeFocus) || (descArea && descArea.editorActiveFocus) || addingProfile)

  signal closeRequested()
  signal shortcutClicked()
  signal switchPanelRequested(int direction)

  function savePendingNotes() {
    if (root.descArea && typeof root.descArea.save === "function") {
      root.descArea.save()
    }
  }

  function addTodo(title, description, profile, reminder) {
    savePendingNotes()
    if (barWidget) {
      barWidget.addTodo(title, description, profile, reminder)
    } else {
      root.store = TodoStore.addTodo(root.store, title, description, profile, reminder)
    }
  }

  function toggleTodo(id) {
    savePendingNotes()
    if (barWidget) {
      barWidget.toggleTodo(id)
    } else {
      root.store = TodoStore.toggleTodo(root.store, id)
    }
  }

  function removeTodo(id) {
    savePendingNotes()
    if (barWidget) {
      barWidget.removeTodo(id)
    } else {
      root.store = TodoStore.removeTodo(root.store, id)
    }
  }

  function updateTodo(id, fields) {
    if (barWidget) {
      barWidget.updateTodo(id, fields)
    } else {
      root.store = TodoStore.updateTodo(root.store, id, fields)
    }
  }

  function clearCompleted(profile) {
    savePendingNotes()
    if (barWidget) {
      barWidget.clearCompleted(profile)
    } else {
      var res = TodoStore.archiveCompleted(root.store, profile, "")
      root.store = res.updatedStore
    }
  }

  function addProfile(name) {
    savePendingNotes()
    if (barWidget) {
      barWidget.addProfile(name)
    } else {
      root.store = TodoStore.addProfile(root.store, name)
    }
  }

  function openArchive() {
    savePendingNotes()
    var p = barWidget ? barWidget.archiveFilePath : Quickshell.env("HOME") + "/.config/omarchy/todos-archive.json"
    if (bar) bar.run("omarchy-launch-editor " + p)
    root.closeRequested()
  }

  function openEditor() {
    savePendingNotes()
    var p = barWidget ? barWidget.todoFilePath : Quickshell.env("HOME") + "/.config/omarchy/todos.json"
    if (bar) bar.run("omarchy-launch-editor " + p)
    root.closeRequested()
  }

  function openQuickAdd() {
    savePendingNotes()
    root.closeRequested()
    if (bar && bar.shell) {
      bar.shell.summon(root.moduleName, "{}")
    }
  }

  function ensureProfileVisible(profileName) {
    if (typeof profileFlickable === "undefined" || !profileFlickable) return
    if (profileName === "all") {
      profileFlickable.contentX = 0
      return
    }
    var idx = root.visibleProfiles.indexOf(profileName)
    if (idx !== -1 && typeof profileRepeater !== "undefined" && profileRepeater && profileRepeater.count > idx) {
      var item = profileRepeater.itemAt(idx)
      if (item) {
        var itemLeft = item.x
        var itemRight = item.x + item.width
        if (itemLeft < profileFlickable.contentX) {
          profileFlickable.contentX = Math.max(0, itemLeft - Style.space(8))
        } else if (itemRight > profileFlickable.contentX + profileFlickable.width) {
          var maxContentX = Math.max(0, profileFlickable.contentWidth - profileFlickable.width)
          profileFlickable.contentX = Math.min(maxContentX, itemRight - profileFlickable.width + Style.space(8))
        }
      }
    }
  }

  onCurrentFilterChanged: {
    savePendingNotes()
    Qt.callLater(function() { root.ensureProfileVisible(root.currentFilter) })
  }

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(8)

    // Header
    Item {
      width: parent.width
      implicitHeight: Math.max(headerLeft.implicitHeight, shortcutBtn.implicitHeight)

      Row {
        id: headerLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          text: "Ardoise"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.filteredPendingCount + " pending"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // Compact shortcut info/copy button with bottom-right status indicator
      PanelActionButton {
        id: shortcutBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(26)
        iconText: "󰌌"
        fontSize: Style.font.subtitle
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: root.shortcutRegistered ? root.barForeground : Color.muted
        tooltipText: root.shortcutRegistered
          ? ("Shortcut active: " + root.detectedShortcut + " (click to copy & edit config)")
          : ("Set shortcut: " + root.detectedShortcut + " (click to copy & edit config)")
        onClicked: root.shortcutClicked()

        Rectangle {
          id: indicatorBadge
          width: Style.space(10)
          height: Style.space(10)
          radius: width / 2
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.bottomMargin: Style.space(1)
          anchors.rightMargin: Style.space(1)
          color: root.shortcutRegistered ? Color.accent
            : (root.shortcutState === "commented" ? "#e67e22" : Color.urgent)
          border.color: Color.menu.background
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: root.shortcutRegistered ? "✓" : "✕"
            color: "white"
            font.pixelSize: Style.space(6.5)
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: shortcutBtn.clicked()
          }
        }
      }
    }

    // Profile Filter Section with thin horizontal scrollbar & wheel scrolling
    Item {
      id: profileFilterSection
      width: parent.width
      implicitHeight: Style.space(30)

      WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          profileFlickable.scrollHorizontal(event.angleDelta.y, event.angleDelta.x)
        }
      }

      Flickable {
        id: profileFlickable
        anchors.left: parent.left
        anchors.right: addProfileBtn.left
        anchors.rightMargin: Style.space(6)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        contentWidth: profileFilterRow.implicitWidth
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function scrollHorizontal(deltaY, deltaX) {
          var delta = deltaY !== 0 ? deltaY : deltaX
          if (delta === 0) return
          var step = (delta > 0 ? Style.space(60) : -Style.space(60))
          var maxContentX = Math.max(0, contentWidth - width)
          contentX = Math.max(0, Math.min(maxContentX, contentX - step))
        }

        ScrollBar.horizontal: ScrollBar {
          id: profileScrollBar
          policy: profileFlickable.contentWidth > profileFlickable.width ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          interactive: true
          padding: 0
          implicitHeight: Style.space(2)

          contentItem: Rectangle {
            implicitHeight: Style.space(2)
            radius: Style.space(1)
            color: profileScrollBar.pressed ? Color.accent : (profileScrollBar.hovered ? Color.accent : Color.muted)
            opacity: profileScrollBar.active ? 0.9 : 0.4
          }

          background: Rectangle {
            implicitHeight: Style.space(2)
            radius: Style.space(1)
            color: Color.menu.selectedBackground
            opacity: 0.25
          }
        }

        Row {
          id: profileFilterRow
          spacing: Style.space(4)

          // "All" filter pill
          Rectangle {
            id: allPill
            implicitWidth: allPillRow.implicitWidth + Style.space(10)
            implicitHeight: Style.space(24)
            radius: implicitHeight / 2
            color: root.currentFilter === "all" ? Color.accent : Color.menu.selectedBackground
            border.color: root.currentFilter === "all" ? Color.accent : Color.menu.border
            border.width: 1

            Row {
              id: allPillRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "All"
                color: root.currentFilter === "all" ? "white" : root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: root.currentFilter === "all"
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.pendingCount)
                color: root.currentFilter === "all" ? "white" : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.space(9)
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.currentFilter = "all"
              onWheel: function(wheel) {
                profileFlickable.scrollHorizontal(wheel.angleDelta.y, wheel.angleDelta.x)
              }
            }
          }

          // Individual active profile pills
          Repeater {
            id: profileRepeater
            model: root.visibleProfiles

            Rectangle {
              id: profPill
              required property string modelData
              readonly property int count: TodoStore.getPendingCount(root.store, modelData)
              implicitWidth: profPillRow.implicitWidth + Style.space(10)
              implicitHeight: Style.space(24)
              radius: implicitHeight / 2
              color: root.currentFilter === modelData ? Color.accent : Color.menu.selectedBackground
              border.color: root.currentFilter === modelData ? Color.accent : Color.menu.border
              border.width: 1

              Row {
                id: profPillRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: TodoStore.getProfileGlyph(profPill.modelData)
                  color: root.currentFilter === profPill.modelData ? "white" : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: profPillText
                  anchors.verticalCenter: parent.verticalCenter
                  text: profPill.modelData
                  color: root.currentFilter === profPill.modelData ? "white" : root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: root.currentFilter === profPill.modelData
                  width: Math.min(implicitWidth, Style.space(80))
                  elide: Text.ElideRight
                }

                Text {
                  visible: profPill.count > 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(profPill.count)
                  color: root.currentFilter === profPill.modelData ? "white" : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.space(9)
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentFilter = profPill.modelData
                onWheel: function(wheel) {
                  profileFlickable.scrollHorizontal(wheel.angleDelta.y, wheel.angleDelta.x)
                }
              }

              HoverHandler {
                id: profPillHover
              }

              PanelToolTip {
                visible: profPillHover.hovered && profPillText.truncated
                text: profPill.modelData
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              }
            }
          }
        }
      }

      // Soft blur/fade edge on the left
      Rectangle {
        id: leftFadeEdge
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(24)
        visible: opacity > 0
        opacity: (profileFlickable.contentWidth > profileFlickable.width && profileFlickable.contentX > 4) ? 1.0 : 0.0

        Behavior on opacity {
          NumberAnimation { duration: 150 }
        }

        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: root.cardBackground }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      // Soft blur/fade edge on the right
      Rectangle {
        id: rightFadeEdge
        anchors.right: addProfileBtn.left
        anchors.rightMargin: Style.space(6)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(32)
        visible: opacity > 0
        opacity: (profileFlickable.contentWidth > profileFlickable.width && profileFlickable.contentX < (profileFlickable.contentWidth - profileFlickable.width - 2)) ? 1.0 : 0.0

        Behavior on opacity {
          NumberAnimation { duration: 150 }
        }

        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(root.cardBackground.r, root.cardBackground.g, root.cardBackground.b, 0.6) }
          GradientStop { position: 1.0; color: root.cardBackground }
        }
      }

      // Pinned New Profile button
      PanelActionButton {
        id: addProfileBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(24)
        iconText: root.addingProfile ? "󰅖" : "󰐕"
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: Color.muted
        hoverColor: Color.accent
        tooltipText: root.addingProfile ? "Cancel" : "Add profile / tag"
        onClicked: {
          root.addingProfile = !root.addingProfile
          if (root.addingProfile) {
            Qt.callLater(function() { newProfileInput.forceActiveFocus() })
          }
        }
      }
    }

    // Inline Add Profile Input
    Row {
      width: parent.width
      visible: root.addingProfile
      spacing: Style.space(6)

      TextField {
        id: newProfileInput
        width: parent.width - confirmProfileBtn.implicitWidth - Style.space(6)
        placeholderText: "Profile name (e.g. project1)..."
        font.pixelSize: Style.font.caption
        onAccepted: {
          if (text.trim() !== "") {
            var p = TodoStore.cleanProfileName(text)
            root.addProfile(p)
            root.currentFilter = p
            text = ""
            root.addingProfile = false
          }
        }
        Keys.onEscapePressed: {
          text = ""
          root.addingProfile = false
        }
      }

      PanelActionButton {
        id: confirmProfileBtn
        size: Style.space(26)
        iconText: "󰄲"
        fontSize: Style.font.icon
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: Color.accent
        hoverColor: Color.accent
        tooltipText: "Create profile"
        onClicked: {
          if (newProfileInput.text.trim() !== "") {
            var p = TodoStore.cleanProfileName(newProfileInput.text)
            root.addProfile(p)
            root.currentFilter = p
            newProfileInput.text = ""
            root.addingProfile = false
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // Input row
    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: newTodoField
        width: parent.width - addBtn.implicitWidth - Style.space(6)
        placeholderText: root.currentFilter === "all"
          ? "Add new task (e.g. #work Fix bug)..."
          : ("Add task to #" + (root.currentFilter.length > 15 ? (root.currentFilter.slice(0, 13) + "…") : root.currentFilter) + "...")
        font.pixelSize: Style.font.caption
        onAccepted: {
          if (text.trim() !== "") {
            var prof = (root.currentFilter !== "all") ? root.currentFilter : null
            root.addTodo(text, "", prof, null)
            text = ""
          }
        }
      }

      PanelActionButton {
        id: addBtn
        size: Style.space(26)
        iconText: "󰐕"
        fontSize: Style.font.icon
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: Color.accent
        hoverColor: Color.accent
        tooltipText: "Add task (Enter)"
        onClicked: {
          if (newTodoField.text.trim() !== "") {
            var prof = (root.currentFilter !== "all") ? root.currentFilter : null
            root.addTodo(newTodoField.text, "", prof, null)
            newTodoField.text = ""
          }
        }
      }
    }

    // Empty state
    Text {
      visible: root.filteredTodos.length === 0
      text: root.currentFilter === "all"
        ? "No tasks yet. Type a task above and press Enter!"
        : ("No tasks in #" + (root.currentFilter.length > 20 ? (root.currentFilter.slice(0, 18) + "…") : root.currentFilter) + ". Add one above!")
      color: Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.italic: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      width: parent.width
      topPadding: Style.space(8)
      bottomPadding: Style.space(8)
    }

    // Task items list
    Flickable {
      id: todoListFlickable
      visible: root.filteredTodos.length > 0
      width: parent.width
      implicitHeight: Math.min(Style.space(280), todoListCol.implicitHeight)
      contentHeight: todoListCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      HoverHandler {
        id: listHoverHandler
        onHoveredChanged: {
          if (!hovered && root.expandedTaskId !== -1) {
            listFoldTimer.restart()
          } else {
            listFoldTimer.stop()
          }
        }
      }

      Timer {
        id: listFoldTimer
        interval: 350
        repeat: false
        onTriggered: {
          if (root.expandedTaskId !== -1) {
            if (root.descArea && root.descArea.editorActiveFocus) {
              return
            }
            root.savePendingNotes()
            root.expandedTaskId = -1
          }
        }
      }

      Column {
        id: todoListCol
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.filteredTodos

          Rectangle {
            id: itemRow
            required property var modelData
            required property int index

            readonly property bool isExpanded: root.expandedTaskId === modelData.id
            readonly property bool isDone: Boolean(modelData.done)
            readonly property bool isOverdueTask: !isDone && TodoStore.isOverdue(modelData)
            readonly property bool isDueTodayTask: !isDone && !isOverdueTask && Boolean(modelData.reminder) && (new Date(modelData.reminder).toDateString() === new Date().toDateString())

            width: parent.width
            implicitHeight: isExpanded ? expandedContent.implicitHeight + Style.space(14) : Style.space(40)
            radius: Style.cornerRadius
            color: isExpanded
              ? Color.menu.selectedBackground
              : (rowHoverHandler.hovered ? Color.menu.selectedBackground : "transparent")
            border.color: isExpanded
              ? Color.menu.border
              : (isOverdueTask ? Util.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.35) : (isDueTodayTask ? Util.alpha(Color.accent, 0.35) : "transparent"))
            border.width: isExpanded || isOverdueTask || isDueTodayTask ? 1 : 0

            Behavior on implicitHeight {
              NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // Subtle horizontal gradient tint for overdue and due-today tasks
            Rectangle {
              id: urgencyGradient
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              visible: itemRow.isOverdueTask || itemRow.isDueTodayTask
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                  position: 0.0
                  color: itemRow.isOverdueTask
                    ? Util.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.15)
                    : Util.alpha(Color.accent, 0.12)
                }
                GradientStop {
                  position: 0.4
                  color: itemRow.isOverdueTask
                    ? Util.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.03)
                    : Util.alpha(Color.accent, 0.02)
                }
                GradientStop {
                  position: 1.0
                  color: "transparent"
                }
              }
            }

            // Left edge indicator stripe
            Rectangle {
              id: urgencyStripe
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.space(4)
              anchors.bottomMargin: Style.space(4)
              width: Style.space(2.5)
              radius: width / 2
              visible: itemRow.isOverdueTask || itemRow.isDueTodayTask
              color: itemRow.isOverdueTask
                ? (root.bar ? root.bar.urgent : Color.urgent)
                : Color.accent
            }

            HoverHandler {
              id: rowHoverHandler
              onHoveredChanged: {
                if (hovered) {
                  hoverFoldTimer.stop()
                  if (!itemRow.isExpanded) {
                    hoverExpandTimer.restart()
                  }
                } else {
                  hoverExpandTimer.stop()
                  if (itemRow.isExpanded) {
                    hoverFoldTimer.restart()
                  }
                }
              }
            }

            Timer {
              id: hoverExpandTimer
              interval: 800
              repeat: false
              onTriggered: {
                if (rowHoverHandler.hovered && !itemRow.isExpanded) {
                  root.savePendingNotes()
                  root.expandedTaskId = itemRow.modelData.id
                }
              }
            }

            Timer {
              id: hoverFoldTimer
              interval: 350
              repeat: false
              onTriggered: {
                if (itemRow.isExpanded && !rowHoverHandler.hovered) {
                  if (root.descArea && root.descArea.editorActiveFocus) {
                    return
                  }
                  root.savePendingNotes()
                  root.expandedTaskId = -1
                }
              }
            }

            onIsExpandedChanged: {
              hoverExpandTimer.stop()
              hoverFoldTimer.stop()
            }

            MouseArea {
              id: rowMouseArea
              anchors.fill: parent
              onClicked: {
                hoverExpandTimer.stop()
                hoverFoldTimer.stop()
                root.toggleTodo(itemRow.modelData.id)
              }
            }

            Column {
              id: expandedContent
              width: parent.width
              spacing: Style.space(6)
              anchors.top: parent.top
              anchors.topMargin: Style.space(5)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)

              // Primary row
              Item {
                width: parent.width
                implicitHeight: Style.space(30)

                Row {
                  id: titleRow
                  anchors.left: parent.left
                  anchors.right: rowActions.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  // Checkbox icon (neutral by default, urgent red only when overdue)
                  Text {
                    id: checkboxIcon
                    anchors.verticalCenter: parent.verticalCenter
                    text: itemRow.isDone ? "󰄲" : "󰄱"
                    color: itemRow.isDone
                      ? Color.muted
                      : (TodoStore.isOverdue(itemRow.modelData) ? (root.bar ? root.bar.urgent : Color.urgent) : Color.muted)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  // Profile badge when viewing "All"
                  Rectangle {
                    id: profBadge
                    visible: root.currentFilter === "all" && Boolean(itemRow.modelData.profile)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Math.min(Style.space(75), profLabel.implicitWidth + Style.space(8))
                    implicitHeight: Style.space(16)
                    radius: implicitHeight / 2
                    color: Color.menu.background
                    border.color: Color.menu.border
                    border.width: 1

                    Text {
                      id: profLabel
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, profBadge.implicitWidth - Style.space(8))
                      text: "#" + itemRow.modelData.profile
                      color: Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(8.5)
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                    }

                    HoverHandler {
                      id: profBadgeHover
                    }

                    PanelToolTip {
                      visible: profBadgeHover.hovered && profLabel.truncated
                      text: "#" + itemRow.modelData.profile
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }

                  // Title text
                  Text {
                    id: titleLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Style.space(40), titleRow.width - checkboxIcon.implicitWidth - (profBadge.visible ? profBadge.implicitWidth + titleRow.spacing : 0) - titleRow.spacing)
                    text: TodoStore.capitalizeTitle(itemRow.modelData.title || "")
                    color: itemRow.isDone ? Color.muted : root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.strikeout: itemRow.isDone
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight

                    HoverHandler {
                      id: titleHover
                    }

                    PanelToolTip {
                      visible: titleHover.hovered && titleLabel.truncated
                      text: TodoStore.capitalizeTitle(itemRow.modelData.title || "")
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }
                }

                // Indicators and action buttons
                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  // Description indicator icon
                  Text {
                    visible: !itemRow.isExpanded && Boolean(itemRow.modelData.description)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰏫"
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  // Reminder badge
                  Rectangle {
                    visible: !itemRow.isExpanded && Boolean(itemRow.modelData.reminder)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: remRow.implicitWidth + Style.space(6)
                    implicitHeight: Style.space(18)
                    radius: implicitHeight / 2
                    color: itemRow.isDone ? Color.menu.background : Util.alpha(Color.accent, 0.14)
                    border.color: itemRow.isDone ? Color.menu.border : Color.accent
                    border.width: 1

                    Row {
                      id: remRow
                      anchors.centerIn: parent
                      spacing: Style.space(2)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰥔"
                        color: itemRow.isDone ? Color.muted : Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(8.5)
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: TodoStore.formatReminder(itemRow.modelData.reminder)
                        color: itemRow.isDone ? Color.muted : Color.accent
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(8.5)
                      }
                    }
                  }

                  // Expand / Collapse details button
                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Style.space(22)
                    iconText: itemRow.isExpanded ? "󰅃" : "󰅀"
                    fontSize: Style.font.caption
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    foreground: Color.muted
                    hoverColor: Color.accent
                    tooltipText: itemRow.isExpanded ? "Hide details" : "Show notes & reminders"
                    onClicked: {
                      root.savePendingNotes()
                      root.expandedTaskId = itemRow.isExpanded ? -1 : itemRow.modelData.id
                    }
                  }

                  // Remove button
                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Style.space(22)
                    iconText: "󰅙"
                    fontSize: Style.font.caption
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    foreground: Color.muted
                    hoverColor: root.bar ? root.bar.urgent : Color.urgent
                    tooltipText: "Delete task"
                    onClicked: {
                      root.removeTodo(itemRow.modelData.id)
                    }
                  }
                }
              }

              // Expanded Details Section
              Column {
                visible: itemRow.isExpanded
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator { width: parent.width }

                // Description / Notes input (reusable multi-line TaskNotesArea component)
                TaskNotesArea {
                  id: descArea
                  width: parent.width
                  text: itemRow.modelData.description || ""
                  placeholderText: "Notes / description (Shift+Enter for newline)..."
                  bar: root.bar
                  foreground: root.barForeground
                  accentColor: Color.accent
                  onEditorActiveFocusChanged: {
                    if (editorActiveFocus) {
                      root.descArea = descArea
                    } else if (root.descArea === descArea) {
                      root.descArea = null
                      if (itemRow.isExpanded && !rowHoverHandler.hovered) {
                        hoverFoldTimer.restart()
                      }
                    }
                  }
                  Component.onDestruction: {
                    if (root.descArea === descArea) {
                      root.descArea = null
                    }
                  }
                  onSaved: function(newText) {
                    if (itemRow.modelData && newText !== (itemRow.modelData.description || "")) {
                      root.updateTodo(itemRow.modelData.id, { description: newText })
                    }
                  }
                }

                // Reminder Presets Row
                Row {
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰥔 Reminder:"
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.space(9.5)
                  }

                  Repeater {
                    model: root.reminderPresets

                    Rectangle {
                      id: remPresetBtn
                      required property var modelData
                      readonly property bool isSelected: itemRow.modelData.reminder === modelData.value
                      implicitWidth: remPresetText.implicitWidth + Style.space(8)
                      implicitHeight: Style.space(20)
                      radius: Style.cornerRadius
                      color: isSelected ? Color.accent : Color.menu.background
                      border.color: isSelected ? Color.accent : Color.menu.border
                      border.width: 1

                      Text {
                        id: remPresetText
                        anchors.centerIn: parent
                        text: remPresetBtn.modelData.label
                        color: remPresetBtn.isSelected ? "white" : root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(9)
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.updateTodo(itemRow.modelData.id, { reminder: remPresetBtn.modelData.value })
                        }
                      }
                    }
                  }

                  // Clear reminder button
                  Rectangle {
                    visible: Boolean(itemRow.modelData.reminder)
                    implicitWidth: clearRemText.implicitWidth + Style.space(8)
                    implicitHeight: Style.space(20)
                    radius: Style.cornerRadius
                    color: Color.menu.background
                    border.color: Color.menu.border
                    border.width: 1

                    Text {
                      id: clearRemText
                      anchors.centerIn: parent
                      text: "✕ Clear"
                      color: Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(9)
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.updateTodo(itemRow.modelData.id, { reminder: null })
                      }
                    }
                  }
                }

                // Profile selector row
                Flow {
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    text: "Profile:"
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.space(9.5)
                    topPadding: Style.space(3)
                  }

                  Repeater {
                    model: TodoStore.getSortedProfiles(root.store, false, "")

                    Rectangle {
                      id: profReassignBtn
                      required property string modelData
                      readonly property bool isSelected: itemRow.modelData.profile === modelData
                      implicitWidth: profReassignText.width + Style.space(8)
                      implicitHeight: Style.space(20)
                      radius: Style.cornerRadius
                      color: isSelected ? Color.accent : Color.menu.background
                      border.color: isSelected ? Color.accent : Color.menu.border
                      border.width: 1

                      Text {
                        id: profReassignText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Style.space(80))
                        text: profReassignBtn.modelData
                        color: profReassignBtn.isSelected ? "white" : root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(9)
                        font.bold: profReassignBtn.isSelected
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.updateTodo(itemRow.modelData.id, { profile: profReassignBtn.modelData })
                        }
                      }

                      HoverHandler {
                        id: profReassignHover
                      }

                      PanelToolTip {
                        visible: profReassignHover.hovered && profReassignText.truncated
                        text: profReassignBtn.modelData
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    PanelSeparator { width: parent.width }

    // Footer quick actions
    Item {
      id: footerContainer
      width: parent.width
      implicitHeight: Math.max(footerLeft.implicitHeight, quickAddBtn.implicitHeight)

      readonly property bool wrapNeeded: {
        var filterLabel = (root.currentFilter === "all") ? "Clear" : ("Clear #" + root.currentFilter)
        var fullButtonsWidth = Style.space(288) + (filterLabel.length * Style.space(7.2))
        return fullButtonsWidth > (parent.width - Style.space(12))
      }

      Row {
        id: footerLeft
        anchors.left: parent.left
        anchors.right: quickAddBtn.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        clip: true

        Button {
          iconText: "󰃢"
          text: footerContainer.wrapNeeded ? "" : (root.currentFilter === "all" ? "Clear" : ("Clear #" + root.currentFilter))
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          tooltipText: root.currentFilter === "all" ? "Archive and clear completed tasks" : ("Archive and clear completed tasks in #" + root.currentFilter)
          onClicked: root.clearCompleted(root.currentFilter)
        }

        Button {
          iconText: "󰋚"
          text: footerContainer.wrapNeeded ? "" : "Archive"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          tooltipText: "Open todos-archive.json in editor"
          onClicked: root.openArchive()
        }

        Button {
          iconText: "󰏫"
          text: footerContainer.wrapNeeded ? "" : "Edit"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          tooltipText: "Open todos.json in editor"
          onClicked: root.openEditor()
        }
      }

      Button {
        id: quickAddBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐕"
        text: footerContainer.wrapNeeded ? "" : "Quick Add"
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        tooltipText: "Open Quick Add modal (" + root.detectedShortcut + ")"
        onClicked: root.openQuickAdd()
      }
    }
  }
}
