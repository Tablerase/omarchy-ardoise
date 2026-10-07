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
  readonly property string bindingsFilePath: dataDirPath + "/bindings.lua"
  readonly property string defaultBindingsTemplatePath: Qt.resolvedUrl("tools/default-bindings.lua").toString().replace(/^file:\/\//, "")

  property string deviceName: Quickshell.env("HOSTNAME") || "omarchy"
  property string lastCommitAction: "Update tasks"
  property var gitSnapshots: []
  property string lastGitLog: "[]"
  property string remoteUrl: ""
  property string gitSyncStatus: "idle" // "idle" | "syncing" | "success" | "error"
  property string gitSyncMessage: ""
  property string lastSyncOutput: ""
  property string recoveringHash: ""
  property string lastArchiveText: ""

  // Durable archive-operation state. Restore/purge read both files fresh from
  // disk (never the possibly-stale lastArchiveText), write the active store
  // before touching the archive, and confirm each write landed.
  property bool _storeLoaded: false
  property bool _archiveLoaded: false
  property bool _archiveOpInFlight: false
  property var _readCb: null
  property var _writeCb: null

  function getArchiveText() {
    return root.lastArchiveText || archiveFile.text() || "{\"version\":1,\"archived\":[]}"
  }

  // Reads a file from disk, bypassing FileView's cached text. Authoritative.
  function readFile(path, cb) {
    root._readCb = cb
    readProc.readPath = path
    readProc.running = true
  }

  function _completeWrite(ok) {
    var cb = root._writeCb
    root._writeCb = null
    writeTimeout.stop()
    if (cb) cb(ok)
  }

  function writeFileAndConfirm(fileView, json, cb) {
    root._writeCb = cb
    fileView.setText(json)
    writeTimeout.restart()
  }

  function _storeHasId(id, cb) {
    root.readFile(root.todoFilePath, function(raw) {
      var s = TodoStore.normalize(raw)
      for (var i = 0; i < s.todos.length; i++) {
        if (String(s.todos[i].id) === String(id)) { cb(true); return }
      }
      cb(false)
    })
  }

  function _archiveHasId(id, cb) {
    root.readFile(root.archiveFilePath, function(raw) {
      var arc = TodoStore.normalizeArchive(raw)
      for (var i = 0; i < arc.archived.length; i++) {
        if (String(arc.archived[i].id) === String(id)) { cb(true); return }
      }
      cb(false)
    })
  }

  // Writes the archive and confirms the id is gone, retrying a bounded number
  // of times to absorb any lost write.
  function _writeArchiveUntilGone(id, archiveJson, actionName, attempts) {
    root.writeFileAndConfirm(archiveFile, archiveJson, function(ok) {
      root._archiveHasId(id, function(still) {
        if (still && attempts > 0) {
          root._writeArchiveUntilGone(id, archiveJson, actionName, attempts - 1)
          return
        }
        root.lastArchiveText = archiveJson
        root.lastCommitAction = actionName || "Update archive"
        commitProcess.running = true
        root._archiveOpInFlight = false
      })
    })
  }

  // Self-heal duplicates left by a crash between the two restore writes: any
  // archived id that is also active is dropped from the archive.
  function maybeReconcileArchive() {
    if (!root._storeLoaded || !root._archiveLoaded) return
    var res = TodoStore.reconcileArchive(root.store, root.getArchiveText())
    if (res.removedCount > 0) {
      var json = JSON.stringify(res.updatedArchive, null, 2) + "\n"
      root.lastArchiveText = json
      archiveFile.setText(json)
      root.triggerAutoCommit("Reconcile archive (" + res.removedCount + " duplicate" + (res.removedCount === 1 ? "" : "s") + ")")
    }
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
    saveStore(TodoStore.addTodo(root.store, title, description, profile, reminder), "Add task")
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

  // Moves one archived task back into the active store. Idempotent and
  // data-loss safe: both files are read fresh, the active store is written and
  // confirmed to contain the id BEFORE the archive entry is removed, and the
  // archive write is verified with bounded retries. If any step fails the
  // archive is left untouched, so the task can never vanish.
  function unarchiveTask(id) {
    if (root._archiveOpInFlight) return false
    root._archiveOpInFlight = true
    root.readFile(root.todoFilePath, function(storeRaw) {
      root.readFile(root.archiveFilePath, function(archiveRaw) {
        var result = TodoStore.unarchive(TodoStore.normalize(storeRaw), archiveRaw, id)
        if (!result.restored) {
          root._archiveOpInFlight = false
          return
        }
        var storeJson = JSON.stringify(result.updatedStore, null, 2) + "\n"
        var archiveJson = JSON.stringify(result.updatedArchive, null, 2) + "\n"
        root.writeFileAndConfirm(todoFile, storeJson, function(ok) {
          if (!ok) {
            root._archiveOpInFlight = false
            return
          }
          root._storeHasId(id, function(present) {
            if (!present) {
              // The active write did not land: never remove the archive entry.
              root._archiveOpInFlight = false
              return
            }
            root.store = result.updatedStore
            root.lastArchiveText = archiveJson
            root._writeArchiveUntilGone(id, archiveJson, "Restore task from archive", 3)
          })
        })
      })
    })
    return true
  }

  // Permanently removes one task from the archive (hold-to-confirm in the
  // archive browser). Irreversible except through git history.
  function purgeArchivedTask(id) {
    if (root._archiveOpInFlight) return false
    root._archiveOpInFlight = true
    root.readFile(root.archiveFilePath, function(archiveRaw) {
      var result = TodoStore.purgeArchived(archiveRaw, id)
      if (!result.purged) {
        root._archiveOpInFlight = false
        return
      }
      var archiveJson = JSON.stringify(result.updatedArchive, null, 2) + "\n"
      root.lastArchiveText = archiveJson
      root._writeArchiveUntilGone(id, archiveJson, "Delete archived task permanently", 3)
    })
    return true
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

  function seedTutorial() {
    var updated = TodoStore.seedTutorialTasks(root.store)
    saveStore(updated, "Seed onboarding tutorial tasks")
    return "ok"
  }

  function markReleaseSeen() {
    var updated = TodoStore.markReleaseSeen(root.store)
    saveStore(updated, "Acknowledge release highlights")
    return "ok"
  }

  function resetReleaseHighlights() {
    var updated = TodoStore.resetReleaseHighlights(root.store)
    saveStore(updated, "Reset release highlights")
    return "ok"
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

  readonly property string initialStoreJson: JSON.stringify(TodoStore.createInitialStore(), null, 2)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  // Ensure data folder, todos.json, and todos-archive.json exist, and git repo is initialized
  Process {
    id: initFileProc
    command: [
      "bash", "-c",
      "mkdir -p \"" + root.dataDirPath + "\" && " +
      "[ -f \"" + root.todoFilePath + "\" ] || cat << 'EOF' > \"" + root.todoFilePath + "\"\n" + root.initialStoreJson + "\nEOF\n; " +
      "[ -f \"" + root.archiveFilePath + "\" ] || echo '{\"version\":1,\"archived\":[]}' > \"" + root.archiveFilePath + "\"; " +
      "if [ ! -f \"" + root.bindingsFilePath + "\" ] && [ -f \"" + root.defaultBindingsTemplatePath + "\" ]; then cp \"" + root.defaultBindingsTemplatePath + "\" \"" + root.bindingsFilePath + "\" 2>/dev/null || true; fi; " +
      "if [ ! -f \"" + root.dataDirPath + "/.gitignore\" ]; then printf 'bindings.lua\\n*.tmp\\n' > \"" + root.dataDirPath + "/.gitignore\"; fi; " +
      "cd \"" + root.dataDirPath + "\" && " +
      "git config gc.auto 100 2>/dev/null || true; " +
      "if [ ! -d \".git\" ]; then " +
      "  git init -b main; " +
      "  git config user.name \"" + root.deviceName + "\"; " +
      "  git config user.email \"" + Quickshell.env("USER") + "@" + root.deviceName + "\"; " +
      "  git config gc.auto 100; " +
      "  git add todos.json todos-archive.json .gitignore 2>/dev/null || git add todos.json todos-archive.json; " +
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
      'cd "$1" && git add todos.json todos-archive.json && if ! git diff --cached --quiet; then printf \'%s\\n\' "$2" | git commit -F - && git gc --auto --quiet; fi',
      "_",
      root.dataDirPath,
      GitSync.buildCommitMessage(root.deviceName, root.lastCommitAction, root.pendingCount)
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
      "  FETCH_OUT=$(git fetch origin main 2>&1); " +
      "  FETCH_CODE=$?; " +
      "  if [ $FETCH_CODE -ne 0 ]; then " +
      "    if echo \"$FETCH_OUT\" | grep -qE \"couldn't find remote ref\"; then " +
      "      PUSH_INIT_OUT=$(git push -u origin main 2>&1); " +
      "      if [ $? -eq 0 ]; then " +
      "        echo \"INITIALIZED_AND_PUSHED\"; " +
      "      else " +
      "        echo \"$PUSH_INIT_OUT\"; " +
      "        exit 2; " +
      "      fi; " +
      "    else " +
      "      echo \"$FETCH_OUT\"; " +
      "      exit 1; " +
      "    fi; " +
      "  else " +
      "    LOCAL_HEAD=$(git rev-parse HEAD); " +
      "    REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo \"$LOCAL_HEAD\"); " +
      "    if [ \"$LOCAL_HEAD\" != \"$REMOTE_HEAD\" ] && git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then " +
      "      PUSH_OUT=$(git push origin main 2>&1); " +
      "      if [ $? -eq 0 ]; then " +
      "        echo \"UP_TO_DATE\"; " +
      "      else " +
      "        echo \"$PUSH_OUT\"; " +
      "        exit 3; " +
      "      fi; " +
      "    elif [ \"$LOCAL_HEAD\" != \"$REMOTE_HEAD\" ]; then " +
      "      echo \"NEEDS_MERGE\"; " +
      "    else " +
      "      echo \"UP_TO_DATE\"; " +
      "    fi; " +
      "  fi; " +
      "else " +
      "  echo \"NO_REMOTE\"; " +
      "fi"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = text.trim()
        root.lastSyncOutput = out
        if (out.indexOf("NEEDS_MERGE") !== -1) {
          mergeRemoteChangesProc.running = true
        } else if (out.indexOf("INITIALIZED_AND_PUSHED") !== -1) {
          root.gitSyncStatus = "success"
          root.gitSyncMessage = "Initialized remote & pushed tasks"
          root.refreshGitHistory()
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
        root.gitSyncMessage = GitSync.diagnoseGitSyncError(root.lastSyncOutput, code)
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
                "cd \"" + root.dataDirPath + "\" && git merge --no-commit -s ours origin/main 2>/dev/null || true; git add todos.json todos-archive.json && git commit -m \"[" + root.deviceName + "] Auto-merge remote changes\" && git push origin main"
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

  Process {
    id: setupGitRemoteProc
    property string targetRepoName: "ardoise-tasks"
    command: [
      "bash", "-c",
      "\"" + Qt.resolvedUrl("tools/setup-git-remote.sh").toString().replace(/^file:\/\//, "") +
      "\" \"" + targetRepoName + "\" \"" + root.dataDirPath + "\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res && res.success) {
            root.remoteUrl = res.remoteUrl || ""
            root.gitSyncStatus = "success"
            root.gitSyncMessage = res.message || "Synced with GitHub"
            root.refreshGitHistory()
          } else {
            root.gitSyncStatus = "error"
            root.gitSyncMessage = (res && res.message) ? res.message : "GitHub setup failed"
          }
        } catch (_e) {
          root.gitSyncStatus = "error"
          root.gitSyncMessage = "Unexpected response from setup script"
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.gitSyncStatus === "syncing") {
        root.gitSyncStatus = "error"
        root.gitSyncMessage = "GitHub setup failed (code " + code + ")"
      }
    }
  }

  function autoSetupGitRemote(repoName) {
    if (setupGitRemoteProc.running) return "already_running"
    root.gitSyncStatus = "syncing"
    root.gitSyncMessage = "Setting up GitHub repository..."
    setupGitRemoteProc.targetRepoName = (repoName && String(repoName).trim()) ? String(repoName).trim() : "ardoise-tasks"
    setupGitRemoteProc.running = true
    return "started"
  }


  FileView {
    id: todoFile
    path: root.todoFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadTodos(text())
      root._storeLoaded = true
      root.maybeReconcileArchive()
    }
    onLoadFailed: {
      root.loadTodos("{}")
      root._storeLoaded = true
    }
    onSaved: root._completeWrite(true)
    onSaveFailed: root._completeWrite(false)
    onFileChanged: reload()
  }

  FileView {
    id: archiveFile
    path: root.archiveFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.lastArchiveText = text()
      root._archiveLoaded = true
      root.maybeReconcileArchive()
    }
    onLoadFailed: {
      root.lastArchiveText = "{\"version\":1,\"archived\":[]}"
      root._archiveLoaded = true
    }
    onSaved: root._completeWrite(true)
    onSaveFailed: root._completeWrite(false)
    onFileChanged: reload()
  }

  // Authoritative disk reads for archive operations. `cat` is used (rather
  // than FileView.text()) so a restore can never act on stale cached text.
  Process {
    id: readProc
    property string readPath: ""
    command: ["cat", readPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cb = root._readCb
        root._readCb = null
        if (cb) cb(text)
      }
    }
  }

  // Bounds a write confirmation; if neither saved nor saveFailed arrives the
  // operation aborts without touching the archive.
  Timer {
    id: writeTimeout
    interval: 2500
    repeat: false
    onTriggered: root._completeWrite(false)
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
      var computed = (r && TodoStore && typeof TodoStore.computePresetReminder === "function")
        ? TodoStore.computePresetReminder(r)
        : null
      if (computed) {
        finalRem = computed
      } else if (r && TodoStore && typeof TodoStore.parseCustomReminder === "function") {
        var custom = TodoStore.parseCustomReminder(r)
        if (custom && custom.iso) finalRem = custom.iso
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
        if (fields && fields.reminder && typeof fields.reminder === "string") {
          var remStr = fields.reminder.trim()
          var comp = (remStr.length > 0 && TodoStore && typeof TodoStore.computePresetReminder === "function")
            ? TodoStore.computePresetReminder(remStr)
            : null
          if (comp) {
            fields.reminder = comp
          } else if (remStr.length > 0 && TodoStore && typeof TodoStore.parseCustomReminder === "function") {
            var parsed = TodoStore.parseCustomReminder(remStr)
            if (parsed && parsed.iso) fields.reminder = parsed.iso
          }
        }
        root.updateTodo(id, fields)
        return "ok"
      } catch (e) {
        return "invalid_json"
      }
    }
    function clear(): string { root.clearCompleted(); return "ok" }
    function count(): string { return String(root.pendingCount) }
    function list(): string { return JSON.stringify(root.todos) }
    function get(idStr: string): string {
      var id = Number(idStr)
      if (isNaN(id)) return "invalid_id"
      var task = TodoStore.getTaskById(root.store, id)
      if (task) return JSON.stringify(task)
      var arc = TodoStore.getArchivedTasks(root.getArchiveText())
      for (var i = 0; i < arc.length; i++) {
        if (arc[i] && String(arc[i].id) === String(id)) return JSON.stringify(arc[i])
      }
      return "not_found"
    }
    function profiles(): string { return JSON.stringify(root.profiles) }
    function searchProfiles(queryStr: string): string {
      return JSON.stringify(TodoStore.searchProfiles(root.store, queryStr || ""))
    }
    function setProfile(profile: string): string { root.setActiveProfile(profile); return "ok" }
    function archived(): string { return root.getArchiveText() }
    function archiveCount(): string { return String(TodoStore.getArchivedCount(root.getArchiveText())) }
    function unarchive(id: string): string { return root.unarchiveTask(id) ? "ok" : "busy" }
    function purgeArchived(id: string): string { return root.purgeArchivedTask(id) ? "ok" : "busy" }
    function gitHistory(): string { return root.lastGitLog || "[]" }
    function gitRollback(hashStr: string): string { root.rollbackToCommit(hashStr); return "ok" }
    function gitRecover(hashStr: string): string { root.recoverFromCommit(hashStr); return "ok" }
    function gitSync(): string { root.syncWithRemote(); return "ok" }
    function gitSetRemote(urlStr: string): string { return root.setRemoteUrl(urlStr) }
    function gitGetRemote(): string { return root.remoteUrl }
    function gitSearch(queryStr: string): string {
      return JSON.stringify(GitSync.filterSnapshots(root.gitSnapshots, queryStr || ""))
    }
    function autoSetupGitRemote(repoName: string): string { return root.autoSetupGitRemote(repoName) }
    function gitAutoSetup(repoName: string): string { return root.autoSetupGitRemote(repoName) }
    function seedTutorial(): string { return root.seedTutorial() }
    function whatsNew(): string { return JSON.stringify(TodoStore.RELEASE_HIGHLIGHTS) }
    function markReleaseSeen(): string { return root.markReleaseSeen() }
    function resetReleaseHighlights(): string { return root.resetReleaseHighlights() }
    function help(): string { return TodoStore.getIpcHelp() }
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
