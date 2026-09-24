// =============================================================================
// TaskNotesArea.qml
//
// Reusable multi-line auto-expanding notes & description editor with scrollbar,
// Shift+Enter line breaks, Enter to commit, Escape to blur, and blur autosave.
// Shared across PanelContent task rows and the QuickAdd modal.
// =============================================================================

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

ScrollView {
  id: root

  property string text: ""
  property string placeholderText: "Notes / description (Shift+Enter for newline)..."
  property var bar: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property color accentColor: Color.accent
  property int minHeight: Style.space(56)
  property int maxHeight: Style.space(130)
  property bool isNavFocused: false

  readonly property bool editorActiveFocus: textArea.activeFocus
  readonly property alias textArea: textArea

  signal saved(string newText)
  signal submitted()
  signal escapePressed()
  signal tabPressed(int direction)

  function forceActiveFocus() {
    textArea.forceActiveFocus()
  }

  function focusEditor() {
    textArea.forceActiveFocus()
  }

  function save() {
    if (root.text !== textArea.text) {
      root.text = textArea.text
      root.saved(textArea.text)
    }
  }

  onTextChanged: {
    if (textArea.text !== root.text) {
      textArea.text = root.text
    }
  }

  implicitHeight: Math.min(maxHeight, Math.max(minHeight, textArea.implicitHeight))
  clip: true

  background: BorderSurface {
    color: Style.controlFill(textArea.activeFocus || root.isNavFocused, textArea.hovered, root.foreground, root.accentColor)
    borderSpec: Border.controlSpec(
      (textArea.activeFocus || root.isNavFocused) ? "focus" : (textArea.hovered ? "hover-cursor" : "normal"),
      root.foreground,
      root.accentColor
    )
    radius: Style.cornerRadius
  }

  ScrollBar.vertical: ScrollBar {
    id: scrollBar
    policy: textArea.implicitHeight > root.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    interactive: true
    padding: 0
    implicitWidth: Style.space(3)

    contentItem: Rectangle {
      implicitWidth: Style.space(3)
      radius: Style.space(1.5)
      color: scrollBar.pressed ? root.accentColor : (scrollBar.hovered ? root.accentColor : Color.muted)
      opacity: scrollBar.active ? 0.9 : 0.4
    }

    background: Rectangle {
      implicitWidth: Style.space(3)
      radius: Style.space(1.5)
      color: Color.menu.selectedBackground
      opacity: 0.25
    }
  }

  TextArea {
    id: textArea
    width: root.availableWidth
    text: root.text
    placeholderText: root.placeholderText
    wrapMode: TextEdit.Wrap
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    color: root.foreground
    selectionColor: Style.selectionFillFor(root.foreground, root.accentColor)
    selectedTextColor: root.foreground
    placeholderTextColor: Qt.darker(root.foreground, 1.6)
    leftPadding: Style.space(8)
    rightPadding: Style.space(8)
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)
    background: null

    function insertLineBreak() {
      if (selectedText && selectedText.length > 0) {
        var s = selectionStart
        var e = selectionEnd
        remove(s, e)
        insert(s, "\n")
      } else {
        insert(cursorPosition, "\n")
      }
    }

    Keys.onReturnPressed: function(event) {
      if (event.modifiers & Qt.ShiftModifier) {
        insertLineBreak()
        event.accepted = true
      } else {
        event.accepted = true
        root.save()
        root.submitted()
        focus = false
      }
    }

    Keys.onEnterPressed: function(event) {
      if (event.modifiers & Qt.ShiftModifier) {
        insertLineBreak()
        event.accepted = true
      } else {
        event.accepted = true
        root.save()
        root.submitted()
        focus = false
      }
    }

    Keys.onEscapePressed: function(event) {
      event.accepted = true
      root.save()
      root.escapePressed()
      focus = false
    }

    Keys.onTabPressed: function(event) {
      event.accepted = true
      root.save()
      root.tabPressed(1)
    }

    Keys.onBacktabPressed: function(event) {
      event.accepted = true
      root.save()
      root.tabPressed(-1)
    }

    onActiveFocusChanged: {
      if (!activeFocus) {
        root.save()
      }
    }

    onEditingFinished: {
      root.save()
    }

    Component.onDestruction: {
      root.save()
    }
  }
}
