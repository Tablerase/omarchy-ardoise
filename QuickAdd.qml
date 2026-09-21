// =============================================================================
// QuickAdd.qml
//
// Fullscreen overlay modal for keyboard-first task capture.
// Supports schema v1, profiles (#work, #personal, etc.), optional descriptions,
// and configurable reminder presets.
// =============================================================================

import QtQuick
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

  readonly property var reminderPresets: TodoStore.getReminderPresets()

  function open(payloadJson) {
    root.opened = true
    taskInput.text = ""
    descInput.text = ""
    showNote = false
    showReminderOptions = false
    selectedReminder = ""
    selectedProfile = (store && store.activeProfile) ? store.activeProfile : "personal"
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

  function submit() {
    var rawText = taskInput.text.trim()
    if (!rawText) {
      root.dismiss()
      return
    }

    var desc = showNote ? descInput.text.trim() : ""
    var rem = selectedReminder || null

    var newStore = TodoStore.addTodo(root.store, rawText, desc, root.selectedProfile, rem)
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
    root.dismiss()
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
      width: Math.min(Style.space(480), panel.width - Style.space(32))
      height: contentCol.implicitHeight + Style.space(32)
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1
      radius: Style.cornerRadius

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
          onAccepted: root.submit()
          Keys.onEscapePressed: root.dismiss()
          onTextChanged: {
            var match = text.match(/#\s*([a-zA-Z0-9_-]+)/)
            if (match) {
              root.selectedProfile = TodoStore.cleanProfileName(match[1])
            }
          }
        }

        // Profile Selector Pills
        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Profile:"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.store.profiles || ["personal", "work"]

            Rectangle {
              id: profilePill
              required property string modelData
              implicitWidth: pillRow.implicitWidth + Style.space(12)
              implicitHeight: Style.space(24)
              radius: implicitHeight / 2
              color: root.selectedProfile === modelData ? Color.accent : Color.menu.selectedBackground
              border.color: root.selectedProfile === modelData ? Color.accent : Color.menu.border
              border.width: 1

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
                  anchors.verticalCenter: parent.verticalCenter
                  text: profilePill.modelData
                  color: root.selectedProfile === profilePill.modelData ? "white" : (Color.menu.text || Color.foreground)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: root.selectedProfile === profilePill.modelData
                }
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

        // Option Toggles (Note & Reminder)
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            iconText: "󰏫"
            text: root.showNote ? "Hide Note" : "Add Note"
            selected: root.showNote
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            onClicked: {
              root.showNote = !root.showNote
              if (root.showNote) {
                Qt.callLater(function() { descInput.forceActiveFocus() })
              }
            }
          }

          Button {
            iconText: "󰀉"
            text: root.selectedReminder ? TodoStore.formatReminder(root.selectedReminder) : "Set Reminder"
            selected: Boolean(root.selectedReminder)
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            onClicked: {
              root.showReminderOptions = !root.showReminderOptions
            }
          }
        }

        // Expandable Description field
        Column {
          width: parent.width
          visible: root.showNote
          spacing: Style.space(4)

          TextField {
            id: descInput
            width: parent.width
            placeholderText: "Add note / description..."
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            onAccepted: root.submit()
            Keys.onEscapePressed: root.dismiss()
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
                text: modelData.label
                fontSize: Style.font.caption
                fontFamily: Style.font.family
                selected: root.selectedReminder === modelData.value
                onClicked: {
                  root.selectedReminder = modelData.value
                  root.showReminderOptions = false
                }
              }
            }

            Button {
              visible: Boolean(root.selectedReminder)
              iconText: "󰅖"
              text: "Clear"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              onClicked: {
                root.selectedReminder = ""
                root.showReminderOptions = false
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
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌑 Enter  •  Esc Cancel"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            id: actionButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Button {
              iconText: "󰅖"
              text: "Cancel"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              onClicked: root.dismiss()
            }

            Button {
              iconText: "󰐕"
              text: "Add"
              fontSize: Style.font.caption
              fontFamily: Style.font.family
              selected: true
              onClicked: root.submit()
            }
          }
        }
      }
    }
  }
}
