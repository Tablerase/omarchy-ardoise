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

  readonly property string todoFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos.json"
  property var store: TodoStore.defaultStore()

  function loadStore(raw) {
    root.store = TodoStore.normalize(raw)
  }

  function saveStore(newStore) {
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
  }

  function checkReminders() {
    var due = TodoStore.pendingReminders(root.store)
    if (!due || due.length === 0) return

    var bin = root.omarchyPath + "/bin/omarchy-notification-send"
    var updated = root.store

    for (var i = 0; i < due.length; i++) {
      var task = due[i]
      var headline = "Todo: " + task.title
      var desc = (task.profile && task.profile !== "personal" ? "[" + task.profile + "] " : "")
        + (task.description ? task.description : "Scheduled reminder")

      Quickshell.execDetached([
        bin,
        "--app-name", "Ardoise",
        "-g", "󰥔",
        "-u", "normal",
        headline,
        desc,
        "--exec", "omarchy-shell", "shell", "toggle", "tablerase.ardoise", "{}"
      ])

      updated = TodoStore.updateTodo(updated, task.id, { notified: true })
    }

    root.saveStore(updated)
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

  Component.onCompleted: {
    if (todoFile.loaded) root.checkReminders()
  }
}
