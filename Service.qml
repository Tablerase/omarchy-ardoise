// =============================================================================
// Service.qml
//
// Background headless service for tablerase.ardoise (Ardoise).
// Monitors scheduled reminders and triggers Omarchy desktop notifications.
// =============================================================================

import QtQuick
import Quickshell
import Quickshell.Io
import "TodoStore.js" as TodoStore

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

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
  property var store: TodoStore.defaultStore()

  // In-memory deduplication cache: key is taskId + "_" + reminderIso
  // Prevents duplicate notifications during a session even if disk writes are in-flight
  property var sentNotifications: ({})
  property bool isSelfSaving: false

  function loadStore(raw) {
    root.store = TodoStore.normalize(raw)
  }

  function saveStore(newStore) {
    root.isSelfSaving = true
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
  }

  function checkReminders() {
    var due = TodoStore.pendingReminders(root.store)
    if (!due || due.length === 0) return

    var bin = root.omarchyPath + "/bin/omarchy-notification-send"
    var toNotify = []
    var idsToMark = []

    for (var i = 0; i < due.length; i++) {
      var task = due[i]
      var reminderKey = String(task.id) + "_" + String(task.reminder)
      if (root.sentNotifications[reminderKey]) {
        // Already notified in this session
        idsToMark.push(task.id)
        continue
      }
      root.sentNotifications[reminderKey] = true
      toNotify.push(task)
      idsToMark.push(task.id)
    }

    // Fire notifications only for unsent reminders
    for (var j = 0; j < toNotify.length; j++) {
      var t = toNotify[j]
      var headline = (t.profile && t.profile !== "personal" ? "[" + t.profile + "] " : "") + "Task Reminder"
      var desc = "Scheduled reminder is due"

      Quickshell.execDetached([
        bin,
        "--app-name", "Ardoise",
        "-g", "󰥔",
        "-u", "normal",
        headline,
        desc,
        "--exec", "omarchy-shell", "shell", "toggle", "tablerase.ardoise", "{}"
      ])
    }

    // Batch update notified state in store and persist once
    if (idsToMark.length > 0) {
      var updated = TodoStore.markTasksNotified(root.store, idsToMark)
      root.saveStore(updated)
    }
  }

  FileView {
    id: todoFile
    path: root.todoFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadStore(text())
    onLoadFailed: root.loadStore("{}")
    onFileChanged: {
      if (root.isSelfSaving) {
        root.isSelfSaving = false
        return
      }
      reload()
      Qt.callLater(root.checkReminders)
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.checkReminders()
  }

  // Hourly background sync (3600 seconds)
  Timer {
    id: hourlySyncTimer
    interval: 3600000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: syncProc.running = true
  }

  Process {
    id: syncProc
    command: ["bash", "-c", "omarchy-shell tablerase.ardoise gitSync 2>/dev/null || true"]
  }

  Component.onCompleted: {
    if (todoFile.loaded) root.checkReminders()
  }
}
