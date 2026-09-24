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
  property var store: (barWidget && barWidget.store) ? barWidget.store : TodoStore.defaultStore()
  readonly property var todos: store ? (store.todos || []) : []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  readonly property var profiles: store ? (store.profiles || ["personal", "work"]) : ["personal", "work"]
  readonly property var visibleProfiles: TodoStore.getSortedProfiles(root.store, true, root.currentFilter)

  readonly property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color cardBackground: Color.popups.background

  property string currentFilter: "all"
  property var expandedTaskId: -1
  property bool expandedViaKeyboard: false
  property bool mouseMovementDetected: false
  property bool addingProfile: false
  property string shortcutState: "active"
  property string detectedShortcut: "SUPER + SHIFT + T"
  property bool shortcutRegistered: false
  property string moduleName: "tablerase.ardoise"
  property var descArea: null

  property string focusSection: "tasks"
  property int cursorIndex: 0
  property bool cursorActive: false
  property int footerButtonIndex: 0
  property bool showKeyHelp: false
  property string keyHelpSearch: ""
  property string expandedSubSection: "header" // "header" | "notes" | "reminders" | "profiles" | "codebase"
  property int expandedReminderIndex: 0
  property int expandedProfileIndex: 0

  function cleanRepoName(repo) {
    if (!repo) return ""
    var str = String(repo).trim()
    var idx = str.lastIndexOf("/")
    return (idx !== -1 && idx < str.length - 1) ? str.slice(idx + 1) : str
  }

  function openCodebase(task) {
    if (!task || !task.location || !task.location.localPath) return
    root.savePendingNotes()
    root.closeRequested()
    var locPath = task.location.localPath
    if (locPath.startsWith("~")) locPath = Quickshell.env("HOME") + locPath.slice(1)
    if (root.bar) root.bar.run("omarchy-launch-editor \"" + locPath + "\"")
  }

  function handleEscape() {
    if (root.showKeyHelp) {
      root.showKeyHelp = false
      return true
    }
    if (root.focusSection === "tasks" && root.expandedSubSection !== "header") {
      root.expandedSubSection = "header"
      return true
    }
    if (root.expandedTaskId !== -1) {
      root.savePendingNotes()
      root.expandedTaskId = -1
      root.expandedViaKeyboard = false
      root.expandedSubSection = "header"
      return true
    }
    return false
  }

  onVisibleChanged: {
    if (!visible) {
      savePendingNotes()
      expandedTaskId = -1
      expandedViaKeyboard = false
      mouseMovementDetected = false
      cursorActive = false
      focusSection = "tasks"
      showKeyHelp = false
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
      keyHelpSearch = ""
      Qt.callLater(function() {
        if (typeof keySearchField !== "undefined" && keySearchField) {
          keySearchField.forceActiveFocus()
        }
      })
    }
  }

  onExpandedTaskIdChanged: {
    expandedSubSection = "header"
    expandedReminderIndex = 0
    expandedProfileIndex = 0
    if (expandedTaskId !== -1) {
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

  function handleMove(dx, dy) {
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (!root.expandedViaKeyboard && root.expandedTaskId !== -1) {
      root.savePendingNotes()
      root.expandedTaskId = -1
    }
    if (root.focusSection === "tasks") {
      var currentTask = (root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) ? root.filteredTodos[root.cursorIndex] : null
      var isCurExpanded = Boolean(currentTask && root.expandedTaskId === currentTask.id)

      if (isCurExpanded) {
        var hasLoc = Boolean(currentTask.location && currentTask.location.localPath)
        if (dy > 0) {
          if (root.expandedSubSection === "header") {
            root.expandedSubSection = "notes"
          } else if (root.expandedSubSection === "notes") {
            root.expandedSubSection = "reminders"
            root.expandedReminderIndex = 0
          } else if (root.expandedSubSection === "reminders") {
            root.expandedSubSection = "profiles"
            root.expandedProfileIndex = 0
          } else if (root.expandedSubSection === "profiles") {
            if (hasLoc) {
              root.expandedSubSection = "codebase"
            } else {
              if (root.cursorIndex < root.filteredTodos.length - 1) {
                root.cursorIndex++
                root.expandedSubSection = "header"
                root.ensureTaskVisible(root.cursorIndex, false)
              } else {
                root.focusSection = "footer"
                root.footerButtonIndex = 0
              }
            }
          } else if (root.expandedSubSection === "codebase") {
            if (root.cursorIndex < root.filteredTodos.length - 1) {
              root.cursorIndex++
              root.expandedSubSection = "header"
              root.ensureTaskVisible(root.cursorIndex, false)
            } else {
              root.focusSection = "footer"
              root.footerButtonIndex = 0
            }
          }
          return
        } else if (dy < 0) {
          if (root.expandedSubSection === "codebase") {
            root.expandedSubSection = "profiles"
          } else if (root.expandedSubSection === "profiles") {
            root.expandedSubSection = "reminders"
          } else if (root.expandedSubSection === "reminders") {
            root.expandedSubSection = "notes"
          } else if (root.expandedSubSection === "notes") {
            root.expandedSubSection = "header"
          } else if (root.expandedSubSection === "header") {
            if (root.cursorIndex > 0) {
              root.cursorIndex--
              root.expandedSubSection = "header"
              root.ensureTaskVisible(root.cursorIndex, false)
            } else {
              root.focusSection = "input"
              Qt.callLater(function() { newTodoField.forceActiveFocus() })
            }
          }
          return
        } else if (dx !== 0) {
          if (root.expandedSubSection === "reminders") {
            var maxRem = root.reminderPresets.length + (currentTask.reminder ? 1 : 0)
            root.expandedReminderIndex = Math.max(0, Math.min(maxRem - 1, root.expandedReminderIndex + dx))
            return
          } else if (root.expandedSubSection === "profiles") {
            var allProfs = TodoStore.getSortedProfiles(root.store, false, "")
            root.expandedProfileIndex = Math.max(0, Math.min(allProfs.length - 1, root.expandedProfileIndex + dx))
            return
          }
        }
      }

      if (dy < 0) {
        if (root.cursorIndex > 0) {
          root.cursorIndex--
          root.expandedSubSection = "header"
          root.ensureTaskVisible(root.cursorIndex, false)
        } else {
          // At top of task list: move UP into task input field!
          root.focusSection = "input"
          Qt.callLater(function() { newTodoField.forceActiveFocus() })
        }
      } else if (dy > 0) {
        if (root.filteredTodos.length > 0 && root.cursorIndex < root.filteredTodos.length - 1) {
          root.cursorIndex++
          root.expandedSubSection = "header"
          root.ensureTaskVisible(root.cursorIndex, false)
        } else {
          // At bottom of task list or empty: move DOWN into footer buttons!
          root.focusSection = "footer"
          root.footerButtonIndex = 0
        }
      } else if (dx !== 0) {
        cycleProfileFilter(dx)
      }
    } else if (root.focusSection === "profiles") {
      if (dx !== 0) {
        cycleProfileFilter(dx)
      } else if (dy > 0) {
        // From profiles moving DOWN: move into task input field!
        root.focusSection = "input"
        Qt.callLater(function() { newTodoField.forceActiveFocus() })
      }
    } else if (root.focusSection === "footer") {
      if (dx !== 0) {
        root.footerButtonIndex = Math.max(0, Math.min(3, root.footerButtonIndex + dx))
      } else if (dy < 0) {
        // From footer moving UP: return to bottom of task list if tasks exist, else input!
        if (root.filteredTodos.length > 0) {
          root.focusSection = "tasks"
          root.cursorIndex = root.filteredTodos.length - 1
          root.expandedSubSection = "header"
          root.ensureTaskVisible(root.cursorIndex, false)
        } else {
          root.focusSection = "input"
          Qt.callLater(function() { newTodoField.forceActiveFocus() })
        }
      }
    }
  }

  property bool _suppressActivateOnReturn: false

  function handleActivate() {
    if (_suppressActivateOnReturn) return
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (root.focusSection === "tasks") {
      if (root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
        var task = root.filteredTodos[root.cursorIndex]
        if (task) {
          if (root.expandedTaskId === task.id && root.expandedSubSection !== "header") {
            if (root.expandedSubSection === "notes") {
              if (root.descArea) root.descArea.forceActiveFocus()
            } else if (root.expandedSubSection === "reminders") {
              if (root.expandedReminderIndex < root.reminderPresets.length) {
                root.updateTodo(task.id, { reminder: root.reminderPresets[root.expandedReminderIndex].value })
              } else {
                root.updateTodo(task.id, { reminder: null })
              }
            } else if (root.expandedSubSection === "profiles") {
              var profs = TodoStore.getSortedProfiles(root.store, false, "")
              if (root.expandedProfileIndex >= 0 && root.expandedProfileIndex < profs.length) {
                root.updateTodo(task.id, { profile: profs[root.expandedProfileIndex] })
              }
            } else if (root.expandedSubSection === "codebase") {
              root.openCodebase(task)
            }
          } else {
            root.toggleTodo(task.id)
          }
        }
      }
    } else if (root.focusSection === "footer") {
      triggerFooterButton(root.footerButtonIndex)
    }
  }

  function handleReturn() {
    _suppressActivateOnReturn = true
    Qt.callLater(function() { _suppressActivateOnReturn = false })
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (root.focusSection === "tasks") {
      if (root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
        var task = root.filteredTodos[root.cursorIndex]
        if (task) {
          if (root.expandedTaskId === task.id && root.expandedSubSection !== "header") {
            if (root.expandedSubSection === "notes") {
              if (root.descArea) root.descArea.forceActiveFocus()
            } else if (root.expandedSubSection === "reminders") {
              if (root.expandedReminderIndex < root.reminderPresets.length) {
                root.updateTodo(task.id, { reminder: root.reminderPresets[root.expandedReminderIndex].value })
              } else {
                root.updateTodo(task.id, { reminder: null })
              }
            } else if (root.expandedSubSection === "profiles") {
              var profs = TodoStore.getSortedProfiles(root.store, false, "")
              if (root.expandedProfileIndex >= 0 && root.expandedProfileIndex < profs.length) {
                root.updateTodo(task.id, { profile: profs[root.expandedProfileIndex] })
              }
            } else if (root.expandedSubSection === "codebase") {
              root.openCodebase(task)
            }
          } else {
            root.savePendingNotes()
            if (root.expandedTaskId === task.id) {
              root.expandedTaskId = -1
              root.expandedViaKeyboard = false
              root.expandedSubSection = "header"
            } else {
              root.expandedTaskId = task.id
              root.expandedViaKeyboard = true
              root.expandedSubSection = "header"
            }
          }
        }
      }
    } else if (root.focusSection === "footer") {
      triggerFooterButton(root.footerButtonIndex)
    }
  }

  function handleDelete() {
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (root.focusSection === "tasks") {
      if (root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
        var task = root.filteredTodos[root.cursorIndex]
        if (task) {
          root.removeTodo(task.id)
          if (root.cursorIndex >= root.filteredTodos.length) {
            root.cursorIndex = Math.max(0, root.filteredTodos.length - 1)
          }
        }
      }
    }
  }

  function handleTextKey(text) {
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (text === "?") {
      root.showKeyHelp = !root.showKeyHelp
      return
    }
    if (text === "A") {
      root.openQuickAdd()
      return
    }
    if (text === "c") {
      root.clearCompleted(root.currentFilter)
      return
    }
    if (text === "d") {
      root.openArchive()
      return
    }
    if (text === "e") {
      var currentTaskId = null
      if (root.focusSection === "tasks" && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
        var t = root.filteredTodos[root.cursorIndex]
        if (t) currentTaskId = t.id
      }
      root.openEditor(currentTaskId)
      return
    }
    if (text === "i" && root.focusSection === "tasks" && root.expandedSubSection === "notes") {
      if (root.descArea) root.descArea.forceActiveFocus()
      return
    }
    if (text === "i" || text === "a" || text === "/") {
      root.focusSection = "input"
      Qt.callLater(function() { newTodoField.forceActiveFocus() })
    } else if (text === "g" && root.focusSection === "tasks") {
      root.cursorIndex = 0
      root.ensureTaskVisible(0, false)
    } else if (text === "G" && root.focusSection === "tasks") {
      root.cursorIndex = Math.max(0, root.filteredTodos.length - 1)
      root.ensureTaskVisible(root.cursorIndex, false)
    }
  }

  function handleTab(direction) {
    root.cursorActive = true
    root.mouseMovementDetected = false
    if (!root.expandedViaKeyboard && root.expandedTaskId !== -1) {
      root.savePendingNotes()
      root.expandedTaskId = -1
    }

    if (root.focusSection === "tasks") {
      var currentTask = (root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) ? root.filteredTodos[root.cursorIndex] : null
      var isCurExpanded = Boolean(currentTask && root.expandedTaskId === currentTask.id)
      if (isCurExpanded) {
        var hasLoc = Boolean(currentTask.location && currentTask.location.localPath)
        if (direction > 0) {
          if (root.expandedSubSection === "header") {
            root.expandedSubSection = "notes"
            return true
          } else if (root.expandedSubSection === "notes") {
            root.expandedSubSection = "reminders"
            root.expandedReminderIndex = 0
            return true
          } else if (root.expandedSubSection === "reminders") {
            root.expandedSubSection = "profiles"
            root.expandedProfileIndex = 0
            return true
          } else if (root.expandedSubSection === "profiles") {
            if (hasLoc) {
              root.expandedSubSection = "codebase"
              return true
            }
          }
        } else if (direction < 0) {
          if (root.expandedSubSection === "codebase") {
            root.expandedSubSection = "profiles"
            return true
          } else if (root.expandedSubSection === "profiles") {
            root.expandedSubSection = "reminders"
            return true
          } else if (root.expandedSubSection === "reminders") {
            root.expandedSubSection = "notes"
            return true
          } else if (root.expandedSubSection === "notes") {
            root.expandedSubSection = "header"
            return true
          }
        }
      }
    }

    var sections = ["profiles", "input", "tasks", "footer"]
    var currentIdx = sections.indexOf(root.focusSection)
    if (currentIdx === -1) currentIdx = 2
    var nextIdx = currentIdx + direction
    if (nextIdx < 0 || nextIdx >= sections.length) {
      return false
    }
    root.focusSection = sections[nextIdx]
    if (root.focusSection === "tasks") {
      root.expandedSubSection = "header"
    }
    if (root.focusSection === "input") {
      Qt.callLater(function() { newTodoField.forceActiveFocus() })
    } else {
      root.releaseFocus()
    }
    return true
  }

  function triggerFooterButton(idx) {
    if (idx === 0) root.clearCompleted(root.currentFilter)
    else if (idx === 1) root.openArchive()
    else if (idx === 2) root.openEditor()
    else if (idx === 3) root.openQuickAdd()
  }

  readonly property var filteredTodos: TodoStore.getFilteredTodos(root.store, root.currentFilter)
  readonly property int filteredPendingCount: TodoStore.getPendingCount(root.store, root.currentFilter)
  readonly property var reminderPresets: TodoStore.getReminderPresets()
  readonly property bool activeFocusBlocked: Boolean(
    (newTodoField && newTodoField.activeFocus) ||
    (descArea && descArea.editorActiveFocus) ||
    addingProfile ||
    (typeof keySearchField !== "undefined" && keySearchField && keySearchField.activeFocus)
  )

  readonly property var keybindingsList: [
    { key: "j / ↓", desc: "Next task", category: "Navigation" },
    { key: "k / ↑", desc: "Previous task", category: "Navigation" },
    { key: "h / l / ← / →", desc: "Cycle profile filters or footer buttons", category: "Navigation" },
    { key: "Tab / Shift+Tab", desc: "Switch section (profiles ↔ input ↔ tasks ↔ footer)", category: "Navigation" },
    { key: "g / G", desc: "Jump to top / bottom of task list", category: "Navigation" },
    { key: "Space", desc: "Toggle completed status of selected task", category: "Task Actions" },
    { key: "Enter / Return", desc: "Expand or collapse task details (notes & reminders)", category: "Task Actions" },
    { key: "x", desc: "Delete selected task", category: "Task Actions" },
    { key: "e", desc: "Open todos.json in editor (at task line if selected)", category: "Actions & Storage" },
    { key: "c", desc: "Archive and clear completed tasks in current profile", category: "Actions & Storage" },
    { key: "d", desc: "Open todos-archive.json in editor", category: "Actions & Storage" },
    { key: "i / a / <slash>", desc: "Focus new task input field", category: "Input & Create" },
    { key: "A", desc: "Open Quick Add modal", category: "Input & Create" },
    { key: "Shift+Enter", desc: "Insert newline in task notes", category: "Input & Create" },
    { key: "Esc", desc: "Leave input / editor or close panel", category: "Global" },
    { key: "? / Backspace", desc: "Toggle or dismiss keybindings help modal", category: "Global" },
    { key: root.detectedShortcut, desc: "Global shortcut: toggle Ardoise panel", category: "Global" }
  ]

  readonly property var filteredKeybindings: {
    var q = root.keyHelpSearch.toLowerCase().trim()
    if (!q) return root.keybindingsList
    return root.keybindingsList.filter(function(item) {
      return item.key.toLowerCase().includes(q) ||
             item.desc.toLowerCase().includes(q) ||
             item.category.toLowerCase().includes(q)
    })
  }

  signal closeRequested()
  signal shortcutClicked()
  signal switchPanelRequested(int direction)
  signal returnFocusRequested()

  function releaseFocus() {
    if (newTodoField) newTodoField.focus = false
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

  function openEditor(taskId) {
    savePendingNotes()
    var p = barWidget ? barWidget.todoFilePath : Quickshell.env("HOME") + "/.config/omarchy/todos.json"
    if (bar) {
      if (taskId) {
        var escapedPath = p.replace(/'/g, "'\\''")
        var cmd = "bash -c 'file=\"$1\"; tid=\"$2\"; line=$(grep -n \"\\\"id\\\": $tid\" \"$file\" 2>/dev/null | head -n1 | cut -d: -f1); ed_file=\"$HOME/.local/state/omarchy/defaults/editor\"; ed=\"\"; [ -f \"$ed_file\" ] && read -r ed < \"$ed_file\"; [ -z \"$ed\" ] && ed=\"nvim\"; if [ -n \"$line\" ]; then case \"${ed##*/}\" in hx|helix) exec omarchy-launch-editor \"$file:$line\" ;; code|codium|cursor) exec omarchy-launch-editor -g \"$file:$line\" ;; *) exec omarchy-launch-editor \"+$line\" \"$file\" ;; esac; else exec omarchy-launch-editor \"$file\"; fi' -- '" + escapedPath + "' '" + taskId + "'"
        bar.run(cmd)
      } else {
        bar.run("omarchy-launch-editor " + p)
      }
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

        Item {
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: brandRow.implicitWidth
          implicitHeight: brandRow.implicitHeight

          Row {
            id: brandRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            InboxIcon {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              height: width
              color: brandMouse.containsMouse ? Color.accent : (root.barForeground || Color.foreground)
              Behavior on color { ColorAnimation { duration: 120 } }
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
          id: helpBtn
          size: Style.space(26)
          iconText: "󰞋"
          fontSize: Style.font.subtitle
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: root.showKeyHelp ? Color.accent : Color.muted
          hoverColor: Color.accent
          tooltipText: "Shortcuts & Vim motions (?)"
          onClicked: {
            root.showKeyHelp = !root.showKeyHelp
            if (!root.showKeyHelp) {
              root.releaseFocus()
            }
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
        onActiveFocusChanged: {
          if (activeFocus) {
            root.focusSection = "input"
            root.cursorActive = true
          }
        }
        onAccepted: {
          if (text.trim() !== "") {
            var prof = (root.currentFilter !== "all") ? root.currentFilter : null
            root.addTodo(text, "", prof, null)
            text = ""
          }
        }

        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.focusSection = "tasks"
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

      Behavior on contentY {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      HoverHandler {
        id: listHoverHandler
        onHoveredChanged: {
          if (!hovered) {
            root.mouseMovementDetected = false
            if (root.expandedTaskId !== -1 && !root.expandedViaKeyboard) {
              listFoldTimer.restart()
            }
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
          if (root.expandedTaskId !== -1 && !root.expandedViaKeyboard) {
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
          id: todoListRepeater
          model: root.filteredTodos

          Rectangle {
            id: itemRow
            required property var modelData
            required property int index

            readonly property bool hasBadges: Boolean((root.currentFilter === "all" && itemRow.modelData.profile) || itemRow.modelData.repo || (itemRow.modelData.tags && itemRow.modelData.tags.length > 0))
            readonly property bool isCursorSelected: root.cursorActive && (root.focusSection === "tasks") && (index === root.cursorIndex)
            readonly property bool isHeaderFocused: isCursorSelected && (!isExpanded || root.expandedSubSection === "header")
            readonly property bool isExpanded: root.expandedTaskId === modelData.id
            readonly property bool isDone: Boolean(modelData.done)
            readonly property bool isOverdueTask: !isDone && TodoStore.isOverdue(modelData)
            readonly property bool isDueTodayTask: !isDone && !isOverdueTask && Boolean(modelData.reminder) && (new Date(modelData.reminder).toDateString() === new Date().toDateString())

            width: parent.width
            implicitHeight: isExpanded
              ? (expandedContent.implicitHeight + Style.space(14))
              : (hasBadges ? Style.space(48) : Style.space(34))
            radius: Style.cornerRadius
            color: isHeaderFocused
              ? Util.alpha(Color.accent, 0.12)
              : (isExpanded
                ? Color.menu.selectedBackground
                : (rowHoverHandler.hovered ? Color.menu.selectedBackground : "transparent"))
            border.color: isHeaderFocused
              ? Color.accent
              : (isExpanded
                ? Color.menu.border
                : (isOverdueTask ? Util.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.35) : (isDueTodayTask ? Util.alpha(Color.accent, 0.35) : "transparent")))
            border.width: isHeaderFocused ? 1.5 : (isExpanded || isOverdueTask || isDueTodayTask ? 1 : 0)

            Behavior on implicitHeight {
              NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
                onRunningChanged: {
                  if (!running && itemRow.isExpanded) {
                    root.ensureTaskVisible(itemRow.index, true)
                  }
                }
              }
            }

            // Subtle horizontal gradient tint for overdue and due-today tasks confined to left edge
            Rectangle {
              id: urgencyGradient
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Math.min(parent.width * 0.35, Style.space(110))
              radius: parent.radius
              color: "transparent"
              visible: itemRow.isOverdueTask || itemRow.isDueTodayTask
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                  position: 0.0
                  color: itemRow.isOverdueTask
                    ? Util.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.06)
                    : Util.alpha(Color.accent, 0.05)
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
                  if (!root.mouseMovementDetected) return
                  hoverFoldTimer.stop()
                  if (!itemRow.isExpanded) {
                    hoverExpandTimer.restart()
                  }
                } else {
                  hoverExpandTimer.stop()
                  if (itemRow.isExpanded && !root.expandedViaKeyboard) {
                    hoverFoldTimer.restart()
                  }
                }
              }
            }

            Timer {
              id: hoverExpandTimer
              interval: 1500
              repeat: false
              onTriggered: {
                if (rowHoverHandler.hovered && !itemRow.isExpanded && root.mouseMovementDetected) {
                  root.savePendingNotes()
                  root.cursorIndex = itemRow.index
                  root.expandedTaskId = itemRow.modelData.id
                  root.expandedViaKeyboard = false
                }
              }
            }

            Timer {
              id: hoverFoldTimer
              interval: 350
              repeat: false
              onTriggered: {
                if (itemRow.isExpanded && !rowHoverHandler.hovered && !root.expandedViaKeyboard) {
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
              hoverEnabled: true
              onPositionChanged: {
                if (!root.mouseMovementDetected) {
                  root.mouseMovementDetected = true
                  if (rowHoverHandler.hovered && !itemRow.isExpanded) {
                    hoverExpandTimer.restart()
                  }
                }
              }
              onClicked: {
                hoverExpandTimer.stop()
                hoverFoldTimer.stop()
                root.cursorIndex = itemRow.index
                root.focusSection = "tasks"
                root.cursorActive = true
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

              // Primary header block (Title + Actions + Chips if present)
              Column {
                id: itemHeaderCol
                width: parent.width
                spacing: Style.space(3)

                // Row 1: Checkbox + Full-width Title + Action buttons
                Item {
                  width: parent.width
                  implicitHeight: Style.space(26)

                  Row {
                    id: titleLeadRow
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

                    // Title text (takes all available width!)
                    Text {
                      id: titleLabel
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.max(Style.space(40), titleLeadRow.width - checkboxIcon.implicitWidth - titleLeadRow.spacing)
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
                        root.cursorIndex = itemRow.index
                        if (itemRow.isExpanded) {
                          root.expandedTaskId = -1
                          root.expandedViaKeyboard = false
                          root.expandedSubSection = "header"
                        } else {
                          root.expandedTaskId = itemRow.modelData.id
                          root.expandedViaKeyboard = true
                          root.expandedSubSection = "header"
                        }
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

                // Row 2 (Sub-line): Profile chip, Repo chip, and Tag chips (aligned under title)
                Row {
                  id: chipsRow
                  visible: itemRow.hasBadges
                  anchors.left: parent.left
                  anchors.leftMargin: checkboxIcon.implicitWidth + Style.space(6)
                  spacing: Style.space(4)

                  // Profile badge when viewing "All"
                  Rectangle {
                    id: profBadge
                    visible: root.currentFilter === "all" && Boolean(itemRow.modelData.profile)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Math.min(Style.space(85), profLabel.implicitWidth + Style.space(8))
                    implicitHeight: Style.space(16)
                    radius: implicitHeight / 2
                    color: Color.menu.background
                    border.color: Color.menu.border
                    border.width: 1

                    Text {
                      id: profLabel
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, profBadge.implicitWidth - Style.space(8))
                      text: {
                        var prof = itemRow.modelData.profile || ""
                        var r = root.cleanRepoName(itemRow.modelData.repo)
                        return "#" + prof + (r ? ("/" + r) : "")
                      }
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
                      visible: profBadgeHover.hovered && (profLabel.truncated || Boolean(itemRow.modelData.repo))
                      text: "#" + (itemRow.modelData.profile || "") + (itemRow.modelData.repo ? ("/" + itemRow.modelData.repo) : "")
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }

                  // Repo badge when filtered by profile
                  Rectangle {
                    id: repoBadge
                    visible: root.currentFilter !== "all" && Boolean(itemRow.modelData.repo)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Math.min(Style.space(85), repoLabel.implicitWidth + Style.space(8))
                    implicitHeight: Style.space(16)
                    radius: implicitHeight / 2
                    color: Util.alpha(Color.accent, 0.12)
                    border.color: Util.alpha(Color.accent, 0.35)
                    border.width: 1

                    Text {
                      id: repoLabel
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, repoBadge.implicitWidth - Style.space(8))
                      text: "󰊤 " + root.cleanRepoName(itemRow.modelData.repo)
                      color: Color.accent
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(8.5)
                      font.bold: true
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                    }

                    HoverHandler {
                      id: repoBadgeHover
                    }

                    PanelToolTip {
                      visible: repoBadgeHover.hovered
                      text: "Repo: " + (itemRow.modelData.repo || "")
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    }
                  }

                  // Tag chips
                  Repeater {
                    model: itemRow.modelData.tags || []

                    Rectangle {
                      required property string modelData
                      anchors.verticalCenter: parent.verticalCenter
                      implicitWidth: Math.min(Style.space(70), tagChipText.implicitWidth + Style.space(8))
                      implicitHeight: Style.space(16)
                      radius: implicitHeight / 2
                      color: Color.menu.background
                      border.color: Color.menu.border
                      border.width: 1

                      Text {
                        id: tagChipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Style.space(62))
                        text: "#" + parent.modelData
                        color: Color.muted
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(8.5)
                        elide: Text.ElideRight
                      }
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
                Rectangle {
                  id: descAreaWrapper
                  width: parent.width
                  implicitHeight: descArea.implicitHeight + ((root.expandedSubSection === "notes" && !descArea.editorActiveFocus) ? Style.space(4) : 0)
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.color: (root.expandedSubSection === "notes" && !descArea.editorActiveFocus) ? Color.accent : "transparent"
                  border.width: (root.expandedSubSection === "notes" && !descArea.editorActiveFocus) ? 1.5 : 0

                  TaskNotesArea {
                    id: descArea
                    width: parent.width
                    text: itemRow.modelData.description || ""
                    placeholderText: "Notes / description (Shift+Enter for newline)..."
                    bar: root.bar
                    foreground: root.barForeground
                    accentColor: Color.accent
                    Component.onCompleted: {
                      if (itemRow.isExpanded) {
                        root.descArea = descArea
                      }
                    }
                    onEditorActiveFocusChanged: {
                      if (editorActiveFocus) {
                        root.descArea = descArea
                      } else if (root.descArea === descArea && !editorActiveFocus) {
                        if (itemRow.isExpanded && !rowHoverHandler.hovered) {
                          hoverFoldTimer.restart()
                        }
                      }
                    }
                    onEscapePressed: {
                      root.savePendingNotes()
                      root.expandedSubSection = "notes"
                      root.releaseFocus()
                    }
                    onTabPressed: function(direction) {
                      root.savePendingNotes()
                      root.releaseFocus()
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
                }

                // Reminder Presets Row
                Row {
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰥔 Reminder:"
                    color: (root.expandedSubSection === "reminders") ? Color.accent : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.space(9.5)
                    font.bold: root.expandedSubSection === "reminders"
                  }

                  Repeater {
                    model: root.reminderPresets

                    Rectangle {
                      id: remPresetBtn
                      required property var modelData
                      required property int index
                      readonly property bool isSelected: itemRow.modelData.reminder === modelData.value
                      readonly property bool isNavFocused: (root.expandedSubSection === "reminders") && (root.expandedReminderIndex === index)

                      implicitWidth: remPresetText.implicitWidth + Style.space(8)
                      implicitHeight: Style.space(20)
                      radius: Style.cornerRadius
                      color: isSelected ? Color.accent : (isNavFocused ? Util.alpha(Color.accent, 0.2) : Color.menu.background)
                      border.color: isNavFocused ? Color.accent : (isSelected ? Color.accent : Color.menu.border)
                      border.width: isNavFocused ? 1.5 : 1
                      scale: isNavFocused ? 1.05 : 1.0
                      Behavior on scale { NumberAnimation { duration: 80 } }

                      Text {
                        id: remPresetText
                        anchors.centerIn: parent
                        text: remPresetBtn.modelData.label
                        color: remPresetBtn.isSelected ? "white" : (remPresetBtn.isNavFocused ? Color.accent : root.barForeground)
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(9)
                        font.bold: remPresetBtn.isSelected || remPresetBtn.isNavFocused
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.expandedReminderIndex = remPresetBtn.index
                          root.updateTodo(itemRow.modelData.id, { reminder: remPresetBtn.modelData.value })
                        }
                      }
                    }
                  }

                  // Clear reminder button
                  Rectangle {
                    id: clearRemBtn
                    readonly property bool isNavFocused: (root.expandedSubSection === "reminders") && (root.expandedReminderIndex === root.reminderPresets.length)
                    visible: Boolean(itemRow.modelData.reminder)
                    implicitWidth: clearRemText.implicitWidth + Style.space(8)
                    implicitHeight: Style.space(20)
                    radius: Style.cornerRadius
                    color: clearRemBtn.isNavFocused ? Util.alpha(Color.accent, 0.2) : Color.menu.background
                    border.color: clearRemBtn.isNavFocused ? Color.accent : Color.menu.border
                    border.width: clearRemBtn.isNavFocused ? 1.5 : 1
                    scale: clearRemBtn.isNavFocused ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 80 } }

                    Text {
                      id: clearRemText
                      anchors.centerIn: parent
                      text: "✕ Clear"
                      color: clearRemBtn.isNavFocused ? Color.accent : Color.muted
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.space(9)
                      font.bold: clearRemBtn.isNavFocused
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.expandedReminderIndex = root.reminderPresets.length
                        root.updateTodo(itemRow.modelData.id, { reminder: null })
                      }
                    }
                  }
                }

                // Profile selector row (Compact single-line horizontal scrollable row)
                Item {
                  id: profReassignContainer
                  width: parent.width
                  implicitHeight: Style.space(22)

                  Row {
                    id: profLabelRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
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

                  Flickable {
                    id: profReassignFlickable
                    anchors.left: profLabelRow.right
                    anchors.leftMargin: Style.space(4)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    contentWidth: profReassignRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                      id: profReassignRow
                      spacing: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter

                      Repeater {
                        id: profReassignRepeater
                        model: TodoStore.getSortedProfiles(root.store, false, "")

                        Rectangle {
                          id: profReassignBtn
                          required property string modelData
                          required property int index
                          readonly property bool isSelected: itemRow.modelData.profile === modelData
                          readonly property bool isNavFocused: (root.expandedSubSection === "profiles") && (root.expandedProfileIndex === index)

                          implicitWidth: profReassignText.implicitWidth + Style.space(10)
                          implicitHeight: Style.space(20)
                          radius: Style.cornerRadius
                          color: isSelected ? Color.accent : (isNavFocused ? Util.alpha(Color.accent, 0.2) : Color.menu.background)
                          border.color: isNavFocused ? Color.accent : (isSelected ? Color.accent : Color.menu.border)
                          border.width: isNavFocused ? 1.5 : 1
                          scale: isNavFocused ? 1.05 : 1.0
                          Behavior on scale { NumberAnimation { duration: 80 } }

                          Text {
                            id: profReassignText
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, Style.space(80))
                            text: profReassignBtn.modelData
                            color: profReassignBtn.isSelected ? "white" : (profReassignBtn.isNavFocused ? Color.accent : root.barForeground)
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.space(9)
                            font.bold: profReassignBtn.isSelected || profReassignBtn.isNavFocused
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root.expandedProfileIndex = profReassignBtn.index
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

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      implicitWidth: locContentRow.implicitWidth + Style.space(10)
                      implicitHeight: Style.space(20)
                      radius: Style.cornerRadius
                      color: Util.alpha(Color.accent, 0.12)
                      border.color: Util.alpha(Color.accent, 0.35)
                      border.width: 1

                      Row {
                        id: locContentRow
                        anchors.centerIn: parent
                        spacing: Style.space(4)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: (itemRow.modelData.location && itemRow.modelData.location.repo) ? "󰊤" : "󰉋"
                          color: Color.accent
                          font.family: Style.font.family
                          font.pixelSize: Style.space(9.5)
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
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
                          color: Color.accent
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.space(9)
                          font.bold: true
                          elide: Text.ElideMiddle
                          maximumLineCount: 1
                        }
                      }
                    }

                    // Display tag chips if any
                    Repeater {
                      model: itemRow.modelData.tags || []
                      Rectangle {
                        required property string modelData
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: tagLabel.implicitWidth + Style.space(8)
                        implicitHeight: Style.space(18)
                        radius: Style.cornerRadius
                        color: Color.menu.background
                        border.color: Color.menu.border
                        border.width: 1

                        Text {
                          id: tagLabel
                          anchors.centerIn: parent
                          text: "#" + modelData
                          color: Color.muted
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.space(8.5)
                        }
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
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 0)
          tooltipText: (root.currentFilter === "all" ? "Archive and clear completed tasks" : ("Archive and clear completed tasks in #" + root.currentFilter)) + " (c)"
          onClicked: root.clearCompleted(root.currentFilter)
        }

        Button {
          iconText: "󰋚"
          text: footerContainer.wrapNeeded ? "" : "Archive"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 1)
          tooltipText: "Open todos-archive.json in editor (d)"
          onClicked: root.openArchive()
        }

        Button {
          iconText: "󰏫"
          text: footerContainer.wrapNeeded ? "" : "Edit"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 2)
          tooltipText: "Open todos.json in editor (e)"
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
        hasCursor: root.cursorActive && (root.focusSection === "footer") && (root.footerButtonIndex === 3)
        tooltipText: "Open Quick Add modal (A / " + root.detectedShortcut + ")"
        onClicked: root.openQuickAdd()
      }
    }
  }

  // Keybindings & Vim motions search / cheat-sheet overlay
  Rectangle {
    id: keyHelpOverlay
    anchors.fill: parent
    visible: root.showKeyHelp
    z: 999
    color: Util.alpha(Color.popups.background, 0.96)
    radius: Style.cornerRadius

    MouseArea {
      anchors.fill: parent
      // Block mouse clicks from propagating through overlay
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      // Modal header
      Item {
        width: parent.width
        implicitHeight: Math.max(helpTitle.implicitHeight, closeHelpBtn.implicitHeight)

        Text {
          id: helpTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰞋 Keyboard & Vim Shortcuts"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        PanelActionButton {
          id: closeHelpBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(24)
          iconText: "󰅖"
          fontSize: Style.font.caption
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          foreground: Color.muted
          hoverColor: root.bar ? root.bar.urgent : Color.urgent
          tooltipText: "Close (Esc)"
          onClicked: {
            root.showKeyHelp = false
            root.releaseFocus()
          }
          Keys.onEscapePressed: {
            root.showKeyHelp = false
            root.releaseFocus()
          }
          Keys.onTabPressed: keySearchField.forceActiveFocus()
          Keys.onBacktabPressed: {
            helpFlickable.focus = true
            helpFlickable.forceActiveFocus()
          }
        }
      }

      // Search input to filter shortcuts
      TextField {
        id: keySearchField
        width: parent.width
        placeholderText: "Search shortcuts (e.g. vim, add, esc, tab)..."
        font.pixelSize: Style.font.caption
        text: root.keyHelpSearch
        onTextChanged: root.keyHelpSearch = text
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.showKeyHelp = false
          root.releaseFocus()
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Backspace && keySearchField.text.length === 0) {
            event.accepted = true
            root.showKeyHelp = false
            root.releaseFocus()
          }
        }
        Keys.onDownPressed: function(event) {
          event.accepted = true
          helpFlickable.focus = true
          helpFlickable.forceActiveFocus()
        }
        Keys.onTabPressed: function(event) {
          event.accepted = true
          helpFlickable.focus = true
          helpFlickable.forceActiveFocus()
        }
        Keys.onBacktabPressed: function(event) {
          event.accepted = true
          closeHelpBtn.forceActiveFocus()
        }
      }

      PanelSeparator { width: parent.width }

      // Filtered list of shortcuts
      Flickable {
        id: helpFlickable
        width: parent.width
        height: Math.max(Style.space(120), parent.height - y - Style.space(26))
        contentWidth: width
        contentHeight: helpListCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        focus: true

        property int selectedIndex: 0

        function ensureItemVisible() {
          var itemY = selectedIndex * Style.space(31)
          if (itemY < contentY) {
            contentY = itemY
          } else if (itemY + Style.space(31) > contentY + height) {
            contentY = Math.max(0, itemY + Style.space(31) - height)
          }
        }

        Keys.onUpPressed: function(event) {
          event.accepted = true
          if (selectedIndex > 0) {
            selectedIndex--
            ensureItemVisible()
          } else {
            keySearchField.forceActiveFocus()
          }
        }

        Keys.onDownPressed: function(event) {
          event.accepted = true
          if (selectedIndex < root.filteredKeybindings.length - 1) {
            selectedIndex++
            ensureItemVisible()
          }
        }

        Keys.onPressed: function(event) {
          if (event.text === "j") {
            event.accepted = true
            if (selectedIndex < root.filteredKeybindings.length - 1) {
              selectedIndex++
              ensureItemVisible()
            }
          } else if (event.text === "k") {
            event.accepted = true
            if (selectedIndex > 0) {
              selectedIndex--
              ensureItemVisible()
            } else {
              keySearchField.forceActiveFocus()
            }
          } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.text === "?") {
            event.accepted = true
            root.showKeyHelp = false
            root.releaseFocus()
          } else if (event.key === Qt.Key_Backtab) {
            event.accepted = true
            keySearchField.forceActiveFocus()
          } else if (event.key === Qt.Key_Tab) {
            event.accepted = true
            closeHelpBtn.forceActiveFocus()
          } else if (event.text && event.text.length === 1 && event.text !== "j" && event.text !== "k") {
            keySearchField.forceActiveFocus()
            keySearchField.text += event.text
            event.accepted = true
          }
        }

        ScrollBar.vertical: ScrollBar {
          policy: helpListCol.implicitHeight > helpFlickable.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        Column {
          id: helpListCol
          width: parent.width
          spacing: Style.space(5)

          Repeater {
            model: root.filteredKeybindings

            Rectangle {
              id: keyHelpRow
              required property var modelData
              required property int index
              readonly property bool isSelected: helpFlickable.activeFocus && (helpFlickable.selectedIndex === index)
              width: parent.width
              implicitHeight: Style.space(26)
              radius: Style.cornerRadius
              color: isSelected ? Util.alpha(Color.accent, 0.14) : Color.menu.selectedBackground
              border.color: isSelected ? Color.accent : Color.menu.border
              border.width: isSelected ? 1.5 : 1

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: keyLabel.implicitWidth + Style.space(8)
                  implicitHeight: Style.space(18)
                  radius: Style.space(4)
                  color: Util.alpha(Color.accent, 0.15)
                  border.color: Color.accent
                  border.width: 1

                  Text {
                    id: keyLabel
                    anchors.centerIn: parent
                    text: keyHelpRow.modelData.key
                    color: Color.accent
                    font.family: "monospace"
                    font.pixelSize: Style.space(9)
                    font.bold: true
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: keyHelpRow.modelData.desc
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: keyHelpRow.modelData.category
                color: Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.space(8.5)
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Press Esc or ? to close"
        color: Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.space(9)
      }
    }
  }
}
