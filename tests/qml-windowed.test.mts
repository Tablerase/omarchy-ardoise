import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { findOnPath, repoDir } from "./helpers/qml-test-utils.mts";

test("Quickshell Headless Lifecycle [local-only]: QuickAdd, PanelContent, BarWidget, and Service instantiate and toggle without errors", (t) => {
  // LOCAL-ONLY BY DESIGN. QuickAdd.qml is a WlrLayer.Overlay, so mounting it
  // requires a wlr-layer-shell compositor; `offscreen` has no PanelWindow
  // backend and the config fails to load. CI therefore covers the window-free
  // components via the "Quickshell Core (no compositor)" test above, and this
  // test adds the windowed lifecycle on a real desktop session.
  if (process.env.CI) {
    t.skip("local-only: QuickAdd needs a wlr-layer-shell compositor; CI covers the core harness instead");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display, so a WlrLayer.Overlay cannot be mounted");
    return;
  }

  // Check if quickshell is installed and accessible
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH; skipping runtime instantiation test");
    return;
  }

  // Check if Omarchy shell assets exist
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");

  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) {
      throw new Error("Omarchy shell Commons/Ui modules must be provided in CI (OMARCHY_PATH=" + omarchyPath + ")");
    }
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath + "; skipping runtime instantiation test");
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-qml-test-"));

  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    // Write test harness shell.qml that mounts components and exercises their open/dismiss methods
    const harnessQml = `
import QtQuick
import Quickshell
import "plugin" as Plugin
import "Ui" as Ui

ShellRoot {
    id: root

    Plugin.QuickAdd {
        id: quickAdd
    }

    Plugin.BarWidget {
        id: barWidget
    }

    Plugin.PanelContent {
        id: panelContent
        barWidget: barWidget
    }

    Ui.PanelKeyCatcher {
        id: panelKeyCatcher
        blocked: panelContent.activeFocusBlocked
        onMoveRequested: function(dx, dy) { panelContent.handleMove(dx, dy) }
        onTabRequested: function(dir) { panelContent.handleTab(dir) }
        onActivateRequested: function() { panelContent.handleActivate() }
        onReturnRequested: function() { panelContent.handleReturn() }
        onTextKey: function(t) { panelContent.handleTextKey(t) }
        onDeleteRequested: function() { panelContent.handleDelete() }
        onCloseRequested: function() {
            if (panelContent.handleEscape && panelContent.handleEscape()) return
            panelContent.closeRequested()
        }
    }

    Plugin.Service {
        id: service
    }

    Timer {
        id: testRunner
        interval: 150
        running: true
        repeat: false
        onTriggered: {
            console.log("[TEST] Testing QuickAdd open/dismiss lifecycle...");
            quickAdd.open("{}");
            if (!quickAdd.opened) {
                console.error("[TEST FAIL] quickAdd.opened is false after open()");
                Qt.exit(101);
                return;
            }

            // Test draft saving and restoration
            quickAdd.draftTitle = "Automated test task";
            quickAdd.dismiss();
            if (quickAdd.opened) {
                console.error("[TEST FAIL] quickAdd.opened is true after dismiss()");
                Qt.exit(102);
                return;
            }

            quickAdd.open("{}");
            if (!quickAdd.opened) {
                console.error("[TEST FAIL] quickAdd failed to reopen with draft");
                Qt.exit(103);
                return;
            }
            quickAdd.clearDraft();
            quickAdd.dismiss();

            console.log("[TEST] Testing PanelContent filter state and properties...");
            panelContent.currentFilter = "work";
            if (panelContent.currentFilter !== "work") {
                console.error("[TEST FAIL] panelContent.currentFilter did not update");
                Qt.exit(104);
                return;
            }

            console.log("[TEST] Testing BarWidget methods...");
            if (typeof barWidget.toggle !== "function" || typeof barWidget.addTodo !== "function") {
                console.error("[TEST FAIL] barWidget missing essential methods");
                Qt.exit(105);
                return;
            }

            console.log("[TEST] Testing PanelKeyCatcher & PanelContent Vim motions & navigation pipeline...");

            // 1. Initial State: KeyCatcher and panelContent MUST NOT be blocked!
            if (panelKeyCatcher.blocked) {
                console.error("[TEST FAIL] panelKeyCatcher.blocked is true on default startup! Vim motions and Tab are dead.");
                Qt.exit(120);
                return;
            }
            if (panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelContent.activeFocusBlocked is true on default startup!");
                Qt.exit(121);
                return;
            }

            // 2. Normal tasks navigation: panelKeyCatcher must remain unblocked
            panelContent.currentFilter = "all";
            var testStore = {
                version: 1,
                activeProfile: "personal",
                profiles: ["personal", "work"],
                todos: [
                    { id: 1, title: "Automated task 1", profile: "personal", done: false },
                    { id: 2, title: "Automated task 2", profile: "personal", done: false }
                ]
            };
            barWidget.store = testStore;
            panelContent.store = testStore;
            panelContent.focusSection = "tasks";
            panelContent.cursorActive = true;
            panelContent.cursorIndex = 0;
            panelContent.handleMove(0, 1);
            if (panelContent.cursorIndex < 1) {
                console.error("[TEST FAIL] handleMove failed to advance cursorIndex in tasks (cursorIndex=" + panelContent.cursorIndex + ")");
                Qt.exit(122);
                return;
            }
            if (panelKeyCatcher.blocked || panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher became blocked during task motion!");
                Qt.exit(123);
                return;
            }

            panelContent.handleMove(0, -1);
            if (panelContent.cursorIndex !== 0) {
                console.error("[TEST FAIL] handleMove failed to move cursorIndex back");
                Qt.exit(124);
                return;
            }

            // 3. Section transitions (Tab / Shift+Tab): panelKeyCatcher must remain unblocked
            panelContent.handleTab(1);
            if (panelContent.focusSection !== "footer") {
                console.error("[TEST FAIL] handleTab failed to transition forward to footer");
                Qt.exit(125);
                return;
            }
            if (panelKeyCatcher.blocked || panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher became blocked in footer section!");
                Qt.exit(126);
                return;
            }

            panelContent.handleTab(-1);
            if (panelContent.focusSection !== "tasks") {
                console.error("[TEST FAIL] handleTab failed to transition back to tasks");
                Qt.exit(127);
                return;
            }

            // 4. Input section normal (motion) mode: panelKeyCatcher MUST NOT be blocked
            panelContent.focusSection = "input";
            panelContent.releaseFocus(); // ensure not in edit mode
            if (panelKeyCatcher.blocked || panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher must NOT be blocked when input section is in motion mode!");
                Qt.exit(128);
                return;
            }

            // 5. Help Modal Lifecycle: KeyCatcher MUST BE BLOCKED while open, and UNBLOCKED when closed!
            panelContent.focusSection = "tasks";
            panelContent.handleTextKey("?");
            if (!panelContent.showKeyHelp) {
                console.error("[TEST FAIL] handleTextKey('?') failed to open HelpModal");
                Qt.exit(129);
                return;
            }
            if (!panelKeyCatcher.blocked || !panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher must be blocked while HelpModal is open");
                Qt.exit(130);
                return;
            }

            // Close HelpModal via '?' toggle
            panelContent.handleTextKey("?");
            if (panelContent.showKeyHelp) {
                console.error("[TEST FAIL] handleTextKey('?') failed to close HelpModal");
                Qt.exit(131);
                return;
            }
            if (panelKeyCatcher.blocked || panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher remained blocked after closing HelpModal! This breaks all panel vim motions.");
                Qt.exit(132);
                return;
            }

            // Verify motions continue smoothly after HelpModal closes
            panelContent.handleMove(0, 1);
            if (panelContent.cursorIndex < 1) {
                console.error("[TEST FAIL] Motions failed to work after closing HelpModal");
                Qt.exit(133);
                return;
            }

            // 5b. Git Modal Lifecycle: KeyCatcher MUST BE BLOCKED while open, and UNBLOCKED when closed!
            panelContent.focusSection = "tasks";
            panelContent.handleTextKey("u");
            if (!panelContent.showGitModal) {
                console.error("[TEST FAIL] handleTextKey('u') failed to open GitModal");
                Qt.exit(140);
                return;
            }
            if (!panelKeyCatcher.blocked || !panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher must be blocked while GitModal is open");
                Qt.exit(141);
                return;
            }

            // Test GitModal Tab section navigation & Vim motions
            var gm = panelContent.gitModal;
            if (!gm) {
                console.error("[TEST FAIL] panelContent.gitModal is not accessible");
                Qt.exit(159);
                return;
            }
            if (gm.snapshotSection !== "snapshots") {
                console.error("[TEST FAIL] GitModal default snapshotSection should be 'snapshots', got: " + gm.snapshotSection);
                Qt.exit(160);
                return;
            }
            // Tab transitions from snapshots list to actions button section
            gm.handleKey({ key: Qt.Key_Tab, text: "", modifiers: 0, accepted: false });
            if (gm.snapshotSection !== "actions" || gm.actionButtonIndex !== 0) {
                console.error("[TEST FAIL] Tab failed to transition to actions section (snapshotSection=" + gm.snapshotSection + ", actionButtonIndex=" + gm.actionButtonIndex + ")");
                Qt.exit(161);
                return;
            }
            // 'l' / Right moves to button 1 (Recover Deleted)
            gm.handleKey({ key: Qt.Key_L, text: "l", modifiers: 0, accepted: false });
            if (gm.actionButtonIndex !== 1) {
                console.error("[TEST FAIL] 'l' failed to advance actionButtonIndex to 1");
                Qt.exit(162);
                return;
            }
            // 'h' / Left moves back to button 0 (Rollback)
            gm.handleKey({ key: Qt.Key_H, text: "h", modifiers: 0, accepted: false });
            if (gm.actionButtonIndex !== 0) {
                console.error("[TEST FAIL] 'h' failed to move actionButtonIndex back to 0");
                Qt.exit(163);
                return;
            }
            // 'k' / Up transitions back up to snapshots list
            gm.handleKey({ key: Qt.Key_K, text: "k", modifiers: 0, accepted: false });
            if (gm.snapshotSection !== "snapshots") {
                console.error("[TEST FAIL] 'k' in actions failed to transition back up to snapshots");
                Qt.exit(164);
                return;
            }
            // Backtab (Shift+Tab) reverse-transitions to actions button 1
            gm.handleKey({ key: Qt.Key_Backtab, text: "", modifiers: 0, accepted: false });
            if (gm.snapshotSection !== "actions" || gm.actionButtonIndex !== 1) {
                console.error("[TEST FAIL] Shift+Tab failed to reverse-transition to actions (actionButtonIndex=" + gm.actionButtonIndex + ")");
                Qt.exit(165);
                return;
            }
            // Tab wraps from last action button back to snapshots
            gm.handleKey({ key: Qt.Key_Tab, text: "", modifiers: 0, accepted: false });
            if (gm.snapshotSection !== "snapshots") {
                console.error("[TEST FAIL] Tab from action button 1 failed to wrap to snapshots");
                Qt.exit(166);
                return;
            }

            // Test GitContextMenu open, sizing, vim navigation, and escape dismiss lifecycle
            gm.contextMenu.open({ hash: "abcdef1234567890", shortHash: "abcdef1", message: "Test snapshot", timestamp: Date.now() }, 100, 100);
            if (!gm.contextMenu.isOpen) {
                console.error("[TEST FAIL] contextMenu.open() failed to open GitContextMenu");
                Qt.exit(167);
                return;
            }
            if (gm.contextMenu.card.height <= 0) {
                console.error("[TEST FAIL] GitContextMenu card height must be > 0, got: " + gm.contextMenu.card.height);
                Qt.exit(169);
                return;
            }
            if (gm.contextMenu.card.width <= 0) {
                console.error("[TEST FAIL] GitContextMenu card width must be > 0, got: " + gm.contextMenu.card.width);
                Qt.exit(170);
                return;
            }
            // Navigate menu with 'j' / 'k'
            gm.handleKey({ key: Qt.Key_J, text: "j", modifiers: 0, accepted: false });
            if (gm.contextMenu.selectedMenuIndex !== 1) {
                console.error("[TEST FAIL] GitContextMenu 'j' failed to advance selectedMenuIndex to 1");
                Qt.exit(171);
                return;
            }
            gm.handleKey({ key: Qt.Key_K, text: "k", modifiers: 0, accepted: false });
            if (gm.contextMenu.selectedMenuIndex !== 0) {
                console.error("[TEST FAIL] GitContextMenu 'k' failed to move selectedMenuIndex back to 0");
                Qt.exit(172);
                return;
            }
            gm.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false });
            if (gm.contextMenu.isOpen) {
                console.error("[TEST FAIL] Escape failed to dismiss GitContextMenu");
                Qt.exit(168);
                return;
            }

            // Close GitModal via 'u' toggle
            panelContent.handleTextKey("u");
            if (panelContent.showGitModal) {
                console.error("[TEST FAIL] handleTextKey('u') failed to close GitModal");
                Qt.exit(142);
                return;
            }
            if (panelKeyCatcher.blocked || panelContent.activeFocusBlocked) {
                console.error("[TEST FAIL] panelKeyCatcher remained blocked after closing GitModal!");
                Qt.exit(143);
                return;
            }

            // Test Quick Add trigger via 'A' key
            var closeRequestedReceived = false;
            panelContent.closeRequested.connect(function() {
                closeRequestedReceived = true;
            });
            panelContent.handleTextKey("A");
            if (!closeRequestedReceived) {
                console.error("[TEST FAIL] handleTextKey('A') failed to trigger openQuickAdd / closeRequested");
                Qt.exit(111);
                return;
            }

            // Test releaseFocus method
            panelContent.releaseFocus();
            if (typeof panelContent.ensureReminderVisible !== "function") {
                console.error("[TEST FAIL] panelContent is missing ensureReminderVisible");
                Qt.exit(134);
                return;
            }

            // Test footer shortcut hotkeys: 'c', 'd', 'e'
            var closeRequestedCount = 0;
            panelContent.closeRequested.connect(function() {
                closeRequestedCount++;
            });
            panelContent.focusSection = "footer";
            panelContent.handleTextKey("e");
            if (closeRequestedCount < 1) {
                console.error("[TEST FAIL] handleTextKey('e') failed to trigger openEditor / closeRequested");
                Qt.exit(124);
                return;
            }
            panelContent.focusSection = "tasks";
            panelContent.cursorIndex = 0;
            var countBeforeTaskE = closeRequestedCount;
            panelContent.handleTextKey("e");
            if (closeRequestedCount <= countBeforeTaskE) {
                console.error("[TEST FAIL] handleTextKey('e') in tasks section failed to trigger openEditor / closeRequested");
                Qt.exit(126);
                return;
            }
            var countBeforeD = closeRequestedCount;
            panelContent.handleTextKey("d");
            if (closeRequestedCount <= countBeforeD) {
                console.error("[TEST FAIL] handleTextKey('d') failed to trigger openArchive / closeRequested");
                Qt.exit(125);
                return;
            }
            // Test Clear Completed via 'c' key and footer button
            // 1. Add and complete a task
            barWidget.addTodo("Completed Task To Clear", "", "personal", "");
            panelContent.store = barWidget.store;
            panelContent.syncFilteredTodos();
            var taskToClear = null;
            for (var k = 0; k < panelContent.filteredTodos.length; k++) {
                if (panelContent.filteredTodos[k].title === "Completed Task To Clear") {
                    taskToClear = panelContent.filteredTodos[k];
                    break;
                }
            }
            if (!taskToClear) {
                console.error("[TEST FAIL] Failed to prepare task for clear test");
                Qt.exit(144);
                return;
            }
            panelContent.applyToggleTodo(taskToClear.id);
            if (panelContent.completedCount < 1) {
                console.error("[TEST FAIL] completedCount should be >= 1 after toggling task done");
                Qt.exit(145);
                return;
            }
            var countBeforeClear = panelContent.filteredTodos.length;

            // 2. Press 'c' to clear completed tasks
            panelContent.focusSection = "tasks";
            panelContent.handleTextKey("c");

            // 3. Verify task is removed from panelContent.filteredTodos and completedCount is 0
            if (panelContent.completedCount !== 0) {
                console.error("[TEST FAIL] completedCount was not 0 after handleTextKey('c')");
                Qt.exit(146);
                return;
            }
            if (panelContent.filteredTodos.length !== countBeforeClear - 1) {
                console.error("[TEST FAIL] filteredTodos length did not decrease after clearCompleted");
                Qt.exit(147);
                return;
            }
            for (var cIdx = 0; cIdx < panelContent.filteredTodos.length; cIdx++) {
                if (panelContent.filteredTodos[cIdx].id === taskToClear.id) {
                    console.error("[TEST FAIL] Cleared task still present in panelContent.filteredTodos");
                    Qt.exit(148);
                    return;
                }
            }
            if (panelContent.store.todos.some(function(t) { return t.id === taskToClear.id })) {
                console.error("[TEST FAIL] Cleared task still present in panelContent.store.todos");
                Qt.exit(149);
                return;
            }

            // 4. Test footer Clear button (triggerFooterButton(0))
            barWidget.addTodo("Footer Task To Clear", "", "personal", "");
            panelContent.store = barWidget.store;
            panelContent.syncFilteredTodos();
            var footerTask = null;
            for (var f = 0; f < panelContent.filteredTodos.length; f++) {
                if (panelContent.filteredTodos[f].title === "Footer Task To Clear") {
                    footerTask = panelContent.filteredTodos[f];
                    break;
                }
            }
            if (!footerTask) {
                console.error("[TEST FAIL] Failed to find Footer Task To Clear");
                Qt.exit(153);
                return;
            }
            panelContent.applyToggleTodo(footerTask.id);
            if (panelContent.completedCount < 1) {
                console.error("[TEST FAIL] completedCount should be >= 1 before footer clear");
                Qt.exit(150);
                return;
            }
            panelContent.triggerFooterButton(0);
            if (panelContent.completedCount !== 0) {
                console.error("[TEST FAIL] completedCount was not 0 after triggerFooterButton(0)");
                Qt.exit(151);
                return;
            }
            if (panelContent.store.todos.some(function(t) { return t.id === footerTask.id })) {
                console.error("[TEST FAIL] Footer cleared task still present in store");
                Qt.exit(152);
                return;
            }

            // Test moving UP at task 0 transitions focus into input field
            panelContent.focusSection = "tasks";
            panelContent.cursorIndex = 0;
            panelContent.handleMove(0, -1);
            if (panelContent.focusSection !== "input") {
                console.error("[TEST FAIL] handleMove(0, -1) at task 0 failed to transition to input");
                Qt.exit(112);
                return;
            }

            // Test moving DOWN from profiles transitions focus into input field
            panelContent.focusSection = "profiles";
            panelContent.handleMove(0, 1);
            if (panelContent.focusSection !== "input") {
                console.error("[TEST FAIL] handleMove(0, 1) from profiles failed to transition to input");
                Qt.exit(113);
                return;
            }

            // Test Enter vs Space separation on task list
            panelContent.focusSection = "tasks";
            panelContent.cursorIndex = 0;
            if (panelContent.filteredTodos && panelContent.filteredTodos.length > 0) {
                var testTask = panelContent.filteredTodos[0];
                var initialDone = Boolean(testTask.done);
                panelContent.handleReturn();
                panelContent.handleActivate(); // simulates PanelKeyCatcher emitting activate after return
                var taskAfterEnter = panelContent.filteredTodos[0];
                if (Boolean(taskAfterEnter.done) !== initialDone) {
                    console.error("[TEST FAIL] handleReturn + handleActivate toggled task completion (should be suppressed)");
                    Qt.exit(118);
                    return;
                }
                if (panelContent.expandedTaskId !== testTask.id) {
                    console.error("[TEST FAIL] handleReturn failed to expand task");
                    Qt.exit(119);
                    return;
                }
                // Test ensureTaskVisible with alignTop true (auto-top alignment)
                panelContent.ensureTaskVisible(0, true);
                panelContent.ensureTaskVisible(0, false);
                if (!panelContent.expandedViaKeyboard) {
                    console.error("[TEST FAIL] handleReturn did not set expandedViaKeyboard to true");
                    Qt.exit(120);
                    return;
                }
                // Keyboard motion while expandedViaKeyboard should NOT collapse the expanded task
                panelContent.handleMove(0, 1);
                if (panelContent.expandedTaskId !== testTask.id || panelContent.expandedSubSection !== "notes") {
                    console.error("[TEST FAIL] handleMove failed to navigate to notes while keeping task expanded");
                    Qt.exit(121);
                    return;
                }
                // Test notes editor activation, text edit, and Escape recovery without delegate destruction
                panelContent.focusNotesEditor();
                if (panelContent.descArea) {
                    var originalDescArea = panelContent.descArea;
                    if (originalDescArea.textArea) {
                        originalDescArea.textArea.text = "Updated description during test edit";
                    }
                    originalDescArea.releaseFocus();
                    originalDescArea.escapePressed();
                    originalDescArea.save();
                    if (panelContent.descArea !== originalDescArea) {
                        console.error("[TEST FAIL] Editing and saving notes caused delegate rebuild / glitch (item collapsed/re-expanded)");
                        Qt.exit(132);
                        return;
                    }
                    if (panelContent.descArea.editorActiveFocus) {
                        console.error("[TEST FAIL] descArea.escapePressed() failed to release editor focus");
                        Qt.exit(127);
                        return;
                    }
                    if (panelContent.activeFocusBlocked) {
                        console.error("[TEST FAIL] activeFocusBlocked remained true after escaping notes editor");
                        Qt.exit(128);
                        return;
                    }
                    if (panelContent.expandedSubSection !== "notes" || !panelContent.expandedViaKeyboard) {
                        console.error("[TEST FAIL] Escape from notes editor lost notes sub-section or expandedViaKeyboard flag");
                        Qt.exit(129);
                        return;
                    }
                }
                // Moving down after Escape from notes enters reminders sub-section
                panelContent.handleMove(0, 1);
                if (panelContent.expandedSubSection !== "reminders" || panelContent.expandedTaskId !== testTask.id) {
                    console.error("[TEST FAIL] handleMove(0, 1) after notes Escape failed to enter reminders");
                    Qt.exit(130);
                    return;
                }
                // Lateral navigation on reminders cycles presets and triggers ensureReminderVisible
                panelContent.handleMove(1, 0);
                if (panelContent.expandedReminderIndex !== 1) {
                    console.error("[TEST FAIL] handleMove(1, 0) failed to increment expandedReminderIndex");
                    Qt.exit(131);
                    return;
                }
                // Return cursor to header and collapse back
                panelContent.cursorIndex = 0;
                panelContent.expandedSubSection = "header";
                panelContent.handleReturn();
                if (panelContent.expandedTaskId !== -1 || panelContent.expandedViaKeyboard) {
                    console.error("[TEST FAIL] handleReturn failed to collapse task or reset expandedViaKeyboard");
                    Qt.exit(122);
                    return;
                }
                // Test mouse hover expansion simulation: expandedViaKeyboard is false
                panelContent.expandedTaskId = testTask.id;
                panelContent.expandedViaKeyboard = false;
                panelContent.handleMove(0, 1);
                if (panelContent.expandedTaskId !== -1) {
                    console.error("[TEST FAIL] handleMove failed to collapse temporary hover expansion");
                    Qt.exit(123);
                    return;
                }

                // Test inline title editing lifecycle
                panelContent.cursorIndex = 0;
                panelContent.focusSection = "tasks";
                panelContent.handleTextKey("r");
                if (panelContent.editingTaskId !== testTask.id || !panelContent.activeFocusBlocked) {
                    console.error("[TEST FAIL] handleTextKey('r') failed to initiate title editing on focused task");
                    Qt.exit(134);
                    return;
                }
                // Two-stage escape from title editing cancels editing without closing panel
                if (!panelContent.handleEscape()) {
                    console.error("[TEST FAIL] handleEscape() did not consume escape during title editing");
                    Qt.exit(135);
                    return;
                }
                if (panelContent.editingTaskId !== -1 || panelContent.activeFocusBlocked) {
                    console.error("[TEST FAIL] handleEscape() failed to cancel editingTaskId or unblock activeFocus");
                    Qt.exit(136);
                    return;
                }
                // Commit title edit
                panelContent.startEditingTask(testTask.id);
                panelContent.commitEditingTask(testTask.id, "Renamed through runtime test");
                if (panelContent.editingTaskId !== -1 || panelContent.activeFocusBlocked) {
                    console.error("[TEST FAIL] commitEditingTask failed to reset editingTaskId or activeFocusBlocked");
                    Qt.exit(137);
                    return;
                }
                if (panelContent.store.todos[0].title !== "Renamed through runtime test") {
                    console.error("[TEST FAIL] commitEditingTask did not update task title in store (got: " + panelContent.store.todos[0].title + ")");
                    Qt.exit(138);
                    return;
                }

                // Test In-Panel Search activation and two-stage escape
                panelContent.activateSearch();
                if (!panelContent.searchActive) {
                    console.error("[TEST FAIL] activateSearch() failed to set searchActive=true");
                    Qt.exit(140);
                    return;
                }
                panelContent.searchQuery = "Renamed";
                if (panelContent.filteredTodos.length === 0) {
                    console.error("[TEST FAIL] searchQuery 'Renamed' returned 0 matching tasks");
                    Qt.exit(141);
                    return;
                }
                // Two-stage escape: first clears query
                panelContent.handleEscape();
                if (panelContent.searchQuery !== "") {
                    console.error("[TEST FAIL] handleEscape did not clear non-empty searchQuery");
                    Qt.exit(142);
                    return;
                }
                // Second escape collapses search bar
                panelContent.handleEscape();
                if (panelContent.searchActive) {
                    console.error("[TEST FAIL] handleEscape did not collapse empty search bar");
                    Qt.exit(143);
                    return;
                }
            }

            // Test QuickAdd advanceSection and cycleProfileSelection
            quickAdd.open("{}");
            if (quickAdd.focusSection !== "title") {
                console.error("[TEST FAIL] quickAdd.open() did not reset focusSection to title");
                Qt.exit(114);
                return;
            }
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "options") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) failed to move to options");
                Qt.exit(115);
                return;
            }
            // Enable notes section
            quickAdd.showNote = true;
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "notes") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) failed to move to notes when showNote=true");
                Qt.exit(130);
                return;
            }
            // Move from notes down to profiles
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "profiles") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) from notes failed to move to profiles");
                Qt.exit(116);
                return;
            }
            quickAdd.cycleProfileSelection(1);
            // Enable location context: location is positioned between profiles and actions
            quickAdd.detectedContext = { repo: "test/repo", localPath: "/tmp" };
            quickAdd.attachLocation = true;
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "location") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) from profiles failed to move to location");
                Qt.exit(131);
                return;
            }
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "actions") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) from location failed to move to actions");
                Qt.exit(132);
                return;
            }
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "title") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) from actions failed to wrap to title");
                Qt.exit(133);
                return;
            }
            quickAdd.dismiss();

            console.log("[TEST] All components loaded, opened, and toggled successfully!");
            Qt.exit(0);
        }
    }
}
`;

    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const testConfigDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(testConfigDir, { recursive: true });
    fs.writeFileSync(path.join(testConfigDir, "todos.json"), JSON.stringify({ version: 1, activeProfile: "personal", profiles: ["personal", "work"], todos: [] }), "utf8");
    fs.writeFileSync(path.join(testConfigDir, "todos-archive.json"), JSON.stringify({ version: 1, archived: [] }), "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 6000,
      env: {
        ...process.env,
        HOME: tmpDir,
        ARDOISE_DATA_DIR: testConfigDir,
        // If Wayland is not active, let Quickshell use minimal platform
        QT_QPA_PLATFORM: process.env.WAYLAND_DISPLAY ? undefined : "offscreen"
      }
    });

    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    // Look for QML type errors or runtime compilation failures
    const hasTypeError = /is not a type|ReferenceError|Type .* unavailable|Cannot read property/i.test(output);
    const hasBindingLoop = /Binding loop detected for property/i.test(output);

    assert.ok(
      !hasTypeError,
      "Quickshell output reported QML type/reference errors:\n" + output
    );
    assert.ok(
      !hasBindingLoop,
      "Quickshell output reported property binding loop:\n" + output
    );

    // If Wayland display is present, full interactive lifecycle should have exited 0
    if (process.env.WAYLAND_DISPLAY) {
      assert.equal(
        qsResult.status,
        0,
        "Quickshell harness failed with exit code " + qsResult.status + ":\n" + output
      );

      // Verify that the sandboxed todos file received the runtime edits
      if (fs.existsSync(path.join(testConfigDir, "todos.json"))) {
        const sandboxedRaw = fs.readFileSync(path.join(testConfigDir, "todos.json"), "utf8");
        assert.ok(
          sandboxedRaw.includes("Renamed through runtime test"),
          "Expected runtime test write to be sandboxed in temporary testConfigDir"
        );
      }
      if (fs.existsSync(path.join(testConfigDir, "todos-archive.json"))) {
        const sandboxedArchive = fs.readFileSync(path.join(testConfigDir, "todos-archive.json"), "utf8");
        assert.ok(
          sandboxedArchive.includes("Completed Task To Clear") && sandboxedArchive.includes("Footer Task To Clear"),
          "Expected cleared tasks to be archived in temporary testConfigDir/todos-archive.json"
        );
      }
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
