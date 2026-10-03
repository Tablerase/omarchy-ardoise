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
        holdDuration: 0
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
            // 'd' now opens the Archive browser modal (it no longer opens the
            // raw JSON in an editor / closes the panel; that moved to 'e'
            // inside the modal).
            panelContent.handleTextKey("d");
            if (!panelContent.showArchiveModal) {
                console.error("[TEST FAIL] handleTextKey('d') failed to open the Archive browser modal");
                Qt.exit(125);
                return;
            }
            panelContent.closeArchiveModal();
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

test("Quickshell Drawer Fit [local-only]: an expanded long title stays fully visible in the panel viewport", (t) => {
  // LOCAL-ONLY BY DESIGN. This is the reproduction harness for the reported
  // bug "when expanded with title and notes the UI doesn't fit": a long title
  // wraps in the drawer, and the wrapped title / the drawer must not be
  // clipped. It mounts the same structure Panel.qml uses - a real layer-shell
  // bar window with a BarWidget, a KeyboardPanel whose content height is
  // fitted from PanelContent.implicitHeight, and a PanelKeyCatcher wrapping
  // PanelContent - then expands a long-title task through the real
  // cursor + handleReturn() path a keypress takes.
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor to mount KeyboardPanel");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display, so KeyboardPanel cannot be mounted");
    return;
  }

  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }

  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) {
      throw new Error("Omarchy shell Commons/Ui modules must be provided in CI (OMARCHY_PATH=" + omarchyPath + ")");
    }
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-drawer-fit-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    // Eight tasks with the long-title + long-notes + repo task in the middle,
    // so the list is taller than the viewport cap and expansion has to scroll.
    const longTitle = "I want a context menu over panel item/task to allow copy";
    // Real newlines: the notes area grows to its max height (130), which makes
    // the expanded drawer taller than the 280px list viewport - the condition
    // under which the reported clipping happens.
    const notes =
      "the goal of this tool/menu is to quickly send the info to your llm/ai agents.\n\n" +
      "the key to do that would be K (to open contextual menu from the keyboard) - and y to quickly copy the todo/task info\n\n" +
      "let's discuss the best way to do that together, and keep going for a while so the notes area reaches its maximum height\n\n" +
      "and one more paragraph to be sure the drawer is taller than the list viewport";
    const todos = [];
    for (let i = 0; i < 8; i++) {
      const isLong = i === 4;
      todos.push({
        id: 100 + i,
        title: isLong ? longTitle : "Short " + i,
        description: isLong ? notes : "",
        done: false,
        profile: "personal",
        reminder: null,
        tags: [],
        repo: isLong ? "Tablerase/omarchy-ardoise" : null,
        createdAt: i,
        updatedAt: i
      });
    }
    fs.writeFileSync(
      path.join(dataDir, "todos.json"),
      JSON.stringify({ version: 1, activeProfile: "personal", profiles: ["personal", "work"], todos }),
      "utf8"
    );
    fs.writeFileSync(
      path.join(dataDir, "todos-archive.json"),
      JSON.stringify({ version: 1, archived: [] }),
      "utf8"
    );

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Item { id: anchor; width: 20; height: 30 }
        Plugin.BarWidget { id: barWidget }
    }

    QtObject {
        id: fakeBarObj
        property string position: "top"
        property string fontFamily: Style.font.family
        property color barForeground: Color.foreground
        property color urgent: Color.urgent
        function switchPanelFrom() { return false }
    }

    KeyboardPanel {
        id: kp
        anchorItem: anchor
        bar: fakeBarObj
        open: true
        contentWidth: kp.fittedContentWidth(Style.space(400))
        contentHeight: kp.fittedContentHeight(panelContent.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: panelContent.activeFocusBlocked
            Plugin.PanelContent {
                id: panelContent
                anchors.fill: parent
                bar: fakeBarObj
                barWidget: barWidget
            }
        }
    }

    function walk(item, out, depth) {
        if (!item || depth > 40) return out
        out.push(item)
        var kids = item.children
        if (kids) for (var i = 0; i < kids.length; i++) walk(kids[i], out, depth + 1)
        if (item.contentItem) walk(item.contentItem, out, depth + 1)
        if (item.item) walk(item.item, out, depth + 1)
        return out
    }

    function findTitle() {
        var all = walk(panelContent, [], 0)
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && all[i].lineCount !== undefined &&
                String(all[i].text).indexOf("I want") === 0) return all[i]
        }
        return null
    }

    function report(tag) {
        var t = findTitle()
        if (!t) { console.log("[FIT] " + tag + "=NO_TITLE"); return }
        var titleRow = t.parent
        var drawer = titleRow.parent.parent
        var taskRow = drawer.parent
        var flick = taskRow
        while (flick && flick.contentHeight === undefined) flick = flick.parent
        var vp = t.mapToItem(flick, 0, 0)
        var drawerBottom = drawer.mapToItem(flick, 0, drawer.implicitHeight).y
        console.log("[FIT] " + tag
            + " lines=" + t.lineCount
            + " titleViewportY=" + Math.round(vp.y)
            + " titleSlack=" + Math.round(titleRow.height - t.height)
            + " drawerSlack=" + Math.round(taskRow.height - drawer.implicitHeight)
            + " drawerBottom=" + Math.round(drawerBottom)
            + " viewportH=" + Math.round(flick.height))
    }

    Timer { interval: 1200; running: true; onTriggered: report("collapsed") }
    Timer {
        interval: 2000; running: true
        onTriggered: {
            var idx = -1
            for (var i = 0; i < panelContent.filteredTodos.length; i++)
                if (panelContent.filteredTodos[i].id === 104) idx = i
            panelContent.cursorIndex = idx
            panelContent.focusSection = "tasks"
            panelContent.cursorActive = true
            panelContent.handleReturn()
        }
    }
    Timer { interval: 3000; running: true; onTriggered: report("expanded") }
    // The reported sequence: expand, move up to the previous item, then move
    // back down onto the still-expanded item. Moving down used to bottom-align
    // the too-tall expanded row, pushing its wrapped title above the viewport.
    Timer { interval: 3400; running: true; onTriggered: panelContent.handleMove(0, -1) }
    Timer { interval: 4000; running: true; onTriggered: panelContent.handleMove(0, 1) }
    Timer { interval: 4800; running: true; onTriggered: report("settled") }
    // Second sample: the whole suite runs several quickshell instances in
    // parallel, so a loaded machine can report the first sample mid-layout.
    Timer { interval: 6200; running: true; onTriggered: report("final") }
    Timer { interval: 6600; running: true; onTriggered: { console.log("[FIT] done=1"); Qt.exit(0) } }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 25000,
      env: {
        ...process.env,
        HOME: tmpDir,
        ARDOISE_DATA_DIR: dataDir
      }
    });

    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");
    const pick = (str: string, key: string) => {
      const match = new RegExp("\\[FIT\\] " + key + "(?:=(\\S+)|\\s+([^\r\n]+))").exec(str);
      return match ? (match[1] || match[2]) : undefined;
    };
    const num = (line: string | undefined, key: string) =>
      Number(new RegExp(key + "=(-?\\d+)").exec(line || "")?.[1]);

    assert.equal(pick(output, "done"), "1", "drawer-fit harness did not run to completion:\n" + output);

    const settled = pick(output, "final");
    assert.ok(settled && settled !== "NO_TITLE", "long-title row must be mounted:\n" + output);

    // The wrapped title must fit its own row, and the row must be tall enough
    // for the whole drawer. Either failure clips the first title line.
    assert.ok(
      num(settled, "titleSlack") >= 0,
      "the title row must be at least as tall as the wrapped title:\n" + output
    );
    assert.ok(
      num(settled, "drawerSlack") >= 0,
      "the task row must be at least as tall as the drawer content:\n" + output
    );
    // The title's top must not sit above the viewport top, or its first line
    // is cut off by the Flickable's clip.
    assert.ok(
      num(settled, "titleViewportY") >= 0,
      "the expanded title must be scrolled into the viewport, not clipped above it:\n" + output
    );
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell Task Menu & Archive [local-only]: context menu actions and archive restore over 5,000 items", (t) => {
  // LOCAL-ONLY: mounts KeyboardPanel, which needs a wlr-layer-shell compositor.
  // Exercises the two new surfaces on a real window: the K context menu
  // (PanelLogic-routed) and the archive browser restoring a task out of a
  // 5,000-item archive, asserting the ListView stays virtualized.
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor to mount KeyboardPanel");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display, so KeyboardPanel cannot be mounted");
    return;
  }

  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }

  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) {
      throw new Error("Omarchy shell Commons/Ui modules must be provided in CI (OMARCHY_PATH=" + omarchyPath + ")");
    }
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-menu-archive-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    const store = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal", "work"],
      todos: [
        {
          id: 1,
          title: "Focused task with notes",
          description: "notes for the LLM",
          done: false,
          profile: "work",
          repo: "Tablerase/omarchy-ardoise",
          tags: ["copy"],
          location: { repo: "Tablerase/omarchy-ardoise", subpath: null, localPath: "~/code/ardoise" },
          createdAt: 1
        },
        { id: 2, title: "Second task", done: false, profile: "personal", createdAt: 2 }
      ]
    };
    const now = Date.now();
    const archived = [{ id: 7000, title: "Restore me from the archive", description: "old notes", profile: "ardoise", repo: "Tablerase/omarchy-ardoise", tags: [], createdAt: 1, completedAt: 2 }];
    for (let i = 0; i < 5000; i++) {
      archived.push({ id: 8000 + i, title: "Archived #" + i, description: "notes", profile: "personal", tags: ["archived"], createdAt: now - i, completedAt: now - i });
    }
    fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(dataDir, "todos-archive.json"), JSON.stringify({ version: 1, archived }, null, 2), "utf8");

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Item { id: anchor; width: 20; height: 30 }
        Plugin.BarWidget { id: barWidget }
    }

    QtObject {
        id: fakeBarObj
        property string position: "top"
        property string fontFamily: Style.font.family
        property color barForeground: Color.foreground
        property color urgent: Color.urgent
        function switchPanelFrom() { return false }
    }

    KeyboardPanel {
        id: kp
        anchorItem: anchor
        bar: fakeBarObj
        open: true
        contentWidth: kp.fittedContentWidth(Style.space(400))
        contentHeight: kp.fittedContentHeight(panelContent.implicitHeight)

        PanelKeyCatcher {
            anchors.fill: parent
            blocked: panelContent.activeFocusBlocked
            Plugin.PanelContent {
                id: panelContent
                anchors.fill: parent
                bar: fakeBarObj
                barWidget: barWidget
            }
        }
    }

    function walk(item, out, depth) {
        if (!item || depth > 40) return out
        out.push(item)
        var kids = item.children
        if (kids) for (var i = 0; i < kids.length; i++) walk(kids[i], out, depth + 1)
        if (item.contentItem) walk(item.contentItem, out, depth + 1)
        if (item.item) walk(item.item, out, depth + 1)
        return out
    }

    function findListView(modal) {
        var all = walk(modal, [], 0)
        for (var i = 0; i < all.length; i++) {
            if (all[i] && typeof all[i].count === "number" && all[i].contentItem !== undefined) return all[i]
        }
        return null
    }

    Timer {
        interval: 1500; running: true
        onTriggered: {
            panelContent.cursorIndex = 0
            panelContent.focusSection = "tasks"
            panelContent.openTaskMenu()
            console.log("[TM] menu=" + (panelContent.showTaskMenu ? 1 : 0) + " items=" + panelContent.taskMenuItems.length)
            panelContent.activateTaskMenuItem("copy_llm")
            console.log("[TM] closed=" + (panelContent.showTaskMenu ? 0 : 1))
        }
    }

    Timer {
        interval: 2300; running: true
        onTriggered: panelContent.openArchiveModal()
    }

    Timer {
        interval: 2800; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            // Search button activates the filter bar.
            modal.activateSearch()
            console.log("[AM] search=" + (modal.searchActive ? 1 : 0))
            modal.closeSearch()
            // Lowercase k must navigate, NOT open the menu.
            modal.selectedIndex = 3
            modal.handleKey({ key: 0x4B, text: "k", modifiers: 0, accepted: false })
            console.log("[AM] lowerK menu=" + (modal.showMenu ? 1 : 0) + " moved=" + (modal.selectedIndex === 2 ? 1 : 0))
            // Uppercase K opens the menu.
            modal.handleKey({ key: 0x4B, text: "K", modifiers: 0x02000000, accepted: false })
            console.log("[AM] upperK menu=" + (modal.showMenu ? 1 : 0) + " items=" + modal.menuItems.length)
            modal.closeMenu()
            // Right-click entry point on the task list.
            panelContent.openTaskMenuAt(0, 130, 130)
            console.log("[AM] rcMenu=" + (panelContent.showTaskMenu ? 1 : 0))
            panelContent.closeTaskMenu()
        }
    }

    Timer {
        interval: 3200; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            var lv = findListView(modal)
            console.log("[AM] raw=" + barWidget.getArchiveText().length + " last=" + barWidget.lastArchiveText.length)
            console.log("[AM] open=" + (modal.isOpen ? 1 : 0)
                + " total=" + modal.archivedTasks.length
                + " delegates=" + (lv ? lv.contentItem.children.length : -1))
            modal.selectedIndex = 0
            modal.restoreSelected()
        }
    }

    Timer {
        interval: 4200; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            console.log("[AM] restored store=" + barWidget.store.todos.length + " arch=" + modal.archivedTasks.length)
            console.log("[AM] done=1")
            Qt.exit(0)
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 25000,
      env: { ...process.env, HOME: tmpDir, ARDOISE_DATA_DIR: dataDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");
    const pick = (key: string) => new RegExp("\\[TM\\] " + key + "=(\\S+)").exec(output)?.[1];
    const tmLine = new RegExp("\\[TM\\] menu=\\S+ items=\\S+").exec(output)?.[0];
    const pickAm = (key: string) => new RegExp("\\[AM\\] " + key + "=(\\S+)").exec(output)?.[1];
    const num = (line: string | undefined, key: string) =>
      Number(new RegExp(key + "=(-?\\d+)").exec(line || "")?.[1]);

    assert.ok(!/Binding loop detected|ReferenceError|is not a type|TypeError|Cannot read property/i.test(output), "harness reported QML errors:\n" + output);
    assert.equal(pickAm("done"), "1", "menu/archive harness did not run to completion:\n" + output);

    assert.equal(pick("menu"), "1", "K must open the task context menu:\n" + output);
    assert.ok(num(tmLine, "items") >= 4, "the menu must expose the task actions:\n" + output);
    assert.equal(pick("closed"), "1", "activating a menu item must close the menu:\n" + output);

    const am = new RegExp("\\[AM\\] open=1 total=(\\d+) delegates=(\\d+)").exec(output);
    assert.ok(am, "the archive modal must open:\n" + output);
    assert.equal(Number(am![1]), 5001, "the archive must hold every item:\n" + output);
    assert.ok(
      Number(am![2]) < 200,
      "the archive ListView must virtualize 5,001 items (instantiated " + am![2] + " delegates):\n" + output
    );

    const restored = new RegExp("\\[AM\\] restored store=(\\d+) arch=(\\d+)").exec(output);
    assert.ok(restored, "restore result must be reported:\n" + output);
    assert.equal(Number(restored![1]), 3, "the restored task must be in the active store:\n" + output);
    assert.equal(Number(restored![2]), 5000, "the restored task must leave the archive:\n" + output);

    assert.ok(/\[AM\] search=1/.test(output), "the archive search button must activate the filter bar:\n" + output);
    assert.ok(/\[AM\] lowerK menu=0 moved=1/.test(output), "lowercase k must navigate the archive list, not open the menu:\n" + output);
    const amMenu = new RegExp("\\[AM\\] upperK menu=1 items=(\\d+)").exec(output);
    assert.ok(amMenu && Number(amMenu[1]) >= 4, "uppercase K must open the archive context menu with items:\n" + output);
    assert.ok(/\[AM\] rcMenu=1/.test(output), "openTaskMenuAt must open the task context menu (right-click path):\n" + output);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell Archive Safety [local-only]: restore/purge never lose data and duplicates self-heal", (t) => {
  // LOCAL-ONLY. Drives BarWidget's durable archive operations on a real
  // window, then asserts the ON-DISK files after the process exits:
  //   - restore immediately after startup (the race that caused the original
  //     duplicate) leaves the id in exactly one file,
  //   - restoring twice does not duplicate,
  //   - a duplicate seeded in both files is reconciled on load,
  //   - permanent delete removes only the archive entry.
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor to mount BarWidget's panel loader");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display");
    return;
  }

  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) throw new Error("Omarchy shell Commons/Ui modules must be provided in CI");
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-archive-safety-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    const store = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal"],
      todos: [
        { id: 1, title: "Active one", done: false, profile: "personal", createdAt: 1 },
        { id: 2, title: "Duplicate active", done: false, profile: "personal", createdAt: 2 }
      ]
    };
    const archived = [
      { id: 2, title: "Duplicate in archive", profile: "personal", createdAt: 2, completedAt: 2 },
      { id: 100, title: "Restore me", description: "notes", profile: "personal", createdAt: 100, completedAt: 100 },
      { id: 101, title: "Purge me", profile: "personal", createdAt: 101, completedAt: 101 }
    ];
    fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(dataDir, "todos-archive.json"), JSON.stringify({ version: 1, archived }, null, 2), "utf8");

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Plugin.BarWidget { id: barWidget }
    }

    // Restore IMMEDIATELY after startup, inside the old race window.
    Timer { interval: 500; running: true; onTriggered: barWidget.unarchiveTask(100) }
    Timer { interval: 2600; running: true; onTriggered: barWidget.unarchiveTask(100) }
    Timer { interval: 4600; running: true; onTriggered: barWidget.purgeArchivedTask(101) }
    Timer {
        interval: 7000; running: true
        onTriggered: { console.log("[SAFE] done=1"); Qt.exit(0) }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 30000,
      env: { ...process.env, HOME: tmpDir, ARDOISE_DATA_DIR: dataDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");
    assert.ok(/\[SAFE\] done=1/.test(output), "archive-safety harness did not run to completion:\n" + output);
    assert.ok(!/Binding loop detected|ReferenceError|is not a type|TypeError|Cannot read property/i.test(output), "harness reported QML errors:\n" + output);

    // Assert the ON-DISK result.
    const active = JSON.parse(fs.readFileSync(path.join(dataDir, "todos.json"), "utf8"));
    const archive = JSON.parse(fs.readFileSync(path.join(dataDir, "todos-archive.json"), "utf8"));
    const activeIds = active.todos.map((x: any) => x.id);
    const archivedIds = archive.archived.map((x: any) => x.id);
    const count = (arr: number[], id: number) => arr.filter((x) => x === id).length;

    // Restored task: exactly once in active, gone from the archive.
    assert.equal(count(activeIds, 100), 1, "restored task must appear exactly once in the active store (ids " + activeIds + ")");
    assert.equal(count(archivedIds, 100), 0, "restored task must leave the archive (ids " + archivedIds + ")");
    // Duplicate healed: only in active, not the archive.
    assert.equal(count(activeIds, 2), 1, "duplicate id must appear once in active (ids " + activeIds + ")");
    assert.equal(count(archivedIds, 2), 0, "duplicate id must be reconciled out of the archive (ids " + archivedIds + ")");
    // Untouched task survives.
    assert.equal(count(activeIds, 1), 1, "unrelated active task must survive (ids " + activeIds + ")");
    // Purged task: gone from the archive and never added to active.
    assert.equal(count(archivedIds, 101), 0, "purged task must leave the archive (ids " + archivedIds + ")");
    assert.equal(count(activeIds, 101), 0, "purged task must not appear in the active store (ids " + activeIds + ")");
    // No unexpected survivors in the archive.
    assert.equal(archivedIds.length, 0, "archive should be empty after reconcile/restore/purge (ids " + archivedIds + ")");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell ContextActionMenu Hold [local-only]: charge confirms, early release cancels", (t) => {
  // LOCAL-ONLY (mounts a window). Exercises the menu-level hold state machine
  // directly: a hold item must charge over holdDuration and only fire
  // itemActivated on completion; releasing early must cancel.
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display");
    return;
  }
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) throw new Error("Omarchy shell Commons/Ui modules must be provided in CI");
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-menu-hold-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const harnessQml = `
import QtQuick
import Quickshell
import qs.Commons
import "plugin/ui" as ArdoiseUi

ShellRoot {
    id: root

    property int activated: 0
    property string activatedId: ""

    Item {
        id: host
        width: 400
        height: 400

        ArdoiseUi.ContextActionMenu {
            id: menu
            anchors.fill: parent
            isOpen: true
            selectedIndex: 1
            items: [
                { id: "copy", icon: "󰆏", label: "Copy", shortcut: "y", desc: "" },
                { id: "del", icon: "󰅙", label: "Delete", shortcut: "hold x", desc: "", hold: true }
            ]
        }

        Connections {
            target: menu
            function onItemActivated(actionId) { root.activated++; root.activatedId = actionId }
        }
    }

    Timer {
        interval: 300; running: true
        onTriggered: {
            menu.startSelectedHold()
            console.log("[HOLD] start prog=" + menu.holdProgress.toFixed(2))
        }
    }
    Timer {
        interval: 650; running: true
        onTriggered: {
            console.log("[HOLD] mid prog=" + menu.holdProgress.toFixed(2))
            menu.stopHold()
        }
    }
    Timer {
        interval: 1100; running: true
        onTriggered: console.log("[HOLD] cancelled prog=" + menu.holdProgress.toFixed(2) + " activated=" + root.activated)
    }
    Timer {
        interval: 1400; running: true
        onTriggered: menu.startSelectedHold()
    }
    Timer {
        interval: 2300; running: true
        onTriggered: {
            console.log("[HOLD] done prog=" + menu.holdProgress.toFixed(2) + " activated=" + root.activated + " id=" + root.activatedId)
            console.log("[HOLD] complete=1")
            Qt.exit(0)
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 20000,
      env: { ...process.env, HOME: tmpDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    assert.ok(/\[HOLD\] complete=1/.test(output), "hold harness did not complete:\n" + output);
    assert.ok(
      !/Binding loop detected|ReferenceError|is not a type|TypeError|Cannot read property/i.test(output),
      "hold harness reported QML errors:\n" + output
    );
    const mid = Number(new RegExp("\\[HOLD\\] mid prog=([\\d.]+)").exec(output)?.[1]);
    assert.ok(mid > 0 && mid < 1, "a held item must charge over time (mid progress " + mid + "):\n" + output);
    assert.ok(/\[HOLD\] cancelled prog=[\d.]+ activated=0/.test(output), "releasing early must cancel without activating:\n" + output);
    assert.ok(/\[HOLD\] done prog=0\.00 activated=1 id=del/.test(output), "holding to completion must activate the hold item:\n" + output);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell ArchiveModal Lifecycle [local-only]: opening synchronizes, acquires focus, and closes via Escape without QML errors", (t) => {
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display");
    return;
  }
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) throw new Error("Omarchy shell Commons/Ui modules must be provided in CI");
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-archive-open-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    const store = { version: 1, activeProfile: "personal", profiles: ["personal"], todos: [] };
    const archived = [
      { id: 101, title: "Test archive item 1", profile: "personal", createdAt: 100, completedAt: 100 },
      { id: 102, title: "Test archive item 2", profile: "personal", createdAt: 200, completedAt: 200 }
    ];
    fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(dataDir, "todos-archive.json"), JSON.stringify({ version: 1, archived }, null, 2), "utf8");

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Plugin.BarWidget { id: barWidget }
    }

    QtObject {
        id: fakeBarObj
        property string position: "top"
        property color foreground: "#ffffff"
        property string fontFamily: "sans-serif"
        function run(cmd) {}
    }

    PanelWindow {
        id: panelWindow
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        PanelKeyCatcher {
            anchors.fill: parent
            blocked: panelContent.activeFocusBlocked
            Plugin.PanelContent {
                id: panelContent
                anchors.fill: parent
                bar: fakeBarObj
                barWidget: barWidget
            }
        }
    }

    Timer {
        interval: 400; running: true
        onTriggered: {
            // Open through footer / keyboard action
            panelContent.openArchiveModal()
            console.log("[LIFECYCLE] opened=" + (panelContent.showArchiveModal ? 1 : 0))
            console.log("[LIFECYCLE] modalOpen=" + (panelContent.archiveModal.isOpen ? 1 : 0))
            console.log("[LIFECYCLE] blocked=" + (panelContent.activeFocusBlocked ? 1 : 0))
        }
    }

    Timer {
        interval: 1000; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            console.log("[LIFECYCLE] count=" + modal.filteredArchived.length)
            // Dismiss via handleKey escape
            modal.handleKey({ key: Qt.Key_Escape, text: "", modifiers: 0, accepted: false })
            console.log("[LIFECYCLE] closed=" + (!panelContent.showArchiveModal ? 1 : 0))
            console.log("[LIFECYCLE] done=1")
            Qt.exit(0)
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 20000,
      env: { ...process.env, HOME: tmpDir, ARDOISE_DATA_DIR: dataDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    assert.ok(/\[LIFECYCLE\] done=1/.test(output), "archive lifecycle harness did not complete:\n" + output);
    assert.ok(
      !/Binding loop detected|ReferenceError|is not a type|TypeError|Cannot read property/i.test(output),
      "harness reported QML errors:\n" + output
    );
    assert.ok(/\[LIFECYCLE\] opened=1/.test(output), "openArchiveModal must set showArchiveModal=true:\n" + output);
    assert.ok(/\[LIFECYCLE\] modalOpen=1/.test(output), "archiveModal must have isOpen=true:\n" + output);
    assert.ok(/\[LIFECYCLE\] blocked=1/.test(output), "activeFocusBlocked must be true while archive modal is open:\n" + output);
    assert.ok(/\[LIFECYCLE\] count=2/.test(output), "archived tasks must be loaded:\n" + output);
    assert.ok(/\[LIFECYCLE\] closed=1/.test(output), "Escape must close archive modal:\n" + output);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell Restored Task Cycle [local-only]: unarchive synchronizes store, toggle done, clear completed moves back to archive without vanishing", (t) => {
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display");
    return;
  }
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) throw new Error("Omarchy shell Commons/Ui modules must be provided in CI");
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-restore-cycle-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    const store = { version: 1, activeProfile: "personal", profiles: ["personal"], todos: [] };
    const archived = [
      { id: 500, title: "Cycle task", description: "notes", profile: "personal", createdAt: 100, completedAt: 100 }
    ];
    fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(dataDir, "todos-archive.json"), JSON.stringify({ version: 1, archived }, null, 2), "utf8");

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Plugin.BarWidget { id: barWidget }
    }

    Timer {
        interval: 600; running: true
        onTriggered: {
            // Restore from archive
            barWidget.unarchiveTask(500)
        }
    }

    Timer {
        interval: 1800; running: true
        onTriggered: {
            var inMemHas500 = barWidget.store && barWidget.store.todos && barWidget.store.todos.some(function(t) { return t.id === 500 })
            console.log("[CYCLE] inMemHas500=" + (inMemHas500 ? 1 : 0))
            // Toggle to done
            barWidget.toggleTodo(500)
            var isDone = barWidget.store && barWidget.store.todos && barWidget.store.todos.some(function(t) { return t.id === 500 && t.done })
            console.log("[CYCLE] isDone=" + (isDone ? 1 : 0))
        }
    }

    Timer {
        interval: 2800; running: true
        onTriggered: {
            // Clear completed
            barWidget.clearCompleted("personal")
            var inMemActiveCount = barWidget.store ? barWidget.store.todos.length : -1
            console.log("[CYCLE] inMemActiveCount=" + inMemActiveCount)
        }
    }

    Timer {
        interval: 4000; running: true
        onTriggered: {
            console.log("[CYCLE] done=1")
            Qt.exit(0)
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 25000,
      env: { ...process.env, HOME: tmpDir, ARDOISE_DATA_DIR: dataDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    assert.ok(/\[CYCLE\] done=1/.test(output), "restore-cycle harness did not complete:\n" + output);
    assert.ok(/\[CYCLE\] inMemHas500=1/.test(output), "unarchiveTask must update barWidget.store in memory:\n" + output);
    assert.ok(/\[CYCLE\] isDone=1/.test(output), "restored task must be toggleable in memory:\n" + output);
    assert.ok(/\[CYCLE\] inMemActiveCount=0/.test(output), "clearCompleted must clear task from active store:\n" + output);

    const active = JSON.parse(fs.readFileSync(path.join(dataDir, "todos.json"), "utf8"));
    const archive = JSON.parse(fs.readFileSync(path.join(dataDir, "todos-archive.json"), "utf8"));
    const activeIds = active.todos.map((x: any) => x.id);
    const archivedIds = archive.archived.map((x: any) => x.id);

    assert.ok(!activeIds.includes(500), "task 500 must not be in active store after clearCompleted");
    assert.ok(archivedIds.includes(500), "task 500 MUST be preserved in archive and not vanish!");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell ArchiveModal Hold Delete [local-only]: holding x with auto-repeat typematic events completes purge and deletes from disk", (t) => {
  if (process.env.CI) {
    t.skip("local-only: needs a wlr-layer-shell compositor");
    return;
  }
  if (!process.env.WAYLAND_DISPLAY) {
    t.skip("local-only: no Wayland display");
    return;
  }
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    t.skip("quickshell binary not found on system PATH");
    return;
  }
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) throw new Error("Omarchy shell Commons/Ui modules must be provided in CI");
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-archive-hold-delete-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(dataDir, { recursive: true });

    const store = { version: 1, activeProfile: "personal", profiles: ["personal"], todos: [] };
    const archived = [
      { id: 700, title: "Purge me with hold", profile: "personal", createdAt: 100, completedAt: 100 }
    ];
    fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(dataDir, "todos-archive.json"), JSON.stringify({ version: 1, archived }, null, 2), "utf8");

    const harnessQml = `
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
    id: root

    PanelWindow {
        id: fakeBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay

        Plugin.BarWidget { id: barWidget }
    }

    QtObject {
        id: fakeBarObj
        property string position: "top"
        property color foreground: "#ffffff"
        property string fontFamily: "sans-serif"
        function run(cmd) {}
    }

    PanelWindow {
        id: panelWindow
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        PanelKeyCatcher {
            anchors.fill: parent
            blocked: panelContent.activeFocusBlocked
            Plugin.PanelContent {
                id: panelContent
                anchors.fill: parent
                bar: fakeBarObj
                barWidget: barWidget
            }
        }
    }

    property int repeatTicks: 0

    Timer {
        id: repeatTimer
        interval: 80
        repeat: true
        running: false
        onTriggered: {
            var modal = panelContent.archiveModal
            root.repeatTicks++
            // Simulate OS typematic repeat: KeyRelease(isAutoRepeat: true) followed by KeyPress(isAutoRepeat: true)
            modal.Keys.onReleased({ key: Qt.Key_X, text: "x", modifiers: 0, accepted: false, isAutoRepeat: true })
            modal.handleKey({ key: Qt.Key_X, text: "x", modifiers: 0, accepted: false, isAutoRepeat: true })
            if (root.repeatTicks >= 14) {
                repeatTimer.stop()
            }
        }
    }

    Timer {
        interval: 400; running: true
        onTriggered: {
            panelContent.openArchiveModal()
            console.log("[PURGE] modalOpen=" + (panelContent.archiveModal.isOpen ? 1 : 0))
        }
    }

    Timer {
        interval: 800; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            console.log("[PURGE] initialCount=" + modal.filteredArchived.length)
            // Initial key press (start charge)
            modal.handleKey({ key: Qt.Key_X, text: "x", modifiers: 0, accepted: false, isAutoRepeat: false })
            repeatTimer.start()
        }
    }

    Timer {
        interval: 2400; running: true
        onTriggered: {
            var modal = panelContent.archiveModal
            // After 800ms hold charge completes, task 700 should be purged
            console.log("[PURGE] remainingCount=" + modal.filteredArchived.length)
            console.log("[PURGE] done=1")
            Qt.exit(0)
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 25000,
      env: { ...process.env, HOME: tmpDir, ARDOISE_DATA_DIR: dataDir }
    });
    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    assert.ok(/\[PURGE\] done=1/.test(output), "archive hold delete harness did not complete:\n" + output);
    assert.ok(/\[PURGE\] initialCount=1/.test(output), "archive modal must initially show 1 item:\n" + output);
    assert.ok(/\[PURGE\] remainingCount=0/.test(output), "holding x with auto-repeat must permanently purge task from UI list:\n" + output);

    const archive = JSON.parse(fs.readFileSync(path.join(dataDir, "todos-archive.json"), "utf8"));
    const archivedIds = archive.archived.map((x: any) => x.id);
    assert.ok(!archivedIds.includes(700), "task 700 must be permanently deleted from todos-archive.json on disk");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
