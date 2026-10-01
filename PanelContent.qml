import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore
import "PanelLogic.js" as Logic
import "./ui" as Ui

Item {
  id: root

  property var bar: null
  property var barWidget: null
  property var store: (barWidget && barWidget.store) ? barWidget.store : TodoStore.defaultStore()

  onBarWidgetChanged: {
    if (barWidget && barWidget.store) {
      root.store = barWidget.store
      root.syncFilteredTodos()
    }
  }

  Connections {
    target: root.barWidget
    function onStoreChanged() {
      if (root.barWidget && root.barWidget.store) {
        root.store = root.barWidget.store
        root.syncFilteredTodos()
      }
    }
  }
  readonly property var todos: store ? (store.todos || []) : []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  readonly property var profiles: store ? (store.profiles || ["personal", "work"]) : ["personal", "work"]
  readonly property var visibleProfiles: TodoStore.getSortedProfiles(root.store, true, root.currentFilter)
  property alias gitModal: gitModal

  readonly property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  // Late-task severity, read by the header ArdoiseIcon (which owns the theme
  // lookup) and handed down to every task row so panel rows, brand mark and
  // bar all render the same amber. The literal fallback covers the window
  // before the header exists, and keeps the value a real QColor so it can be
  // assigned to a typed `color` property without a coercion warning.
  readonly property color warningColor: brandIcon ? brandIcon.warningColor : "#df8e1d"
  readonly property color cardBackground: Color.popups.background
  // Opaque composite of selectedBackground tint over the solid card base — used as
  // fadeColor for pill rows inside expanded task drawers so the gradient has real contrast.
  readonly property color expandedCardColor: Qt.rgba(
    Color.popups.background.r * (1 - Color.menu.selectedBackground.a) + Color.menu.selectedBackground.r * Color.menu.selectedBackground.a,
    Color.popups.background.g * (1 - Color.menu.selectedBackground.a) + Color.menu.selectedBackground.g * Color.menu.selectedBackground.a,
    Color.popups.background.b * (1 - Color.menu.selectedBackground.a) + Color.menu.selectedBackground.b * Color.menu.selectedBackground.a,
    1.0
  )

  property string currentFilter: "all"
  property var expandedTaskId: -1
  property bool expandedViaKeyboard: false
  property bool mouseMovementDetected: false
  property bool addingProfile: false
  property string shortcutState: "active"
  property string detectedShortcut: root.detectedPanelShortcut
  property string detectedPanelShortcut: "SUPER + ALT + T"
  property string detectedQuickAddShortcut: "SUPER + SHIFT + T"
  property bool panelShortcutRegistered: false
  property bool quickAddShortcutRegistered: false
  property bool shortcutRegistered: false
  property string moduleName: "tablerase.ardoise"
  property var descArea: null

  property string focusSection: "tasks"
  property int cursorIndex: 0
  property bool cursorActive: false
  property int footerButtonIndex: 0
  property bool showKeyHelp: false
  property bool showGitModal: false
  property string keyHelpSearch: ""
  property string searchQuery: ""
  property bool searchActive: false
  property string expandedSubSection: "header" // "header" | "notes" | "reminders" | "profiles" | "codebase"
  property int expandedReminderIndex: 0
  property int expandedProfileIndex: 0
  property var editingTaskId: -1

  function activateSearch() {
    root.searchActive = true
    Qt.callLater(function() {
      if (typeof searchField !== "undefined" && searchField) {
        searchField.forceActiveFocus()
      }
    })
  }

  function closeSearch() {
    root.searchActive = false
    root.searchQuery = ""
    if (typeof searchField !== "undefined" && searchField) {
      searchField.text = ""
    }
    root.focusSection = "tasks"
    root.cursorActive = true
    root.releaseFocus()
  }

  function clearSearchText() {
    root.searchQuery = ""
    if (typeof searchField !== "undefined" && searchField) {
      searchField.text = ""
    }
  }

  onExpandedSubSectionChanged: {
    if (root.expandedSubSection === "reminders") {
      root.refreshReminderPresets()
      Qt.callLater(function() {
        root.ensureReminderVisible(root.expandedReminderIndex)
      })
    } else if (root.expandedSubSection === "profiles") {
      Qt.callLater(function() {
        root.ensureReassignProfileVisible(root.expandedProfileIndex)
      })
    }
  }

  function cleanRepoName(repo) {
    return Logic.cleanRepoName(repo)
  }

  function openCodebase(task) {
    if (!task || !task.location || !task.location.localPath) return
    root.savePendingNotes()
    root.closeRequested()
    var cmd = Logic.buildCodebaseCommand(task.location.localPath, Quickshell.env("HOME"))
    if (root.bar && cmd) root.bar.run(cmd)
  }

  function getActiveDescArea() {
    if (root.descArea) return root.descArea
    if (root.cursorIndex >= 0 && typeof todoListRepeater !== "undefined" && todoListRepeater && root.cursorIndex < todoListRepeater.count) {
      var item = todoListRepeater.itemAt(root.cursorIndex)
      if (item && item.descAreaInstance) {
        root.descArea = item.descAreaInstance
        return item.descAreaInstance
      }
    }
    return null
  }

  function focusNotesEditor() {
    var area = root.getActiveDescArea()
    if (area) {
      root.descArea = area
      area.forceActiveFocus()
      return true
    }
    return false
  }

  function ensureReminderVisible(idx) {
    if (root.cursorIndex >= 0 && typeof todoListRepeater !== "undefined" && todoListRepeater && root.cursorIndex < todoListRepeater.count) {
      var item = todoListRepeater.itemAt(root.cursorIndex)
      if (item && item.ensureReminderVisible) {
        item.ensureReminderVisible(idx)
      }
    }
  }

  onExpandedReminderIndexChanged: {
    if (root.expandedSubSection === "reminders") {
      root.ensureReminderVisible(root.expandedReminderIndex)
    }
  }

  function ensureReassignProfileVisible(idx) {
    if (root.cursorIndex >= 0 && typeof todoListRepeater !== "undefined" && todoListRepeater && root.cursorIndex < todoListRepeater.count) {
      var item = todoListRepeater.itemAt(root.cursorIndex)
      if (item && item.ensureReassignProfileVisible) {
        item.ensureReassignProfileVisible(idx)
      }
    }
  }

  onExpandedProfileIndexChanged: {
    if (root.expandedSubSection === "profiles") {
      root.ensureReassignProfileVisible(root.expandedProfileIndex)
    }
  }

  function handleEscape() {
    return Logic.handleEscape(root)
  }

  onVisibleChanged: {
    if (!visible) {
      cancelEditingTask()
      flushPendingCompletions()
      savePendingNotes()
      expandedTaskId = -1
      expandedViaKeyboard = false
      mouseMovementDetected = false
      cursorActive = false
      focusSection = "tasks"
      showKeyHelp = false
      showGitModal = false
      searchActive = false
      searchQuery = ""
      if (typeof searchField !== "undefined" && searchField) {
        searchField.text = ""
      }
      expandedSubSection = "header"
      expandedReminderIndex = 0
      expandedProfileIndex = 0
    } else {
      mouseMovementDetected = false
      expandedViaKeyboard = false
    }
  }

  onShowKeyHelpChanged: {
    if (showKeyHelp) {
      if (typeof helpModal !== "undefined" && helpModal) {
        helpModal.open()
      }
    } else {
      if (typeof helpModal !== "undefined" && helpModal) {
        helpModal.close()
      }
    }
  }

  onShowGitModalChanged: {
    if (showGitModal) {
      if (typeof gitModal !== "undefined" && gitModal) {
        gitModal.open()
      }
    } else {
      if (typeof gitModal !== "undefined" && gitModal) {
        gitModal.close()
      }
    }
  }

  onExpandedTaskIdChanged: {
    expandedSubSection = "header"
    expandedReminderIndex = 0
    expandedProfileIndex = 0
    if (expandedTaskId !== -1) {
      root.refreshReminderPresets()
      Qt.callLater(function() {
        for (var i = 0; i < root.filteredTodos.length; i++) {
          if (root.filteredTodos[i].id === root.expandedTaskId) {
            root.ensureTaskVisible(i, true)
            break
          }
        }
      })
    }
  }

  onFilteredTodosChanged: {
    if (cursorIndex >= filteredTodos.length) {
      cursorIndex = Math.max(0, filteredTodos.length - 1)
    }
  }

  function ensureTaskVisible(taskIndex, alignTop) {
    if (!todoListFlickable || !todoListRepeater || taskIndex < 0 || taskIndex >= todoListRepeater.count) return
    var item = todoListRepeater.itemAt(taskIndex)
    if (!item) return
    var itemTop = item.y
    var itemBottom = item.y + item.height
    var viewTop = todoListFlickable.contentY
    var viewBottom = todoListFlickable.contentY + todoListFlickable.height
    var maxContentY = Math.max(0, todoListFlickable.contentHeight - todoListFlickable.height)

    if (alignTop) {
      var targetY = Math.max(0, itemTop - Style.space(2))
      todoListFlickable.contentY = Math.max(0, Math.min(maxContentY, targetY))
    } else {
      if (itemTop < viewTop) {
        todoListFlickable.contentY = Math.max(0, itemTop - Style.space(6))
      } else if (itemBottom > viewBottom) {
        todoListFlickable.contentY = Math.max(0, Math.min(maxContentY, itemBottom - todoListFlickable.height + Style.space(6)))
      }
    }
  }

  function cycleProfileFilter(step) {
    var list = ["all"].concat(root.visibleProfiles)
    var currentIdx = list.indexOf(root.currentFilter)
    if (currentIdx === -1) currentIdx = 0
    var nextIdx = (currentIdx + step + list.length) % list.length
    root.currentFilter = list[nextIdx]
    root.cursorIndex = 0
    Qt.callLater(function() { root.ensureProfileVisible(root.currentFilter) })
  }

  function focusInputField() {
    Qt.callLater(function() {
      if (typeof newTodoField !== "undefined" && newTodoField) {
        newTodoField.forceActiveFocus()
      }
    })
  }

  function handleMove(dx, dy) {
    Logic.handleMove(root, dx, dy, TodoStore)
  }

  property bool _suppressActivateOnReturn: false

  function handleActivate() {
    if (root._suppressActivateOnReturn) return
    Logic.handleActivate(root, TodoStore)
  }

  function handleReturn() {
    root._suppressActivateOnReturn = true
    Qt.callLater(function() { root._suppressActivateOnReturn = false })
    Logic.handleReturn(root, TodoStore)
  }

  function insertInputText(txt) {
    if (newTodoField && txt && txt.length === 1) {
      newTodoField.text += txt
      newTodoField.cursorPosition = newTodoField.text.length
    }
  }

  function handleDelete() {
    Logic.handleDelete(root)
  }

  function handleTextKey(text) {
    Logic.handleTextKey(root, text, TodoStore)
  }

  function handleTab(direction) {
    return Logic.handleTab(root, direction, TodoStore)
  }

  function triggerFooterButton(idx) {
    if (idx === 0) root.clearCompleted(root.currentFilter)
    else if (idx === 1) root.openArchive()
    else if (idx === 2) root.openEditor()
    else if (idx === 3) root.openQuickAdd()
  }

  property var filteredTodos: []

  function syncFilteredTodos() {
    var next = TodoStore.getFilteredTodos(root.store, root.currentFilter, "all", "all", root.searchQuery)
    if (!root.filteredTodos || root.filteredTodos.length !== next.length) {
      root.filteredTodos = next
      return
    }
    for (var i = 0; i < next.length; i++) {
      if (root.filteredTodos[i].id !== next[i].id || root.filteredTodos[i].done !== next[i].done) {
        root.filteredTodos = next
        return
      }
    }
    // Structure and order unchanged: update properties in-place so Repeater does not rebuild delegates
    for (var j = 0; j < next.length; j++) {
      var cur = root.filteredTodos[j]
      var upd = next[j]
      cur.title = upd.title
      cur.description = upd.description
      cur.profile = upd.profile
      cur.repo = upd.repo
      cur.tags = upd.tags
      cur.location = upd.location
      cur.reminder = upd.reminder
      cur.notified = upd.notified
      cur.updatedAt = upd.updatedAt
      if (typeof todoListRepeater !== "undefined" && todoListRepeater && j < todoListRepeater.count) {
        var delegate = todoListRepeater.itemAt(j)
        if (delegate) {
          if (typeof delegate.updateModelData === "function") {
            delegate.updateModelData(upd)
          } else {
            delegate.modelData = upd
          }
        }
      }
    }
  }

  onSearchQueryChanged: syncFilteredTodos()
  onStoreChanged: syncFilteredTodos()
  Component.onCompleted: syncFilteredTodos()
  property var pendingCompletionIds: []
  property var slidingOutTaskIds: []
  property var justCompletedTaskIds: []
  property bool completedFoldOpen: true

  readonly property int filteredPendingCount: {
    var raw = TodoStore.getPendingCount(root.store, root.currentFilter)
    return Math.max(0, raw - root.pendingCompletionIds.length)
  }

  readonly property int completedCount: {
    var cnt = root.pendingCompletionIds.length
    if (root.filteredTodos) {
      for (var i = 0; i < root.filteredTodos.length; i++) {
        if (root.filteredTodos[i].done && root.pendingCompletionIds.indexOf(root.filteredTodos[i].id) === -1) {
          cnt++
        }
      }
    }
    return cnt
  }

  Timer {
    id: slideStartTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.pendingCompletionIds && root.pendingCompletionIds.length > 0) {
        root.slidingOutTaskIds = root.pendingCompletionIds.slice()
      }
    }
  }

  Timer {
    id: completionGraceTimer
    interval: 600
    repeat: false
    onTriggered: root.flushPendingCompletions()
  }

  Timer {
    id: justCompletedClearTimer
    interval: 350
    repeat: false
    onTriggered: {
      root.justCompletedTaskIds = []
    }
  }

  property var reminderPresets: TodoStore.getReminderPresets()

  function refreshReminderPresets() {
    reminderPresets = TodoStore.getReminderPresets()
  }
  readonly property bool activeFocusBlocked: Boolean(
    (newTodoField && newTodoField.activeFocus) ||
    (typeof searchField !== "undefined" && searchField && searchField.activeFocus) ||
    (descArea && descArea.editorActiveFocus) ||
    addingProfile ||
    root.showKeyHelp ||
    root.showGitModal ||
    (root.editingTaskId !== undefined && root.editingTaskId !== null && root.editingTaskId !== -1) ||
    (typeof helpModal !== "undefined" && helpModal && (helpModal.isOpen || helpModal.searchFieldActiveFocus)) ||
    (typeof gitModal !== "undefined" && gitModal && gitModal.isOpen)
  )

  readonly property var keybindingsList: Logic.getKeybindingsList(root.detectedPanelShortcut, root.detectedQuickAddShortcut)
  readonly property var filteredKeybindings: Logic.filterKeybindings(root.keybindingsList, root.keyHelpSearch)

  signal closeRequested()
  signal shortcutClicked()
  signal switchPanelRequested(int direction)
  signal returnFocusRequested()

  Keys.onPressed: function(event) {
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
      event.accepted = true
      root.activateSearch()
    }
  }

  function releaseFocus() {
    if (newTodoField) newTodoField.focus = false
    if (typeof searchField !== "undefined" && searchField) searchField.focus = false
    if (root.descArea) {
      if (typeof root.descArea.releaseFocus === "function") {
        root.descArea.releaseFocus()
      } else if (root.descArea.textArea) {
        root.descArea.textArea.focus = false
      }
      root.descArea.focus = false
    }
    root.returnFocusRequested()
    if (parent && typeof parent.forceActiveFocus === "function") {
      parent.forceActiveFocus()
    } else {
      root.forceActiveFocus()
    }
  }

  function savePendingNotes() {
    if (root.descArea && typeof root.descArea.save === "function") {
      root.descArea.save()
    }
  }

  function addTodo(title, description, profile, reminder) {
    savePendingNotes()
    if (barWidget) {
      barWidget.addTodo(title, description, profile, reminder)
      if (barWidget.store) root.store = barWidget.store
    } else {
      root.store = TodoStore.addTodo(root.store, title, description, profile, reminder)
    }
    syncFilteredTodos()
  }

  function applyToggleTodo(id) {
    savePendingNotes()
    if (root.expandedTaskId === id) {
      root.expandedTaskId = -1
    }
    if (barWidget) {
      barWidget.toggleTodo(id)
      if (barWidget.store) root.store = barWidget.store
    } else {
      root.store = TodoStore.toggleTodo(root.store, id)
    }
    syncFilteredTodos()
  }

  function flushPendingCompletions() {
    if (slideStartTimer.running) slideStartTimer.stop()
    if (completionGraceTimer.running) completionGraceTimer.stop()
    if (!root.pendingCompletionIds || root.pendingCompletionIds.length === 0) {
      root.slidingOutTaskIds = []
      return
    }
    var ids = root.pendingCompletionIds.slice()
    root.pendingCompletionIds = []
    root.slidingOutTaskIds = []
    root.justCompletedTaskIds = ids.slice()
    justCompletedClearTimer.restart()
    for (var i = 0; i < ids.length; i++) {
      root.applyToggleTodo(ids[i])
    }
  }

  function toggleTodo(id) {
    savePendingNotes()
    var isPending = root.pendingCompletionIds.indexOf(id) !== -1
    if (isPending) {
      var arr = root.pendingCompletionIds.slice()
      var idx = arr.indexOf(id)
      if (idx !== -1) arr.splice(idx, 1)
      root.pendingCompletionIds = arr
      var sArr = root.slidingOutTaskIds.slice()
      var sIdx = sArr.indexOf(id)
      if (sIdx !== -1) sArr.splice(sIdx, 1)
      root.slidingOutTaskIds = sArr
      if (root.pendingCompletionIds.length === 0) {
        slideStartTimer.stop()
        completionGraceTimer.stop()
      }
      return
    }

    var task = null
    for (var i = 0; i < root.filteredTodos.length; i++) {
      if (root.filteredTodos[i].id === id) {
        task = root.filteredTodos[i]
        break
      }
    }

    if (task && task.done) {
      root.applyToggleTodo(id)
    } else {
      var newArr = root.pendingCompletionIds.slice()
      newArr.push(id)
      root.pendingCompletionIds = newArr
      slideStartTimer.restart()
      completionGraceTimer.restart()
    }
  }

  function removeTodo(id) {
    savePendingNotes()
    if (barWidget) {
      barWidget.removeTodo(id)
      if (barWidget.store) root.store = barWidget.store
    } else {
      root.store = TodoStore.removeTodo(root.store, id)
    }
    syncFilteredTodos()
  }

  function updateTodo(id, fields) {
    if (barWidget) {
      barWidget.updateTodo(id, fields)
      if (barWidget.store) root.store = barWidget.store
    } else {
      root.store = TodoStore.updateTodo(root.store, id, fields)
    }
    syncFilteredTodos()
  }

  function startEditingTask(id) {
    savePendingNotes()
    root.editingTaskId = id
    root.focusSection = "tasks"
    root.cursorActive = true
  }

  function cancelEditingTask() {
    root.editingTaskId = -1
    root.focusSection = "tasks"
    root.cursorActive = true
    root.releaseFocus()
  }

  function commitEditingTask(id, newTitle) {
    if (root.editingTaskId === id) {
      root.editingTaskId = -1
    }
    var trimmed = (newTitle || "").trim()
    if (trimmed.length > 0) {
      root.updateTodo(id, { title: trimmed })
    }
    root.focusSection = "tasks"
    root.cursorActive = true
    root.releaseFocus()
  }

  function clearCompleted(profile) {
    flushPendingCompletions()
    savePendingNotes()
    if (barWidget) {
      barWidget.clearCompleted(profile)
      if (barWidget.store) root.store = barWidget.store
    } else {
      var res = TodoStore.archiveCompleted(root.store, profile, "")
      root.store = res.updatedStore
    }
    root.pendingCompletionIds = []
    root.slidingOutTaskIds = []
    root.justCompletedTaskIds = []
    syncFilteredTodos()
    if (root.filteredTodos && root.cursorIndex >= root.filteredTodos.length) {
      root.cursorIndex = Math.max(0, root.filteredTodos.length - 1)
    }
  }

  function addProfile(name) {
    savePendingNotes()
    if (barWidget) {
      barWidget.addProfile(name)
      if (barWidget.store) root.store = barWidget.store
    } else {
      root.store = TodoStore.addProfile(root.store, name)
    }
    syncFilteredTodos()
  }

  function openArchive() {
    savePendingNotes()
    var p = barWidget ? barWidget.archiveFilePath : (Quickshell.env("HOME") + "/.config/omarchy/tablerase.ardoise/todos-archive.json")
    if (bar) bar.run("omarchy-launch-editor " + p)
    root.closeRequested()
  }

  function openEditor(taskId) {
    savePendingNotes()
    var p = barWidget ? barWidget.todoFilePath : (Quickshell.env("HOME") + "/.config/omarchy/tablerase.ardoise/todos.json")
    if (bar) {
      bar.run(Logic.buildEditorCommand(p, taskId))
    }
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
    syncFilteredTodos()
    flushPendingCompletions()
    savePendingNotes()
    Qt.callLater(function() { root.ensureProfileVisible(root.currentFilter) })
  }

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(8)
    opacity: (root.showKeyHelp || root.showGitModal) ? 0 : 1

    // Header
    Item {
      width: parent.width
      implicitHeight: Math.max(headerLeft.implicitHeight, shortcutBtn.implicitHeight)

      Row {
        id: headerLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Item {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: brandRow.implicitWidth
          implicitHeight: brandRow.implicitHeight

          Row {
            id: brandRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Ui.ArdoiseIcon {
              id: brandIcon
              anchors.verticalCenter: parent.verticalCenter
              store: root.store
              bar: root.bar
              iconSize: Style.font.subtitle
              colorOverride: brandMouse.containsMouse ? Color.accent : undefined
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Ardoise"
              color: brandMouse.containsMouse ? Color.accent : (root.barForeground || Color.foreground)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              Behavior on color { ColorAnimation { duration: 120 } }
            }
          }

          MouseArea {
            id: brandMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("https://github.com/Tablerase/omarchy-ardoise")
          }

          PanelToolTip {
            visible: brandMouse.containsMouse
            text: "GitHub: Tablerase/omarchy-ardoise"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.filteredPendingCount + " pending"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: headerRightActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        PanelActionButton {
          id: searchBtn
          size: Style.space(26)
          iconText: "󰍉"
          fontSize: Style.font.subtitle
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
          Ui.ShortcutToolTip {
            visible: searchBtnHover.hovered
            description: "Search tasks, notes & profiles"
            shortcut: "/ or Ctrl+F"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        PanelActionButton {
          id: helpBtn
          size: Style.space(26)
          iconText: "󰞋"
          fontSize: Style.font.subtitle
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.showKeyHelp ? Color.accent : Color.muted
          hoverColor: Color.accent
          tooltipText: ""
          onClicked: {
            root.showKeyHelp = !root.showKeyHelp
            if (!root.showKeyHelp) {
              root.releaseFocus()
            }
          }

          HoverHandler { id: helpBtnHover }
          Ui.ShortcutToolTip {
            visible: helpBtnHover.hovered
            description: "Shortcuts & Vim motions"
            shortcut: "?"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        PanelActionButton {
          id: gitBtn
          size: Style.space(26)
          iconText: "󰊢"
          fontSize: Style.font.subtitle
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.showGitModal ? Color.accent : Color.muted
          hoverColor: Color.accent
          tooltipText: ""
          onClicked: {
            root.showGitModal = !root.showGitModal
            if (!root.showGitModal) {
              root.releaseFocus()
            }
          }

          HoverHandler { id: gitBtnHover }
          Ui.ShortcutToolTip {
            visible: gitBtnHover.hovered
            description: "Git Snapshots & Undo"
            shortcut: "u"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        // Compact shortcut info/copy button with bottom-right status indicator
        PanelActionButton {
          id: shortcutBtn
          size: Style.space(26)
          iconText: "󰌌"
          fontSize: Style.font.subtitle
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.shortcutRegistered ? root.barForeground : Color.muted
          tooltipText: ""
          onClicked: root.shortcutClicked()

          HoverHandler { id: shortcutBtnHover }
          Ui.ShortcutToolTip {
            visible: shortcutBtnHover.hovered
            description: (root.panelShortcutRegistered && root.quickAddShortcutRegistered)
              ? "Shortcuts active: Toggle Panel / Quick Add"
              : (root.shortcutRegistered
                ? (root.panelShortcutRegistered ? "Shortcuts: Panel active (Quick Add missing)" : "Shortcuts: Quick Add active (Panel missing)")
                : "Set shortcuts (click to copy & edit config)")
            shortcut: root.detectedPanelShortcut + " / " + root.detectedQuickAddShortcut
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
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
            color: (root.panelShortcutRegistered && root.quickAddShortcutRegistered) ? Color.accent
              : ((root.panelShortcutRegistered || root.quickAddShortcutRegistered) ? "#e67e22"
              : (root.shortcutState === "commented" ? "#e67e22" : Color.urgent))
            border.color: Color.menu.background
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: (root.panelShortcutRegistered && root.quickAddShortcutRegistered) ? "✓"
                : ((root.panelShortcutRegistered || root.quickAddShortcutRegistered) ? "!" : "✕")
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
            border.color: (root.cursorActive && root.focusSection === "profiles" && root.currentFilter === "all")
              ? Color.foreground
              : (root.currentFilter === "all" ? Color.accent : Color.menu.border)
            border.width: (root.cursorActive && root.focusSection === "profiles" && root.currentFilter === "all") ? 2 : 1

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
              border.color: (root.cursorActive && root.focusSection === "profiles" && root.currentFilter === modelData)
                ? Color.foreground
                : (root.currentFilter === modelData ? Color.accent : Color.menu.border)
              border.width: (root.cursorActive && root.focusSection === "profiles" && root.currentFilter === modelData) ? 2 : 1

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
          GradientStop { position: 1.0; color: Qt.rgba(root.cardBackground.r, root.cardBackground.g, root.cardBackground.b, 0) }
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
          GradientStop { position: 0.0; color: Qt.rgba(root.cardBackground.r, root.cardBackground.g, root.cardBackground.b, 0) }
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
        background: BorderSurface {
          color: newProfileInput.activeFocus
            ? Util.alpha(Color.accent, 0.08)
            : Style.controlFill(false, newProfileInput.hovered, root.barForeground, Color.accent)
          borderSpec: newProfileInput.activeFocus
            ? Border.flat(Color.accent, 2)
            : (newProfileInput.hovered ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent) : Border.controlSpec("normal", root.barForeground, Color.accent))
          radius: Style.cornerRadius
        }
        onAccepted: {
          if (text.trim() !== "") {
            var p = TodoStore.cleanProfileName(text)
            root.addProfile(p)
            root.currentFilter = p
            text = ""
            root.addingProfile = false
            root.focusSection = "profiles"
            root.cursorActive = true
            root.releaseFocus()
          }
        }
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          text = ""
          root.addingProfile = false
          root.focusSection = "profiles"
          root.cursorActive = true
          root.releaseFocus()
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
            root.focusSection = "profiles"
            root.cursorActive = true
            root.releaseFocus()
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
        background: BorderSurface {
          readonly property bool isNavFocused: root.cursorActive && (root.focusSection === "input") && !newTodoField.activeFocus
          color: newTodoField.activeFocus
            ? Util.alpha(Color.accent, 0.08)
            : Style.controlFill(false, newTodoField.hovered, root.barForeground, Color.accent)
          borderSpec: newTodoField.activeFocus
            ? Border.flat(Color.accent, 2)
            : (isNavFocused
                ? Border.flat(Color.accent, 1)
                : (newTodoField.hovered ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent)
                                        : Border.controlSpec("normal", root.barForeground, Color.accent)))
          radius: Style.cornerRadius
        }
        onActiveFocusChanged: {
          if (activeFocus) {
            root.focusSection = "input"
            root.cursorActive = true
          }
        }
        onAccepted: {
          var parsed = TodoStore.parseTaskInput(text)
          if (parsed.title && parsed.title.trim().length > 0) {
            var prof = (root.currentFilter !== "all") ? root.currentFilter : null
            root.addTodo(text, "", prof, null)
            text = ""
          }
        }

        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.focusSection = "input"
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onPressed: function(event) {
          if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            event.accepted = true
            root.activateSearch()
          }
        }

        Keys.onDownPressed: function(event) {
          event.accepted = true
          if (root.filteredTodos.length > 0) {
            root.focusSection = "tasks"
            root.cursorIndex = 0
            root.ensureTaskVisible(0, false)
          } else {
            root.focusSection = "footer"
            root.footerButtonIndex = 0
          }
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onUpPressed: function(event) {
          event.accepted = true
          root.focusSection = "profiles"
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onTabPressed: function(event) {
          event.accepted = true
          if (root.filteredTodos.length > 0) {
            root.focusSection = "tasks"
            root.cursorIndex = 0
            root.ensureTaskVisible(0, false)
          } else {
            root.focusSection = "footer"
            root.footerButtonIndex = 0
          }
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onBacktabPressed: function(event) {
          event.accepted = true
          root.focusSection = "profiles"
          root.cursorActive = true
          root.releaseFocus()
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
        tooltipText: ""
        onClicked: {
          var parsed = TodoStore.parseTaskInput(newTodoField.text)
          if (parsed.title && parsed.title.trim().length > 0) {
            var prof = (root.currentFilter !== "all") ? root.currentFilter : null
            root.addTodo(newTodoField.text, "", prof, null)
            newTodoField.text = ""
          }
        }

        HoverHandler { id: addBtnHover }
        Ui.ShortcutToolTip {
          visible: addBtnHover.hovered
          description: "Add task"
          shortcut: "Enter"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }
      }
    }

    // Search row (expandable via / or Ctrl+F or searchBtn)
    Row {
      id: searchRow
      visible: root.searchActive
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: searchField
        width: parent.width - closeSearchBtn.implicitWidth - Style.space(6)
        placeholderText: "Search tasks, notes, tags, #profiles..."
        font.pixelSize: Style.font.caption
        text: root.searchQuery
        onTextChanged: {
          root.searchQuery = text
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
          } else {
            root.closeSearch()
          }
        }

        Keys.onReturnPressed: function(event) {
          event.accepted = true
          var q = searchField.text.trim()
          if (q.startsWith("#")) {
            var matchedProfs = TodoStore.searchProfiles(root.store, q)
            if (matchedProfs && matchedProfs.length > 0) {
              root.currentFilter = matchedProfs[0]
              root.closeSearch()
              return
            }
          }
          if (root.filteredTodos.length > 0) {
            root.focusSection = "tasks"
            root.cursorIndex = 0
            root.ensureTaskVisible(0, false)
          } else {
            root.focusSection = "footer"
            root.footerButtonIndex = 0
          }
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onDownPressed: function(event) {
          event.accepted = true
          if (root.filteredTodos.length > 0) {
            root.focusSection = "tasks"
            root.cursorIndex = 0
            root.ensureTaskVisible(0, false)
          } else {
            root.focusSection = "footer"
            root.footerButtonIndex = 0
          }
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onTabPressed: function(event) {
          event.accepted = true
          if (root.filteredTodos.length > 0) {
            root.focusSection = "tasks"
            root.cursorIndex = 0
            root.ensureTaskVisible(0, false)
          } else {
            root.focusSection = "footer"
            root.footerButtonIndex = 0
          }
          root.cursorActive = true
          root.releaseFocus()
        }

        Keys.onBacktabPressed: function(event) {
          event.accepted = true
          root.focusSection = "input"
          root.cursorActive = true
          root.releaseFocus()
        }
      }

      PanelActionButton {
        id: closeSearchBtn
        size: Style.space(26)
        iconText: searchField.text.length > 0 ? "✕" : "󰅖"
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: Color.muted
        hoverColor: Color.accent
        tooltipText: ""
        onClicked: {
          if (searchField.text.length > 0) {
            searchField.text = ""
            root.searchQuery = ""
          } else {
            root.closeSearch()
          }
        }

        HoverHandler { id: closeSearchBtnHover }
        Ui.ShortcutToolTip {
          visible: closeSearchBtnHover.hovered
          description: searchField.text.length > 0 ? "Clear search query" : "Close search bar"
          shortcut: "Esc"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }
      }
    }

    // Empty state
    Text {
      visible: root.filteredTodos.length === 0
      text: (root.searchActive && root.searchQuery.trim().length > 0)
        ? ('󰍉 No tasks matching "' + (root.searchQuery.length > 25 ? (root.searchQuery.slice(0, 22) + "…") : root.searchQuery) + '"\nPress Esc to clear search')
        : (root.currentFilter === "all"
            ? "No tasks yet. Type a task above and press Enter!"
            : ("No tasks in #" + (root.currentFilter.length > 20 ? (root.currentFilter.slice(0, 18) + "…") : root.currentFilter) + ". Add one above!"))
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

      Behavior on contentY {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      HoverHandler {
        id: listHoverHandler
        onHoveredChanged: {
          if (!hovered) {
            root.mouseMovementDetected = false
          }
        }
      }

      Column {
        id: todoListCol
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          id: todoListRepeater
          model: root.filteredTodos

          Item {
            id: delegateRoot
            required property var modelData
            required property int index

            readonly property bool isPendingCompletion: root.pendingCompletionIds.indexOf(delegateRoot.modelData.id) !== -1
            readonly property bool isSlidingOut: root.slidingOutTaskIds.indexOf(delegateRoot.modelData.id) !== -1
            readonly property bool isJustCompleted: root.justCompletedTaskIds.indexOf(delegateRoot.modelData.id) !== -1
            readonly property bool isDone: Boolean(delegateRoot.modelData.done || isPendingCompletion)
            readonly property bool isFirstCompleted: delegateRoot.modelData.done && !isPendingCompletion && (delegateRoot.index === 0 || !root.filteredTodos[delegateRoot.index - 1].done)
            readonly property bool isHiddenByFold: delegateRoot.modelData.done && !isPendingCompletion && !root.completedFoldOpen

            readonly property alias descAreaInstance: itemRow.descAreaInstance
            function updateModelData(data) {
              delegateRoot.modelData = data
              if (itemRow) itemRow.modelData = data
            }
            function ensureReminderVisible(idx) {
              if (itemRow && itemRow.ensureReminderVisible) {
                itemRow.ensureReminderVisible(idx)
              }
            }
            function ensureReassignProfileVisible(idx) {
              if (itemRow && itemRow.ensureReassignProfileVisible) {
                itemRow.ensureReassignProfileVisible(idx)
              }
            }

            width: parent.width
            visible: (!isHiddenByFold || isFirstCompleted) && (implicitHeight > 0)
            clip: isSlidingOut
            implicitHeight: {
              if (isSlidingOut) return 0
              var h = 0
              if (isFirstCompleted) h += completedHeader.implicitHeight + (isHiddenByFold ? 0 : Style.space(4))
              if (!isHiddenByFold) h += itemRow.implicitHeight + (rowSep.visible ? (rowSep.implicitHeight + Style.space(4)) : 0)
              return h
            }
            height: implicitHeight

            Behavior on implicitHeight {
              enabled: delegateRoot.isSlidingOut || delegateRoot.isHiddenByFold
              NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
            }

            // Completed fold section header (rendered directly above the first completed task)
            Item {
              id: completedHeader
              visible: delegateRoot.isFirstCompleted
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              implicitHeight: visible ? Style.space(26) : 0
              height: implicitHeight

              // Left divider line
              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: foldPill.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.menu.border
                opacity: 0.6
              }

              // Centered fold toggle button / pill
              Rectangle {
                id: foldPill
                anchors.centerIn: parent
                implicitWidth: foldRow.implicitWidth + Style.space(12)
                implicitHeight: Style.space(18)
                radius: height / 2
                color: foldHover.hovered ? Color.menu.selectedBackground : "transparent"
                border.color: foldHover.hovered ? Color.menu.border : "transparent"
                border.width: 1

                Row {
                  id: foldRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.completedFoldOpen ? "󰅃" : "󰅀"
                    color: foldHover.hovered ? Color.accent : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Completed (" + root.completedCount + ")"
                    color: foldHover.hovered ? (root.barForeground || Color.foreground) : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.space(9)
                    font.bold: true
                  }
                }

                HoverHandler {
                  id: foldHover
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.completedFoldOpen = !root.completedFoldOpen
                  }
                }
              }

              // Right divider line
              Rectangle {
                anchors.left: foldPill.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.menu.border
                opacity: 0.6
              }
            }

            Rectangle {
              id: itemRow
              property var modelData: delegateRoot.modelData
              property int index: delegateRoot.index
              anchors.top: delegateRoot.isFirstCompleted ? completedHeader.bottom : parent.top
              anchors.topMargin: delegateRoot.isFirstCompleted ? Style.space(4) : 0
              anchors.left: parent.left
              anchors.right: parent.right
              visible: !delegateRoot.isHiddenByFold

              readonly property alias descAreaInstance: descArea
              readonly property bool hasNotes: Boolean(itemRow.modelData.description && itemRow.modelData.description.trim().length > 0)
              readonly property bool hasChips: Boolean(itemRow.modelData.repo || (itemRow.modelData.tags && itemRow.modelData.tags.length > 0) || itemRow.modelData.reminder)
              readonly property bool hasBadges: hasChips
              readonly property bool isEditing: root.editingTaskId === itemRow.modelData.id
              readonly property bool isCursorSelected: root.cursorActive && (root.focusSection === "tasks") && (delegateRoot.index === root.cursorIndex)
              readonly property bool isHeaderFocused: isEditing || (isCursorSelected && (!isExpanded || root.expandedSubSection === "header"))
              readonly property bool isExpanded: root.expandedTaskId === itemRow.modelData.id
              readonly property bool isDone: delegateRoot.isDone
              readonly property bool isOverdueTask: !isDone && TodoStore.isOverdue(itemRow.modelData)
              readonly property bool isDueTodayTask: !isDone && !isOverdueTask && Boolean(itemRow.modelData.reminder) && (new Date(itemRow.modelData.reminder).toDateString() === new Date().toDateString())

              function ensureReminderVisible(idx) {
                if (reminderPillsFlickable) {
                  reminderPillsFlickable.ensureVisible(idx)
                }
              }

              function ensureReassignProfileVisible(idx) {
                if (profReassignFlickable) {
                  profReassignFlickable.ensureVisible(idx)
                }
              }

              width: parent.width
              clip: (itemRowHeightAnim && itemRowHeightAnim.running) || delegateRoot.isSlidingOut
              implicitHeight: delegateRoot.isHiddenByFold ? 0 : (isExpanded
                ? (expandedContent.implicitHeight + Style.space(16))
                : (Style.space(34) + (hasNotes ? Style.space(18) : 0) + (hasBadges ? Style.space(22) : 0)))
              height: implicitHeight
              radius: Style.cornerRadius
              color: isHeaderFocused
                ? Util.alpha(Color.accent, 0.12)
                : (delegateRoot.isPendingCompletion
                  ? Util.alpha(Color.accent, 0.08)
                  : (isExpanded
                    ? Color.menu.selectedBackground
                    : (rowHoverHandler.hovered ? Color.menu.selectedBackground : "transparent")))
              border.color: isHeaderFocused
                ? Color.accent
                : (isExpanded ? Color.menu.border : "transparent")
              border.width: isHeaderFocused ? 1.5 : (isExpanded ? 1 : 0)

              opacity: delegateRoot.isSlidingOut ? 0.0 : 1.0

              Behavior on opacity {
                NumberAnimation { duration: 220 }
              }

              transform: Translate {
                id: rowSlideTranslate
                y: delegateRoot.isSlidingOut ? Style.space(24) : 0

                Behavior on y {
                  NumberAnimation { duration: 250; easing.type: Easing.InCubic }
                }
              }

              Component.onCompleted: {
                if (delegateRoot.isJustCompleted) {
                  justCompletedAnim.restart()
                }
              }

              Connections {
                target: delegateRoot
                function onIsJustCompletedChanged() {
                  if (delegateRoot.isJustCompleted) {
                    justCompletedAnim.restart()
                  }
                }
              }

              SequentialAnimation {
                id: justCompletedAnim
                PropertyAction { target: rowSlideTranslate; property: "y"; value: -Style.space(16) }
                NumberAnimation { target: rowSlideTranslate; property: "y"; to: 0; duration: 260; easing.type: Easing.OutBack }
              }

              Behavior on color { ColorAnimation { duration: 150 } }

              Behavior on implicitHeight {
                NumberAnimation {
                  id: itemRowHeightAnim
                  duration: 200
                  easing.type: Easing.OutCubic
                  onRunningChanged: {
                    if (!running && itemRow.isExpanded) {
                      root.ensureTaskVisible(delegateRoot.index, true)
                    }
                  }
                }
              }

              HoverHandler {
                id: rowHoverHandler
              }

              onIsExpandedChanged: {
                if (itemRow.isExpanded) {
                  root.descArea = descArea
                  var profs = TodoStore.getSortedProfiles(root.store, false, "")
                  var curIdx = profs.indexOf(itemRow.modelData.profile)
                  if (curIdx >= 0) {
                    root.expandedProfileIndex = curIdx
                    Qt.callLater(function() {
                      itemRow.ensureReassignProfileVisible(curIdx)
                    })
                  }
                } else if (root.descArea === descArea) {
                  root.descArea = null
                }
              }

              function toggleExpand() {
                root.savePendingNotes()
                root.cursorIndex = delegateRoot.index
                root.focusSection = "tasks"
                root.cursorActive = true
                if (itemRow.isExpanded) {
                  root.expandedTaskId = -1
                  root.expandedViaKeyboard = false
                  root.expandedSubSection = "header"
                } else {
                  root.expandedTaskId = itemRow.modelData.id
                  root.expandedViaKeyboard = true
                  root.expandedSubSection = "header"
                  root.ensureTaskVisible(delegateRoot.index, true)
                }
              }

              MouseArea {
                id: rowMouseArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: itemRow.isExpanded ? (itemHeaderCol.height + Style.space(16)) : parent.height
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: {
                  if (!root.mouseMovementDetected) {
                    root.mouseMovementDetected = true
                  }
                }
                onClicked: {
                  itemRow.toggleExpand()
                }
              }

              Column {
                id: expandedContent
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.top: itemRow.isExpanded ? parent.top : undefined
                anchors.topMargin: itemRow.isExpanded ? Style.space(8) : 0
                anchors.verticalCenter: !itemRow.isExpanded ? parent.verticalCenter : undefined
                height: implicitHeight
                spacing: Style.space(6)

                // Primary header block (Title + Actions + Chips if present)
                Column {
                  id: itemHeaderCol
                  width: parent.width
                  height: implicitHeight
                  spacing: Style.space(3)

                  // Row 1: Checkbox + Full-width Title + Action buttons
                  Item {
                    id: titleRowItem
                    width: parent.width
                    implicitHeight: Math.max(Style.space(22), Math.max(checkBtn.implicitHeight, Math.max(titleLabel.implicitHeight, Math.max(titleEditor.implicitHeight, rowActions.implicitHeight))))
                    height: implicitHeight

                    // Checkbox on the left
                    Ui.TaskCheck {
                      id: checkBtn
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      checked: itemRow.isDone
                      isOverdue: itemRow.isOverdueTask
                      isDueToday: itemRow.isDueTodayTask
                      bar: root.bar
                      barForeground: root.barForeground
                      warningColor: root.warningColor
                      onClicked: {
                        root.cursorIndex = delegateRoot.index
                        root.focusSection = "tasks"
                        root.toggleTodo(itemRow.modelData.id)
                      }
                    }

                    // Indicators and action buttons
                    Row {
                      id: rowActions
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      // Expand / Collapse details button
                      PanelActionButton {
                        id: rowExpandBtn
                        anchors.verticalCenter: parent.verticalCenter
                        size: Style.space(22)
                        iconText: itemRow.isExpanded ? "󰅃" : "󰅀"
                        fontSize: Style.font.caption
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        foreground: Color.muted
                        hoverColor: Color.accent
                        tooltipText: ""
                        onClicked: {
                          itemRow.toggleExpand()
                        }

                        HoverHandler { id: rowExpandHover }
                        Ui.ShortcutToolTip {
                          visible: rowExpandHover.hovered
                          description: itemRow.isExpanded ? "Hide details" : "Show notes & reminders"
                          shortcut: "Enter"
                          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        }
                      }

                      // Edit title button
                      PanelActionButton {
                        id: rowEditBtn
                        anchors.verticalCenter: parent.verticalCenter
                        size: Style.space(22)
                        iconText: "󰏫"
                        fontSize: Style.font.caption
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        foreground: Color.muted
                        hoverColor: Color.accent
                        tooltipText: ""
                        onClicked: {
                          root.cursorIndex = delegateRoot.index
                          root.focusSection = "tasks"
                          root.cursorActive = true
                          root.startEditingTask(itemRow.modelData.id)
                        }

                        HoverHandler { id: rowEditHover }
                        Ui.ShortcutToolTip {
                          visible: rowEditHover.hovered
                          description: "Edit title"
                          shortcut: "r / F2"
                          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        }
                      }

                      // Remove button
                      PanelActionButton {
                        id: rowDeleteBtn
                        anchors.verticalCenter: parent.verticalCenter
                        size: Style.space(22)
                        iconText: "󰅙"
                        fontSize: Style.font.caption
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        foreground: Color.muted
                        hoverColor: root.bar ? root.bar.urgent : Color.urgent
                        tooltipText: ""
                        onClicked: {
                          root.removeTodo(itemRow.modelData.id)
                        }

                        HoverHandler { id: rowDeleteHover }
                        Ui.ShortcutToolTip {
                          visible: rowDeleteHover.hovered
                          description: "Delete task"
                          shortcut: "x"
                          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        }
                      }
                    }

                    // Inline profile indicator (shown when viewing "all" and task has no chips)
                    Text {
                      id: profInlineLabel
                      visible: root.currentFilter === "all" && Boolean(itemRow.modelData.profile) && !itemRow.hasChips
                      anchors.right: rowActions.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      verticalAlignment: Text.AlignVCenter
                      width: Math.min(implicitWidth, parent.width * 0.28)
                      text: "#" + (itemRow.modelData.profile || "")
                      color: Color.muted
                      opacity: itemRow.isDone ? 0.4 : 0.65
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(8.5)
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignRight

                      HoverHandler { id: profInlineHover }
                      PanelToolTip {
                        visible: profInlineHover.hovered && profInlineLabel.truncated
                        text: "#" + (itemRow.modelData.profile || "")
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }

                    // Title text (stretches cleanly between checkBtn and profInlineLabel/rowActions)
                    Text {
                      id: titleLabel
                      visible: root.editingTaskId !== itemRow.modelData.id
                      anchors.left: checkBtn.right
                      anchors.leftMargin: Style.space(8)
                      anchors.right: profInlineLabel.visible ? profInlineLabel.left : rowActions.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      verticalAlignment: Text.AlignVCenter
                      text: TodoStore.capitalizeTitle(itemRow.modelData.title || "")
                      color: itemRow.isDone ? Color.muted : root.barForeground
                      opacity: itemRow.isDone ? 0.55 : 1.0
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: itemRow.isHeaderFocused
                      elide: Text.ElideRight

                      Behavior on opacity {
                        NumberAnimation { duration: 180 }
                      }

                      Behavior on color {
                        ColorAnimation { duration: 180 }
                      }

                      MouseArea {
                        id: titleClickArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: {
                          root.cursorIndex = delegateRoot.index
                          root.focusSection = "tasks"
                          root.cursorActive = true
                          root.startEditingTask(itemRow.modelData.id)
                        }
                        onClicked: {
                          itemRow.toggleExpand()
                        }
                      }

                      HoverHandler {
                        id: titleHover
                      }

                      PanelToolTip {
                        visible: (titleHover.hovered || titleClickArea.containsMouse) && titleLabel.truncated
                        text: TodoStore.capitalizeTitle(itemRow.modelData.title || "")
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }

                    // Inline Title Editor (shown when editingTaskId matches)
                    TextField {
                      id: titleEditor
                      visible: root.editingTaskId === itemRow.modelData.id
                      anchors.left: checkBtn.right
                      anchors.leftMargin: Style.space(8)
                      anchors.right: profInlineLabel.visible ? profInlineLabel.left : rowActions.left
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      color: root.barForeground
                      topPadding: Style.space(2)
                      bottomPadding: Style.space(2)
                      leftPadding: Style.space(6)
                      rightPadding: Style.space(6)
                      verticalAlignment: Text.AlignVCenter
                      background: BorderSurface {
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Color.accent, 1.5)
                        radius: Style.cornerRadius
                      }
                      onVisibleChanged: {
                        if (visible) {
                          text = itemRow.modelData.title || ""
                          forceActiveFocus()
                          selectAll()
                        }
                      }
                      onAccepted: {
                        root.commitEditingTask(itemRow.modelData.id, text)
                      }
                      Keys.onEscapePressed: function(event) {
                        event.accepted = true
                        root.cancelEditingTask()
                      }
                      onActiveFocusChanged: {
                        if (!activeFocus && root.editingTaskId === itemRow.modelData.id) {
                          root.commitEditingTask(itemRow.modelData.id, text)
                        }
                      }
                    }

                    // Strikethrough line that sweeps from left to right on completion
                    Rectangle {
                      id: strikeLine
                      anchors.left: titleLabel.left
                      anchors.verticalCenter: titleLabel.verticalCenter
                      height: Style.space(1.5)
                      radius: height / 2
                      color: itemRow.isDone ? Color.muted : "transparent"
                      visible: opacity > 0.01 && root.editingTaskId !== itemRow.modelData.id
                      opacity: itemRow.isDone ? 0.8 : 0.0
                      width: itemRow.isDone ? Math.min(titleLabel.contentWidth, titleLabel.width) : 0

                      Behavior on width {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                      }
                      Behavior on opacity {
                        NumberAnimation { duration: 160 }
                      }
                    }
                  }

                  // Row 2: Note preview line (visible when collapsed and notes exist)
                  Item {
                    id: notePreviewLine
                    width: parent.width
                    implicitHeight: (visible && !itemRow.isExpanded) ? Style.space(16) : 0
                    height: implicitHeight
                    visible: !itemRow.isExpanded && itemRow.hasNotes

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: checkBtn.width + Style.space(8)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      verticalAlignment: Text.AlignVCenter
                      text: (itemRow.modelData.description || "").replace(/[\r\n]+/g, " ").trim()
                      color: Color.muted
                      opacity: 0.8
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(8.5)
                      font.italic: true
                      elide: Text.ElideRight
                      maximumLineCount: 1

                      HoverHandler { id: notePreviewHover }
                      PanelToolTip {
                        visible: notePreviewHover.hovered
                        text: itemRow.modelData.description || ""
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }
                  }

                  // Row 3 (Sub-line): Profile tag, Repo chip, and Tag chips (aligned under title)
                  Item {
                    id: metadataLine
                    width: parent.width
                    implicitHeight: (visible && !itemRow.isExpanded) ? Style.space(20) : 0
                    height: implicitHeight
                    visible: !itemRow.isExpanded && itemRow.hasBadges

                    // Profile indicator docked on the right
                    Text {
                      id: profLabel
                      visible: root.currentFilter === "all" && Boolean(itemRow.modelData.profile)
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      verticalAlignment: Text.AlignVCenter
                      width: Math.min(implicitWidth, parent.width * 0.3)
                      text: "#" + (itemRow.modelData.profile || "")
                      color: Color.muted
                      opacity: 0.65
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(8.5)
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignRight

                      HoverHandler { id: profHover }
                      PanelToolTip {
                        visible: profHover.hovered && profLabel.truncated
                        text: "#" + (itemRow.modelData.profile || "")
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }

                    // Chips row (Reminder, Repo, Tags) aligned under the title, with comfortable height
                    Item {
                      id: chipsContainer
                      anchors.left: parent.left
                      anchors.leftMargin: checkBtn.width + Style.space(8)
                      anchors.right: profLabel.visible ? profLabel.left : parent.right
                      anchors.rightMargin: profLabel.visible ? Style.space(6) : 0
                      anchors.verticalCenter: parent.verticalCenter
                      height: Style.space(20)
                      clip: true

                      Row {
                        id: chipsRow
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        // Reminder chip
                        Ui.Chip {
                          id: remBadge
                          visible: Boolean(itemRow.modelData.reminder)
                          anchors.verticalCenter: parent.verticalCenter
                          variant: "time"
                          text: TodoStore.formatReminder(itemRow.modelData.reminder)
                          isOverdue: itemRow.isOverdueTask
                          isDueToday: itemRow.isDueTodayTask
                          isDone: itemRow.isDone
                          warningColor: root.warningColor
                          tooltipText: {
                            if (!itemRow.modelData.reminder) return ""
                            var d = new Date(itemRow.modelData.reminder)
                            var prefix = itemRow.isOverdueTask ? "Overdue: " : (itemRow.isDueTodayTask ? "Due today: " : "Reminder: ")
                            return prefix + (isNaN(d.getTime()) ? itemRow.modelData.reminder : d.toLocaleString()) + "\nClick to configure reminders"
                          }
                          maximumWidth: Style.space(110)
                          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                          onClicked: {
                            root.savePendingNotes()
                            root.cursorIndex = delegateRoot.index
                            root.expandedTaskId = itemRow.modelData.id
                            root.expandedViaKeyboard = true
                            root.expandedSubSection = "reminders"
                            root.expandedReminderIndex = 0
                            root.ensureTaskVisible(delegateRoot.index, true)
                          }
                        }

                        // Repo badge (displays clean name without owner, does not touch location)
                        Ui.Chip {
                          id: repoBadge
                          visible: Boolean(itemRow.modelData.repo)
                          anchors.verticalCenter: parent.verticalCenter
                          variant: "location"
                          iconText: "󰊤"
                          text: root.cleanRepoName(itemRow.modelData.repo)
                          tooltipText: {
                            var r = itemRow.modelData.repo || ""
                            var loc = itemRow.modelData.location
                            if (loc && loc.localPath) {
                              return "Repository: " + r + "\nPath: " + loc.localPath + "\nClick to open codebase in editor"
                            }
                            return "Repository: " + r
                          }
                          maximumWidth: Style.space(95)
                          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                          onClicked: {
                            if (itemRow.modelData.location && itemRow.modelData.location.localPath) {
                              root.openCodebase(itemRow.modelData)
                            }
                          }
                        }

                        // Tag chips
                        Repeater {
                          model: itemRow.modelData.tags || []

                          Ui.Chip {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + modelData
                            chipColor: Color.muted
                            maximumWidth: Style.space(65)
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                          }
                        }
                      }
                    }
                  }
                }

                // Expanded Details Section
                Column {
                  id: expandedDetailsCol
                  visible: itemRow.isExpanded
                  opacity: itemRow.isExpanded ? 1.0 : 0.0
                  width: parent.width
                  height: visible ? implicitHeight : 0
                  spacing: Style.space(6)

                  Behavior on opacity {
                    NumberAnimation {
                      duration: 180
                      easing.type: Easing.OutCubic
                    }
                  }

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
                  isNavFocused: (root.expandedSubSection === "notes" && !editorActiveFocus)

                  Component.onCompleted: {
                    if (itemRow.isExpanded) {
                      root.descArea = descArea
                    }
                  }
                  onEditorActiveFocusChanged: {
                    if (editorActiveFocus) {
                      root.descArea = descArea
                      root.expandedSubSection = "notes"
                    }
                  }
                  onEscapePressed: {
                    root.focusSection = "tasks"
                    root.cursorActive = true
                    root.expandedViaKeyboard = true
                    root.expandedSubSection = "notes"
                    if (root.descArea) {
                      if (typeof root.descArea.releaseFocus === "function") {
                        root.descArea.releaseFocus()
                      } else if (root.descArea.textArea) {
                        root.descArea.textArea.focus = false
                      }
                      root.descArea.focus = false
                    }
                    root.releaseFocus()
                    root.savePendingNotes()
                  }
                  onSubmitted: {
                    root.focusSection = "tasks"
                    root.cursorActive = true
                    root.expandedViaKeyboard = true
                    root.expandedSubSection = "notes"
                    if (root.descArea) {
                      if (typeof root.descArea.releaseFocus === "function") {
                        root.descArea.releaseFocus()
                      } else if (root.descArea.textArea) {
                        root.descArea.textArea.focus = false
                      }
                      root.descArea.focus = false
                    }
                    root.releaseFocus()
                    root.savePendingNotes()
                  }
                  onTabPressed: function(direction) {
                    root.focusSection = "tasks"
                    root.cursorActive = true
                    root.expandedViaKeyboard = true
                    if (root.descArea) {
                      if (typeof root.descArea.releaseFocus === "function") {
                        root.descArea.releaseFocus()
                      } else if (root.descArea.textArea) {
                        root.descArea.textArea.focus = false
                      }
                      root.descArea.focus = false
                    }
                    root.releaseFocus()
                    root.savePendingNotes()
                    root.handleTab(direction)
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

                // Reminder Presets Row (Compact single-line horizontal scrollable row with auto-scroll)
                Item {
                  id: reminderContainer
                  width: parent.width
                  implicitHeight: Style.space(26)

                  Row {
                    id: reminderLabelRow
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: (Style.space(22) - implicitHeight) / 2
                    spacing: Style.space(4)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰥔 Reminder:"
                      color: (root.expandedSubSection === "reminders") ? Color.accent : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(9.5)
                      font.bold: root.expandedSubSection === "reminders"
                    }
                  }

                  Ui.ReminderPills {
                    id: reminderPillsFlickable
                    anchors.left: reminderLabelRow.right
                    anchors.leftMargin: Style.space(4)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    fadeColor: root.expandedCardColor
                    presets: root.reminderPresets
                    selectedValue: (itemRow.modelData.reminder && itemRow.modelData.reminder.preset) ? itemRow.modelData.reminder.preset : (itemRow.modelData.reminder || "")
                    hasReminder: Boolean(itemRow.modelData.reminder)
                    focusedIndex: root.expandedReminderIndex
                    isNavFocused: root.expandedSubSection === "reminders"
                    bar: root.bar
                    barForeground: root.barForeground
                    onReminderSelected: function(val, idx) {
                      root.expandedReminderIndex = idx
                      itemRow.ensureReminderVisible(idx)
                      var freshRem = (typeof TodoStore.computePresetReminder === "function")
                        ? TodoStore.computePresetReminder(idx)
                        : val
                      root.updateTodo(itemRow.modelData.id, { reminder: freshRem })
                    }
                    onClearSelected: function(idx) {
                      root.expandedReminderIndex = idx
                      itemRow.ensureReminderVisible(idx)
                      root.updateTodo(itemRow.modelData.id, { reminder: null })
                    }
                  }
                }

                // Profile selector row (Compact single-line horizontal scrollable row with auto-scroll)
                Item {
                  id: profReassignContainer
                  width: parent.width
                  implicitHeight: Style.space(26)

                  Row {
                    id: profLabelRow
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: (Style.space(22) - implicitHeight) / 2
                    spacing: Style.space(4)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Profile:"
                      color: (root.expandedSubSection === "profiles") ? Color.accent : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(9.5)
                      font.bold: root.expandedSubSection === "profiles"
                    }
                  }

                  Ui.ProfileSelector {
                    id: profReassignFlickable
                    anchors.left: profLabelRow.right
                    anchors.leftMargin: Style.space(4)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    fadeColor: root.expandedCardColor
                    profiles: TodoStore.getSortedProfiles(root.store, false, "")
                    selectedProfile: itemRow.modelData.profile || ""
                    focusedIndex: root.expandedProfileIndex
                    isNavFocused: root.expandedSubSection === "profiles"
                    bar: root.bar
                    barForeground: root.barForeground
                    onProfileSelected: function(prof, idx) {
                      root.expandedProfileIndex = idx
                      itemRow.ensureReassignProfileVisible(idx)
                      root.updateTodo(itemRow.modelData.id, { profile: prof })
                    }
                  }
                }

                // Location & Codebase Context Row (if task has location, repo, or tags)
                Item {
                  width: parent.width
                  implicitHeight: Math.max(locRow.implicitHeight, openLocBtn.implicitHeight)
                  visible: Boolean(itemRow.modelData.location || itemRow.modelData.repo || (itemRow.modelData.tags && itemRow.modelData.tags.length > 0))

                  Row {
                    id: locRow
                    anchors.left: parent.left
                    anchors.right: openLocBtn.visible ? openLocBtn.left : parent.right
                    anchors.rightMargin: openLocBtn.visible ? Style.space(6) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰉋 Target:"
                      color: Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(9.5)
                    }

                    Ui.Chip {
                      anchors.verticalCenter: parent.verticalCenter
                      variant: "location"
                      iconText: (itemRow.modelData.location && itemRow.modelData.location.repo) ? "󰊤" : "󰉋"
                      text: {
                        var loc = itemRow.modelData.location
                        if (loc) {
                          if (loc.repo) {
                            var str = loc.repo
                            if (loc.subpath) str += "/" + loc.subpath
                            return str
                          }
                          return loc.localPath || ""
                        }
                        return itemRow.modelData.repo || ""
                      }
                      tooltipText: {
                        var loc = itemRow.modelData.location
                        if (loc && loc.localPath) {
                          return "Target path: " + loc.localPath + "\nClick to open codebase in editor"
                        }
                        return ""
                      }
                      maximumWidth: Style.space(180)
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      onClicked: {
                        if (itemRow.modelData.location && itemRow.modelData.location.localPath) {
                          root.openCodebase(itemRow.modelData)
                        }
                      }
                    }

                    // Display tag chips if any
                    Repeater {
                      model: itemRow.modelData.tags || []
                      Ui.Chip {
                        required property string modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: "#" + modelData
                        chipColor: Color.muted
                        maximumWidth: Style.space(70)
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      }
                    }
                  }

                  // Open Codebase Button
                  Button {
                    id: openLocBtn
                    visible: Boolean(itemRow.modelData.location && itemRow.modelData.location.localPath)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰏫"
                    text: "Codebase"
                    fontSize: Style.space(9)
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    bordered: true
                    hasCursor: (root.expandedSubSection === "codebase")
                    tooltipText: "Open codebase directory in editor"
                    onClicked: {
                      root.openCodebase(itemRow.modelData)
                    }
                  }
                }
              }
            }
          }

            PanelSeparator {
              id: rowSep
              anchors.top: itemRow.bottom
              anchors.topMargin: Style.space(2)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              strength: 0.08
              foreground: root.barForeground || Color.foreground
              visible: !delegateRoot.isHiddenByFold &&
                       !delegateRoot.isSlidingOut &&
                       (delegateRoot.index < root.filteredTodos.length - 1) &&
                       !(!delegateRoot.modelData.done &&
                         root.filteredTodos[delegateRoot.index + 1] &&
                         root.filteredTodos[delegateRoot.index + 1].done &&
                         root.pendingCompletionIds.indexOf(root.filteredTodos[delegateRoot.index + 1].id) === -1)
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
          id: clearBtn
          iconText: "󰃢"
          text: footerContainer.wrapNeeded ? "" : (root.currentFilter === "all" ? "Clear" : ("Clear #" + root.currentFilter))
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 0)
          tooltipText: ""
          onClicked: root.clearCompleted(root.currentFilter)

          HoverHandler { id: clearBtnHover }
          Ui.ShortcutToolTip {
            visible: clearBtnHover.hovered
            description: root.currentFilter === "all" ? "Archive and clear completed tasks" : ("Archive and clear completed tasks in #" + root.currentFilter)
            shortcut: "c"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        Button {
          id: archiveBtn
          iconText: "󰋚"
          text: footerContainer.wrapNeeded ? "" : "Archive"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 1)
          tooltipText: ""
          onClicked: root.openArchive()

          HoverHandler { id: archiveBtnHover }
          Ui.ShortcutToolTip {
            visible: archiveBtnHover.hovered
            description: "Open todos-archive.json in editor"
            shortcut: "d"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
        }

        Button {
          id: editBtn
          iconText: "󰏫"
          text: footerContainer.wrapNeeded ? "" : "Edit"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 2)
          tooltipText: ""
          onClicked: root.openEditor()

          HoverHandler { id: editBtnHover }
          Ui.ShortcutToolTip {
            visible: editBtnHover.hovered
            description: "Open todos.json in editor"
            shortcut: "e"
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }
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
        hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 3)
        tooltipText: ""
        onClicked: root.openQuickAdd()

        HoverHandler { id: quickAddBtnHover }
        Ui.ShortcutToolTip {
          visible: quickAddBtnHover.hovered
          description: "Open Quick Add modal"
          shortcut: "A / " + root.detectedQuickAddShortcut
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }
      }
    }
  }

  // Keybindings & Vim motions search / cheat-sheet overlay
  Ui.HelpModal {
    id: helpModal
    isOpen: root.showKeyHelp
    bar: root.bar
    barForeground: root.barForeground
    detectedShortcut: root.detectedPanelShortcut
    detectedPanelShortcut: root.detectedPanelShortcut
    detectedQuickAddShortcut: root.detectedQuickAddShortcut
    onCloseRequested: {
      root.showKeyHelp = false
      root.releaseFocus()
    }
  }

  // Git Snapshots & Undo overlay modal
  Ui.GitModal {
    id: gitModal
    isOpen: root.showGitModal
    bar: root.bar
    barWidget: root.barWidget
    barForeground: root.barForeground
    onCloseRequested: {
      root.showGitModal = false
      root.returnFocusRequested()
    }
  }
}
