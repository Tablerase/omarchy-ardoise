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

  property string detectedShortcut: "SUPER + SHIFT + T"
  property bool shortcutRegistered: false
  property string shortcutState: shortcutRegistered ? "active" : "missing"
  readonly property bool hasShortcut: shortcutRegistered

  onOpenedChanged: if (opened) checkShortcutProc.running = true
  Component.onCompleted: checkShortcutProc.running = true

  function parseBinds(rawText) {
    var found = false
    var shortcut = "SUPER + SHIFT + T"
    try {
      var list = JSON.parse(rawText)
      if (Array.isArray(list)) {
        for (var i = 0; i < list.length; i++) {
          var item = list[i]
          if (!item) continue
          var desc = (item.description && typeof item.description === "string") ? item.description.toLowerCase() : ""
          var arg = (item.arg && typeof item.arg === "string") ? item.arg : ""
          var matches = (desc && (desc.includes("todo") || desc.includes("ardoise"))) ||
                        (arg && (arg.includes("tablerase.ardoise") || arg.includes("tablerase.todo")))
          if (matches) {
            shortcut = TodoStore.formatKeybind(item.modmask, item.key)
            found = true
            break
          }
        }
      }
    } catch (e) {
      found = false
      shortcut = "SUPER + SHIFT + T"
    }

    root.detectedShortcut = shortcut
    root.shortcutRegistered = found
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
        root.detectedShortcut = "SUPER + SHIFT + T"
        root.shortcutRegistered = false
      }
    }
  }

  // Copy keybinding snippet to clipboard and open bindings file in editor
  Process {
    id: copyAndOpenProc
    command: [
      "bash",
      "-c",
      "if [ -f \"$HOME/.config/hypr/bindings.lua\" ]; then FILE=\"$HOME/.config/hypr/bindings.lua\"; SNIPPET=\"o.bind(\\\"SUPER + SHIFT + T\\\", \\\"Ardoise Quick Add\\\", \\\"omarchy-shell shell toggle tablerase.ardoise '{}'\\\")\"; else FILE=\"$HOME/.config/hypr/bindings.conf\"; SNIPPET=\"bindd = SUPER SHIFT, T, Ardoise Quick Add, exec, omarchy-shell shell toggle tablerase.ardoise \\\"{}\\\"\"; fi; wl-copy \"$SNIPPET\" && notify-send -a 'Ardoise' 'Keybinding Copied & Config Opened' \"Paste into $(basename \\\"$FILE\\\") and run hyprctl reload\" && omarchy-launch-editor \"$FILE\""
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
    contentHeight: panel.fittedContentHeight(panelContent.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: panelContent.activeFocusBlocked
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (!panelContent.handleTab(direction)) {
          root.switchPanel(direction)
        }
      }
      onMoveRequested: function(dx, dy) {
        panelContent.handleMove(dx, dy)
      }
      onActivateRequested: {
        panelContent.handleActivate()
      }
      onReturnRequested: {
        panelContent.handleReturn()
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
