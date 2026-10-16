import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

Item {
  id: root

  property var store: null
  property var profiles: []
  property string selectedProfile: ""
  property int focusedIndex: -1
  property bool isNavFocused: false
  property bool wrap: false
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property color accentColor: Color.accent
  property color fadeColor: Color.menu.background
  readonly property color secondaryText: TodoStore.getReadableSecondary(Color.popups.background, Color.muted, root.barForeground)

  signal profileSelected(string profileName, int index)
  signal editIconRequested(string profileName, int index)

  implicitHeight: root.wrap ? (profileFlow.implicitHeight + Style.space(4)) : Style.space(26)
  implicitWidth: root.wrap ? parent.width : profileRow.implicitWidth

  function resetScroll() {
    if (!root.wrap) {
      profileFlickable.contentX = 0
    }
  }

  function ensureVisible(idx) {
    if (root.wrap || !profileRepeater || idx < 0 || idx >= profileRepeater.count) return
    if (profileFlickable.width <= 0 || profileFlickable.contentWidth <= 0) return
    if (profileFlickable.contentWidth <= profileFlickable.width) {
      profileFlickable.contentX = 0
      return
    }
    var item = profileRepeater.itemAt(idx)
    if (!item) return
    var padLeft = leftFadeEdge.width + Style.space(4)
    var padRight = rightFadeEdge.width + Style.space(4)
    var itemLeft = item.x
    var itemRight = item.x + item.width

    if (idx === 0 || itemLeft - padLeft <= 0) {
      profileFlickable.contentX = 0
    } else if (itemLeft - padLeft < profileFlickable.contentX) {
      profileFlickable.contentX = Math.max(0, itemLeft - padLeft)
    } else if (itemRight + padRight > profileFlickable.contentX + profileFlickable.width) {
      var maxContentX = Math.max(0, profileFlickable.contentWidth - profileFlickable.width)
      profileFlickable.contentX = Math.min(maxContentX, Math.max(0, itemRight + padRight - profileFlickable.width))
    }
  }

  onFocusedIndexChanged: {
    if (!root.wrap && isNavFocused && focusedIndex >= 0) {
      ensureVisible(focusedIndex)
    }
  }

  onIsNavFocusedChanged: {
    if (!root.wrap && isNavFocused && focusedIndex >= 0) {
      ensureVisible(focusedIndex)
    }
  }

  onSelectedProfileChanged: {
    if (!root.wrap && profiles && profiles.length > 0) {
      var idx = profiles.indexOf(selectedProfile)
      if (idx !== -1) {
        Qt.callLater(function() { ensureVisible(idx) })
      }
    }
  }

  Component.onCompleted: {
    if (!root.wrap) {
      var targetIdx = (root.isNavFocused && root.focusedIndex >= 0)
        ? root.focusedIndex
        : (root.profiles ? root.profiles.indexOf(root.selectedProfile) : -1)
      if (targetIdx >= 0) {
        Qt.callLater(function() { ensureVisible(targetIdx) })
      }
    }
  }

  // Component definition for individual profile button pill
  Component {
    id: profileButtonComponent

    Rectangle {
      id: profileBtn
      required property string modelData
      required property int index
      readonly property bool isSelected: root.selectedProfile === modelData
      readonly property bool isBtnNavFocused: root.isNavFocused && (root.focusedIndex === index)

      implicitWidth: pillContent.implicitWidth + Style.space(12)
      implicitHeight: Style.space(20)
      radius: implicitHeight / 2
      color: isSelected ? root.accentColor : (isBtnNavFocused ? Util.alpha(root.accentColor, 0.25) : Color.menu.background)
      border.color: isBtnNavFocused ? root.accentColor : (isSelected ? root.accentColor : Color.menu.border)
      border.width: isBtnNavFocused ? 1.5 : 1
      scale: isBtnNavFocused ? 1.05 : 1.0
      Behavior on scale { NumberAnimation { duration: 80 } }

      Row {
        id: pillContent
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: TodoStore.getProfileGlyph(profileBtn.modelData, root.store)
          color: profileBtn.isSelected ? "white" : (profileBtn.isBtnNavFocused ? root.accentColor : root.secondaryText)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          id: profileText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Style.space(80))
          text: profileBtn.modelData
          color: profileBtn.isSelected ? "white" : (profileBtn.isBtnNavFocused ? root.accentColor : root.barForeground)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: profileBtn.isSelected || profileBtn.isBtnNavFocused
          elide: Text.ElideRight
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            root.editIconRequested(profileBtn.modelData, profileBtn.index)
            return
          }
          root.profileSelected(profileBtn.modelData, profileBtn.index)
          if (!root.wrap) {
            root.ensureVisible(profileBtn.index)
          }
        }
      }

      HoverHandler {
        id: profileHover
      }

      PanelToolTip {
        visible: profileHover.hovered && profileText.truncated
        text: profileBtn.modelData
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }

  // Wrap Mode (Flow Layout) - no clipping, wraps pills cleanly across rows
  Flow {
    id: profileFlow
    visible: root.wrap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(4)

    Repeater {
      id: profileFlowRepeater
      model: root.wrap ? root.profiles : []
      delegate: profileButtonComponent
    }
  }

  // Horizontal Scroll Mode (Single-line Flickable with fade edges)
  Flickable {
    id: profileFlickable
    visible: !root.wrap
    anchors.fill: parent
    anchors.bottomMargin: Style.space(4)
    contentWidth: profileRow.implicitWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    onWidthChanged: {
      if (!root.wrap && width > 0) {
        var targetIdx = (root.isNavFocused && root.focusedIndex >= 0)
          ? root.focusedIndex
          : (root.profiles ? root.profiles.indexOf(root.selectedProfile) : -1)
        if (targetIdx >= 0) {
          Qt.callLater(function() { root.ensureVisible(targetIdx) })
        }
      }
    }
    onContentWidthChanged: {
      if (!root.wrap && contentWidth > width) {
        var targetIdx = (root.isNavFocused && root.focusedIndex >= 0)
          ? root.focusedIndex
          : (root.profiles ? root.profiles.indexOf(root.selectedProfile) : -1)
        if (targetIdx >= 0) {
          Qt.callLater(function() { root.ensureVisible(targetIdx) })
        }
      }
    }

    Behavior on contentX {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    ScrollBar.horizontal: ScrollBar {
      id: hScrollBar
      policy: (!root.wrap && profileFlickable.contentWidth > profileFlickable.width) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      implicitHeight: Style.space(3)
      contentItem: Rectangle {
        radius: height / 2
        color: Util.alpha(Color.foreground, hScrollBar.pressed ? 0.5 : (hScrollBar.hovered ? 0.35 : 0.2))
        Behavior on color { ColorAnimation { duration: 100 } }
      }
      background: Item {}
    }

    Row {
      id: profileRow
      leftPadding: Style.space(6)
      rightPadding: Style.space(6)
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        id: profileRepeater
        model: !root.wrap ? root.profiles : []
        onCountChanged: {
          if (!root.wrap) {
            var targetIdx = (root.isNavFocused && root.focusedIndex >= 0)
              ? root.focusedIndex
              : (root.profiles ? root.profiles.indexOf(root.selectedProfile) : -1)
            if (targetIdx >= 0) {
              Qt.callLater(function() { root.ensureVisible(targetIdx) })
            }
          }
        }
        delegate: profileButtonComponent
      }
    }
  }

  // Soft blur/fade edge on the left
  Rectangle {
    id: leftFadeEdge
    z: 1
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(24)
    enabled: false
    visible: !root.wrap && opacity > 0
    opacity: (!root.wrap && profileFlickable.contentWidth > profileFlickable.width && profileFlickable.contentX > 2) ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.fadeColor }
      GradientStop { position: 1.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
    }
  }

  // Soft blur/fade edge on the right
  Rectangle {
    id: rightFadeEdge
    z: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(32)
    enabled: false
    visible: !root.wrap && opacity > 0
    opacity: (!root.wrap && profileFlickable.contentWidth > profileFlickable.width && profileFlickable.contentX < (profileFlickable.contentWidth - profileFlickable.width - 2)) ? 1.0 : 0.0

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
      GradientStop { position: 1.0; color: root.fadeColor }
    }
  }
}
