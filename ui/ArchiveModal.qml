import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

// Archive browser: restores completed/archived tasks back into the active
// store. Opened with `d` or the footer Archive button.
//
// Large archives (>2,000 items) are handled by parsing ONCE on open and
// rendering through a virtualized ListView, so only the visible delegates are
// instantiated. Filtering runs over the in-memory array on each query change
// (never per frame). Parsing/normalizing 5,000 items stays under the store's
// existing 100ms budget.
Rectangle {
  id: root

  property bool isOpen: false
  property var bar: null
  property var barWidget: null
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground

  // Parsed once on open / after a restore.
  property var archivedTasks: []
  property int selectedIndex: 0
  property bool searchActive: false
  property string searchQuery: ""

  readonly property var filteredArchived: TodoStore.filterArchivedTasks(root.archivedTasks, root.searchQuery)
  readonly property var selectedTask: (root.filteredArchived && root.filteredArchived.length > root.selectedIndex)
    ? root.filteredArchived[root.selectedIndex]
    : null

  signal closeRequested()

  function refresh() {
    var raw = root.barWidget ? root.barWidget.getArchiveText() : "{\"version\":1,\"archived\":[]}"
    root.archivedTasks = TodoStore.getArchivedTasks(raw)
    if (root.selectedIndex >= root.filteredArchived.length) {
      root.selectedIndex = Math.max(0, root.filteredArchived.length - 1)
    }
  }

  function open() {
    isOpen = true
  }

  onIsOpenChanged: {
    if (isOpen) {
      selectedIndex = 0
      searchActive = false
      searchQuery = ""
      refresh()
      Qt.callLater(function() { root.forceActiveFocus() })
    }
  }

  function close() {
    if (searchActive && searchQuery.length > 0) {
      closeSearch()
      return
    }
    isOpen = false
    root.closeRequested()
  }

  function activateSearch() {
    searchActive = true
    Qt.callLater(function() {
      if (typeof searchField !== "undefined" && searchField) {
        searchField.forceActiveFocus()
        searchField.selectAll()
      }
    })
  }

  function closeSearch() {
    searchActive = false
    searchQuery = ""
    if (typeof searchField !== "undefined" && searchField) searchField.text = ""
    selectedIndex = 0
    root.forceActiveFocus()
  }

  function ensureVisible() {
    if (archiveList && root.selectedIndex >= 0 && root.selectedIndex < archiveList.count) {
      archiveList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
  }

  function copyToClipboard(text, label) {
    if (!text) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    Quickshell.execDetached(["notify-send", "-a", "Ardoise", "-i", "edit-copy", "Copied to clipboard", label || ""])
  }

  function copySelected() {
    var task = root.selectedTask
    if (!task) return
    root.copyToClipboard(TodoStore.formatTaskForLLM(task), "Task copied for LLM")
  }

  function restoreSelected() {
    var task = root.selectedTask
    if (!task) return
    if (root.barWidget && typeof root.barWidget.unarchiveTask === "function" && root.barWidget.unarchiveTask(task.id)) {
      // Splice instead of re-parsing the whole archive.
      var next = []
      for (var i = 0; i < root.archivedTasks.length; i++) {
        if (String(root.archivedTasks[i].id) !== String(task.id)) next.push(root.archivedTasks[i])
      }
      root.archivedTasks = next
      if (root.selectedIndex >= root.filteredArchived.length) {
        root.selectedIndex = Math.max(0, root.filteredArchived.length - 1)
      }
      root.forceActiveFocus()
    }
  }

  function openRawFile() {
    if (!root.barWidget) return
    var path = root.barWidget.archiveFilePath
    if (root.bar && root.bar.run) root.bar.run("omarchy-launch-editor " + path)
    else Quickshell.execDetached(["bash", "-c", "omarchy-launch-editor " + Util.shellQuote(path)])
    root.close()
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      root.close()
      return
    }
    if (searchActive && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      event.accepted = true
      root.forceActiveFocus()
      return
    }
    if (searchActive) return

    if (event.key === Qt.Key_Down || event.text === "j") {
      event.accepted = true
      if (root.selectedIndex < root.filteredArchived.length - 1) {
        root.selectedIndex++
        root.ensureVisible()
      }
      return
    }
    if (event.key === Qt.Key_Up || event.text === "k") {
      event.accepted = true
      if (root.selectedIndex > 0) {
        root.selectedIndex--
        root.ensureVisible()
      }
      return
    }
    if (event.text === "g") {
      event.accepted = true
      root.selectedIndex = 0
      root.ensureVisible()
      return
    }
    if (event.text === "G") {
      event.accepted = true
      root.selectedIndex = Math.max(0, root.filteredArchived.length - 1)
      root.ensureVisible()
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "r") {
      event.accepted = true
      root.restoreSelected()
      return
    }
    if (event.text === "y") {
      event.accepted = true
      root.copySelected()
      return
    }
    if (event.text === "e") {
      event.accepted = true
      root.openRawFile()
      return
    }
    if (event.text === "/" || event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
      event.accepted = true
      root.activateSearch()
      return
    }
    if (event.text === "q") {
      event.accepted = true
      root.close()
      return
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

  Keys.onPressed: function(event) { root.handleKey(event) }

  // Unconditional mouse blocker so clicks/hover never bleed to the panel below.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: root.forceActiveFocus()
    onWheel: function(wheel) { wheel.accepted = true }
    z: -1
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(8)

    // Header
    Item {
      width: parent.width
      implicitHeight: Math.max(headerLeft.implicitHeight, closeBtn.implicitHeight)

      Row {
        id: headerLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰋚"
          color: Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Archive"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.filteredArchived.length + (root.searchQuery.length > 0 ? " / " + root.archivedTasks.length : "") + " archived"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        id: closeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅙"
        text: ""
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        tooltipText: "Close archive (Esc)"
        onClicked: root.close()
      }
    }

    // Search row
    Row {
      width: parent.width
      spacing: Style.space(6)
      visible: root.searchActive

      BorderSurface {
        width: parent.width - (clearSearchBtn.visible ? clearSearchBtn.implicitWidth + parent.spacing : 0)
        implicitHeight: Style.space(30)
        color: Util.alpha(Color.accent, 0.08)
        borderSpec: Border.flat(Color.accent, 1.5)
        radius: Style.cornerRadius

        TextField {
          id: searchField
          anchors.fill: parent
          leftPadding: Style.space(8)
          rightPadding: Style.space(8)
          placeholderText: "Filter archived tasks…"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.barForeground
          background: null
          onTextChanged: root.searchQuery = text
          onAccepted: root.forceActiveFocus()
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            root.closeSearch()
          }
        }
      }

      Button {
        id: clearSearchBtn
        visible: root.searchActive
        iconText: "󰅖"
        text: ""
        fontSize: Style.font.caption
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        tooltipText: "Clear filter"
        onClicked: {
          root.searchQuery = ""
          if (searchField) searchField.text = ""
          root.forceActiveFocus()
        }
      }
    }

    PanelSeparator { width: parent.width }

    // Virtualized list: only visible delegates are instantiated.
    Item {
      width: parent.width
      height: parent.height - y - actionRow.implicitHeight - Style.space(8)

      ListView {
        id: archiveList
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Style.space(4)
        model: root.filteredArchived
        currentIndex: root.selectedIndex
        cacheBuffer: Style.space(200)

        ScrollBar.vertical: ScrollBar {
          policy: archiveList.contentHeight > archiveList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        delegate: Rectangle {
          id: archiveItem
          required property var modelData
          required property int index

          readonly property bool isSelected: root.selectedIndex === index
          width: archiveList.width
          implicitHeight: itemLayout.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: isSelected
            ? Util.alpha(Color.accent, 0.14)
            : (itemHover.containsMouse ? Color.menu.selectedBackground : "transparent")
          border.color: isSelected ? Color.accent : Color.menu.border
          border.width: isSelected ? 1.5 : 1

          MouseArea {
            id: itemHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = archiveItem.index
            onClicked: {
              root.selectedIndex = archiveItem.index
              root.restoreSelected()
            }
          }

          Row {
            id: itemLayout
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰄲"
              color: Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Column {
              width: parent.width - Style.space(22) - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: TodoStore.capitalizeTitle(String(archiveItem.modelData.title || ""))
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: {
                  var meta = []
                  if (archiveItem.modelData.profile) meta.push("#" + archiveItem.modelData.profile)
                  if (archiveItem.modelData.repo) meta.push(String(archiveItem.modelData.repo))
                  if (archiveItem.modelData.completedAt) {
                    meta.push("done " + new Date(archiveItem.modelData.completedAt).toLocaleDateString())
                  }
                  return meta.join("  ")
                }
                color: Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption * 0.8
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      // Empty state
      Text {
        anchors.centerIn: parent
        visible: root.filteredArchived.length === 0
        text: root.searchQuery.length > 0
          ? "No archived tasks match \"" + root.searchQuery + "\""
          : "Archive is empty"
        color: Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.italic: true
      }
    }

    // Action hints
    Row {
      id: actionRow
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Enter restore  y copy  e open file  / filter"
        color: Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption * 0.8
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }
}
