import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TodoStore.js" as TodoStore

// =============================================================================
// ReminderPicker.qml
//
// Flexible custom reminder time picker for Ardoise (tablerase.ardoise).
// Combines:
// 1. Natural language / duration text input (e.g. "45m", "2h", "17:30", "tomorrow 9am")
// 2. Real-time parsed feedback badge
// 3. Quick adjustment steppers ([-15m], [+15m], [-1h], [+1h], [+1d])
// 4. Interactive hour/minute spinners
// 5. Visual mini-calendar month grid
// =============================================================================

Item {
  id: root

  property bool isOpen: false
  property string initialIso: ""
  property var bar: null
  property color accentColor: Color.accent
  property color barForeground: root.bar ? root.bar.foreground : Color.foreground
  property color warningColor: Color.urgent

  signal reminderConfirmed(string isoString)
  signal reminderCleared()
  signal closeRequested()

  // State
  property var targetDate: new Date()
  property string manualText: ""
  property var parsedResult: null

  // Calendar navigation month/year
  property int calYear: 2026
  property int calMonth: 9 // 0-indexed

  // Active focus section inside picker: "input" | "steppers" | "actions"
  property string pickerSection: "input"
  property int stepperIndex: 0
  property int actionIndex: 2 // 0: clear, 1: cancel, 2: set

  readonly property var sections: ["input", "steppers", "actions"]

  function advanceSection(delta) {
    var curIdx = sections.indexOf(pickerSection)
    if (curIdx === -1) curIdx = 0
    var nextIdx = (curIdx + delta + sections.length) % sections.length
    pickerSection = sections[nextIdx]
    if (pickerSection === "input") {
      card.forceActiveFocus()
    }
  }

  function cycleSubSelection(delta) {
    if (pickerSection === "steppers") {
      stepperIndex = Math.max(0, Math.min(4, stepperIndex + delta))
    } else if (pickerSection === "actions") {
      var maxActions = root.initialIso ? 3 : 2
      actionIndex = (actionIndex + delta + maxActions) % maxActions
    }
  }

  function activateCurrentSection() {
    if (pickerSection === "input") {
      root.confirm()
    } else if (pickerSection === "steppers") {
      var steppers = [
        { deltaMins: -15 },
        { deltaMins: 15 },
        { deltaMins: -60 },
        { deltaMins: 60 },
        { deltaDays: 1 }
      ]
      var s = steppers[stepperIndex]
      if (s) {
        if (s.deltaDays) root.adjustDays(s.deltaDays)
        else if (s.deltaMins) root.adjustMinutes(s.deltaMins)
      }
    } else if (pickerSection === "actions") {
      if (root.initialIso) {
        if (actionIndex === 0) root.clearReminder()
        else if (actionIndex === 1) root.close()
        else root.confirm()
      } else {
        if (actionIndex === 0) root.close()
        else root.confirm()
      }
    }
  }

  function open(iso) {
    initialIso = iso || ""
    var now = new Date()
    var initDate = (iso && !isNaN(new Date(iso).getTime()))
      ? new Date(iso)
      : new Date(now.getTime() + 60 * 60 * 1000)

    targetDate = initDate
    calYear = initDate.getFullYear()
    calMonth = initDate.getMonth()
    manualText = ""
    parsedResult = null
    pickerSection = "input"
    stepperIndex = 0
    actionIndex = (iso ? 2 : 1)
    isOpen = true
    Qt.callLater(function() {
      if (manualInput && manualInput.forceActiveFocus) {
        manualInput.forceActiveFocus()
      }
    })
  }

  function close() {
    isOpen = false
    root.closeRequested()
  }

  function adjustMinutes(deltaMins) {
    var d = new Date(targetDate.getTime() + deltaMins * 60000)
    targetDate = d
    calYear = d.getFullYear()
    calMonth = d.getMonth()
    manualText = ""
    parsedResult = null
  }

  function adjustDays(deltaDays) {
    var d = new Date(targetDate.getTime() + deltaDays * 86400000)
    targetDate = d
    calYear = d.getFullYear()
    calMonth = d.getMonth()
    manualText = ""
    parsedResult = null
  }

  function setTime(hours, minutes) {
    var d = new Date(targetDate.getTime())
    d.setHours(hours, minutes, 0, 0)
    targetDate = d
    manualText = ""
    parsedResult = null
  }

  function selectDate(year, month, day) {
    var d = new Date(targetDate.getTime())
    d.setFullYear(year, month, day)
    targetDate = d
    calYear = year
    calMonth = month
    manualText = ""
    parsedResult = null
  }

  function prevMonth() {
    if (calMonth === 0) {
      calMonth = 11
      calYear--
    } else {
      calMonth--
    }
  }

  function nextMonth() {
    if (calMonth === 11) {
      calMonth = 0
      calYear++
    } else {
      calMonth++
    }
  }

  function getResolvedIso() {
    if (parsedResult && parsedResult.iso) {
      return parsedResult.iso
    }
    return targetDate.toISOString()
  }

  function confirm() {
    var iso = getResolvedIso()
    root.reminderConfirmed(iso)
    root.isOpen = false
  }

  function clearReminder() {
    root.reminderCleared()
    root.isOpen = false
  }

  onManualTextChanged: {
    if (!manualText || manualText.trim().length === 0) {
      parsedResult = null
      return
    }
    if (typeof TodoStore !== "undefined" && typeof TodoStore.parseCustomReminder === "function") {
      var res = TodoStore.parseCustomReminder(manualText, new Date())
      parsedResult = res
      if (res && res.iso) {
        var d = new Date(res.iso)
        if (!isNaN(d.getTime())) {
          targetDate = d
          calYear = d.getFullYear()
          calMonth = d.getMonth()
        }
      }
    }
  }

  visible: isOpen
  anchors.fill: parent
  z: 100

  // Backdrop scrim
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  // Centered picker card
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(350), parent.width - Style.space(16))
    height: Math.min(contentCol.implicitHeight + Style.space(24), parent.height - Style.space(16))
    radius: Style.cornerRadius
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: 1
    clip: true
    focus: true

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        event.accepted = true
        root.close()
        return
      }

      if (event.key === Qt.Key_I || event.key === Qt.Key_A || (event.text === "i" || event.text === "a")) {
        event.accepted = true
        root.pickerSection = "input"
        manualInput.forceActiveFocus()
        return
      }

      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.text === "j") {
        event.accepted = true
        root.advanceSection(1)
        return
      }

      if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.text === "k") {
        event.accepted = true
        root.advanceSection(-1)
        return
      }

      if (event.key === Qt.Key_Left || event.text === "h") {
        event.accepted = true
        root.cycleSubSelection(-1)
        return
      }

      if (event.key === Qt.Key_Right || event.text === "l") {
        event.accepted = true
        root.cycleSubSelection(1)
        return
      }

      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        event.accepted = true
        root.activateCurrentSection()
        return
      }

      // Typing printable character when in normal mode on input section refocuses input
      if (event.text && event.text.length === 1 && !event.modifiers) {
        event.accepted = true
        root.pickerSection = "input"
        manualInput.forceActiveFocus()
        manualInput.text += event.text
        manualInput.cursorPosition = manualInput.text.length
        return
      }
    }

    // Catch clicks inside card to prevent scrim dismissal and ensure active focus
    MouseArea {
      anchors.fill: parent
      onClicked: card.forceActiveFocus()
    }

    Flickable {
      id: cardFlickable
      anchors.fill: parent
      anchors.margins: Style.space(12)
      contentWidth: width
      contentHeight: contentCol.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      ScrollBar.vertical: ScrollBar {
        policy: cardFlickable.contentHeight > cardFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        implicitWidth: Style.space(3)
      }

      Column {
        id: contentCol
        width: parent.width
        spacing: Style.space(10)

        // Header: Title & Close Button
        Item {
          width: parent.width
          implicitHeight: Style.space(24)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰥔"
              color: root.accentColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Custom Reminder"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Style.space(22)
            implicitHeight: Style.space(22)
            radius: height / 2
            color: closeHover.hovered ? Color.menu.selectedBackground : "transparent"
            border.color: closeHover.hovered ? Color.menu.border : "transparent"
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "󰅖"
              color: closeHover.hovered ? root.barForeground : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            HoverHandler { id: closeHover }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }

        PanelSeparator { width: parent.width }

        // 1. Natural / Manual text input
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Type relative time or date:"
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            width: parent.width
            implicitHeight: Style.space(30)
            radius: Style.cornerRadius
            color: Color.menu.selectedBackground
            readonly property bool isNavFocused: root.pickerSection === "input" && !manualInput.activeFocus
            border.color: manualInput.activeFocus ? root.accentColor : (isNavFocused ? root.accentColor : Color.menu.border)
            border.width: manualInput.activeFocus ? 2 : 1

            TextField {
              id: manualInput
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              verticalAlignment: Text.AlignVCenter
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              placeholderText: "e.g. 45m, 2h, 17:30, tomorrow 9am"
              placeholderTextColor: Color.muted
              background: Item {}
              selectByMouse: true

              text: root.manualText
              onTextChanged: {
                if (root.isOpen) {
                  root.manualText = text
                }
              }
              onActiveFocusChanged: {
                if (activeFocus) {
                  root.pickerSection = "input"
                }
              }

              Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (text.trim().length === 0) {
                  root.close()
                } else {
                  manualInput.focus = false
                  root.pickerSection = "input"
                  card.forceActiveFocus()
                }
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.confirm()
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  if (text.trim().length === 0) {
                    root.close()
                  } else {
                    manualInput.focus = false
                    root.pickerSection = "input"
                    card.forceActiveFocus()
                  }
                  return
                }
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                  event.accepted = true
                  root.pickerSection = "steppers"
                  manualInput.focus = false
                  card.forceActiveFocus()
                  return
                }
              }
            }
          }

          // Live feedback preview badge
          Rectangle {
            width: parent.width
            implicitHeight: Style.space(22)
            radius: height / 2
            color: (root.parsedResult || root.manualText.length === 0)
              ? Util.alpha(root.accentColor, 0.12)
              : Util.alpha(root.warningColor, 0.12)
            border.color: (root.parsedResult || root.manualText.length === 0)
              ? Util.alpha(root.accentColor, 0.35)
              : Util.alpha(root.warningColor, 0.35)
            border.width: 1

            Row {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (root.parsedResult || root.manualText.length === 0) ? "󰥔" : "󱈸"
                color: (root.parsedResult || root.manualText.length === 0) ? root.accentColor : root.warningColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                id: feedbackLabel
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (root.manualText.length > 0 && !root.parsedResult) {
                    return "Unrecognized format — try '2h', '17:30', or 'tomorrow 9am'"
                  }
                  if (root.parsedResult && root.parsedResult.label) {
                    return root.parsedResult.label
                  }
                  if (typeof TodoStore !== "undefined" && typeof TodoStore.formatCustomPreview === "function") {
                    return TodoStore.formatCustomPreview(root.targetDate.toISOString(), new Date())
                  }
                  return root.targetDate.toLocaleString()
                }
                color: (root.parsedResult || root.manualText.length === 0) ? root.barForeground : root.warningColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }
            }
          }
        }

        // 2. Quick Stepper Buttons ([-15m], [+15m], [-1h], [+1h], [+1d])
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Quick Adjustments:"
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: [
                { label: "-15m", deltaMins: -15 },
                { label: "+15m", deltaMins: 15 },
                { label: "-1h", deltaMins: -60 },
                { label: "+1h", deltaMins: 60 },
                { label: "+1d", deltaDays: 1 }
              ]

              Rectangle {
                id: stepperBtn
                required property var modelData
                required property int index
                readonly property bool isSelected: root.pickerSection === "steppers" && root.stepperIndex === stepperBtn.index
                implicitWidth: (contentCol.width - Style.space(16)) / 5
                implicitHeight: Style.space(22)
                radius: height / 2
                color: (stepperHover.hovered || isSelected) ? Color.menu.selectedBackground : "transparent"
                border.color: (stepperHover.hovered || isSelected) ? root.accentColor : Color.menu.border
                border.width: isSelected ? 1.5 : 1

                Text {
                  anchors.centerIn: parent
                  text: stepperBtn.modelData.label
                  color: (stepperHover.hovered || stepperBtn.isSelected) ? root.accentColor : root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.space(9)
                  font.bold: true
                }

                HoverHandler { id: stepperHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (stepperBtn.modelData.deltaDays) {
                      root.adjustDays(stepperBtn.modelData.deltaDays)
                    } else if (stepperBtn.modelData.deltaMins) {
                      root.adjustMinutes(stepperBtn.modelData.deltaMins)
                    }
                  }
                }
              }
            }
          }
        }

        // 3. Time Spinner (HH : MM)
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Time:"
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          // Hours stepper
          Row {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: Style.space(20); height: Style.space(20); radius: 3
              color: hDecHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border; border.width: 1
              Text { anchors.centerIn: parent; text: "−"; color: root.barForeground; font.bold: true }
              HoverHandler { id: hDecHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustMinutes(-60)
              }
            }

            Rectangle {
              width: Style.space(28); height: Style.space(20); radius: 3
              color: Color.menu.selectedBackground
              border.color: Color.menu.border; border.width: 1
              Text {
                anchors.centerIn: parent
                text: (root.targetDate.getHours() < 10 ? "0" : "") + root.targetDate.getHours()
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Rectangle {
              width: Style.space(20); height: Style.space(20); radius: 3
              color: hIncHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border; border.width: 1
              Text { anchors.centerIn: parent; text: "+"; color: root.barForeground; font.bold: true }
              HoverHandler { id: hIncHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustMinutes(60)
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: root.barForeground
            font.bold: true
          }

          // Minutes stepper (steps of 5 min)
          Row {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: Style.space(20); height: Style.space(20); radius: 3
              color: mDecHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border; border.width: 1
              Text { anchors.centerIn: parent; text: "−"; color: root.barForeground; font.bold: true }
              HoverHandler { id: mDecHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustMinutes(-5)
              }
            }

            Rectangle {
              width: Style.space(28); height: Style.space(20); radius: 3
              color: Color.menu.selectedBackground
              border.color: Color.menu.border; border.width: 1
              Text {
                anchors.centerIn: parent
                text: (root.targetDate.getMinutes() < 10 ? "0" : "") + root.targetDate.getMinutes()
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Rectangle {
              width: Style.space(20); height: Style.space(20); radius: 3
              color: mIncHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: Color.menu.border; border.width: 1
              Text { anchors.centerIn: parent; text: "+"; color: root.barForeground; font.bold: true }
              HoverHandler { id: mIncHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustMinutes(5)
              }
            }
          }
        }

        // 4. Interactive Mini-Calendar Month View
        Column {
          width: parent.width
          spacing: Style.space(4)

          // Month header navigation: [<] October 2026 [>]
          Item {
            width: parent.width
            implicitHeight: Style.space(24)

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22); height: Style.space(22); radius: height / 2
              color: prevMonthHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: prevMonthHover.hovered ? Color.menu.border : "transparent"; border.width: 1
              Text { anchors.centerIn: parent; text: "󰅁"; color: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family }
              HoverHandler { id: prevMonthHover }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.prevMonth() }
            }

            Text {
              anchors.centerIn: parent
              text: {
                var d = new Date(root.calYear, root.calMonth, 1)
                return d.toLocaleDateString(undefined, { month: "long", year: "numeric" })
              }
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22); height: Style.space(22); radius: height / 2
              color: nextMonthHover.hovered ? Color.menu.selectedBackground : "transparent"
              border.color: nextMonthHover.hovered ? Color.menu.border : "transparent"; border.width: 1
              Text { anchors.centerIn: parent; text: "󰅂"; color: root.barForeground; font.family: root.bar ? root.bar.fontFamily : Style.font.family }
              HoverHandler { id: nextMonthHover }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nextMonth() }
            }
          }

          // Weekdays header (Mo Tu We Th Fr Sa Su)
          Row {
            width: parent.width
            Repeater {
              model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
              Item {
                required property var modelData
                width: contentCol.width / 7
                implicitHeight: Style.space(16)
                Text {
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.space(9)
                  font.bold: true
                }
              }
            }
          }

          // Calendar days grid (7 columns x up to 6 rows)
          Grid {
            id: calGrid
            columns: 7
            width: parent.width

            // Computes model of 42 cells representing the calendar page
            readonly property var cellData: {
              var year = root.calYear
              var month = root.calMonth
              var firstDayIndex = (new Date(year, month, 1).getDay() + 6) % 7 // Monday = 0
              var daysInMonth = new Date(year, month + 1, 0).getDate()
              var today = new Date()

              var cells = []
              for (var i = 0; i < 42; i++) {
                var dayNum = i - firstDayIndex + 1
                if (dayNum >= 1 && dayNum <= daysInMonth) {
                  var cellDate = new Date(year, month, dayNum)
                  var isToday = cellDate.toDateString() === today.toDateString()
                  var isSelected = root.targetDate.toDateString() === cellDate.toDateString()
                  var isPast = cellDate.getTime() < new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
                  cells.push({
                    day: dayNum,
                    isCurrentMonth: true,
                    isToday: isToday,
                    isSelected: isSelected,
                    isPast: isPast,
                    year: year,
                    month: month
                  })
                } else {
                  cells.push({ day: 0, isCurrentMonth: false, isToday: false, isSelected: false, isPast: false, year: year, month: month })
                }
              }
              return cells
            }

            Repeater {
              model: calGrid.cellData

              Rectangle {
                id: dayCell
                required property var modelData
                width: contentCol.width / 7
                height: Style.space(22)
                radius: height / 2
                visible: dayCell.modelData.isCurrentMonth
                color: dayCell.modelData.isSelected
                  ? root.accentColor
                  : (dayHover.hovered && !dayCell.modelData.isPast ? Color.menu.selectedBackground : "transparent")
                border.color: dayCell.modelData.isToday && !dayCell.modelData.isSelected
                  ? root.accentColor
                  : "transparent"
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: dayCell.modelData.day > 0 ? String(dayCell.modelData.day) : ""
                  color: dayCell.modelData.isSelected
                    ? "white"
                    : (dayCell.modelData.isPast ? Color.muted : root.barForeground)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.space(9.5)
                  font.bold: dayCell.modelData.isSelected || dayCell.modelData.isToday
                }

                HoverHandler { id: dayHover; enabled: dayCell.modelData.isCurrentMonth && !dayCell.modelData.isPast }
                MouseArea {
                  anchors.fill: parent
                  enabled: dayCell.modelData.isCurrentMonth && !dayCell.modelData.isPast
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selectDate(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day)
                  }
                }
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // 5. Action controls (Clear / Cancel / Set Reminder)
        Item {
          width: parent.width
          implicitHeight: Style.space(26)

          // Clear button (visible when reminder is active)
          Rectangle {
            id: clearActionBtn
            visible: Boolean(root.initialIso)
            readonly property bool isSelected: root.pickerSection === "actions" && Boolean(root.initialIso) && root.actionIndex === 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: clearActionText.implicitWidth + Style.space(12)
            implicitHeight: Style.space(22)
            radius: height / 2
            color: (clearHover.hovered || isSelected) ? Util.alpha(root.warningColor, 0.15) : "transparent"
            border.color: (clearHover.hovered || isSelected) ? root.warningColor : Color.menu.border
            border.width: isSelected ? 1.5 : 1

            Text {
              id: clearActionText
              anchors.centerIn: parent
              text: "󰅖 Clear"
              color: (clearHover.hovered || clearActionBtn.isSelected) ? root.warningColor : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            HoverHandler { id: clearHover }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearReminder()
            }
          }

          // Cancel & Set buttons on right
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Rectangle {
              id: cancelBtn
              readonly property bool isSelected: root.pickerSection === "actions" && (root.initialIso ? root.actionIndex === 1 : root.actionIndex === 0)
              implicitWidth: cancelText.implicitWidth + Style.space(14)
              implicitHeight: Style.space(22)
              radius: height / 2
              color: (cancelHover.hovered || isSelected) ? Color.menu.selectedBackground : "transparent"
              border.color: isSelected ? root.accentColor : Color.menu.border
              border.width: isSelected ? 1.5 : 1

              Text {
                id: cancelText
                anchors.centerIn: parent
                text: "Cancel"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              HoverHandler { id: cancelHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.close()
              }
            }

            Rectangle {
              id: confirmBtn
              readonly property bool isSelected: root.pickerSection === "actions" && (root.initialIso ? root.actionIndex === 2 : root.actionIndex === 1)
              implicitWidth: confirmText.implicitWidth + Style.space(16)
              implicitHeight: Style.space(22)
              radius: height / 2
              color: root.accentColor
              border.color: isSelected ? "white" : "transparent"
              border.width: isSelected ? 1.5 : 0
              scale: (confirmHover.hovered || isSelected) ? 1.03 : 1.0
              Behavior on scale { NumberAnimation { duration: 80 } }

              Row {
                id: confirmText
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰄬"
                  color: "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Set Reminder"
                  color: "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              HoverHandler { id: confirmHover }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.confirm()
              }
            }
          }
        }
      }
    }
  }
}
