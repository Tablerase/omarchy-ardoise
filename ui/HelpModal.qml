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
  property string detectedShortcut: "SUPER + SHIFT + T"

  signal closeRequested()

  property string search: ""
  property string focusSection: "search" // "search" | "list" | "close"
  readonly property var keybindingsList: Logic.getKeybindingsList(root.detectedShortcut)
  readonly property var filteredKeybindings: Logic.filterKeybindings(root.keybindingsList, root.search)
  readonly property bool searchFieldActiveFocus: root.isOpen && (keySearchField.activeFocus || (root.focusSection === "search"))

  function open() {
    search = ""
    focusSection = "search"
    isOpen = true
    Qt.callLater(function() {
      if (keySearchField) keySearchField.forceActiveFocus()
    })
  }

  function close() {
    isOpen = false
    focusSection = "search"
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
      Qt.callLater(function() {
        if (keySearchField) keySearchField.forceActiveFocus()
      })
    }
  }

  anchors.fill: parent
  visible: isOpen
  z: 999
  color: Util.alpha(Color.popups.background, 0.96)
  radius: Style.cornerRadius
  focus: true

  Keys.onEscapePressed: function(event) {
    event.accepted = true
    root.close()
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      root.close()
      return
    }
    if (root.focusSection === "search") {
      if (event.key === Qt.Key_I || event.key === Qt.Key_A || (event.text === "i" || event.text === "a")) {
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
          keySearchField.forceActiveFocus()
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

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (keySearchField.activeFocus) {
        keySearchField.focus = false
        root.focusSection = "search"
        root.forceActiveFocus()
      }
    }
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
        tooltipText: "Close (Esc)"
        onClicked: root.close()
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
        color: Style.controlFill(keySearchField.activeFocus || isNavFocused, keySearchField.hovered, root.barForeground, Color.accent)
        borderSpec: Border.controlSpec(
          (keySearchField.activeFocus || isNavFocused) ? "focus" : (keySearchField.hovered ? "hover-cursor" : "normal"),
          root.barForeground,
          Color.accent
        )
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
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }

      Keys.onTabPressed: function(event) {
        event.accepted = true
        root.focusSection = "list"
        helpFlickable.focus = true
        helpFlickable.forceActiveFocus()
      }

      Keys.onBacktabPressed: function(event) {
        event.accepted = true
        root.focusSection = "close"
        closeHelpBtn.forceActiveFocus()
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
        var itemY = selectedIndex * Style.space(31)
        if (itemY < contentY) {
          contentY = itemY
        } else if (itemY + Style.space(31) > contentY + height) {
          contentY = Math.max(0, itemY + Style.space(31) - height)
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
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.text === "?" || event.text === "q") {
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
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: root.filteredKeybindings

          Rectangle {
            id: keyHelpRow
            required property var modelData
            required property int index
            readonly property bool isSelected: helpFlickable.activeFocus && (helpFlickable.selectedIndex === index)
            width: parent.width
            implicitHeight: Style.space(26)
            radius: Style.cornerRadius
            color: isSelected ? Util.alpha(Color.accent, 0.14) : Color.menu.selectedBackground
            border.color: isSelected ? Color.accent : Color.menu.border
            border.width: isSelected ? 1.5 : 1

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: keyLabel.implicitWidth + Style.space(8)
                implicitHeight: Style.space(18)
                radius: Style.space(4)
                color: Util.alpha(Color.accent, 0.15)
                border.color: Color.accent
                border.width: 1

                Text {
                  id: keyLabel
                  anchors.centerIn: parent
                  text: keyHelpRow.modelData.key
                  color: Color.accent
                  font.family: "monospace"
                  font.pixelSize: Style.space(9)
                  font.bold: true
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: keyHelpRow.modelData.desc
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: keyHelpRow.modelData.category
              color: Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.space(8.5)
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Press Esc or ? to close"
      color: Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.space(9)
    }
  }
}
