// =============================================================================
// QuickAdd.qml
//
// Fullscreen overlay modal for keyboard-first task capture.
// Supports schema v1, profiles (#work, #personal, etc.), optional descriptions,
// and configurable reminder presets.
// =============================================================================

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore
import "./ui" as Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

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
  property string selectedProfile: "personal"
  property string selectedReminder: ""
  property bool showNote: false
  property bool showReminderOptions: false

  property string draftTitle: ""
  property string draftDescription: ""
  property string draftProfile: ""
  property string draftReminder: ""
  property var detectedContext: null
  property bool attachLocation: true
  readonly property bool hasDraft: draftTitle.trim().length > 0 || draftDescription.trim().length > 0

  property bool showTitleError: false
  readonly property var parsedInput: TodoStore.parseTaskInput(taskInput.text, root.selectedProfile)
  readonly property bool hasValidTitle: Boolean(parsedInput && parsedInput.title && parsedInput.title.trim().length > 0)
  readonly property bool canSubmit: hasValidTitle

  property var reminderPresets: TodoStore.getReminderPresets()

  function refreshReminderPresets() {
    reminderPresets = TodoStore.getReminderPresets()
  }

  // --- Profile & Tag Autocomplete State ---
  property bool autocompleteActive: false
  property string autocompleteMode: "profile" // "profile" | "tag"
  property string autocompleteQuery: ""
  property int autocompleteIndex: 0
  property int autocompleteTokenStart: -1
  property int autocompleteTokenEnd: -1

  readonly property var autocompleteMatches: {
    if (!autocompleteActive) return []
    if (autocompleteMode === "tag") {
      return (typeof TodoStore.searchTags === "function") ? TodoStore.searchTags(root.store, autocompleteQuery) : []
    }
    return (typeof TodoStore.searchProfiles === "function") ? TodoStore.searchProfiles(root.store, autocompleteQuery) : []
  }

  function checkAutocompleteAtCursor() {
    if (!taskInput.activeFocus) {
      autocompleteActive = false
      return
    }
    var pos = taskInput.cursorPosition
    var text = taskInput.text
    var before = text.slice(0, pos)

    var match = before.match(/(^|\s)#([a-zA-Z0-9_\/-]*)$/)
    if (!match) {
      autocompleteActive = false
      return
    }

    var query = match[2]
    var hashIndex = before.length - query.length - 1

    var textBeforeHash = before.slice(0, hashIndex)
    var isFirstHash = !textBeforeHash.includes("#")

    var after = text.slice(pos)
    var afterMatch = after.match(/^[a-zA-Z0-9_\/-]*/)
    var endPos = pos + (afterMatch ? afterMatch[0].length : 0)

    autocompleteTokenStart = hashIndex
    autocompleteTokenEnd = endPos
    autocompleteMode = isFirstHash ? "profile" : "tag"
    autocompleteQuery = query
    autocompleteActive = true
    if (autocompleteIndex >= autocompleteMatches.length) {
      autocompleteIndex = 0
    }
  }

  function applyAutocomplete(item) {
    if (!item) return
    var text = taskInput.text
    var start = autocompleteTokenStart
    var end = autocompleteTokenEnd
    if (start < 0 || end < start) return

    var afterChar = text.charAt(end)
    var replacement = "#" + item + (afterChar === " " ? "" : " ")
    var newText = text.slice(0, start) + replacement + text.slice(end)
    var newCursor = start + replacement.length + (afterChar === " " ? 1 : 0)

    taskInput.text = newText
    taskInput.cursorPosition = newCursor

    if (autocompleteMode === "profile") {
      root.selectedProfile = TodoStore.cleanProfileName(item)
    }
    autocompleteActive = false
    taskInput.forceActiveFocus()
  }

  function closeAutocomplete() {
    autocompleteActive = false
    autocompleteIndex = 0
  }

  property string focusSection: "title" // "title", "profiles", "options", "notes", "reminders", "actions"
  property int optionIndex: 0 // 0: note, 1: reminder
  property int reminderPresetIndex: 0
  property int actionIndex: 1 // 0: cancel, 1: add

  function getActiveSections() {
    var secs = ["title", "options"]
    if (root.showNote) secs.push("notes")
    if (root.showReminderOptions) secs.push("reminders")
    secs.push("profiles")
    if (Boolean(root.detectedContext && root.attachLocation)) secs.push("location")
    secs.push("actions")
    return secs
  }

  function advanceSection(dir) {
    var secs = getActiveSections()
    var idx = secs.indexOf(focusSection)
    if (idx === -1) idx = 0
    var nextIdx = (idx + dir + secs.length) % secs.length
    focusSection = secs[nextIdx]
    applySectionFocus()
  }

  function applySectionFocus() {
    taskInput.focus = false
    if (descNotesArea) {
      if (descNotesArea.textArea) descNotesArea.textArea.focus = false
      descNotesArea.focus = false
    }
    card.forceActiveFocus()
  }

  function cycleProfileSelection(step) {
    var profs = TodoStore.getSortedProfiles(root.store, false, root.selectedProfile)
    if (!profs || profs.length === 0) return
    var curIdx = profs.indexOf(root.selectedProfile)
    if (curIdx === -1) curIdx = 0
    var nextIdx = (curIdx + step + profs.length) % profs.length
    root.selectedProfile = profs[nextIdx]
  }

  function cycleReminderPreset(step) {
    var count = root.reminderPresets.length + 1 + (root.selectedReminder ? 1 : 0)
    if (count <= 0) return
    reminderPresetIndex = (reminderPresetIndex + step + count) % count
  }

  function clearDraft() {
    closeAutocomplete()
    draftTitle = ""
    draftDescription = ""
    draftProfile = ""
    draftReminder = ""
    detectedContext = null
    attachLocation = false
    taskInput.text = ""
    if (descNotesArea) {
      descNotesArea.text = ""
      if (descNotesArea.textArea) descNotesArea.textArea.text = ""
    }
    showNote = false
    showReminderOptions = false
    selectedReminder = ""
    refreshReminderPresets()
    selectedProfile = TodoStore.resolveDefaultProfile(root.store, root.detectedContext)
    focusSection = "title"
    optionIndex = 0
    actionIndex = 1
    Qt.callLater(function() {
      taskInput.forceActiveFocus()
    })
  }

  function open(payloadJson) {
    root.opened = true
    root.focusSection = "title"
    root.optionIndex = 0
    root.actionIndex = 1
    root.refreshReminderPresets()
    detectContextProc.running = true
    if (root.hasDraft) {
      taskInput.text = root.draftTitle
      if (root.draftDescription) {
        root.showNote = true
        Qt.callLater(function() {
          if (descNotesArea) {
            descNotesArea.text = root.draftDescription
            if (descNotesArea.textArea) descNotesArea.textArea.text = root.draftDescription
          }
        })
      }
      if (root.draftProfile) {
        root.selectedProfile = root.draftProfile
      }
      if (root.draftReminder) {
        root.selectedReminder = root.draftReminder
        root.showReminderOptions = true
      }
    } else {
      taskInput.text = ""
      if (descNotesArea) {
        descNotesArea.text = ""
        if (descNotesArea.textArea) descNotesArea.textArea.text = ""
      }
      showNote = false
      showReminderOptions = false
      selectedReminder = ""
      root.detectedContext = null
      root.attachLocation = false
      selectedProfile = TodoStore.resolveDefaultProfile(root.store, null)
    }
    Qt.callLater(function() {
      taskInput.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.closeAutocomplete()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "tablerase.ardoise")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function ensureProfileVisible(profileName) {
    if (typeof quickAddProfileSelector === "undefined" || !quickAddProfileSelector) return
    var profs = TodoStore.getSortedProfiles(root.store, false, root.selectedProfile)
    var idx = profs.indexOf(profileName)
    if (idx !== -1) {
      quickAddProfileSelector.ensureVisible(idx)
    }
  }

  onSelectedProfileChanged: {
    if (root.opened) {
      root.draftProfile = root.selectedProfile
    }
    Qt.callLater(function() { root.ensureProfileVisible(root.selectedProfile) })
  }

  onSelectedReminderChanged: {
    if (root.opened) {
      root.draftReminder = root.selectedReminder
    }
  }

  onOpenedChanged: {
    if (root.opened) {
      root.showTitleError = false
      root.refreshReminderPresets()
    }
  }

  onShowReminderOptionsChanged: {
    if (root.showReminderOptions) {
      root.refreshReminderPresets()
    }
  }

  function submit() {
    if (!root.canSubmit) {
      root.showTitleError = true
      root.focusSection = "title"
      taskInput.forceActiveFocus()
      return
    }

    var rawText = taskInput.text.trim()
    var desc = (showNote && descNotesArea) ? descNotesArea.text.trim() : ""
    var rem = selectedReminder || null
    var loc = (root.attachLocation && root.detectedContext) ? root.detectedContext : null

    var newStore = TodoStore.addTodo(root.store, rawText, desc, root.selectedProfile, rem, loc)
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
    root.clearDraft()
    root.dismiss()
  }

  Process {
    id: detectContextProc
    command: [
      "bash",
      "-c",
      "SCRIPT=\"$1\"; if [ -x \"$SCRIPT\" ]; then exec \"$SCRIPT\"; elif [ -x \"$HOME/.local/share/omarchy/plugins/tablerase.ardoise/tools/detect-context.sh\" ]; then exec \"$HOME/.local/share/omarchy/plugins/tablerase.ardoise/tools/detect-context.sh\"; elif [ -x \"./tools/detect-context.sh\" ]; then exec \"./tools/detect-context.sh\"; else echo 'null'; fi",
      "--",
      Qt.resolvedUrl("tools/detect-context.sh").toString().replace(/^file:\/\//, "")
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res && (res.repo || res.localPath)) {
            root.detectedContext = res
            root.attachLocation = true
            // If the user hasn't explicitly customized profile in draft, auto-resolve profile via 3-tier hierarchy
            if (!root.hasDraft) {
              root.selectedProfile = TodoStore.resolveDefaultProfile(root.store, res)
            }
          } else {
            root.detectedContext = null
            root.attachLocation = false
            if (!root.hasDraft) {
              root.selectedProfile = TodoStore.resolveDefaultProfile(root.store, null)
            }
          }
        } catch (_e) {
          root.detectedContext = null
          root.attachLocation = false
          if (!root.hasDraft) {
            root.selectedProfile = TodoStore.resolveDefaultProfile(root.store, null)
          }
        }
      }
    }
  }

  FileView {
    id: todoFile
    path: root.todoFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.store = TodoStore.normalize(text())
      if (!root.opened) {
        root.selectedProfile = TodoStore.resolveDefaultProfile(root.store, root.detectedContext)
      }
    }
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-todo-quick-add"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Dimmed background scrim
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // Dismiss when clicking outside the card
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Centered quick-add card
    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(560), panel.width - Style.space(32))
      height: contentCol.implicitHeight + Style.space(32)
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
      radius: Style.cornerRadius
      focus: true

      Keys.onPressed: function(event) {
        if (reminderPicker && reminderPicker.isOpen) {
          return
        }

        if (event.key === Qt.Key_Escape) {
          event.accepted = true
          root.dismiss()
          return
        }

        if (event.key === Qt.Key_Tab) {
          event.accepted = true
          root.advanceSection(1)
          return
        }

        if (event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.advanceSection(-1)
          return
        }

        if (event.key === Qt.Key_Down || event.text === "j") {
          event.accepted = true
          root.advanceSection(1)
          return
        }

        if (event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          root.advanceSection(-1)
          return
        }

        if (event.key === Qt.Key_Left || event.text === "h") {
          event.accepted = true
          if (root.focusSection === "profiles") {
            root.cycleProfileSelection(-1)
          } else if (root.focusSection === "options") {
            root.optionIndex = 0
          } else if (root.focusSection === "reminders") {
            root.cycleReminderPreset(-1)
          } else if (root.focusSection === "actions") {
            root.actionIndex = 0
          }
          return
        }

        if (event.key === Qt.Key_Right || event.text === "l") {
          event.accepted = true
          if (root.focusSection === "profiles") {
            root.cycleProfileSelection(1)
          } else if (root.focusSection === "options") {
            root.optionIndex = 1
          } else if (root.focusSection === "reminders") {
            root.cycleReminderPreset(1)
          } else if (root.focusSection === "actions") {
            root.actionIndex = 1
          }
          return
        }

        if (root.focusSection === "location") {
          if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace || event.text === "x" || event.text === "X" || event.key === Qt.Key_X) {
            event.accepted = true
            root.attachLocation = false
            root.advanceSection(1)
            return
          }
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          event.accepted = true
          if (root.focusSection === "location") {
            root.attachLocation = false
            root.advanceSection(1)
            return
          }
          if (root.focusSection === "options") {
            if (root.optionIndex === 0) {
              root.showNote = !root.showNote
              if (root.showNote) {
                root.focusSection = "notes"
                Qt.callLater(function() { if (descNotesArea) descNotesArea.forceActiveFocus() })
              }
            } else {
              root.showReminderOptions = !root.showReminderOptions
              if (root.showReminderOptions) {
                root.focusSection = "reminders"
                root.reminderPresetIndex = 0
              }
            }
          } else if (root.focusSection === "notes") {
            if (descNotesArea) descNotesArea.forceActiveFocus()
          } else if (root.focusSection === "reminders") {
            var isCustomSelQA = Boolean(root.selectedReminder && (!root.reminderPresets || !root.reminderPresets.some(function(p) { return p && p.value === root.selectedReminder; })))
            var presetsLenQA = root.reminderPresets ? root.reminderPresets.length : 0
            if (isCustomSelQA) {
              if (root.reminderPresetIndex === 0) {
                if (reminderPicker) reminderPicker.open(root.selectedReminder)
              } else if (root.reminderPresetIndex >= 1 && root.reminderPresetIndex <= presetsLenQA) {
                var pIdxQA = root.reminderPresetIndex - 1
                root.selectedReminder = (typeof TodoStore.computePresetReminder === "function")
                  ? TodoStore.computePresetReminder(pIdxQA)
                  : root.reminderPresets[pIdxQA].value
                root.showReminderOptions = false
                root.focusSection = "options"
              } else {
                root.selectedReminder = ""
                root.showReminderOptions = false
                root.focusSection = "options"
              }
            } else {
              if (root.reminderPresetIndex < presetsLenQA) {
                root.selectedReminder = (typeof TodoStore.computePresetReminder === "function")
                  ? TodoStore.computePresetReminder(root.reminderPresetIndex)
                  : root.reminderPresets[root.reminderPresetIndex].value
                root.showReminderOptions = false
                root.focusSection = "options"
              } else if (root.reminderPresetIndex === presetsLenQA) {
                if (reminderPicker) reminderPicker.open(root.selectedReminder)
              } else {
                root.selectedReminder = ""
                root.showReminderOptions = false
                root.focusSection = "options"
              }
            }
          } else if (root.focusSection === "profiles") {
            // Profile selection confirmed with Space/Enter
          } else if (root.focusSection === "actions") {
            if (root.actionIndex === 0) root.dismiss()
            else root.submit()
          } else {
            root.submit()
          }
          return
        }

        if (event.key === Qt.Key_I || event.key === Qt.Key_A || (event.text === "i" || event.text === "a")) {
          event.accepted = true
          if (root.focusSection === "notes" && root.showNote && descNotesArea) {
            descNotesArea.forceActiveFocus()
          } else {
            root.focusSection = "title"
            taskInput.forceActiveFocus()
          }
          return
        }

        if (event.text === "e" && root.focusSection === "notes" && root.showNote && descNotesArea) {
          event.accepted = true
          descNotesArea.forceActiveFocus()
          return
        }

        // Typing any printable character automatically directs to notes (if focused) or task title!
        if (event.text && event.text.length === 1 && !event.modifiers) {
          event.accepted = true
          if (root.focusSection === "notes" && root.showNote && descNotesArea) {
            descNotesArea.forceActiveFocus()
            if (descNotesArea.textArea) {
              descNotesArea.textArea.insert(descNotesArea.textArea.cursorPosition, event.text)
            }
          } else {
            root.focusSection = "title"
            taskInput.forceActiveFocus()
            taskInput.text += event.text
            taskInput.cursorPosition = taskInput.text.length
          }
        }
      }

      MouseArea {
        anchors.fill: parent
      }

      Column {
        id: contentCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.space(16)
        spacing: Style.space(12)

        // Header
        Row {
          width: parent.width
          spacing: Style.space(8)

          Ui.ArdoiseIcon {
            anchors.verticalCenter: parent.verticalCenter
            store: root.store
            iconSize: Style.font.subtitle
            foregroundOverride: Color.menu.text || Color.foreground
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Quick Add Task"
            color: Color.menu.text || Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
        }

        PanelSeparator { width: parent.width }

        // Focused Input Field for task title
        TextField {
          id: taskInput
          width: parent.width
          placeholderText: "What needs to be done? (#tag or #profile optional)"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.menu.text || Color.foreground
          placeholderTextColor: Color.muted
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          topPadding: Style.space(8)
          bottomPadding: Style.space(8)
          background: BorderSurface {
            readonly property bool isNavFocused: (root.focusSection === "title") && !taskInput.activeFocus
            readonly property bool hasError: root.showTitleError || (taskInput.text.trim().length > 0 && !root.hasValidTitle)
            color: taskInput.activeFocus
              ? Util.alpha(hasError ? (Color.urgent || "#d20f39") : Color.accent, 0.08)
              : Style.controlFill(false, taskInput.hovered, Color.foreground, Color.accent)
            borderSpec: hasError
              ? Border.flat(Color.urgent || "#d20f39", taskInput.activeFocus ? 2 : 1)
              : (taskInput.activeFocus
                  ? Border.flat(Color.accent, 2)
                  : (isNavFocused
                      ? Border.flat(Color.accent, 1)
                      : (taskInput.hovered ? Border.controlSpec("hover-cursor", Color.foreground, Color.accent)
                                           : Border.controlSpec("normal", Color.foreground, Color.accent))))
            radius: Style.cornerRadius
          }
          onAccepted: {
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              root.applyAutocomplete(root.autocompleteMatches[root.autocompleteIndex])
            } else {
              root.submit()
            }
          }
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              root.closeAutocomplete()
              return
            }
            if (taskInput.text.trim().length === 0) {
              root.dismiss()
            } else {
              taskInput.focus = false
              root.focusSection = "title"
              card.forceActiveFocus()
            }
          }
          Keys.onTabPressed: function(event) {
            event.accepted = true
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              root.applyAutocomplete(root.autocompleteMatches[root.autocompleteIndex])
              return
            }
            root.advanceSection(1)
          }
          Keys.onBacktabPressed: function(event) {
            event.accepted = true
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              var len = root.autocompleteMatches.length
              root.autocompleteIndex = (root.autocompleteIndex - 1 + len) % len
              return
            }
            root.advanceSection(-1)
          }
          Keys.onDownPressed: function(event) {
            event.accepted = true
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              root.autocompleteIndex = (root.autocompleteIndex + 1) % root.autocompleteMatches.length
              return
            }
            root.advanceSection(1)
          }
          Keys.onUpPressed: function(event) {
            event.accepted = true
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              var len = root.autocompleteMatches.length
              root.autocompleteIndex = (root.autocompleteIndex - 1 + len) % len
              return
            }
            root.advanceSection(-1)
          }
          Keys.onReturnPressed: function(event) {
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              event.accepted = true
              root.applyAutocomplete(root.autocompleteMatches[root.autocompleteIndex])
              return
            }
            event.accepted = true
            root.submit()
          }
          Keys.onEnterPressed: function(event) {
            if (root.autocompleteActive && root.autocompleteMatches.length > 0) {
              event.accepted = true
              root.applyAutocomplete(root.autocompleteMatches[root.autocompleteIndex])
              return
            }
            event.accepted = true
            root.submit()
          }
          Keys.onPressed: function(event) {
            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers & Qt.ControlModifier)) {
              if (root.hasDraft) {
                root.clearDraft()
                event.accepted = true
              }
            }
          }
          onActiveFocusChanged: {
            if (activeFocus) {
              root.checkAutocompleteAtCursor()
            } else {
              root.closeAutocomplete()
            }
          }
          onCursorPositionChanged: {
            root.checkAutocompleteAtCursor()
          }
          onTextChanged: {
            root.draftTitle = text
            if (root.hasValidTitle) {
              root.showTitleError = false
            }
            var match = text.match(/#\s*([a-zA-Z0-9_-]+)/)
            if (match) {
              root.selectedProfile = TodoStore.cleanProfileName(match[1])
            }
            root.checkAutocompleteAtCursor()
          }
        }

        // Autocomplete suggestions popup for #profile and #tag
        Rectangle {
          id: autocompleteBox
          width: parent.width
          visible: root.autocompleteActive && root.autocompleteMatches.length > 0
          color: (Color.popups && Color.popups.background) ? Color.popups.background : Color.menu.background
          border.color: (Color.popups && Color.popups.border) ? Color.popups.border : Color.menu.border
          border.width: 1
          radius: Style.cornerRadius
          clip: true
          implicitHeight: Math.min(Style.space(160), autocompleteInnerCol.implicitHeight + Style.space(8))

          Connections {
            target: root
            function onAutocompleteIndexChanged() {
              if (!root.autocompleteActive) return
              var itemHeight = Style.space(28) + Style.space(2)
              var headerHeight = Style.space(20) + Style.space(2)
              var targetY = headerHeight + root.autocompleteIndex * itemHeight
              if (targetY < autocompleteFlickable.contentY) {
                autocompleteFlickable.contentY = targetY
              } else if (targetY + itemHeight > autocompleteFlickable.contentY + autocompleteFlickable.height) {
                autocompleteFlickable.contentY = targetY + itemHeight - autocompleteFlickable.height
              }
            }
          }

          Flickable {
            id: autocompleteFlickable
            anchors.fill: parent
            anchors.margins: Style.space(4)
            contentWidth: width
            contentHeight: autocompleteInnerCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: autocompleteInnerCol
              width: parent.width
              spacing: Style.space(2)

              // Header indicating mode (Profile or Tag)
              Row {
                width: parent.width
                height: Style.space(20)
                spacing: Style.space(6)
                padding: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.autocompleteMode === "profile" ? "󰭤" : "󰓹"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.autocompleteMode === "profile" ? "Profiles" : "Tags"
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Repeater {
                model: root.autocompleteMatches
                delegate: Rectangle {
                  id: matchItem
                  width: autocompleteInnerCol.width
                  height: Style.space(28)
                  radius: Style.cornerRadius - 2
                  readonly property bool isSelected: index === root.autocompleteIndex
                  color: isSelected
                    ? Util.alpha(Color.accent, 0.2)
                    : (matchMouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent")
                  border.color: isSelected ? Util.alpha(Color.accent, 0.4) : "transparent"
                  border.width: 1

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.right: metaCountText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.autocompleteMode === "profile" ? TodoStore.getProfileGlyph(modelData) : "󰓹"
                      color: matchItem.isSelected ? Color.accent : Color.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "#" + modelData
                      color: Color.menu.text || Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: matchItem.isSelected
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    id: metaCountText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                      if (root.autocompleteMode === "profile") {
                        var pending = TodoStore.getPendingCount(root.store, modelData)
                        return pending > 0 ? (pending + (pending === 1 ? " task" : " tasks")) : ""
                      } else {
                        var tagCount = 0
                        if (root.store && Array.isArray(root.store.todos)) {
                          for (var i = 0; i < root.store.todos.length; i++) {
                            var t = root.store.todos[i]
                            if (Array.isArray(t.tags) && t.tags.indexOf(modelData) !== -1) tagCount++
                          }
                        }
                        return tagCount > 0 ? (tagCount + (tagCount === 1 ? " task" : " tasks")) : ""
                      }
                    }
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: matchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.autocompleteIndex = index
                    }
                    onClicked: {
                      root.applyAutocomplete(modelData)
                    }
                  }
                }
              }
            }
          }
        }

        // Inline validation cue when task title is missing
        Row {
          id: titleErrorRow
          width: parent.width
          visible: root.showTitleError || (taskInput.text.trim().length > 0 && !root.hasValidTitle)
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅚"
            color: Color.urgent || "#d20f39"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: taskInput.text.trim().length > 0
              ? ("Title required: add task name after hashtag (e.g. " + taskInput.text.trim() + " My task)")
              : "Task title is required"
            color: Color.urgent || "#d20f39"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // Draft notice banner when a saved draft is active
        Row {
          width: parent.width
          visible: root.hasDraft
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰁯"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Draft restored"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "•"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            id: clearDraftAction
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear"
            color: clearDraftMouse.containsMouse ? Color.urgent : Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true

            MouseArea {
              id: clearDraftMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: root.clearDraft()
            }
          }
        }


        // Option Toggles (Note & Reminder)
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: noteBtn
            readonly property bool isActive: root.showNote
            iconText: "󰏫"
            text: root.showNote ? "Hide Note" : "Add Note"
            bordered: true
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            hasCursor: (root.focusSection === "options") && (root.optionIndex === 0)
            foreground: (hasCursor || isActive) ? Color.accent : (Color.menu.text || Color.foreground)
            background: isActive ? Util.alpha(Color.accent, 0.12) : "transparent"
            borderSpec: hasCursor
              ? Border.flat(Color.accent, 2)
              : (isActive ? Border.flat(Color.accent, 1) : Border.controlSpec("normal", Color.foreground, Color.accent))
            scale: hasCursor ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: 80 } }
            onClicked: {
              root.showNote = !root.showNote
              if (root.showNote) {
                root.focusSection = "notes"
                Qt.callLater(function() { descNotesArea.forceActiveFocus() })
              }
            }
          }

          Button {
            id: reminderBtn
            readonly property bool isActive: Boolean(root.selectedReminder)
            iconText: "󰥔"
            text: root.selectedReminder ? TodoStore.formatReminder(root.selectedReminder) : "Set Reminder"
            bordered: true
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            hasCursor: (root.focusSection === "options") && (root.optionIndex === 1)
            foreground: (hasCursor || isActive) ? Color.accent : (Color.menu.text || Color.foreground)
            background: isActive ? Util.alpha(Color.accent, 0.12) : "transparent"
            borderSpec: hasCursor
              ? Border.flat(Color.accent, 2)
              : (isActive ? Border.flat(Color.accent, 1) : Border.controlSpec("normal", Color.foreground, Color.accent))
            scale: hasCursor ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: 80 } }
            onClicked: {
              root.showReminderOptions = !root.showReminderOptions
              if (root.showReminderOptions) {
                root.focusSection = "reminders"
                root.reminderPresetIndex = 0
              }
            }
          }
        }

        // Expandable Description field (multi-line auto-expanding)
        Column {
          width: parent.width
          visible: root.showNote
          spacing: Style.space(4)

          TaskNotesArea {
            id: descNotesArea
            width: parent.width
            placeholderText: "Add note / description (Shift+Enter for newline)..."
            isNavFocused: (root.focusSection === "notes") && !editorActiveFocus
            onSubmitted: root.submit()
            onEscapePressed: {
              taskInput.focus = false
              if (descNotesArea.textArea) descNotesArea.textArea.focus = false
              descNotesArea.focus = false
              root.focusSection = "notes"
              card.forceActiveFocus()
            }
            onTabPressed: function(direction) {
              root.advanceSection(direction)
            }
            onTextChanged: {
              if (root.opened) {
                root.draftDescription = text
              }
            }
            Connections {
              target: descNotesArea.textArea
              function onTextChanged() {
                if (root.opened) {
                  root.draftDescription = descNotesArea.textArea.text
                }
              }
            }
            Keys.onPressed: function(event) {
              if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers & Qt.ControlModifier)) {
                if (root.hasDraft) {
                  root.clearDraft()
                  event.accepted = true
                }
              }
            }
          }
        }

        // Expandable Reminder Presets
        Column {
          width: parent.width
          visible: root.showReminderOptions
          spacing: Style.space(6)

          Ui.ReminderPills {
            width: parent.width
            presets: root.reminderPresets
            selectedValue: root.selectedReminder
            hasReminder: Boolean(root.selectedReminder)
            focusedIndex: root.reminderPresetIndex
            isNavFocused: root.focusSection === "reminders"
            onReminderSelected: function(val, idx) {
              root.selectedReminder = (typeof TodoStore.computePresetReminder === "function")
                ? TodoStore.computePresetReminder(idx)
                : val
              root.showReminderOptions = false
              root.focusSection = "options"
            }
            onCustomSelected: function(idx) {
              if (reminderPicker) reminderPicker.open(root.selectedReminder)
            }
            onClearSelected: function(idx) {
              root.selectedReminder = ""
              root.showReminderOptions = false
              root.focusSection = "options"
            }
          }
        }

        // Profile Selector Pills
        Item {
          id: quickAddProfileContainer
          width: parent.width
          implicitHeight: Style.space(24)

          Row {
            id: quickAddProfileLabelRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Profile:"
              color: (root.focusSection === "profiles") ? Color.accent : Color.muted
              font.bold: (root.focusSection === "profiles")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Ui.ProfileSelector {
            id: quickAddProfileSelector
            anchors.left: quickAddProfileLabelRow.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            profiles: TodoStore.getSortedProfiles(root.store, false, root.selectedProfile)
            selectedProfile: root.selectedProfile
            focusedIndex: TodoStore.getSortedProfiles(root.store, false, root.selectedProfile).indexOf(root.selectedProfile)
            isNavFocused: root.focusSection === "profiles"
            onProfileSelected: function(name, idx) {
              root.selectedProfile = name
            }
          }
        }

        // Auto-detected codebase context pill (positioned above actions)
        Row {
          visible: Boolean(root.detectedContext && root.attachLocation)
          spacing: Style.space(6)
          height: visible ? Style.space(22) : 0

          Ui.Chip {
            id: locationPill
            anchors.verticalCenter: parent.verticalCenter
            variant: "location"
            iconText: root.detectedContext && root.detectedContext.repo ? "󰊤" : "󰉋"
            text: {
              if (!root.detectedContext) return ""
              if (root.detectedContext.repo) {
                var txt = root.detectedContext.repo
                if (root.detectedContext.subpath) txt += "/" + root.detectedContext.subpath
                return txt
              }
              return root.detectedContext.localPath || ""
            }
            removable: true
            maximumWidth: Style.space(260)
            borderAlpha: (root.focusSection === "location") ? 1.0 : 0.35
            scale: (root.focusSection === "location") ? 1.04 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            onClicked: {
              root.focusSection = "location"
              root.applySectionFocus()
            }
            onRemoved: {
              root.attachLocation = false
              if (root.focusSection === "location") root.advanceSection(1)
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.focusSection === "location") ? "(press x or Del to remove)" : "(auto-detected)"
            color: (root.focusSection === "location") ? Color.accent : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.space(8.5)
            font.bold: root.focusSection === "location"
          }
        }

        PanelSeparator { width: parent.width }

        // Action controls
        Item {
          width: parent.width
          implicitHeight: Math.max(hintText.implicitHeight, actionButtons.implicitHeight)

          Text {
            id: hintText
            anchors.left: parent.left
            anchors.right: actionButtons.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.showTitleError || (taskInput.text.trim().length > 0 && !root.hasValidTitle)) return "⚠ Title required before sending  •  Esc Cancel"
              if (root.focusSection === "location") return "󰆴 x / Del Remove Location  •  Tab/Vim Nav  •  Esc Cancel"
              if (root.hasDraft) return "󰌑 Enter  •  Tab/Vim Nav  •  Esc Dismiss  •  Ctrl+⌫ Discard"
              return "󰌑 Enter  •  Tab/Vim Nav  •  Esc Cancel"
            }
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Row {
            id: actionButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Button {
              id: cancelBtn
              iconText: "󰅖"
              text: "Cancel"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              bordered: true
              hasCursor: (root.focusSection === "actions") && (root.actionIndex === 0)
              selected: (root.focusSection === "actions") && (root.actionIndex === 0)
              borderSpec: hasCursor
                ? Border.flat(Color.accent, 2)
                : Border.controlSpec("normal", Color.foreground, Color.accent)
              scale: hasCursor ? 1.05 : 1.0
              Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
              onClicked: root.dismiss()
            }

            Button {
              id: addBtn
              iconText: "󰐕"
              text: "Add"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              bordered: true
              enabled: root.canSubmit
              opacity: root.canSubmit ? 1.0 : 0.4
              Behavior on opacity { NumberAnimation { duration: 120 } }
              hasCursor: (root.focusSection === "actions") && (root.actionIndex === 1)
              selected: (root.focusSection === "actions") && (root.actionIndex === 1)
              borderSpec: hasCursor
                ? (root.canSubmit ? Border.flat(Color.accent, 2) : Border.flat(Color.muted, 1))
                : Border.controlSpec("normal", Color.foreground, Color.accent)
              scale: (hasCursor && root.canSubmit) ? 1.05 : 1.0
              Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
              onClicked: {
                if (root.canSubmit) {
                  root.submit()
                } else {
                  root.showTitleError = true
                  root.focusSection = "title"
                  taskInput.forceActiveFocus()
                }
              }
            }
          }
        }
      }
    }

    Ui.ReminderPicker {
      id: reminderPicker
      anchors.fill: parent
      onReminderConfirmed: function(iso) {
        root.selectedReminder = iso
        root.showReminderOptions = false
        root.focusSection = "options"
        card.forceActiveFocus()
      }
      onReminderCleared: function() {
        root.selectedReminder = ""
        root.showReminderOptions = false
        root.focusSection = "options"
        card.forceActiveFocus()
      }
      onCloseRequested: {
        card.forceActiveFocus()
      }
    }
  }
}
