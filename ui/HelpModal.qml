import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../PanelLogic.js" as Logic

Rectangle {
  id: root

  property bool isOpen: false
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property string detectedShortcut: detectedPanelShortcut
  property string detectedPanelShortcut: "SUPER + ALT + T"
  property string detectedQuickAddShortcut: "SUPER + SHIFT + T"

  signal closeRequested()

  property var activeBindings: null
  readonly property string helpShortcutHint: {
    if (root.activeBindings && root.activeBindings.bindings && root.activeBindings.bindings.help && root.activeBindings.bindings.help.length > 0) {
      return root.activeBindings.bindings.help.join(" or ")
    }
    return "?"
  }

  function isHelpDismissKey(event) {
    if (event.key === Qt.Key_Escape) return true
    if (event.text === "q") return true
    if (root.activeBindings && root.activeBindings.bindings && root.activeBindings.bindings.help) {
      var keys = root.activeBindings.bindings.help
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i]
        if (event.text && (event.text === k || event.text.toLowerCase() === k.toLowerCase())) return true
        if (k === "F1" && event.key === Qt.Key_F1) return true
        if (k === "F2" && event.key === Qt.Key_F2) return true
        if (k === "F3" && event.key === Qt.Key_F3) return true
        if (k === "F4" && event.key === Qt.Key_F4) return true
        if (k === "F5" && event.key === Qt.Key_F5) return true
        if (k === "F6" && event.key === Qt.Key_F6) return true
        if (k === "F7" && event.key === Qt.Key_F7) return true
        if (k === "F8" && event.key === Qt.Key_F8) return true
        if (k === "F9" && event.key === Qt.Key_F9) return true
        if (k === "F10" && event.key === Qt.Key_F10) return true
        if (k === "F11" && event.key === Qt.Key_F11) return true
        if (k === "F12" && event.key === Qt.Key_F12) return true
      }
    } else {
      if (event.text === "?") return true
    }
    return false
  }

  property string search: ""
  onSearchChanged: {
    if (helpFlickable) {
      helpFlickable.selectedIndex = 0
      helpFlickable.contentY = 0
    }
  }
  property string focusSection: "search" // "search" | "list" | "close"
  readonly property var keybindingsList: Logic.getKeybindingsList(root.detectedPanelShortcut, root.detectedQuickAddShortcut, root.activeBindings)
  readonly property var filteredKeybindings: Logic.filterKeybindings(root.keybindingsList, root.search)
  readonly property bool searchFieldActiveFocus: root.isOpen && (keySearchField.activeFocus || (root.focusSection === "search"))

  function open() {
    search = ""
    focusSection = "search"
    isOpen = true
    if (helpFlickable) {
      helpFlickable.selectedIndex = 0
      helpFlickable.contentY = 0
    }
    if (keySearchField) keySearchField.focus = false
    Qt.callLater(function() {
      root.forceActiveFocus()
    })
  }

  function close() {
    isOpen = false
    focusSection = "search"
    if (keySearchField) keySearchField.focus = false
    root.closeRequested()
  }

  function toggle() {
    if (isOpen) close()
    else open()
  }

  onIsOpenChanged: {
    if (isOpen) {
      search = ""
      focusSection = "search"
      if (keySearchField) keySearchField.focus = false
      Qt.callLater(function() {
        root.forceActiveFocus()
      })
    } else {
      if (keySearchField) keySearchField.focus = false
    }
  }

  anchors.fill: parent
  visible: isOpen
  z: 999
  color: {
    var base = (Color.popups && Color.popups.background) ? Color.popups.background : Color.background
    return Qt.rgba(base.r, base.g, base.b, 1.0)
  }
  radius: Style.cornerRadius
  focus: true

  Keys.onEscapePressed: function(event) {
    event.accepted = true
    root.close()
  }

  Keys.onPressed: function(event) {
    if (root.isHelpDismissKey(event)) {
      event.accepted = true
      root.close()
      return
    }
    if (root.focusSection === "search") {
      if (event.key === Qt.Key_I || event.key === Qt.Key_A || event.text === "i" || event.text === "a" || event.text === "/") {
        event.accepted = true
        keySearchField.forceActiveFocus()
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        event.accepted = true
        keySearchField.forceActiveFocus()
        return
      }
      if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.text === "j") {
        event.accepted = true
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
        return
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.text === "k") {
        event.accepted = true
        root.focusSection = "close"
        closeHelpBtn.forceActiveFocus()
        return
      }
      if (event.key === Qt.Key_Backspace) {
        event.accepted = true
        if (keySearchField.text.length > 0) {
          keySearchField.text = keySearchField.text.slice(0, -1)
          keySearchField.cursorPosition = keySearchField.text.length
        } else {
          root.close()
        }
        return
      }
      if (event.text && event.text.length === 1 && !event.modifiers) {
        event.accepted = true
        keySearchField.forceActiveFocus()
        keySearchField.text += event.text
        keySearchField.cursorPosition = keySearchField.text.length
        return
      }
    }
  }

  // Unconditional mouse event blocker — prevents hover/click bleed-through to items below
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    z: -1
    onClicked: function(mouse) {
      if (keySearchField.activeFocus) {
        keySearchField.focus = false
        root.focusSection = "search"
        root.forceActiveFocus()
      } else {
        root.forceActiveFocus()
      }
    }
    onWheel: function(wheel) { wheel.accepted = true }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    // Modal header
    Item {
      width: parent.width
      implicitHeight: Math.max(helpTitle.implicitHeight, closeHelpBtn.implicitHeight)

      Text {
        id: helpTitle
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "󰞋 Keyboard & Vim Shortcuts"
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      PanelActionButton {
        id: closeHelpBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(24)
        iconText: "󰅖"
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        foreground: (root.focusSection === "close") ? (root.bar ? root.bar.urgent : Color.urgent) : Color.muted
        hoverColor: root.bar ? root.bar.urgent : Color.urgent
        hasCursor: root.focusSection === "close"
        tooltipText: ""
        onClicked: root.close()

        HoverHandler { id: closeHelpBtnHover }
        ShortcutToolTip {
          visible: closeHelpBtnHover.hovered
          description: "Close"
          shortcut: "Esc"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }
        onActiveFocusChanged: {
          if (activeFocus) {
            root.focusSection = "close"
          }
        }
        Keys.onEscapePressed: function(event) {
          event.accepted = true
          root.close()
        }
        Keys.onTabPressed: function(event) {
          event.accepted = true
          root.focusSection = "search"
          root.forceActiveFocus()
        }
        Keys.onDownPressed: function(event) {
          event.accepted = true
          root.focusSection = "search"
          root.forceActiveFocus()
        }
        Keys.onBacktabPressed: function(event) {
          event.accepted = true
          root.focusSection = "list"
          helpFlickable.focus = true
          helpFlickable.forceActiveFocus()
        }
        Keys.onUpPressed: function(event) {
          event.accepted = true
          root.focusSection = "list"
          helpFlickable.focus = true
          helpFlickable.forceActiveFocus()
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_J || event.text === "j") {
            event.accepted = true
            root.focusSection = "search"
            root.forceActiveFocus()
            return
          }
          if (event.key === Qt.Key_K || event.text === "k") {
            event.accepted = true
            root.focusSection = "list"
            helpFlickable.focus = true
            helpFlickable.forceActiveFocus()
            return
          }
          if (root.isHelpDismissKey(event)) {
            event.accepted = true
            root.close()
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.close()
            return
          }
        }
      }
    }

    // Search input to filter shortcuts
    TextField {
      id: keySearchField
      width: parent.width
      placeholderText: "Search shortcuts (e.g. vim, add, esc, tab)..."
      placeholderTextColor: Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      color: root.barForeground
      selectByMouse: true
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      topPadding: Style.space(8)
      bottomPadding: Style.space(8)
      text: root.search
      onTextChanged: root.search = text

      background: BorderSurface {
        readonly property bool isNavFocused: (root.focusSection === "search") && !keySearchField.activeFocus
        color: keySearchField.activeFocus
          ? Util.alpha(Color.accent, 0.08)
          : Style.controlFill(false, keySearchField.hovered, root.barForeground, Color.accent)
        borderSpec: keySearchField.activeFocus
          ? Border.flat(Color.accent, 2)
          : (isNavFocused
              ? Border.flat(Color.accent, 1)
              : (keySearchField.hovered ? Border.controlSpec("hover-cursor", root.barForeground, Color.accent)
                                      : Border.controlSpec("normal", root.barForeground, Color.accent)))
        radius: Style.cornerRadius
      }

      onActiveFocusChanged: {
        if (activeFocus) {
          root.focusSection = "search"
        }
      }

      Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (keySearchField.text.trim().length === 0) {
          root.close()
        } else {
          keySearchField.focus = false
          root.focusSection = "search"
          root.forceActiveFocus()
        }
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Backspace && keySearchField.text.length === 0) {
          event.accepted = true
          root.close()
        }
      }

      Keys.onDownPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }

      Keys.onUpPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "close"
        closeHelpBtn.forceActiveFocus()
      }

      Keys.onTabPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }

      Keys.onBacktabPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "close"
        closeHelpBtn.forceActiveFocus()
      }

      Keys.onReturnPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }

      Keys.onEnterPressed: function(event) {
        event.accepted = true
        keySearchField.focus = false
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }
    }

    PanelSeparator { width: parent.width }

    // Filtered list of shortcuts
    Flickable {
      id: helpFlickable
      width: parent.width
      height: Math.max(Style.space(120), parent.height - y - Style.space(26))
      contentWidth: width
      contentHeight: helpListCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      focus: true

      property int selectedIndex: 0

      onActiveFocusChanged: {
        if (activeFocus) {
          root.focusSection = "list"
        }
      }

      function ensureItemVisible() {
        if (!helpListRepeater || selectedIndex < 0 || selectedIndex >= helpListRepeater.count) return
        var item = helpListRepeater.itemAt(selectedIndex)
        if (!item) return
        var itemY = item.y
        var itemH = item.height
        if (itemY < contentY) {
          contentY = itemY
        } else if (itemY + itemH > contentY + height) {
          contentY = Math.max(0, itemY + itemH - height)
        }
      }

      Keys.onUpPressed: function(event) {
        event.accepted = true
        if (selectedIndex > 0) {
          selectedIndex--
          ensureItemVisible()
        } else {
          root.focusSection = "search"
          root.forceActiveFocus()
        }
      }

      Keys.onDownPressed: function(event) {
        event.accepted = true
        if (selectedIndex < root.filteredKeybindings.length - 1) {
          selectedIndex++
          ensureItemVisible()
        }
      }

      Keys.onPressed: function(event) {
        if (event.text === "j") {
          event.accepted = true
          if (selectedIndex < root.filteredKeybindings.length - 1) {
            selectedIndex++
            ensureItemVisible()
          }
        } else if (event.text === "k") {
          event.accepted = true
          if (selectedIndex > 0) {
            selectedIndex--
            ensureItemVisible()
          } else {
            root.focusSection = "search"
            root.forceActiveFocus()
          }
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || root.isHelpDismissKey(event)) {
          event.accepted = true
          root.close()
        } else if (event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.focusSection = "search"
          root.forceActiveFocus()
        } else if (event.key === Qt.Key_Tab) {
          event.accepted = true
          root.focusSection = "close"
          closeHelpBtn.forceActiveFocus()
        } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier || event.text === "G")) {
          event.accepted = true
          if (root.filteredKeybindings.length > 0) {
            selectedIndex = root.filteredKeybindings.length - 1
            ensureItemVisible()
          }
        } else if (event.key === Qt.Key_G || event.text === "g") {
          event.accepted = true
          selectedIndex = 0
          ensureItemVisible()
        } else if (event.text === "/" || event.text === "i" || event.text === "a") {
          event.accepted = true
          root.focusSection = "search"
          keySearchField.forceActiveFocus()
        } else if (event.text && event.text.length === 1 && event.text !== "j" && event.text !== "k") {
          event.accepted = true
          root.focusSection = "search"
          keySearchField.forceActiveFocus()
          keySearchField.text += event.text
          keySearchField.cursorPosition = keySearchField.text.length
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: helpListCol.implicitHeight > helpFlickable.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }

      Column {
        id: helpListCol
        width: helpFlickable.width - Style.space(8)
        spacing: Style.space(6)

        Repeater {
          id: helpListRepeater
          model: root.filteredKeybindings

          Rectangle {
            id: keyHelpRow
            required property var modelData
            required property int index
            readonly property bool isSelected: helpFlickable.activeFocus && (helpFlickable.selectedIndex === index)
            width: parent.width
            implicitHeight: cardCol.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: isSelected ? Util.alpha(Color.accent, 0.14) : Color.menu.selectedBackground
            border.color: isSelected ? Color.accent : Color.menu.border
            border.width: isSelected ? 1.5 : 1

            Column {
              id: cardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: Math.max(badgeItem.implicitHeight, categoryText.implicitHeight)

                KeyBadge {
                  id: badgeItem
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  keyText: keyHelpRow.modelData.key
                }

                Text {
                  id: categoryText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: keyHelpRow.modelData.category
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.space(8.5)
                }
              }

              Text {
                width: parent.width
                text: keyHelpRow.modelData.desc
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Press Esc or " + root.helpShortcutHint + " to close"
      color: Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.space(9)
    }
  }
}
