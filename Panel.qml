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

  property string shortcutState: "missing"
  readonly property bool hasShortcut: shortcutState === "active"

  onOpenedChanged: if (opened) checkShortcutProc.running = true
  Component.onCompleted: checkShortcutProc.running = true

  // Query running Hyprland compositor or config files for active/commented keybinding
  Process {
    id: checkShortcutProc
    command: [
      "bash",
      "-c",
      "if hyprctl binds 2>/dev/null | grep -E -q 'Todo Quick Add|tablerase\\.todo'; then echo 'active'; elif grep -E -s -q '^[[:space:]]*(o\\.bind|bindd?).*(tablerase\\.todo|Todo Quick Add)' \"$HOME/.config/hypr/bindings.lua\" \"$HOME/.config/hypr/bindings.conf\" 2>/dev/null; then echo 'active'; elif grep -E -s -q '^[[:space:]]*(--|#).*(tablerase\\.todo|Todo Quick Add)' \"$HOME/.config/hypr/bindings.lua\" \"$HOME/.config/hypr/bindings.conf\" 2>/dev/null; then echo 'commented'; else echo 'missing'; fi"
    ]
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line).trim()
        if (s === "active" || s === "commented" || s === "missing") {
          root.shortcutState = s
        }
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
      onTabRequested: function(direction) { root.switchPanel(direction) }

      PanelContent {
        id: panelContent
        anchors.fill: parent
        bar: root.bar
        barWidget: root.barWidget
        shortcutState: root.shortcutState
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
