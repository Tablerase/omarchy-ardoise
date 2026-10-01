import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore
import "./GitSync.js" as GitSync
import "./ui" as Ui

BarWidget {
  id: root
  moduleName: "tablerase.ardoise"

  property var store: TodoStore.defaultStore()
  readonly property var todos: store.todos || []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  // Glyph, color and badge number all come from this one resolution, so the
  // mark and its count can never describe different states. `pendingCount`
  // above stays the *total* and is used by the tooltip and the `count` IPC.
  readonly property var ladderState: TodoStore.getArdoiseIconState(store)
  readonly property string activeProfile: store.activeProfile || "personal"
  readonly property var profiles: store.profiles || ["personal", "work"]

  readonly property string pluginDirPath: (function() {
    var url = Qt.resolvedUrl(".").toString()
    var p = url.replace(/^file:\/\//, "").replace(/\/$/, "")
    return p && p !== "." ? p : (Quickshell.env("HOME") + "/.config/omarchy/plugins/tablerase.ardoise")
  })()
  readonly property string dataDirPath: (function() {
    var custom = Quickshell.env("ARDOISE_DATA_DIR")
    if (custom && custom.length > 0) return custom
    var home = Quickshell.env("HOME")
    if (home && home.length > 0) return home + "/.config/omarchy/tablerase.ardoise"
    return pluginDirPath + "/data"
  })()
  readonly property string todoFilePath: dataDirPath + "/todos.json"
  readonly property string archiveFilePath: dataDirPath + "/todos-archive.json"

  property string deviceName: Quickshell.env("HOSTNAME") || "omarchy"
  property string lastCommitAction: "Update tasks"
  property var gitSnapshots: []
  property string lastGitLog: "[]"
  property string remoteUrl: ""
  property string gitSyncStatus: "idle" // "idle" | "syncing" | "success" | "error"
  property string gitSyncMessage: ""
  property string recoveringHash: ""
  property string lastArchiveText: ""

  function getArchiveText() {
    return root.lastArchiveText || archiveFile.text() || "{\"version\":1,\"archived\":[]}"
  }

  function loadTodos(raw) {
    root.store = TodoStore.normalize(raw)
  }

  function triggerAutoCommit(actionName) {
    root.lastCommitAction = actionName || "Update tasks"
    autoCommitTimer.restart()
  }

  function saveStore(newStore, actionName) {
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
    root.triggerAutoCommit(actionName)
  }

  function addTodo(title, description, profile, reminder) {
    saveStore(TodoStore.addTodo(root.store, title, description, profile, reminder), "Add task: " + title)
  }

  function toggleTodo(id) {
    saveStore(TodoStore.toggleTodo(root.store, id), "Toggle task")
  }

  function removeTodo(id) {
    saveStore(TodoStore.removeTodo(root.store, id), "Delete task")
  }

  function updateTodo(id, fields) {
    saveStore(TodoStore.updateTodo(root.store, id, fields), "Update task")
  }

  function clearCompleted(profile) {
    var currentText = root.getArchiveText()
    var result = TodoStore.archiveCompleted(root.store, profile, currentText)
    saveStore(result.updatedStore, "Clear completed")
    var json = JSON.stringify(result.updatedArchive, null, 2) + "\n"
    root.lastArchiveText = json
    archiveFile.setText(json)
  }

  function setActiveProfile(profile) {
    var s = TodoStore.cloneStore(root.store)
    s.activeProfile = TodoStore.cleanProfileName(profile)
    saveStore(s, "Switch profile: " + s.activeProfile)
  }

  function addProfile(name) {
    saveStore(TodoStore.addProfile(root.store, name), "Add profile: " + name)
  }

  function removeProfile(name) {
    saveStore(TodoStore.removeProfile(root.store, name), "Remove profile: " + name)
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

  // Ensure data folder, todos.json, and todos-archive.json exist, and git repo is initialized
  Process {
    id: initFileProc
    command: [
      "bash", "-c",
      "mkdir -p \"" + root.dataDirPath + "\" && " +
      "[ -f \"" + root.todoFilePath + "\" ] || echo '{\"version\":1,\"activeProfile\":\"personal\",\"profiles\":[\"personal\",\"work\"],\"todos\":[]}' > \"" + root.todoFilePath + "\"; " +
      "[ -f \"" + root.archiveFilePath + "\" ] || echo '{\"version\":1,\"archived\":[]}' > \"" + root.archiveFilePath + "\"; " +
      "cd \"" + root.dataDirPath + "\" && " +
      "git config gc.auto 100 2>/dev/null || true; " +
      "if [ ! -d \".git\" ]; then " +
      "  git init -b main; " +
      "  git config user.name \"" + root.deviceName + "\"; " +
      "  git config user.email \"" + Quickshell.env("USER") + "@" + root.deviceName + "\"; " +
      "  git config gc.auto 100; " +
      "  git add todos.json todos-archive.json; " +
      "  git commit -m \"[" + root.deviceName + "] Initial task repository\"; " +
      "fi"
    ]
    onExited: {
      todoFile.reload()
      archiveFile.reload()
      root.refreshGitHistory()
    }
  }

  Component.onCompleted: initFileProc.running = true

  Timer {
    id: autoCommitTimer
    interval: 3000
    repeat: false
    onTriggered: {
      commitProcess.running = true
    }
  }

  Process {
    id: commitProcess
    command: [
      "bash", "-c",
      "cd \"" + root.dataDirPath + "\" && " +
      "git add todos.json todos-archive.json && " +
      "if ! git diff --cached --quiet; then " +
      "  git commit -m \"" + GitSync.buildCommitMessage(root.deviceName, root.lastCommitAction, root.pendingCount) + "\"; " +
      "  git gc --auto --quiet; " +
      "fi"
    ]
    onExited: root.refreshGitHistory()
  }

  property int gitLogLimit: 30
  property bool gitLogHasMore: true

  Process {
    id: gitLogProc
    command: ["git", "-C", root.dataDirPath, "log", "-n", String(root.gitLogLimit), "--pretty=format:%H|%an|%ae|%at|%s"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = GitSync.parseGitLog(text)
        root.gitSnapshots = parsed
        root.lastGitLog = JSON.stringify(parsed)
        root.gitLogHasMore = (parsed.length >= root.gitLogLimit)
      }
    }
  }

  Process {
    id: gitRemoteProc
    command: ["git", "-C", root.dataDirPath, "remote", "get-url", "origin"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.remoteUrl = text.trim()
      }
    }
  }

  Process {
    id: recoverProc
    command: ["git", "-C", root.dataDirPath, "show", root.recoveringHash + ":todos.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var snapshotStore = JSON.parse(text)
          var missing = TodoStore.filterMissingTasks(root.store, snapshotStore)
          if (missing.length > 0) {
            var updated = TodoStore.cloneStore(root.store)
            for (var i = 0; i < missing.length; i++) {
              updated.todos.push(missing[i])
            }
            updated.todos.sort(TodoStore.compareTasks)
            root.saveStore(updated, "Recovered " + missing.length + " missing tasks from " + root.recoveringHash.substring(0, 7))
          }
        } catch (_e) {}
      }
    }
  }

  Process {
    id: syncProcess
    command: [
      "bash", "-c",
      "cd \"" + root.dataDirPath + "\" && " +
      "if git remote get-url origin >/dev/null 2>&1; then " +
      "  git fetch origin main 2>&1 || exit 1; " +
      "  LOCAL_HEAD=$(git rev-parse HEAD); " +
      "  REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo \"$LOCAL_HEAD\"); " +
      "  if [ \"$LOCAL_HEAD\" != \"$REMOTE_HEAD\" ] && git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then " +
      "    git push origin main 2>&1 || exit 2; " +
      "  elif [ \"$LOCAL_HEAD\" != \"$REMOTE_HEAD\" ]; then " +
      "    echo \"NEEDS_MERGE\"; " +
      "  else " +
      "    echo \"UP_TO_DATE\"; " +
      "  fi; " +
      "else " +
      "  echo \"NO_REMOTE\"; " +
      "fi"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = text.trim()
        if (out.indexOf("NEEDS_MERGE") !== -1) {
          mergeRemoteChangesProc.running = true
        } else if (out.indexOf("UP_TO_DATE") !== -1 || out.indexOf("Everything up-to-date") !== -1) {
          root.gitSyncStatus = "success"
          root.gitSyncMessage = "Up to date"
          root.refreshGitHistory()
        } else if (out.indexOf("NO_REMOTE") !== -1) {
          root.gitSyncStatus = "idle"
          root.gitSyncMessage = "No remote configured"
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        root.gitSyncStatus = "error"
        root.gitSyncMessage = "Sync failed (check connection/auth)"
      }
    }
  }

  Process {
    id: mergeRemoteChangesProc
    command: [
      "bash", "-c",
      "cd \"" + root.dataDirPath + "\" && " +
      "REMOTE_TODOS=$(git show origin/main:todos.json 2>/dev/null || echo '') && " +
      "REMOTE_ARCHIVE=$(git show origin/main:todos-archive.json 2>/dev/null || echo '') && " +
      "printf '%s\\n---SPLIT---\\n%s' \"$REMOTE_TODOS\" \"$REMOTE_ARCHIVE\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parts = text.split("\n---SPLIT---\n")
          if (parts.length >= 2) {
            var remoteTodos = parts[0].trim()
            var remoteArchive = parts[1].trim()
            if (remoteTodos) {
              var mergedStore = TodoStore.mergeStores(root.store, remoteTodos)
              var mergedArch = TodoStore.mergeArchives(root.getArchiveText(), remoteArchive)
              root.store = mergedStore
              todoFile.setText(JSON.stringify(mergedStore, null, 2) + "\n")
              var json = JSON.stringify(mergedArch, null, 2) + "\n"
              root.lastArchiveText = json
              archiveFile.setText(json)
              Quickshell.execDetached([
                "bash", "-c",
                "cd \"" + root.dataDirPath + "\" && git add todos.json todos-archive.json && git commit -m \"[" + root.deviceName + "] Auto-merge remote changes\" && git push origin main"
              ])
              root.gitSyncStatus = "success"
              root.gitSyncMessage = "Merged & synced with remote"
              root.refreshGitHistory()
            }
          }
        } catch (_e) {
          root.gitSyncStatus = "error"
          root.gitSyncMessage = "Merge failed"
        }
      }
    }
  }

  function refreshGitHistory(resetLimit) {
    if (resetLimit !== false) {
      root.gitLogLimit = 30
    }
    gitLogProc.running = true
    gitRemoteProc.running = true
  }

  function loadMoreGitHistory() {
    if (!gitLogProc.running && root.gitLogHasMore) {
      root.gitLogLimit += 30
      gitLogProc.running = true
    }
  }

  function setRemoteUrl(urlStr) {
    var u = (urlStr || "").trim()
    if (!u) {
      Quickshell.execDetached(["git", "-C", root.dataDirPath, "remote", "remove", "origin"])
      root.remoteUrl = ""
      root.gitSyncStatus = "idle"
      root.gitSyncMessage = "No remote configured"
      return "removed"
    }
    if (!GitSync.isValidRemoteUrl(u)) {
      return "invalid_url"
    }
    Quickshell.execDetached(["bash", "-c", "cd \"" + root.dataDirPath + "\" && git remote remove origin 2>/dev/null; git remote add origin \"" + u + "\""])
    root.remoteUrl = u
    root.gitSyncStatus = "idle"
    root.gitSyncMessage = "Remote configured"
    return "ok"
  }

  function rollbackToCommit(hashStr) {
    if (!hashStr) return
    var h = String(hashStr).trim()
    var cmd = "cd \"" + root.dataDirPath + "\" && git checkout " + h + " -- todos.json todos-archive.json && git commit -m \"[" + root.deviceName + "] Restored snapshot " + h.substring(0, 7) + "\""
    Quickshell.execDetached(["bash", "-c", cmd])
    Qt.callLater(function() {
      todoFile.reload()
      archiveFile.reload()
      root.refreshGitHistory()
    })
  }

  function recoverFromCommit(hashStr) {
    if (!hashStr) return
    root.recoveringHash = String(hashStr).trim()
    recoverProc.running = true
  }

  function syncWithRemote() {
    root.gitSyncStatus = "syncing"
    root.gitSyncMessage = "Syncing..."
    syncProcess.running = true
  }

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
    onLoaded: root.lastArchiveText = text()
    onLoadFailed: root.lastArchiveText = "{\"version\":1,\"archived\":[]}"
    onFileChanged: {
      reload()
      root.lastArchiveText = text()
    }
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
    function addDetailed(task: string, notes: string, reminder: string): string {
      var t = String(task || "").trim()
      var d = String(notes || "")
      var r = reminder && String(reminder).trim() ? String(reminder).trim() : null
      var finalRem = r
      if (r && TodoStore && typeof TodoStore.computePresetReminder === "function") {
        var computed = TodoStore.computePresetReminder(r)
        if (computed) finalRem = computed
      }
      root.addTodo(t, d, null, finalRem)
      return "ok"
    }
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
    function searchProfiles(queryStr: string): string {
      return JSON.stringify(TodoStore.searchProfiles(root.store, queryStr || ""))
    }
    function setProfile(profile: string): string { root.setActiveProfile(profile); return "ok" }
    function archived(): string { return root.getArchiveText() }
    function archiveCount(): string { return String(TodoStore.getArchivedCount(root.getArchiveText())) }
    function gitHistory(): string { return root.lastGitLog || "[]" }
    function gitRollback(hashStr: string): string { root.rollbackToCommit(hashStr); return "ok" }
    function gitRecover(hashStr: string): string { root.recoverFromCommit(hashStr); return "ok" }
    function gitSync(): string { root.syncWithRemote(); return "ok" }
    function gitSetRemote(urlStr: string): string { return root.setRemoteUrl(urlStr) }
    function gitGetRemote(): string { return root.remoteUrl }
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

      Ui.ArdoiseIcon {
        id: ardoiseIcon
        anchors.verticalCenter: parent.verticalCenter
        store: root.store
        bar: root.bar
        iconSize: Style.bar.iconFont
      }

      // Rung-scoped: the number always answers "how many tasks are in the
      // state the glyph depicts", and takes the glyph's color role. Total
      // pending stays available in the tooltip.
      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.ladderState.count > 0
        text: String(root.ladderState.count)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: ardoiseIcon.ladderColor

        Behavior on color {
          ColorAnimation { duration: 150 }
        }
      }
    }
  }
}
