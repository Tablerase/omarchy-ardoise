import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

Rectangle {
  id: root

  property string mode: "profile" // "profile" | "tag"
  property var store: null
  property var bar: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color secondaryText: TodoStore.getReadableSecondary(Color.popups.background, Color.muted, root.barForeground)
  property string currentProfile: ""
  property var currentTags: []
  property string searchQuery: ""
  property int selectedIndex: 0

  signal profileSelected(string profileName)
  signal tagSelected(string tagName)
  signal closed()

  readonly property var matches: {
    var list = []
    if (mode === "profile") {
      list = (typeof TodoStore !== "undefined" && typeof TodoStore.searchProfiles === "function")
        ? TodoStore.searchProfiles(root.store, root.searchQuery)
        : []
    } else {
      list = (typeof TodoStore !== "undefined" && typeof TodoStore.searchTags === "function")
        ? TodoStore.searchTags(root.store, root.searchQuery)
        : []
    }
    return list || []
  }

  readonly property string cleanQuery: {
    var q = root.searchQuery ? String(root.searchQuery).replace(/^#+/, "").trim() : ""
    if (typeof TodoStore !== "undefined" && typeof TodoStore.cleanProfileName === "function") {
      return TodoStore.cleanProfileName(q)
    }
    return q.toLowerCase()
  }

  readonly property bool canCreateNew: {
    if (!root.cleanQuery) return false
    for (var i = 0; i < matches.length; i++) {
      if (String(matches[i]).toLowerCase() === root.cleanQuery.toLowerCase()) return false
    }
    return true
  }

  readonly property int totalCount: matches.length + (canCreateNew ? 1 : 0)

  function applySelection(idx) {
    if (idx < 0 || idx >= totalCount) return
    var item = (idx < matches.length) ? matches[idx] : root.cleanQuery
    if (!item) return
    if (mode === "profile") {
      root.profileSelected(item)
    } else {
      root.tagSelected(item)
    }
    root.closed()
  }

  function reset() {
    searchQuery = ""
    selectedIndex = 0
    if (searchInput) {
      searchInput.text = ""
      searchInput.forceActiveFocus()
    }
  }

  implicitHeight: searchBoxCol.implicitHeight + Style.space(8)
  radius: Style.cornerRadius
  color: (Color.popups && Color.popups.background) ? Color.popups.background : Color.menu.background
  border.color: Util.alpha(Color.accent, 0.4)
  border.width: 1
  clip: true

  Column {
    id: searchBoxCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(4)
    spacing: Style.space(4)

    // Row 1: Search Input
    Rectangle {
      width: parent.width
      height: Style.space(24)
      radius: Style.cornerRadius - 2
      color: Util.alpha(Color.menu.selectedBackground, 0.5)
      border.color: searchInput.activeFocus ? Color.accent : Color.menu.border
      border.width: searchInput.activeFocus ? 1.5 : 1

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          color: Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        TextField {
          id: searchInput
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(34)
          placeholderText: root.mode === "profile" ? "Search or add profile..." : "Search or add tag..."
          placeholderTextColor: root.secondaryText
          color: Color.menu.text || Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          background: Item {}
          padding: 0
          leftPadding: 0
          rightPadding: 0
          topPadding: 0
          bottomPadding: 0
          text: root.searchQuery
          onTextChanged: {
            root.searchQuery = text
            root.selectedIndex = 0
          }

          Keys.onDownPressed: function(event) {
            event.accepted = true
            if (root.totalCount > 0) {
              root.selectedIndex = (root.selectedIndex + 1) % root.totalCount
            }
          }

          Keys.onUpPressed: function(event) {
            event.accepted = true
            if (root.totalCount > 0) {
              root.selectedIndex = (root.selectedIndex - 1 + root.totalCount) % root.totalCount
            }
          }

          Keys.onTabPressed: function(event) {
            event.accepted = true
            if (root.totalCount > 0) {
              root.selectedIndex = (root.selectedIndex + 1) % root.totalCount
            }
          }

          Keys.onBacktabPressed: function(event) {
            event.accepted = true
            if (root.totalCount > 0) {
              root.selectedIndex = (root.selectedIndex - 1 + root.totalCount) % root.totalCount
            }
          }

          Keys.onReturnPressed: function(event) {
            event.accepted = true
            if (root.totalCount > 0) {
              root.applySelection(root.selectedIndex)
            } else if (root.cleanQuery) {
              root.applySelection(0)
            }
          }

          Keys.onEscapePressed: function(event) {
            event.accepted = true
            if (searchInput.text.length > 0) {
              searchInput.text = ""
              root.searchQuery = ""
            } else {
              root.closed()
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅖"
          color: closeHover.hovered ? Color.urgent : root.secondaryText
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.space(10)

          HoverHandler {
            id: closeHover
          }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (searchInput.text.length > 0) {
                searchInput.text = ""
                root.searchQuery = ""
              } else {
                root.closed()
              }
            }
          }
        }
      }
    }

    // Row 2: Header (Mode & Count)
    Row {
      width: parent.width
      height: Style.space(18)
      spacing: Style.space(6)
      padding: Style.space(2)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.mode === "profile" ? "󰭤" : "󰓹"
        color: Color.accent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.mode === "profile" ? "Profiles" : "Tags"
        color: root.secondaryText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "(" + root.totalCount + ")"
        color: root.secondaryText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.space(8.5)
      }
    }

    // Row 3: Suggestions List (Flickable with max height)
    Flickable {
      id: listFlickable
      width: parent.width
      implicitHeight: Math.min(Style.space(120), listCol.implicitHeight)
      contentWidth: width
      contentHeight: listCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: listCol
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.matches
          delegate: Rectangle {
            id: matchRow
            required property string modelData
            required property int index
            width: listCol.width
            height: Style.space(24)
            radius: Style.cornerRadius - 2
            readonly property bool isSelected: index === root.selectedIndex
            readonly property bool isCurrent: (root.mode === "profile")
              ? (root.currentProfile === modelData)
              : (Array.isArray(root.currentTags) && root.currentTags.indexOf(modelData) !== -1)
            color: isSelected
              ? Util.alpha(Color.accent, 0.2)
              : (rowMouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent")
            border.color: isSelected ? Util.alpha(Color.accent, 0.4) : "transparent"
            border.width: 1

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: metaText.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "profile" ? TodoStore.getProfileGlyph(matchRow.modelData) : "󰓹"
                color: matchRow.isSelected ? Color.accent : root.secondaryText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "#" + matchRow.modelData
                color: matchRow.isSelected ? (Color.menu.text || Color.foreground) : (matchRow.isCurrent ? Color.accent : (Color.menu.text || Color.foreground))
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: matchRow.isSelected || matchRow.isCurrent
                elide: Text.ElideRight
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: matchRow.isCurrent
                text: "󰄬"
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              id: metaText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.mode === "profile") {
                  var pCount = TodoStore.getPendingCount(root.store, matchRow.modelData)
                  return pCount > 0 ? (pCount + (pCount === 1 ? " task" : " tasks")) : ""
                } else {
                  var tCount = 0
                  if (root.store && Array.isArray(root.store.todos)) {
                    for (var i = 0; i < root.store.todos.length; i++) {
                      var t = root.store.todos[i]
                      if (Array.isArray(t.tags) && t.tags.indexOf(matchRow.modelData) !== -1) tCount++
                    }
                  }
                  return tCount > 0 ? (tCount + (tCount === 1 ? " used" : " used")) : ""
                }
              }
              color: root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.space(8.5)
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: { root.selectedIndex = matchRow.index }
              onClicked: { root.applySelection(matchRow.index) }
            }
          }
        }

        // New item option (if query is non-empty and not in matches)
        Rectangle {
          id: createRow
          visible: root.canCreateNew
          width: listCol.width
          height: Style.space(24)
          radius: Style.cornerRadius - 2
          readonly property int createIndex: root.matches.length
          readonly property bool isSelected: root.selectedIndex === createIndex
          color: isSelected
            ? Util.alpha(Color.accent, 0.2)
            : (createMouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent")
          border.color: isSelected ? Util.alpha(Color.accent, 0.4) : "transparent"
          border.width: 1

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰐕"
              color: Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: 'Add #' + root.cleanQuery
              color: Color.accent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            id: createMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: { root.selectedIndex = createRow.createIndex }
            onClicked: { root.applySelection(createRow.createIndex) }
          }
        }
      }
    }
  }

  Component.onCompleted: {
    searchInput.forceActiveFocus()
  }
}
