import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore

Panel {
  id: root
  moduleName: "tablerase.todo"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var barWidget: null

  readonly property var store: barWidget ? barWidget.store : TodoStore.defaultStore()
  readonly property var todos: barWidget ? barWidget.todos : []
  readonly property int pendingCount: barWidget ? barWidget.pendingCount : 0
  readonly property var profiles: barWidget ? barWidget.profiles : ["personal", "work"]
  readonly property var visibleProfiles: {
    var list = []
    var allProfs = root.profiles || ["personal", "work"]
    for (var i = 0; i < allProfs.length; i++) {
      var p = allProfs[i]
      var count = TodoStore.getPendingCount(root.store, p)
      if (count > 0 || p === root.currentFilter) {
        list.push(p)
      }
    }
    if (list.length === 0) {
      list.push((root.store && root.store.activeProfile) ? root.store.activeProfile : "personal")
    }
    return list
  }
  readonly property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color cardBackground: Color.popups.background

  property string currentFilter: "all"
  property var expandedTaskId: -1
  property bool addingProfile: false

  readonly property var filteredTodos: TodoStore.getFilteredTodos(root.store, root.currentFilter)
  readonly property int filteredPendingCount: TodoStore.getPendingCount(root.store, root.currentFilter)
  readonly property var reminderPresets: TodoStore.getReminderPresets()

  property string shortcutState: "missing"
  readonly property bool hasShortcut: shortcutState === "active"

  onOpenedChanged: if (opened) checkShortcutProc.running = true
  Component.onCompleted: checkShortcutProc.running = true

  // Query running Hyprland compositor or config files for active/commented keybinding
  Process {
    id: checkShortcutProc
    command: [
      "bash",
      "-c",
      "if hyprctl binds 2>/dev/null | grep -E -q 'Todo Quick Add|tablerase\\.todo'; then echo 'active'; elif grep -E -s -q '^[[:space:]]*(o\\.bind|bindd?).*(tablerase\\.todo|Todo Quick Add)' \"$HOME/.config/hypr/bindings.lua\" \"$HOME/.config/hypr/bindings.conf\" 2>/dev/null; then echo 'active'; elif grep -E -s -q '^[[:space:]]*(--|#).*(tablerase\\.todo|Todo Quick Add)' \"$HOME/.config/hypr/bindings.lua\" \"$HOME/.config/hypr/bindings.conf\" 2>/dev/null; then echo 'commented'; else echo 'missing'; fi"
    ]
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line).trim()
        if (s === "active" || s === "commented" || s === "missing") {
          root.shortcutState = s
        }
      }
    }
  }

  // Copy keybinding snippet to clipboard and open bindings file in editor
  Process {
    id: copyAndOpenProc
    command: [
      "bash",
      "-c",
      "if [ -f \"$HOME/.config/hypr/bindings.lua\" ]; then FILE=\"$HOME/.config/hypr/bindings.lua\"; SNIPPET=\"o.bind(\\\"SUPER + SHIFT + T\\\", \\\"Todo Quick Add\\\", \\\"omarchy-shell shell toggle tablerase.todo '{}'\\\")\"; else FILE=\"$HOME/.config/hypr/bindings.conf\"; SNIPPET=\"bindd = SUPER SHIFT, T, Todo Quick Add, exec, omarchy-shell shell toggle tablerase.todo \\\"{}\\\"\"; fi; wl-copy \"$SNIPPET\" && notify-send -a 'Omarchy Todo' 'Keybinding Copied & Config Opened' \"Paste into $(basename \\\"$FILE\\\") and run hyprctl reload\" && omarchy-launch-editor \"$FILE\""
    ]
    onExited: function(exitCode) {
      checkShortcutProc.running = true
    }
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
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

  onCurrentFilterChanged: Qt.callLater(function() { root.ensureProfileVisible(root.currentFilter) })

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: newTodoField.activeFocus || root.expandedTaskId !== -1 || root.addingProfile
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

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
              text: "Todos"
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
            foreground: root.shortcutState === "active" ? root.barForeground : Color.muted
            tooltipText: root.shortcutState === "active"
              ? "Shortcut active: SUPER + SHIFT + T (click to copy & edit config)"
              : (root.shortcutState === "commented"
                ? "Shortcut commented out in config (click to edit)"
                : "Click to copy shortcut & open bindings in editor")
            onClicked: {
              copyAndOpenProc.running = true
              root.close()
            }

            Rectangle {
              id: indicatorBadge
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.bottomMargin: Style.space(1)
              anchors.rightMargin: Style.space(1)
              color: root.shortcutState === "active" ? Color.accent
                : (root.shortcutState === "commented" ? "#e67e22" : Color.urgent)
              border.color: Color.menu.background
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: root.shortcutState === "missing" ? "✕" : "✓"
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

              // Individual active profile pills (only profiles with active todos or currently selected)
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
                      anchors.verticalCenter: parent.verticalCenter
                      text: profPill.modelData
                      color: root.currentFilter === profPill.modelData ? "white" : root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: root.currentFilter === profPill.modelData
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
                }
              }
            }
          }

          // Soft blur/fade edge on the left when scrolled right
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

          // Soft blur/fade edge on the right before the add profile button
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
                if (root.barWidget) root.barWidget.addProfile(p)
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
                if (root.barWidget) root.barWidget.addProfile(p)
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
              : ("Add task to #" + root.currentFilter + "...")
            font.pixelSize: Style.font.caption
            onAccepted: {
              if (text.trim() !== "") {
                var prof = (root.currentFilter !== "all") ? root.currentFilter : null
                if (root.barWidget) root.barWidget.addTodo(text, "", prof, null)
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
                if (root.barWidget) root.barWidget.addTodo(newTodoField.text, "", prof, null)
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
            : ("No tasks in #" + root.currentFilter + ". Add one above!")
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: true
          horizontalAlignment: Text.AlignHCenter
          width: parent.width
          topPadding: Style.space(8)
          bottomPadding: Style.space(8)
        }

        // Task items list
        Flickable {
          visible: root.filteredTodos.length > 0
          width: parent.width
          implicitHeight: Math.min(Style.space(280), todoListCol.implicitHeight)
          contentHeight: todoListCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

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

                width: parent.width
                implicitHeight: isExpanded ? expandedContent.implicitHeight + Style.space(12) : Style.space(34)
                radius: Style.cornerRadius
                color: isExpanded
                  ? Color.menu.selectedBackground
                  : (rowMouseArea.containsMouse ? Color.menu.selectedBackground : "transparent")
                border.color: isExpanded ? Color.menu.border : "transparent"
                border.width: isExpanded ? 1 : 0

                MouseArea {
                  id: rowMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    if (root.barWidget) root.barWidget.toggleTodo(itemRow.modelData.id)
                  }
                }

                Column {
                  id: expandedContent
                  width: parent.width
                  spacing: Style.space(6)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)

                  // Primary row
                  Item {
                    width: parent.width
                    implicitHeight: Style.space(26)

                    Row {
                      id: titleRow
                      anchors.left: parent.left
                      anchors.right: rowActions.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)

                      // Checkbox icon
                      Text {
                        id: checkboxIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: itemRow.isDone ? "󰄲" : "󰄱"
                        color: itemRow.isDone ? Color.muted : (root.bar ? root.bar.urgent : Color.urgent)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                      }

                      // Profile badge when viewing "All"
                      Rectangle {
                        id: profBadge
                        visible: root.currentFilter === "all" && Boolean(itemRow.modelData.profile)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: profLabel.implicitWidth + Style.space(8)
                        implicitHeight: Style.space(16)
                        radius: implicitHeight / 2
                        color: Color.menu.background
                        border.color: Color.menu.border
                        border.width: 1

                        Text {
                          id: profLabel
                          anchors.centerIn: parent
                          text: "#" + itemRow.modelData.profile
                          color: Color.muted
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.space(8.5)
                        }
                      }

                      // Title text
                      Text {
                        id: titleLabel
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(Style.space(40), titleRow.width - checkboxIcon.implicitWidth - (profBadge.visible ? profBadge.implicitWidth + titleRow.spacing : 0) - titleRow.spacing)
                        text: itemRow.modelData.title || ""
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
                          text: itemRow.modelData.title || ""
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
                        color: itemRow.isDone ? Color.menu.background : (Color.accent + "22")
                        border.color: itemRow.isDone ? Color.menu.border : Color.accent
                        border.width: 1

                        Row {
                          id: remRow
                          anchors.centerIn: parent
                          spacing: Style.space(2)

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰀉"
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
                          if (root.barWidget) root.barWidget.removeTodo(itemRow.modelData.id)
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

                    // Description / Notes input
                    TextField {
                      id: descField
                      width: parent.width
                      text: itemRow.modelData.description || ""
                      placeholderText: "Notes / description..."
                      font.pixelSize: Style.font.caption
                      onAccepted: {
                        if (root.barWidget) {
                          root.barWidget.updateTodo(itemRow.modelData.id, { description: text })
                        }
                      }
                      onEditingFinished: {
                        if (root.barWidget) {
                          root.barWidget.updateTodo(itemRow.modelData.id, { description: text })
                        }
                      }
                    }

                    // Reminder Presets Row
                    Row {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰀉 Reminder:"
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
                              if (root.barWidget) {
                                root.barWidget.updateTodo(itemRow.modelData.id, { reminder: remPresetBtn.modelData.value })
                              }
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
                            if (root.barWidget) {
                              root.barWidget.updateTodo(itemRow.modelData.id, { reminder: null })
                            }
                          }
                        }
                      }
                    }

                    // Profile selector row
                    Row {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Profile:"
                        color: Color.muted
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(9.5)
                      }

                      Repeater {
                        model: root.profiles

                        Rectangle {
                          id: profReassignBtn
                          required property string modelData
                          readonly property bool isSelected: itemRow.modelData.profile === modelData
                          implicitWidth: profReassignText.implicitWidth + Style.space(8)
                          implicitHeight: Style.space(20)
                          radius: Style.cornerRadius
                          color: isSelected ? Color.accent : Color.menu.background
                          border.color: isSelected ? Color.accent : Color.menu.border
                          border.width: 1

                          Text {
                            id: profReassignText
                            anchors.centerIn: parent
                            text: profReassignBtn.modelData
                            color: profReassignBtn.isSelected ? "white" : root.barForeground
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.space(9)
                            font.bold: profReassignBtn.isSelected
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (root.barWidget) {
                                root.barWidget.updateTodo(itemRow.modelData.id, { profile: profReassignBtn.modelData })
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
          }
        }

        PanelSeparator { width: parent.width }

        // Footer quick actions
        Item {
          width: parent.width
          implicitHeight: Math.max(footerLeft.implicitHeight, quickAddBtn.implicitHeight)

          Row {
            id: footerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              iconText: "󰃢"
              text: root.currentFilter === "all" ? "Clear" : ("Clear #" + root.currentFilter)
              fontSize: Style.font.caption
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              tooltipText: "Clear completed tasks"
              onClicked: {
                if (root.barWidget) root.barWidget.clearCompleted(root.currentFilter)
              }
            }

            Button {
              iconText: "󰏫"
              text: "Edit"
              fontSize: Style.font.caption
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              tooltipText: "Open todos.json in editor"
              onClicked: {
                var p = root.barWidget ? root.barWidget.todoFilePath : "$HOME/.config/omarchy/todos.json"
                if (root.bar) root.bar.run("omarchy-launch-editor " + p)
                root.close()
              }
            }
          }

          Button {
            id: quickAddBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰐕"
            text: "Quick Add"
            fontSize: Style.font.caption
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            tooltipText: "Open Quick Add modal (SUPER + SHIFT + T)"
            onClicked: {
              root.close()
              if (root.bar && root.bar.shell) {
                root.bar.shell.summon(root.moduleName, "{}")
              }
            }
          }
        }
      }
    }
  }
}
