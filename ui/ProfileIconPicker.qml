import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

// =============================================================================
// ProfileIconPicker.qml
//
// Interactive icon customizer and search modal for Ardoise (tablerase.ardoise).
// Supports two categories: curated "Presets" and "All Glyphs".
// Features instant keyword search, full keyboard navigation (vim motions),
// centered grid layout, row-snapped scrolling, and custom glyph auto-detection.
// =============================================================================

Item {
  id: root

  property bool isOpen: false
  property string targetProfile: ""
  property string currentIcon: ""
  property var store: null
  property var bar: null
  property color accentColor: Color.accent
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color secondaryText: TodoStore.getReadableSecondary(Color.popups.background, Color.muted, root.barForeground)

  signal iconSelected(string profile, string glyph)
  signal iconReset(string profile)
  signal closeRequested()

  property string searchQuery: ""
  // Categories: "recent", "presets", or "all"
  property string selectedCategory: "presets"
  property int focusedGridIndex: 0
  property var filteredIcons: []

  readonly property var recentIconsList: root.store ? TodoStore.getRecentIcons(root.store) : []
  readonly property int recentCount: recentIconsList.length
  readonly property int presetCount: TodoStore.PROFILE_ICON_CATALOG.length
  readonly property int allGlyphCount: TodoStore.ALL_GLYPHS_CATALOG.length
  readonly property int gridColumns: (selectedCategory === "all") ? 7 : 6

  // Modal focus sections: "grid", "search", "categories", "actions"
  property string focusSection: "grid"
  // Action buttons: 0: Reset Default, 1: Cancel, 2: Apply
  property int actionIndex: 2

  function getAvailableCategories() {
    var cats = []
    if (root.recentCount > 0) cats.push("recent")
    cats.push("presets")
    cats.push("all")
    return cats
  }

  function cycleCategory(forward) {
    var cats = getAvailableCategories()
    var idx = cats.indexOf(root.selectedCategory)
    if (idx < 0) idx = 0
    if (forward) {
      idx = (idx + 1) % cats.length
    } else {
      idx = (idx - 1 + cats.length) % cats.length
    }
    setCategory(cats[idx])
  }

  function refreshList() {
    filteredIcons = TodoStore.searchIconCatalog(searchQuery, selectedCategory, root.store)
    if (focusedGridIndex >= filteredIcons.length) {
      focusedGridIndex = Math.max(0, filteredIcons.length - 1)
    }
  }

  onSearchQueryChanged: {
    refreshList()
  }

  function setCategory(cat) {
    if (selectedCategory === cat) return
    selectedCategory = cat
    focusedGridIndex = 0
    gridFlick.contentY = 0
    refreshList()
    ensureVisible(0)
  }

  function ensureVisible(index) {
    if (index < 0 || !iconGrid || !gridFlick) return
    var cols = root.gridColumns
    var row = Math.floor(index / cols)
    var rowH = iconGrid.rowHeight
    var visibleRows = 3

    var minRow = Math.floor(gridFlick.contentY / rowH)
    var maxRow = minRow + visibleRows - 1

    if (row < minRow) {
      gridFlick.contentY = Math.max(0, row * rowH)
    } else if (row > maxRow) {
      gridFlick.contentY = Math.max(0, (row - visibleRows + 1) * rowH)
    }
  }

  function open(profileName, iconGlyph) {
    targetProfile = profileName || ""
    currentIcon = iconGlyph || (targetProfile ? TodoStore.getProfileGlyph(targetProfile, root.store) : "")
    searchQuery = ""
    selectedCategory = (root.recentCount > 0) ? "recent" : "presets"
    if (searchField) searchField.text = ""
    gridFlick.contentY = 0
    refreshList()

    // Find preselected index matching currentIcon in active category
    var matchIdx = -1
    for (var i = 0; i < filteredIcons.length; i++) {
      if (filteredIcons[i].glyph === currentIcon) {
        matchIdx = i
        break
      }
    }

    // If not found in current category, check presets then all glyphs
    if (matchIdx < 0 && currentIcon) {
      var presetIcons = TodoStore.searchIconCatalog("", "presets", root.store)
      for (var p = 0; p < presetIcons.length; p++) {
        if (presetIcons[p].glyph === currentIcon) {
          selectedCategory = "presets"
          refreshList()
          matchIdx = p
          break
        }
      }
    }

    if (matchIdx < 0 && currentIcon) {
      var allIcons = TodoStore.searchIconCatalog("", "all", root.store)
      for (var j = 0; j < allIcons.length; j++) {
        if (allIcons[j].glyph === currentIcon) {
          selectedCategory = "all"
          refreshList()
          matchIdx = j
          break
        }
      }
    }

    focusedGridIndex = matchIdx >= 0 ? matchIdx : 0
    focusSection = "grid"
    actionIndex = 2
    isOpen = true
    Qt.callLater(function() {
      root.ensureVisible(focusedGridIndex)
      card.forceActiveFocus()
    })
  }

  function close() {
    isOpen = false
    searchQuery = ""
    root.closeRequested()
  }

  function chooseGlyph(glyph) {
    if (root.targetProfile) {
      root.iconSelected(root.targetProfile, glyph)
    }
    root.close()
  }

  function resetToDefault() {
    if (root.targetProfile) {
      root.iconReset(root.targetProfile)
    }
    root.close()
  }

  visible: isOpen
  anchors.fill: parent
  z: 110

  // Backdrop scrim
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // Centered picker card
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(440), parent.width - Style.space(24))
    implicitHeight: pickerCol.implicitHeight + Style.space(28)
    radius: Style.cornerRadius
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: 1
    clip: true
    focus: true

    Keys.onPressed: function(event) {
      // 1. Grid section keyboard handling
      if (root.focusSection === "grid") {
        if (event.key === Qt.Key_Escape) {
          event.accepted = true
          root.close()
          return
        }

        // Category cycling via [ (previous) and ] (next)
        if (event.text === "[") {
          event.accepted = true
          root.cycleCategory(false)
          return
        }
        if (event.text === "]" || event.text === "c" || event.text === "C") {
          event.accepted = true
          root.cycleCategory(true)
          return
        }

        if (event.key === Qt.Key_Left || event.text === "h") {
          event.accepted = true
          if (root.filteredIcons.length > 0) {
            root.focusedGridIndex = Math.max(0, root.focusedGridIndex - 1)
            root.ensureVisible(root.focusedGridIndex)
          }
          return
        }

        if (event.key === Qt.Key_Right || event.text === "l") {
          event.accepted = true
          if (root.filteredIcons.length > 0) {
            root.focusedGridIndex = Math.min(root.filteredIcons.length - 1, root.focusedGridIndex + 1)
            root.ensureVisible(root.focusedGridIndex)
          }
          return
        }

        if (event.key === Qt.Key_Down || event.text === "j") {
          event.accepted = true
          if (root.filteredIcons.length > 0) {
            root.focusedGridIndex = Math.min(root.filteredIcons.length - 1, root.focusedGridIndex + root.gridColumns)
            root.ensureVisible(root.focusedGridIndex)
          }
          return
        }

        if (event.key === Qt.Key_Up || event.text === "k") {
          event.accepted = true
          if (root.filteredIcons.length > 0) {
            root.focusedGridIndex = Math.max(0, root.focusedGridIndex - root.gridColumns)
            root.ensureVisible(root.focusedGridIndex)
          }
          return
        }

        if (event.text === "g") {
          event.accepted = true
          root.focusedGridIndex = 0
          root.ensureVisible(0)
          return
        }

        if (event.text === "G") {
          event.accepted = true
          root.focusedGridIndex = Math.max(0, root.filteredIcons.length - 1)
          root.ensureVisible(root.focusedGridIndex)
          return
        }

        if (event.text === "/" || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
          event.accepted = true
          root.focusSection = "search"
          searchField.forceActiveFocus()
          return
        }

        if (event.key === Qt.Key_Tab) {
          event.accepted = true
          root.focusSection = "actions"
          root.actionIndex = 2
          return
        }

        if (event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.focusSection = "search"
          searchField.forceActiveFocus()
          return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          event.accepted = true
          if (root.filteredIcons.length > 0 && root.focusedGridIndex >= 0 && root.focusedGridIndex < root.filteredIcons.length) {
            root.chooseGlyph(root.filteredIcons[root.focusedGridIndex].glyph)
          }
          return
        }

        if (event.text === "d" || event.text === "r") {
          event.accepted = true
          root.resetToDefault()
          return
        }
      }

      // 2. Action buttons section keyboard handling
      if (root.focusSection === "actions") {
        if (event.key === Qt.Key_Escape) {
          event.accepted = true
          root.close()
          return
        }

        if (event.key === Qt.Key_Left || event.text === "h") {
          event.accepted = true
          root.actionIndex = Math.max(0, root.actionIndex - 1)
          return
        }

        if (event.key === Qt.Key_Right || event.text === "l") {
          event.accepted = true
          root.actionIndex = Math.min(2, root.actionIndex + 1)
          return
        }

        if (event.key === Qt.Key_Tab) {
          event.accepted = true
          root.focusSection = "search"
          searchField.forceActiveFocus()
          return
        }

        if (event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.focusSection = "grid"
          card.forceActiveFocus()
          root.ensureVisible(root.focusedGridIndex)
          return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          event.accepted = true
          if (root.actionIndex === 0) {
            root.resetToDefault()
          } else if (root.actionIndex === 1) {
            root.close()
          } else if (root.actionIndex === 2) {
            if (root.filteredIcons.length > 0 && root.focusedGridIndex >= 0 && root.focusedGridIndex < root.filteredIcons.length) {
              root.chooseGlyph(root.filteredIcons[root.focusedGridIndex].glyph)
            } else {
              root.close()
            }
          }
          return
        }
      }
    }

    Column {
      id: pickerCol
      anchors.top: parent.top
      anchors.topMargin: Style.space(14)
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(16)
      spacing: Style.space(10)

      // 1. Header Row
      Item {
        width: parent.width
        height: Math.max(headerTitle.implicitHeight, currentIconPill.implicitHeight)

        Text {
          id: headerTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰏘 Icon for #" + root.targetProfile
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subheading
          font.bold: true
        }

        // Current icon pill
        Rectangle {
          id: currentIconPill
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(22)
          width: currentPillRow.implicitWidth + Style.space(12)
          radius: height / 2
          color: Util.alpha(root.accentColor, 0.15)
          border.color: root.accentColor
          border.width: 1

          Row {
            id: currentPillRow
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.currentIcon || TodoStore.getProfileGlyph(root.targetProfile, root.store)
              color: root.accentColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Current"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // 2. Search Input Field (Clean Anchored Layout, Inside Boundary)
      Rectangle {
        width: parent.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        border.color: searchField.activeFocus ? root.accentColor : Color.menu.border
        border.width: searchField.activeFocus ? 2 : 1

        Item {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)

          Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: searchField.activeFocus ? root.accentColor : root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TextInput {
            id: searchField
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: clearBtn.visible ? clearBtn.left : parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.searchQuery
            color: Color.menu.text || Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectByMouse: true
            clip: true
            onTextChanged: {
              root.searchQuery = text
            }
            onActiveFocusChanged: {
              if (activeFocus) {
                root.focusSection = "search"
              }
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                event.accepted = true
                if (searchField.text.length > 0) {
                  searchField.text = ""
                  root.searchQuery = ""
                }
                root.focusSection = "grid"
                card.forceActiveFocus()
                root.ensureVisible(root.focusedGridIndex)
                return
              }

              if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true
                root.focusSection = "grid"
                card.forceActiveFocus()
                root.ensureVisible(root.focusedGridIndex)
                return
              }

              if (event.key === Qt.Key_Tab) {
                event.accepted = true
                root.focusSection = "grid"
                card.forceActiveFocus()
                root.ensureVisible(root.focusedGridIndex)
                return
              }

              if (event.key === Qt.Key_Backtab) {
                event.accepted = true
                root.focusSection = "actions"
                root.actionIndex = 2
                card.forceActiveFocus()
                return
              }
            }
          }

          // Placeholder: firmly anchored inside searchField
          Text {
            id: searchPlaceholder
            anchors.left: searchField.left
            anchors.verticalCenter: searchField.verticalCenter
            visible: !searchField.text && !searchField.activeFocus
            text: (root.selectedCategory === "presets") ? "Search presets or paste glyph..." : "Search all glyphs..."
            color: root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Clear button
          Text {
            id: clearBtn
            visible: searchField.text.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            color: clearMouse.containsMouse ? root.accentColor : root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                searchField.text = ""
                root.searchQuery = ""
                searchField.forceActiveFocus()
              }
            }
          }
        }
      }

      // 3. Category Switcher (Recent vs Presets vs All Glyphs with KeyBadge cues)
      Row {
        spacing: Style.space(6)
        anchors.horizontalCenter: parent.horizontalCenter

        KeyBadge {
          keyText: "["
          anchors.verticalCenter: parent.verticalCenter
          badgeColor: root.secondaryText
        }

        Rectangle {
          visible: root.recentCount > 0
          height: Style.space(24)
          width: recentTabRow.implicitWidth + Style.space(16)
          radius: height / 2
          color: (root.selectedCategory === "recent") ? Util.alpha(root.accentColor, 0.2) : "transparent"
          border.color: (root.selectedCategory === "recent") ? root.accentColor : Util.alpha(Color.foreground, 0.15)
          border.width: 1

          Row {
            id: recentTabRow
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              text: "󰋚"
              color: (root.selectedCategory === "recent") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "Recent (" + root.recentCount + ")"
              color: (root.selectedCategory === "recent") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: root.selectedCategory === "recent"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setCategory("recent")
          }
        }

        Rectangle {
          height: Style.space(24)
          width: presetTabRow.implicitWidth + Style.space(16)
          radius: height / 2
          color: (root.selectedCategory === "presets") ? Util.alpha(root.accentColor, 0.2) : "transparent"
          border.color: (root.selectedCategory === "presets") ? root.accentColor : Util.alpha(Color.foreground, 0.15)
          border.width: 1

          Row {
            id: presetTabRow
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              text: "󰏘"
              color: (root.selectedCategory === "presets") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "Presets (" + root.presetCount + ")"
              color: (root.selectedCategory === "presets") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: root.selectedCategory === "presets"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setCategory("presets")
          }
        }

        Rectangle {
          height: Style.space(24)
          width: allGlyphsTabRow.implicitWidth + Style.space(16)
          radius: height / 2
          color: (root.selectedCategory === "all") ? Util.alpha(root.accentColor, 0.2) : "transparent"
          border.color: (root.selectedCategory === "all") ? root.accentColor : Util.alpha(Color.foreground, 0.15)
          border.width: 1

          Row {
            id: allGlyphsTabRow
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              text: "󰞔"
              color: (root.selectedCategory === "all") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "All Glyphs (" + root.allGlyphCount + ")"
              color: (root.selectedCategory === "all") ? root.accentColor : root.secondaryText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: root.selectedCategory === "all"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setCategory("all")
          }
        }

        KeyBadge {
          keyText: "]"
          anchors.verticalCenter: parent.verticalCenter
          badgeColor: root.secondaryText
        }
      }

      // 4. Grid of Icons Container (Symmetrically Centered, Non-overlapping Scrollbar)
      Rectangle {
        id: gridContainer
        width: parent.width
        height: Style.space(172)
        radius: Style.cornerRadius
        color: Util.alpha(Color.foreground, 0.03)
        border.color: (root.focusSection === "grid") ? root.accentColor : Color.menu.border
        border.width: (root.focusSection === "grid") ? 2 : 1
        clip: true

        WheelHandler {
          target: null
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var step = iconGrid.rowHeight
            var maxScroll = Math.max(0, gridFlick.contentHeight - gridFlick.height)
            if (event.angleDelta.y < 0) {
              gridFlick.contentY = Math.min(maxScroll, gridFlick.contentY + step)
            } else if (event.angleDelta.y > 0) {
              gridFlick.contentY = Math.max(0, gridFlick.contentY - step)
            }
          }
        }

        Flickable {
          id: gridFlick
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)

          contentWidth: width
          contentHeight: iconGrid.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Grid {
            id: iconGrid
            columns: root.gridColumns
            spacing: Style.space(6)
            readonly property real cellHeight: Style.space(48)
            readonly property real rowHeight: cellHeight + spacing

            readonly property real availableWidth: gridFlick.width - (columns - 1) * spacing
            readonly property real computedCellWidth: Math.floor(availableWidth / columns)
            readonly property real gridContentWidth: columns * computedCellWidth + (columns - 1) * spacing

            width: gridContentWidth
            x: Math.max(0, Math.floor((gridFlick.width - gridContentWidth) / 2))

            Repeater {
              model: root.filteredIcons

              Rectangle {
                id: iconBtn
                required property var modelData
                required property int index
                width: iconGrid.computedCellWidth
                height: iconGrid.cellHeight
                radius: Style.space(6)
                readonly property bool isFocused: (root.focusSection === "grid") && (root.focusedGridIndex === index)
                readonly property bool isCurrent: iconBtn.modelData.glyph === root.currentIcon

                color: isFocused
                  ? Util.alpha(root.accentColor, 0.25)
                  : (isCurrent
                      ? Util.alpha(root.accentColor, 0.12)
                      : (iconMouse.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"))
                border.color: isFocused ? root.accentColor : (isCurrent ? root.accentColor : Util.alpha(Color.foreground, 0.12))
                border.width: isFocused ? 2 : 1

                // Centered Icon Layout: single glyph when in "All Glyphs" mode, rigid balanced containers in "Presets" / "Recent" mode
                Item {
                  anchors.fill: parent

                  // 1. All Glyphs Mode: Single glyph filling the cell, optically centered
                  OpticalGlyph {
                    visible: (root.selectedCategory === "all") && !(iconBtn.modelData.name && iconBtn.modelData.name.startsWith("Custom"))
                    anchors.fill: parent
                    text: iconBtn.modelData.glyph
                    color: (iconBtn.isFocused || iconBtn.isCurrent) ? root.accentColor : (Color.menu.text || Color.foreground)
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    fontSize: Style.space(22)
                  }

                  // 2. Presets & Recent Mode: Rigid top/bottom containers with equal 4px outer margins
                  Item {
                    visible: (root.selectedCategory !== "all") || (iconBtn.modelData.name && iconBtn.modelData.name.startsWith("Custom"))
                    anchors.fill: parent

                    // Upper half: Icon container (height: 24px, centered horizontally)
                    Item {
                      id: glyphContainer
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(4)
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width
                      height: Style.space(24)

                      OpticalGlyph {
                        anchors.fill: parent
                        text: iconBtn.modelData.glyph
                        color: (iconBtn.isFocused || iconBtn.isCurrent) ? root.accentColor : (Color.menu.text || Color.foreground)
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        fontSize: Style.space(18)
                      }
                    }

                    // Lower half: Label container (height: 14px, centered horizontally)
                    Item {
                      id: labelContainer
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(4)
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width
                      height: Style.space(14)

                      Text {
                        anchors.centerIn: parent
                        width: parent.width - Style.space(4)
                        text: iconBtn.modelData.name || ""
                        color: (iconBtn.isFocused || iconBtn.isCurrent) ? root.accentColor : root.secondaryText
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.space(9)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                MouseArea {
                  id: iconMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.focusSection = "grid"
                    root.focusedGridIndex = iconBtn.index
                    card.forceActiveFocus()
                    root.chooseGlyph(iconBtn.modelData.glyph)
                  }
                }

                ShortcutToolTip {
                  visible: iconMouse.containsMouse
                  description: iconBtn.modelData.name + (iconBtn.modelData.keywords ? " (" + iconBtn.modelData.keywords.slice(0, 3).join(", ") + ")" : "")
                  fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                }
              }
            }
          }
        }

        // Vertical scrollbar indicator (Placed neatly in the right margin)
        Rectangle {
          id: scrollbar
          anchors.right: parent.right
          anchors.rightMargin: Style.space(3)
          anchors.top: parent.top
          anchors.topMargin: Style.space(6)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          width: Style.space(4)
          radius: width / 2
          color: Util.alpha(Color.foreground, 0.08)
          visible: gridFlick.contentHeight > gridFlick.height

          Rectangle {
            width: parent.width
            height: Math.max(Style.space(20), (gridFlick.height / Math.max(1, gridFlick.contentHeight)) * parent.height)
            y: (gridFlick.contentHeight > gridFlick.height)
              ? (gridFlick.contentY / (gridFlick.contentHeight - gridFlick.height)) * (parent.height - height)
              : 0
            radius: width / 2
            color: Util.alpha(root.accentColor, 0.6)
          }
        }

        // Empty state when no icons match
        Item {
          anchors.fill: parent
          visible: root.filteredIcons.length === 0

          Column {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰍉"
              color: root.secondaryText
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No icons matching \"" + root.searchQuery + "\""
              color: root.secondaryText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // 5. Action Buttons Footer
      Item {
        width: parent.width
        height: Math.max(resetBtn.implicitHeight, applyBtn.implicitHeight)

        Button {
          id: resetBtn
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰁯"
          text: "Reset Default"
          fontSize: Style.font.caption
          fontFamily: Style.font.family
          bordered: true
          borderSpec: Border.controlSpec((root.focusSection === "actions" && root.actionIndex === 0) ? "focused" : "normal", Color.foreground, Color.accent)
          selected: (root.focusSection === "actions" && root.actionIndex === 0)
          onClicked: root.resetToDefault()
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            id: cancelBtn
            iconText: "󰅖"
            text: "Cancel"
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            bordered: true
            borderSpec: Border.controlSpec((root.focusSection === "actions" && root.actionIndex === 1) ? "focused" : "normal", Color.foreground, Color.accent)
            selected: (root.focusSection === "actions" && root.actionIndex === 1)
            onClicked: root.close()
          }

          Button {
            id: applyBtn
            iconText: "󰄬"
            text: "Apply"
            fontSize: Style.font.caption
            fontFamily: Style.font.family
            bordered: true
            borderSpec: (root.focusSection === "actions" && root.actionIndex === 2)
              ? Border.flat(Color.accent, 2.0)
              : Border.flat(Color.accent, 1.2)
            selected: (root.focusSection === "actions" && root.actionIndex === 2) || (root.focusSection === "grid")
            onClicked: {
              if (root.filteredIcons.length > 0 && root.focusedGridIndex >= 0 && root.focusedGridIndex < root.filteredIcons.length) {
                root.chooseGlyph(root.filteredIcons[root.focusedGridIndex].glyph)
              } else {
                root.close()
              }
            }
          }
        }
      }

      // 6. Subtle Keyboard Hint Footer (Clear Distinction Between Category & Search)
      Item {
        width: parent.width
        height: hintText.implicitHeight

        Text {
          id: hintText
          anchors.centerIn: parent
          text: root.focusSection === "search"
            ? "Enter/↓ Return to Grid • Esc Clear/Blur • Tab Navigate"
            : (root.focusSection === "actions"
                ? "h/l Switch Button • Enter/Space Trigger • Tab Next • Esc Close"
                : "h/j/k/l Nav • [ ] Category • / Search • Space/Enter Apply • Esc Close")
          color: root.secondaryText
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.fineprint || Style.space(9)
        }
      }
    }
  }
}
