import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore
import "./ui" as Ui

BarWidget {
  id: root
  moduleName: "tablerase.ardoise"

  property var store: TodoStore.defaultStore()
  readonly property var todos: store.todos || []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  readonly property string activeProfile: store.activeProfile || "personal"
  readonly property var profiles: store.profiles || ["personal", "work"]

  readonly property string todoFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos.json"
  readonly property string archiveFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos-archive.json"

  function loadTodos(raw) {
    root.store = TodoStore.normalize(raw)
  }

  function saveStore(newStore) {
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
  }

  function addTodo(title, description, profile, reminder) {
    saveStore(TodoStore.addTodo(root.store, title, description, profile, reminder))
  }

  function toggleTodo(id) {
    saveStore(TodoStore.toggleTodo(root.store, id))
  }

  function removeTodo(id) {
    saveStore(TodoStore.removeTodo(root.store, id))
  }

  function updateTodo(id, fields) {
    saveStore(TodoStore.updateTodo(root.store, id, fields))
  }

  function clearCompleted(profile) {
    var result = TodoStore.archiveCompleted(root.store, profile, archiveFile.text())
    saveStore(result.updatedStore)
    archiveFile.setText(JSON.stringify(result.updatedArchive, null, 2) + "\n")
  }

  function setActiveProfile(profile) {
    var s = TodoStore.cloneStore(root.store)
    s.activeProfile = TodoStore.cleanProfileName(profile)
    saveStore(s)
  }

  function addProfile(name) {
    saveStore(TodoStore.addProfile(root.store, name))
  }

  function removeProfile(name) {
    saveStore(TodoStore.removeProfile(root.store, name))
  }

  function getTooltip() {
    var lines = []

    // 1. Navigation and controls first
    lines.push("󰍽 [L] Panel   󰍽 [R] Quick Add   󰍽 [M] Edit")

    // Empty state
    if (root.pendingCount === 0) {
      lines.push("──────────────────────────────────────────")
      lines.push("󰄲 Inbox zero! All tasks completed.")
      return lines.join("\n")
    }

    lines.push("──────────────────────────────────────────")

    // 2. Completion Progress & Counts
    var completedCount = 0
    if (root.store && Array.isArray(root.store.todos)) {
      for (var i = 0; i < root.store.todos.length; i++) {
        if (root.store.todos[i].done) completedCount++
      }
    }
    var allTasks = root.pendingCount + completedCount
    var pct = allTasks > 0 ? Math.round((completedCount / allTasks) * 100) : 0
    var meter = TodoStore.makeProgressBar(completedCount, allTasks, 8)
    lines.push("󰄲 " + root.pendingCount + " pending   󰁯 " + completedCount + " done   " + meter + " " + pct + "%")

    // 3. Urgency & Deadlines (if any reminders)
    var urg = TodoStore.getTaskUrgencyBreakdown(root.store)
    var urgItems = []
    if (urg.overdue > 0) {
      urgItems.push("󰀦 " + urg.overdue + " overdue" + (urg.earliestOverdueDiff ? " (" + urg.earliestOverdueDiff + ")" : ""))
    }
    if (urg.dueToday > 0) {
      urgItems.push("󰥔 " + urg.dueToday + " due today" + (urg.nextDueDiff ? " (" + urg.nextDueDiff + ")" : ""))
    } else if (urg.upcoming > 0 && urg.nextDueDiff) {
      urgItems.push("󰥔 next " + urg.nextDueDiff)
    }

    if (urgItems.length > 0) {
      lines.push(urgItems.join("   "))
    }

    // 4. Profiles with Glyphs
    lines.push("──────────────────────────────────────────")
    var sortedProfs = TodoStore.getSortedProfiles(root.store, true, "")
    var profItems = []
    for (var j = 0; j < sortedProfs.length; j++) {
      var p = sortedProfs[j]
      var c = TodoStore.getPendingCount(root.store, p)
      if (c > 0) {
        var glyph = TodoStore.getProfileGlyph(p)
        profItems.push(glyph + " " + c + " " + p)
      }
    }

    if (profItems.length > 0) {
      if (profItems.length <= 3) {
        lines.push(profItems.join("   "))
      } else {
        var top3 = profItems.slice(0, 3).join("   ")
        var extra = profItems.length - 3
        lines.push(top3 + "   (+" + extra + " more)")
      }
    }

    return lines.join("\n")
  }

  // ---- Panel lifecycle contract for Omarchy Quattro shell
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("barWidget" in target) target.barWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  // Ensure config folder, todos.json, and todos-archive.json exist so FileView can watch them
  Process {
    id: initFileProc
    command: ["bash", "-c", "mkdir -p \"$HOME/.config/omarchy\" && [ -f \"$HOME/.config/omarchy/todos.json\" ] || echo '{\"version\":1,\"activeProfile\":\"personal\",\"profiles\":[\"personal\",\"work\"],\"todos\":[]}' > \"$HOME/.config/omarchy/todos.json\"; [ -f \"$HOME/.config/omarchy/todos-archive.json\" ] || echo '{\"version\":1,\"archived\":[]}' > \"$HOME/.config/omarchy/todos-archive.json\""]
    onExited: {
      todoFile.reload()
      archiveFile.reload()
    }
  }

  Component.onCompleted: initFileProc.running = true

  FileView {
    id: todoFile
    path: root.todoFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadTodos(text())
    onLoadFailed: root.loadTodos("{}")
    onFileChanged: reload()
  }

  FileView {
    id: archiveFile
    path: root.archiveFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  function widgetScreenName(w) {
    if (!w) return ""
    var win = null
    if (w.button && w.button.QsWindow) win = w.button.QsWindow.window
    if (!win && w.QsWindow) win = w.QsWindow.window
    if (!win && w.parent && w.parent.QsWindow) win = w.parent.QsWindow.window
    return (win && win.screen) ? String(win.screen.name || "") : ""
  }

  readonly property string screenName: root.widgetScreenName(root)

  function allWidgets() {
    var items = (root.bar && typeof root.bar.moduleWidgets === "function")
      ? root.bar.moduleWidgets(root.moduleName)
      : []
    return (items && items.length > 0) ? items : [root]
  }

  function findTargetWidget() {
    var widgets = root.allWidgets()
    if (widgets.length <= 1) return widgets[0] || root

    // If any widget's panel is currently open, target that one so toggle/close acts on it
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && widgets[i].opened) return widgets[i]
    }

    // Otherwise find the widget on the currently focused monitor
    var focusedName = (typeof Hyprland !== "undefined" && Hyprland && Hyprland.focusedMonitor)
      ? String(Hyprland.focusedMonitor.name || "")
      : ""

    if (focusedName) {
      for (var j = 0; j < widgets.length; j++) {
        var w = widgets[j]
        if (w && root.widgetScreenName(w) === focusedName) return w
      }
    }

    return widgets[0] || root
  }

  IpcHandler {
    target: "tablerase.ardoise"

    // Route open/close/toggle to the BarWidget on the focused monitor via
    // root.bar.moduleWidgets() and Hyprland.focusedMonitor.
    function toggle(): string {
      var target = root.findTargetWidget()
      if (target && typeof target.toggle === "function") {
        target.toggle()
      } else {
        root.toggle()
      }
      return "ok"
    }
    function open(): string {
      var widgets = root.allWidgets()
      var target = root.findTargetWidget()
      // Close other open panels so only the focused monitor panel is shown
      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i] && widgets[i] !== target && widgets[i].opened && typeof widgets[i].close === "function") {
          widgets[i].close()
        }
      }
      if (target && typeof target.open === "function") {
        target.open()
      } else {
        root.open()
      }
      return "ok"
    }
    function close(): string {
      var widgets = root.allWidgets()
      for (var i = 0; i < widgets.length; i++) {
        if (widgets[i] && widgets[i].opened && typeof widgets[i].close === "function") {
          widgets[i].close()
        }
      }
      root.close()
      return "ok"
    }
    function add(task: string): string { root.addTodo(task); return "ok" }
    function toggleTodo(idStr: string): string {
      var id = Number(idStr)
      if (!isNaN(id)) { root.toggleTodo(id); return "ok" }
      return "invalid_id"
    }
    function remove(idStr: string): string {
      var id = Number(idStr)
      if (!isNaN(id)) { root.removeTodo(id); return "ok" }
      return "invalid_id"
    }
    function update(idStr: string, fieldsJson: string): string {
      var id = Number(idStr)
      if (isNaN(id)) return "invalid_id"
      try {
        var fields = JSON.parse(fieldsJson)
        root.updateTodo(id, fields)
        return "ok"
      } catch (e) {
        return "invalid_json"
      }
    }
    function clear(): string { root.clearCompleted(); return "ok" }
    function count(): string { return String(root.pendingCount) }
    function list(): string { return JSON.stringify(root.todos) }
    function profiles(): string { return JSON.stringify(root.profiles) }
    function setProfile(profile: string): string { root.setActiveProfile(profile); return "ok" }
    function archived(): string { return archiveFile.text() || "{\"version\":1,\"archived\":[]}" }
    function archiveCount(): string { return String(TodoStore.getArchivedCount(archiveFile.text())) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? barSize : readout.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? readout.implicitHeight + scaledVerticalPadding * 2 : barSize
    tooltipText: root.getTooltip()
    active: false

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      } else if (buttonCode === Qt.RightButton) {
        if (root.bar && root.bar.shell) {
          root.close()
          root.bar.shell.summon(root.moduleName, "{}")
        }
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.bar) root.bar.run("omarchy-launch-editor " + root.todoFilePath)
      }
    }

    Row {
      id: readout
      anchors.centerIn: parent
      spacing: Style.space(6)

      Ui.InboxIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: width
        color: button.foreground
      }

      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.pendingCount > 0
        text: String(root.pendingCount)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: button.foreground
      }
    }
  }
}
