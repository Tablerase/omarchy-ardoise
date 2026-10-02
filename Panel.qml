import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore

Panel {
  id: root
  moduleName: "tablerase.ardoise"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var barWidget: null

  property string detectedShortcut: detectedPanelShortcut
  property string detectedPanelShortcut: "SUPER + ALT + T"
  property string detectedQuickAddShortcut: "SUPER + SHIFT + T"

  property bool panelShortcutRegistered: false
  property bool quickAddShortcutRegistered: false
  property bool shortcutRegistered: panelShortcutRegistered || quickAddShortcutRegistered
  property string shortcutState: (panelShortcutRegistered && quickAddShortcutRegistered)
    ? "active"
    : ((panelShortcutRegistered || quickAddShortcutRegistered) ? "partial" : "missing")
  readonly property bool hasShortcut: shortcutRegistered

  onOpenedChanged: {
    if (opened) {
      checkShortcutProc.running = true
      if (panelContent && typeof panelContent.refreshReminderPresets === "function") {
        panelContent.refreshReminderPresets()
      }
    }
  }
  Component.onCompleted: checkShortcutProc.running = true

  function parseBinds(rawText) {
    var panelFound = false
    var quickAddFound = false
    var panelKey = "SUPER + ALT + T"
    var quickAddKey = "SUPER + SHIFT + T"

    try {
      var list = JSON.parse(rawText)
      if (Array.isArray(list)) {
        for (var i = 0; i < list.length; i++) {
          var item = list[i]
          if (!item) continue
          var desc = (item.description && typeof item.description === "string") ? item.description.toLowerCase() : ""
          var arg = (item.arg && typeof item.arg === "string") ? item.arg : ""
          var isArdoise = (desc && (desc.includes("todo") || desc.includes("ardoise"))) ||
                          (arg && (arg.includes("tablerase.ardoise") || arg.includes("tablerase.todo")))
          if (!isArdoise) continue

          var keybind = TodoStore.formatKeybind(item.modmask, item.key)

          var isQuickAdd = (desc && (desc.includes("quick") || desc.includes("add"))) ||
                           (arg && (arg.includes("shell toggle") || arg.includes("shell summon") || arg.includes("quickadd")))
          var isPanel = (desc && (desc.includes("panel") || desc.includes("toggle") || desc.includes("main") || desc.includes("open"))) ||
                        (arg && (arg.includes("tablerase.ardoise toggle") || arg.includes("tablerase.ardoise open")))

          if (isQuickAdd && !quickAddFound) {
            quickAddKey = keybind
            quickAddFound = true
          } else if (isPanel && !panelFound) {
            panelKey = keybind
            panelFound = true
          } else if (!panelFound) {
            panelKey = keybind
            panelFound = true
          } else if (!quickAddFound) {
            quickAddKey = keybind
            quickAddFound = true
          }
        }
      }
    } catch (e) {
      panelFound = false
      quickAddFound = false
      panelKey = "SUPER + ALT + T"
      quickAddKey = "SUPER + SHIFT + T"
    }

    root.detectedPanelShortcut = panelKey
    root.detectedQuickAddShortcut = quickAddKey
    root.detectedShortcut = panelKey
    root.panelShortcutRegistered = panelFound
    root.quickAddShortcutRegistered = quickAddFound
    root.shortcutRegistered = panelFound || quickAddFound
  }

  // Query running Hyprland compositor for active keybinding
  Process {
    id: checkShortcutProc
    command: ["bash", "-c", "hyprctl -j binds 2>/dev/null || echo '[]'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseBinds(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.shortcutRegistered) {
        root.detectedPanelShortcut = "SUPER + ALT + T"
        root.detectedQuickAddShortcut = "SUPER + SHIFT + T"
        root.detectedShortcut = "SUPER + ALT + T"
        root.panelShortcutRegistered = false
        root.quickAddShortcutRegistered = false
        root.shortcutRegistered = false
      }
    }
  }

  // Copy keybinding snippets to clipboard and open bindings file in editor
  Process {
    id: copyAndOpenProc
    command: [
      "bash",
      "-c",
      "if [ -f \"$HOME/.config/hypr/bindings.lua\" ]; then FILE=\"$HOME/.config/hypr/bindings.lua\"; SNIPPET=\"o.bind(\\\"SUPER + ALT + T\\\", \\\"Ardoise Panel Toggle\\\", \\\"omarchy-shell tablerase.ardoise toggle\\\")\\no.bind(\\\"SUPER + SHIFT + T\\\", \\\"Ardoise Quick Add\\\", \\\"omarchy-shell shell toggle tablerase.ardoise '{}'\\\")\"; else FILE=\"$HOME/.config/hypr/bindings.conf\"; SNIPPET=\"bindd = SUPER ALT, T, Ardoise Panel Toggle, exec, omarchy-shell tablerase.ardoise toggle\\nbindd = SUPER SHIFT, T, Ardoise Quick Add, exec, omarchy-shell shell toggle tablerase.ardoise \\\"{}\\\"\"; fi; wl-copy \"$SNIPPET\" && notify-send -a 'Ardoise' 'Keybindings Copied & Config Opened' \"Paste into $(basename \\\"$FILE\\\") and run hyprctl reload\" && omarchy-launch-editor \"$FILE\""
    ]
    onExited: function(exitCode) {
      checkShortcutProc.running = true
    }
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    // When a modal is open, enforce a minimum panel height so the modal
    // always has enough room to render — independent of task-list content count.
    contentHeight: panel.fittedContentHeight(
      (panelContent.showKeyHelp || panelContent.showGitModal || panelContent.showArchiveModal || panelContent.showTaskMenu)
        ? Math.max(panelContent.implicitHeight, Style.space(380))
        : panelContent.implicitHeight
    )

    property bool _returnHandledThisFrame: false

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: panelContent.activeFocusBlocked
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F2) {
          event.accepted = true
          panelContent.handleTextKey("r")
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
          event.accepted = true
          panelContent.activateSearch()
        }
      }
      Keys.onReleased: function(event) {
        if (event.isAutoRepeat) return
        if (event.key === Qt.Key_X || event.text === "x" || event.text === "X") {
          panelContent.handleKeyRelease("x")
        } else if (event.key === Qt.Key_C || event.text === "c" || event.text === "C") {
          panelContent.handleKeyRelease("c")
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          panelContent.handleKeyRelease("action")
        }
      }
      onCloseRequested: {
        if (panelContent.handleEscape && panelContent.handleEscape()) return
        root.close()
      }
      onTabRequested: function(direction) {
        if (!panelContent.handleTab(direction)) {
          root.switchPanel(direction)
        }
      }
      onMoveRequested: function(dx, dy) {
        panelContent.handleMove(dx, dy)
      }
      onReturnRequested: {
        panel._returnHandledThisFrame = true
        Qt.callLater(function() { panel._returnHandledThisFrame = false })
        panelContent.handleReturn()
      }
      onActivateRequested: {
        if (panel._returnHandledThisFrame) return
        panelContent.handleActivate()
      }
      onDeleteRequested: {
        panelContent.handleDelete()
      }
      onTextKey: function(t) {
        panelContent.handleTextKey(t)
      }

      PanelContent {
        id: panelContent
        anchors.fill: parent
        bar: root.bar
        barWidget: root.barWidget
        shortcutState: root.shortcutState
        detectedShortcut: root.detectedShortcut
        detectedPanelShortcut: root.detectedPanelShortcut
        detectedQuickAddShortcut: root.detectedQuickAddShortcut
        panelShortcutRegistered: root.panelShortcutRegistered
        quickAddShortcutRegistered: root.quickAddShortcutRegistered
        shortcutRegistered: root.shortcutRegistered
        onReturnFocusRequested: keyCatcher.forceActiveFocus()
        onCloseRequested: root.close()
        onShortcutClicked: {
          copyAndOpenProc.running = true
          root.close()
        }
        onSwitchPanelRequested: function(direction) {
          root.switchPanel(direction)
        }
      }
    }
  }
}
