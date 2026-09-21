import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as TodoStore

BarWidget {
  id: root
  moduleName: "tablerase.ardoise"

  property var store: TodoStore.defaultStore()
  readonly property var todos: store.todos || []
  readonly property int pendingCount: TodoStore.getPendingCount(store, "all")
  readonly property string activeProfile: store.activeProfile || "personal"
  readonly property var profiles: store.profiles || ["personal", "work"]

  readonly property string todoFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos.json"
  readonly property string archiveFilePath: Quickshell.env("HOME") + "/.config/omarchy/todos-archive.json"

  function loadTodos(raw) {
    root.store = TodoStore.normalize(raw)
  }

  function saveStore(newStore) {
    root.store = newStore
    todoFile.setText(JSON.stringify(newStore, null, 2) + "\n")
  }

  function addTodo(title, description, profile, reminder) {
    saveStore(TodoStore.addTodo(root.store, title, description, profile, reminder))
  }

  function toggleTodo(id) {
    saveStore(TodoStore.toggleTodo(root.store, id))
  }

  function removeTodo(id) {
    saveStore(TodoStore.removeTodo(root.store, id))
  }

  function updateTodo(id, fields) {
    saveStore(TodoStore.updateTodo(root.store, id, fields))
  }

  function clearCompleted(profile) {
    var result = TodoStore.archiveCompleted(root.store, profile, archiveFile.text())
    saveStore(result.updatedStore)
    archiveFile.setText(JSON.stringify(result.updatedArchive, null, 2) + "\n")
  }

  function setActiveProfile(profile) {
    var s = TodoStore.cloneStore(root.store)
    s.activeProfile = TodoStore.cleanProfileName(profile)
    saveStore(s)
  }

  function addProfile(name) {
    saveStore(TodoStore.addProfile(root.store, name))
  }

  function removeProfile(name) {
    saveStore(TodoStore.removeProfile(root.store, name))
  }

  function getTooltip() {
    if (root.pendingCount === 0) {
      return "Inbox zero! All done.\n󰍽 [L] Panel   󰍽 [R] Quick Add   󰍽 [M] Edit"
    }
    var parts = []
    for (var i = 0; i < root.profiles.length; i++) {
      var p = root.profiles[i]
      var c = TodoStore.getPendingCount(root.store, p)
      if (c > 0) parts.push(c + " " + p)
    }
    var breakdown = parts.length > 1 ? " (" + parts.join(", ") + ")" : ""
    var summary = root.pendingCount + " pending task" + (root.pendingCount > 1 ? "s" : "") + breakdown
    return summary + "\n󰍽 [L] Panel   󰍽 [R] Quick Add   󰍽 [M] Edit"
  }

  // ---- Panel lifecycle contract for Omarchy Quattro shell
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("barWidget" in target) target.barWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  // Ensure config folder, todos.json, and todos-archive.json exist so FileView can watch them
  Process {
    id: initFileProc
    command: ["bash", "-c", "mkdir -p \"$HOME/.config/omarchy\" && [ -f \"$HOME/.config/omarchy/todos.json\" ] || echo '{\"version\":1,\"activeProfile\":\"personal\",\"profiles\":[\"personal\",\"work\"],\"todos\":[]}' > \"$HOME/.config/omarchy/todos.json\"; [ -f \"$HOME/.config/omarchy/todos-archive.json\" ] || echo '{\"version\":1,\"archived\":[]}' > \"$HOME/.config/omarchy/todos-archive.json\""]
    onExited: {
      todoFile.reload()
      archiveFile.reload()
    }
  }

  Component.onCompleted: initFileProc.running = true

  FileView {
    id: todoFile
    path: root.todoFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadTodos(text())
    onLoadFailed: root.loadTodos("{}")
    onFileChanged: reload()
  }

  FileView {
    id: archiveFile
    path: root.archiveFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "tablerase.ardoise"

    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function add(task: string): string { root.addTodo(task); return "ok" }
    function clear(): string { root.clearCompleted(); return "ok" }
    function count(): string { return String(root.pendingCount) }
    function list(): string { return JSON.stringify(root.todos) }
    function profiles(): string { return JSON.stringify(root.profiles) }
    function setProfile(profile: string): string { root.setActiveProfile(profile); return "ok" }
    function archived(): string { return archiveFile.text() || "{\"version\":1,\"archived\":[]}" }
    function archiveCount(): string { return String(TodoStore.getArchivedCount(archiveFile.text())) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? barSize : readout.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? readout.implicitHeight + scaledVerticalPadding * 2 : barSize
    tooltipText: root.getTooltip()
    active: root.pendingCount > 0

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      } else if (buttonCode === Qt.RightButton) {
        if (root.bar && root.bar.shell) {
          root.close()
          root.bar.shell.summon(root.moduleName, "{}")
        }
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.bar) root.bar.run("omarchy-launch-editor " + root.todoFilePath)
      }
    }

    Row {
      id: readout
      anchors.centerIn: parent
      spacing: Style.space(6)

      InboxIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: width
        color: button.active ? (root.bar ? root.bar.urgent : Color.urgent) : button.foreground
      }

      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.pendingCount > 0
        text: String(root.pendingCount)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        color: button.active ? (root.bar ? root.bar.urgent : Color.urgent) : button.foreground
      }
    }
  }
}
