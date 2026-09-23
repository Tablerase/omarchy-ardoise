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

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string todoFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos.json"

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

  readonly property var reminderPresets: TodoStore.getReminderPresets()

  property string focusSection: "title" // "title", "profiles", "options", "notes", "reminders", "actions"
  property int optionIndex: 0 // 0: note, 1: reminder
  property int reminderPresetIndex: 0
  property int actionIndex: 1 // 0: cancel, 1: add

  function getActiveSections() {
    var secs = ["title"]
    if (Boolean(root.detectedContext && root.attachLocation)) secs.push("location")
    secs.push("options")
    if (root.showNote) secs.push("notes")
    if (root.showReminderOptions) secs.push("reminders")
    secs.push("profiles")
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
    if (focusSection === "title") {
      Qt.callLater(function() { taskInput.forceActiveFocus() })
    } else if (focusSection === "notes") {
      Qt.callLater(function() {
        if (descNotesArea) descNotesArea.forceActiveFocus()
      })
    } else {
      taskInput.focus = false
      if (descNotesArea) descNotesArea.focus = false
      card.forceActiveFocus()
    }
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
    var count = root.reminderPresets.length + (root.selectedReminder ? 1 : 0)
    if (count <= 0) return
    reminderPresetIndex = (reminderPresetIndex + step + count) % count
  }

  function clearDraft() {
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
    selectedProfile = (store && store.activeProfile) ? store.activeProfile : "personal"
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
      selectedProfile = (store && store.activeProfile) ? store.activeProfile : "personal"
    }
    Qt.callLater(function() {
      taskInput.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
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
    if (typeof profileFlickable === "undefined" || !profileFlickable) return
    var profs = TodoStore.getSortedProfiles(root.store, false, root.selectedProfile)
    var idx = profs.indexOf(profileName)
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

  function submit() {
    var rawText = taskInput.text.trim()
    if (!rawText) {
      root.dismiss()
      return
    }

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
            // If the user hasn't explicitly customized profile in draft, auto-match known profile
            if (!root.hasDraft && root.store && Array.isArray(root.store.profiles)) {
              var candidates = []
              if (res.repo) {
                var parts = res.repo.split("/")
                candidates.push(TodoStore.cleanProfileName(parts[parts.length - 1]))
                candidates.push(TodoStore.cleanProfileName(parts[0]))
              }
              if (res.repoName) {
                candidates.push(TodoStore.cleanProfileName(res.repoName))
              }
              for (var i = 0; i < candidates.length; i++) {
                var c = candidates[i]
                if (c && root.store.profiles.indexOf(c) !== -1) {
                  root.selectedProfile = c
                  break
                }
              }
            }
          } else {
            root.detectedContext = null
            root.attachLocation = false
          }
        } catch (_e) {
          root.detectedContext = null
          root.attachLocation = false
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
        root.selectedProfile = root.store.activeProfile || "personal"
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
            if (root.reminderPresetIndex < root.reminderPresets.length) {
              root.selectedReminder = root.reminderPresets[root.reminderPresetIndex].value
            } else {
              root.selectedReminder = ""
            }
            root.showReminderOptions = false
            root.focusSection = "options"
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

        // Typing any letter automatically directs to task title!
        if (event.text && event.text.length === 1 && !event.modifiers) {
          event.accepted = true
          root.focusSection = "title"
          taskInput.forceActiveFocus()
          taskInput.text += event.text
          taskInput.cursorPosition = taskInput.text.length
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

          InboxIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: width
            color: Color.menu.text || Color.foreground
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
          placeholderText: "What needs to be done? (e.g. #work Fix bug)"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.menu.text || Color.foreground
          placeholderTextColor: Color.muted
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          topPadding: Style.space(8)
          bottomPadding: Style.space(8)
          background: BorderSurface {
            color: Style.controlFill(taskInput.activeFocus, taskInput.hovered, Color.foreground, Color.accent)
            borderSpec: Border.controlSpec(taskInput.activeFocus ? "focus" : (taskInput.hovered ? "hover-cursor" : "normal"), Color.foreground, Color.accent)
            radius: Style.cornerRadius
          }
          onAccepted: root.submit()
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            if (taskInput.text.trim().length === 0) {
              root.dismiss()
            } else {
              taskInput.focus = false
              root.focusSection = "options"
              card.forceActiveFocus()
            }
          }
          Keys.onTabPressed: function(event) {
            event.accepted = true
            root.advanceSection(1)
          }
          Keys.onBacktabPressed: function(event) {
            event.accepted = true
            root.advanceSection(-1)
          }
          Keys.onDownPressed: function(event) {
            event.accepted = true
            root.advanceSection(1)
          }
          Keys.onUpPressed: function(event) {
            event.accepted = true
            root.advanceSection(-1)
          }
          Keys.onPressed: function(event) {
            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && (event.modifiers & Qt.ControlModifier)) {
              if (root.hasDraft) {
                root.clearDraft()
                event.accepted = true
              }
            }
          }
          onTextChanged: {
            root.draftTitle = text
            var match = text.match(/#\s*([a-zA-Z0-9_-]+)/)
            if (match) {
              root.selectedProfile = TodoStore.cleanProfileName(match[1])
            }
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

        // Auto-detected codebase context pill
        Row {
          visible: Boolean(root.detectedContext && root.attachLocation)
          spacing: Style.space(6)
          height: visible ? Style.space(22) : 0

          Rectangle {
            id: locationPill
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: ctxRow.implicitWidth + Style.space(14)
            implicitHeight: Style.space(20)
            radius: Style.cornerRadius
            color: (root.focusSection === "location") ? Util.alpha(Color.accent, 0.24) : Util.alpha(Color.accent, 0.12)
            border.color: (root.focusSection === "location") ? Color.accent : Util.alpha(Color.accent, 0.35)
            border.width: (root.focusSection === "location") ? 2 : 1
            scale: (root.focusSection === "location") ? 1.04 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.focusSection = "location"
                root.applySectionFocus()
              }
            }

            Row {
              id: ctxRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.detectedContext && root.detectedContext.repo ? "󰊤" : "󰉋"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.space(10)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (!root.detectedContext) return ""
                  if (root.detectedContext.repo) {
                    var txt = root.detectedContext.repo
                    if (root.detectedContext.subpath) txt += "/" + root.detectedContext.subpath
                    return txt
                  }
                  return root.detectedContext.localPath || ""
                }
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideMiddle
                maximumLineCount: 1
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"
                color: (detachMouse.containsMouse || root.focusSection === "location") ? Color.urgent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption

                MouseArea {
                  id: detachMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.attachLocation = false
                    if (root.focusSection === "location") root.advanceSection(1)
                  }
                }
              }
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

        // Option Toggles (Note & Reminder)
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: noteBtn
            iconText: "󰏫"
            text: root.showNote ? "Hide Note" : "Add Note"
            selected: root.showNote
            bordered: true
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            hasCursor: (root.focusSection === "options") && (root.optionIndex === 0)
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
            iconText: "󰥔"
            text: root.selectedReminder ? TodoStore.formatReminder(root.selectedReminder) : "Set Reminder"
            selected: Boolean(root.selectedReminder)
            bordered: true
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            hasCursor: (root.focusSection === "options") && (root.optionIndex === 1)
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
            onSubmitted: root.submit()
            onEscapePressed: {
              taskInput.focus = false
              root.focusSection = "options"
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

          Row {
            spacing: Style.space(6)

            Repeater {
              model: root.reminderPresets

              Button {
                id: presetBtn
                required property var modelData
                required property int index
                text: modelData.label
                fontSize: Style.font.caption
                fontFamily: Style.font.family
                bordered: true
                selected: root.selectedReminder === modelData.value
                hasCursor: (root.focusSection === "reminders") && (root.reminderPresetIndex === index)
                onClicked: {
                  root.selectedReminder = modelData.value
                  root.showReminderOptions = false
                  root.focusSection = "options"
                }
              }
            }

            Button {
              visible: Boolean(root.selectedReminder)
              iconText: "󰅖"
              text: "Clear"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              bordered: true
              hasCursor: (root.focusSection === "reminders") && (root.reminderPresetIndex === root.reminderPresets.length)
              onClicked: {
                root.selectedReminder = ""
                root.showReminderOptions = false
                root.focusSection = "options"
              }
            }
          }
        }

        // Profile Selector Pills with responsive wrap Flow
        Flow {
          id: profileFlow
          width: parent.width
          spacing: Style.space(6)

          Row {
            spacing: Style.space(4)
            height: Style.space(24)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Profile:"
              color: (root.focusSection === "profiles") ? Color.accent : Color.muted
              font.bold: (root.focusSection === "profiles")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            id: profileRepeater
            model: TodoStore.getSortedProfiles(root.store, false, root.selectedProfile)

            Rectangle {
              id: profilePill
              required property string modelData
              readonly property bool isKeyboardFocused: (root.focusSection === "profiles") && (root.selectedProfile === modelData)
              implicitWidth: pillRow.implicitWidth + Style.space(12)
              implicitHeight: Style.space(24)
              radius: implicitHeight / 2
              color: root.selectedProfile === modelData ? Color.accent : Color.menu.selectedBackground
              border.color: isKeyboardFocused ? (Color.menu.text || Color.foreground) : (root.selectedProfile === modelData ? Color.accent : Color.menu.border)
              border.width: isKeyboardFocused ? 2 : 1
              scale: isKeyboardFocused ? 1.05 : 1.0

              Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
              }

              Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: TodoStore.getProfileGlyph(profilePill.modelData)
                  color: root.selectedProfile === profilePill.modelData ? "white" : Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: pillLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: profilePill.modelData
                  color: root.selectedProfile === profilePill.modelData ? "white" : (Color.menu.text || Color.foreground)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: root.selectedProfile === profilePill.modelData
                  width: Math.min(implicitWidth, Style.space(90))
                  elide: Text.ElideRight
                }
              }

              HoverHandler {
                id: pillHover
              }

              PanelToolTip {
                visible: pillHover.hovered && pillLabel.truncated
                text: profilePill.modelData
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedProfile = profilePill.modelData
                }
              }
            }
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
              hasCursor: (root.focusSection === "actions") && (root.actionIndex === 1)
              selected: (root.focusSection === "actions") && (root.actionIndex === 1)
              scale: hasCursor ? 1.05 : 1.0
              Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
              onClicked: root.submit()
            }
          }
        }
      }
    }
  }
}
