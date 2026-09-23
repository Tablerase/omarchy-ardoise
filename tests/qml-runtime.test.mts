import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execSync, spawnSync } from "node:child_process";

const repoDir = path.resolve(import.meta.dirname, "..");

test("Static QML Analysis: All QQC2 and custom UI components have required imports", () => {
  const qmlFiles = fs
    .readdirSync(repoDir)
    .filter((f) => f.endsWith(".qml"))
    .map((f) => path.join(repoDir, f));

  assert.ok(qmlFiles.length >= 4, "Found core QML files in repository");

  const qqc2Controls = [
    "ToolTip",
    "TextArea",
    "TextField",
    "ScrollView",
    "Button",
    "RoundButton",
    "Popup",
    "Dialog",
    "SpinBox",
    "ComboBox",
    "ProgressBar",
    "Slider",
    "Switch",
    "TabBar",
    "TabButton"
  ];

  for (const file of qmlFiles) {
    const filename = path.basename(file);
    const content = fs.readFileSync(file, "utf8");

    // Remove single-line and multi-line comments for syntax checking
    const stripped = content
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/\/\/.*$/gm, "");

    // Check QQC2 controls: if used as a QML type declaration (e.g. `ToolTip {` or `TextArea {`),
    // the file MUST import QtQuick.Controls
    for (const ctrl of qqc2Controls) {
      const typeDeclRegex = new RegExp(`\\b${ctrl}\\s*\\{`, "g");
      if (typeDeclRegex.test(stripped)) {
        const hasControlsImport = /import\s+QtQuick\.Controls\b/.test(stripped);
        assert.ok(
          hasControlsImport,
          `File ${filename} uses '${ctrl}' but is missing 'import QtQuick.Controls'`
        );
      }
    }

    // Naked ToolTip check: Omarchy plugins should use PanelToolTip instead of raw ToolTip
    // unless explicitly needed. But if ToolTip is declared, it must have import QtQuick.Controls.
    const nakedToolTip = /\bToolTip\s*\{/.test(stripped);
    if (nakedToolTip) {
      assert.ok(
        /import\s+QtQuick\.Controls\b/.test(stripped),
        `File ${filename} uses bare 'ToolTip' without 'import QtQuick.Controls'`
      );
    }

    // Check qs.Commons usage: Color.*, Style.*, Border.* require import qs.Commons
    if (/\b(Color|Style|Border)\.[a-zA-Z0-9_]/.test(stripped)) {
      assert.ok(
        /import\s+qs\.Commons\b/.test(stripped),
        `File ${filename} uses Color/Style/Border but is missing 'import qs.Commons'`
      );
    }

    // Check qs.Ui usage: PanelToolTip, PanelActionButton, etc. require import qs.Ui
    if (/\b(PanelToolTip|PanelActionButton|PanelSectionHeader|KeyboardPanel|PanelKeyCatcher)\s*\{/.test(stripped)) {
      assert.ok(
        /import\s+qs\.Ui\b/.test(stripped),
        `File ${filename} uses Omarchy Ui components but is missing 'import qs.Ui'`
      );
    }
  }
});

test("UI Ergonomics & Shortcuts Integrity: Action buttons focus, help Backspace dismiss, and GitHub brand link", () => {
  const quickAddContent = fs.readFileSync(path.join(repoDir, "QuickAdd.qml"), "utf8");
  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");

  // 1. QuickAdd action buttons: Add button must NOT have hardcoded 'selected: true',
  // and both buttons must link 'selected' and 'hasCursor' to the active actionIndex.
  const actionButtonsStart = quickAddContent.indexOf("id: actionButtons");
  assert.ok(actionButtonsStart !== -1, "Found actionButtons row in QuickAdd.qml");
  const actionButtonsCode = quickAddContent.slice(actionButtonsStart);
  assert.ok(
    !/selected:\s*true\b/.test(actionButtonsCode),
    "QuickAdd action buttons must not have hardcoded selected: true"
  );
  assert.ok(
    quickAddContent.includes('selected: (root.focusSection === "actions") && (root.actionIndex === 0)'),
    "cancelBtn must bind selected state to actionIndex === 0"
  );
  assert.ok(
    quickAddContent.includes('selected: (root.focusSection === "actions") && (root.actionIndex === 1)'),
    "addBtn must bind selected state to actionIndex === 1"
  );

  // 2. Help search & shortcuts: Backspace on empty text dismisses modal
  assert.ok(
    panelContent.includes("event.key === Qt.Key_Backspace && keySearchField.text.length === 0"),
    "keySearchField must handle Backspace when empty to dismiss help modal"
  );
  assert.ok(
    !panelContent.includes('"i / a / /"'),
    "keybindingsList must avoid ambiguous 'i / a / /' notation"
  );
  assert.ok(
    panelContent.includes('"i / a / <slash>"'),
    "keybindingsList must use unambiguous 'i / a / <slash>' key entry"
  );
  assert.ok(
    panelContent.includes("root.detectedShortcut"),
    "keybindingsList must include the detected desktop shortcut"
  );

  // 3. Panel header brand logo linking to GitHub repo
  assert.ok(
    panelContent.includes("https://github.com/Tablerase/omarchy-ardoise"),
    "Panel header brand link must point to Tablerase/omarchy-ardoise"
  );
  assert.ok(
    panelContent.includes("InboxIcon") && panelContent.includes("id: brandRow"),
    "Panel header must feature InboxIcon brand logo beside the Ardoise title"
  );

  // 4. Codebase & Multi-Repo Context
  assert.ok(
    quickAddContent.includes("id: detectContextProc"),
    "QuickAdd must feature detectContextProc for Hyprland CWD auto-detection"
  );
  assert.ok(
    quickAddContent.includes("TodoStore.addTodo(root.store, rawText, desc, root.selectedProfile, rem, loc)"),
    "QuickAdd submit must pass location context to TodoStore.addTodo"
  );
  assert.ok(
    panelContent.includes("id: repoBadge"),
    "PanelContent must display repoBadge for multi-repo task identification"
  );
  assert.ok(
    panelContent.includes("id: openLocBtn") && panelContent.includes("Codebase"),
    "PanelContent must display openLocBtn to launch editor directly in target codebase"
  );
});

test("Quickshell Headless Lifecycle: QuickAdd, PanelContent, BarWidget, and Service instantiate and toggle without errors", (t) => {
  // Check if quickshell is installed and accessible
  let quickshellPath = "";
  try {
    quickshellPath = execSync("which quickshell 2>/dev/null", { encoding: "utf8" }).trim();
  } catch {
    t.skip("quickshell binary not found on system PATH; skipping runtime instantiation test");
    return;
  }

  // Check if Omarchy shell assets exist
  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");

  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
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

            console.log("[TEST] Testing PanelContent Vim motions & navigation...");
            panelContent.focusSection = "tasks";
            panelContent.handleMove(0, 1);
            if (panelContent.cursorIndex < 0) {
                console.error("[TEST FAIL] handleMove failed to update cursorIndex");
                Qt.exit(106);
                return;
            }
            panelContent.handleReturn();
            panelContent.handleActivate();
            panelContent.handleTab(1);
            if (panelContent.focusSection !== "footer") {
                console.error("[TEST FAIL] handleTab failed to switch section to footer");
                Qt.exit(107);
                return;
            }
            panelContent.handleTab(-1);
            if (panelContent.focusSection !== "tasks") {
                console.error("[TEST FAIL] handleTab failed to switch section back to tasks");
                Qt.exit(108);
                return;
            }

            // Test Help Overlay toggle via '?' key
            panelContent.handleTextKey("?");
            if (!panelContent.showKeyHelp) {
                console.error("[TEST FAIL] handleTextKey('?') failed to open showKeyHelp");
                Qt.exit(109);
                return;
            }
            panelContent.handleTextKey("?");
            if (panelContent.showKeyHelp) {
                console.error("[TEST FAIL] handleTextKey('?') failed to close showKeyHelp");
                Qt.exit(110);
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
            panelContent.handleTextKey("c");

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
                if (panelContent.expandedTaskId !== testTask.id) {
                    console.error("[TEST FAIL] handleMove collapsed task that was expandedViaKeyboard");
                    Qt.exit(121);
                    return;
                }
                // Return cursor and collapse back
                panelContent.cursorIndex = 0;
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
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "profiles") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) failed to move to profiles");
                Qt.exit(116);
                return;
            }
            quickAdd.cycleProfileSelection(1);
            quickAdd.advanceSection(1);
            if (quickAdd.focusSection !== "actions") {
                console.error("[TEST FAIL] quickAdd.advanceSection(1) failed to move to actions");
                Qt.exit(117);
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

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 6000,
      env: {
        ...process.env,
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
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Live Shell IPC: Omarchy shell responds to summon, hide, and toggle", (t) => {
  // Check if omarchy-shell is installed
  try {
    execSync("which omarchy-shell 2>/dev/null", { encoding: "utf8" });
  } catch {
    t.skip("omarchy-shell binary not found; skipping live shell IPC test");
    return;
  }

  // Ping running shell
  try {
    const ping = execSync("omarchy-shell shell ping 2>/dev/null", { encoding: "utf8" }).trim();
    if (ping !== "ok") {
      t.skip("Omarchy shell is not actively responding to ping; skipping live shell IPC test");
      return;
    }
  } catch {
    t.skip("Omarchy shell is not currently running; skipping live shell IPC test");
    return;
  }

  // Verify summon
  const summonResult = execSync("omarchy-shell shell summon tablerase.ardoise '{}'", {
    encoding: "utf8"
  }).trim();
  assert.equal(summonResult, "ok", "Shell summon tablerase.ardoise should return 'ok'");

  // Verify hide
  execSync("omarchy-shell shell hide tablerase.ardoise", { encoding: "utf8" });

  // Verify toggle (opens then closes)
  execSync("omarchy-shell shell toggle tablerase.ardoise '{}'", { encoding: "utf8" });
  execSync("omarchy-shell shell hide tablerase.ardoise", { encoding: "utf8" });
});
