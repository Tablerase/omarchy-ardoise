import QtQuick

// =============================================================================
// DatePicker.qml
//
// Reusable date and time picker component for due dates, milestones, and generic dates.
// Built on ReminderPicker with customizable defaults for date selection.
// =============================================================================

ReminderPicker {
  id: root

  title: "Select Date"
  icon: "󰃭"
  confirmLabel: "Confirm Date"
  clearLabel: "Clear Date"
  mode: "dueDate"
  allowPastDates: true
}
