import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execSync, spawnSync } from "node:child_process";

const repoDir = path.resolve(import.meta.dirname, "..");

test("Static QML Analysis: All QQC2 and custom UI components have required imports", () => {
  const rootFiles = fs
    .readdirSync(repoDir)
    .filter((f) => f.endsWith(".qml"))
    .map((f) => path.join(repoDir, f));
  const uiSubDir = path.join(repoDir, "ui");
  const uiFiles = fs.existsSync(uiSubDir)
    ? fs.readdirSync(uiSubDir).filter((f) => f.endsWith(".qml")).map((f) => path.join(uiSubDir, f))
    : [];
  const qmlFiles = [...rootFiles, ...uiFiles];

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
  const panelLogicContent = fs.readFileSync(path.join(repoDir, "PanelLogic.js"), "utf8");
  const panelQmlContent = fs.readFileSync(path.join(repoDir, "Panel.qml"), "utf8");
  const taskNotesAreaContent = fs.readFileSync(path.join(repoDir, "TaskNotesArea.qml"), "utf8");
  const uiSubDir = path.join(repoDir, "ui");
  const uiFilesContent = fs.existsSync(uiSubDir)
    ? fs.readdirSync(uiSubDir).filter((f) => f.endsWith(".qml")).map((f) => fs.readFileSync(path.join(uiSubDir, f), "utf8")).join("\n")
    : "";
  const allUiContent = panelContent + "\n" + uiFilesContent;

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

  // 1b. Title validation & disabled state when title is missing
  assert.ok(
    quickAddContent.includes("readonly property bool hasValidTitle:") &&
      quickAddContent.includes("readonly property bool canSubmit: hasValidTitle"),
    "QuickAdd must declare hasValidTitle and canSubmit properties"
  );
  assert.ok(
    quickAddContent.includes("enabled: root.canSubmit") &&
      quickAddContent.includes("opacity: root.canSubmit ? 1.0 : 0.4"),
    "addBtn must visibly disable with opacity 0.4 when title is missing"
  );
  assert.ok(
    quickAddContent.includes("id: titleErrorRow") &&
      quickAddContent.includes("visible: root.showTitleError || (taskInput.text.trim().length > 0 && !root.hasValidTitle)"),
    "QuickAdd must display inline titleErrorRow cue when title is missing"
  );
  assert.ok(
    quickAddContent.includes("if (!root.canSubmit)") &&
      quickAddContent.includes("root.showTitleError = true"),
    "QuickAdd submit must block execution and focus title field when canSubmit is false"
  );
  assert.ok(
    panelContent.includes("var parsed = TodoStore.parseTaskInput(text)") &&
      panelContent.includes("if (parsed.title && parsed.title.trim().length > 0)"),
    "PanelContent onAccepted must validate parsed title before adding"
  );

  // 2. Help search & shortcuts: Backspace on empty text dismisses modal
  assert.ok(
    allUiContent.includes("event.key === Qt.Key_Backspace && keySearchField.text.length === 0"),
    "keySearchField must handle Backspace when empty to dismiss help modal"
  );
  assert.ok(
    allUiContent.includes('keySearchField.text.trim().length === 0'),
    "keySearchField must implement two-stage escape checking for empty text"
  );
  assert.ok(
    allUiContent.includes('readonly property bool isNavFocused: (root.focusSection === "search") && !keySearchField.activeFocus'),
    "keySearchField BorderSurface must reflect navigation focus when blurred in search section"
  );
  assert.ok(
    !panelLogicContent.includes('"i / a / /"'),
    "keybindingsList must avoid ambiguous 'i / a / /' notation"
  );
  assert.ok(
    panelLogicContent.includes('"i / a / <slash>"'),
    "keybindingsList must use unambiguous 'i / a / <slash>' key entry"
  );
  assert.ok(
    panelContent.includes("root.detectedPanelShortcut") || panelContent.includes("root.detectedShortcut"),
    "keybindingsList must include the detected desktop shortcut"
  );

  // 3. Panel header brand logo linking to GitHub repo
  assert.ok(
    panelContent.includes("https://github.com/Tablerase/omarchy-ardoise"),
    "Panel header brand link must point to Tablerase/omarchy-ardoise"
  );
  assert.ok(
    panelContent.includes("ArdoiseIcon") && panelContent.includes("id: brandRow"),
    "Panel header must feature the ArdoiseIcon brand mark beside the Ardoise title"
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
  assert.ok(
    quickAddContent.includes('if (Boolean(root.detectedContext && root.attachLocation)) secs.push("location")'),
    "QuickAdd must include location in getActiveSections when location is detected and attached"
  );
  assert.ok(
    quickAddContent.includes('if (root.focusSection === "location")') &&
      quickAddContent.includes("root.attachLocation = false"),
    "QuickAdd must allow detaching location via x/Del/Backspace/Enter key navigation"
  );
  assert.ok(
    quickAddContent.includes("id: locationPill") &&
      quickAddContent.includes('(root.focusSection === "location")'),
    "QuickAdd location pill must display focus styling when active"
  );
  assert.ok(
    panelContent.includes("id: itemHeaderCol") && panelContent.includes("id: chipsRow"),
    "PanelContent must feature a two-line layout separating title and chips when badges are present"
  );
  assert.ok(
    panelContent.includes("cleanRepoName") &&
      panelContent.includes("root.cleanRepoName(itemRow.modelData.repo)"),
    "PanelContent must format repo chip to strip repo owner for display without modifying location"
  );
  assert.ok(
    panelContent.includes("id: profReassignContainer") &&
      panelContent.includes("id: profReassignFlickable"),
    "PanelContent must feature a compact horizontal scrollable profile reassignment bar in expanded view"
  );
  assert.ok(
    panelContent.includes('property string expandedSubSection: "header"') &&
      panelContent.includes("root.expandedSubSection === "),
    "PanelContent must support navigable sub-sections in expanded tasks (notes, reminders, profiles, codebase)"
  );
  assert.ok(
    panelQmlContent.includes("panelContent.handleEscape && panelContent.handleEscape()"),
    "Panel.qml must delegate escape handling to panelContent.handleEscape for two-stage escape"
  );
  assert.ok(
    taskNotesAreaContent.includes("property bool isNavFocused: false") &&
      taskNotesAreaContent.includes("textArea.activeFocus") &&
      taskNotesAreaContent.includes("root.isNavFocused"),
    "TaskNotesArea must support isNavFocused for differentiated nav (1px) vs insert (2px) focus border"
  );
  assert.ok(
    panelContent.includes("function focusNotesEditor()") &&
      (panelContent + panelLogicContent).includes("root.focusNotesEditor()"),
    "PanelContent must provide robust focusNotesEditor helper for notes navigation"
  );
  assert.ok(
    allUiContent.includes("function ensureVisible(idx)") &&
      panelContent.includes("itemRow.ensureReassignProfileVisible"),
    "profReassignFlickable must support ensureVisible auto-scrolling on profile navigation"
  );

  // 4b. Task Completion Satisfaction & Dedicated Completed Fold
  const taskCheckContent = fs.readFileSync(path.join(repoDir, "ui", "TaskCheck.qml"), "utf8");
  assert.ok(
    taskCheckContent.includes("id: popAnimation") &&
      taskCheckContent.includes("SequentialAnimation") &&
      taskCheckContent.includes("Easing.OutBack"),
    "TaskCheck must feature bouncy pop scale animation on completion toggle"
  );
  assert.ok(
    panelContent.includes("id: strikeLine") &&
      panelContent.includes("Behavior on width") &&
      panelContent.includes("Math.min(titleLabel.contentWidth, titleLabel.width)"),
    "PanelContent must feature left-to-right animated strikethrough line across title"
  );
  assert.ok(
    panelContent.includes("pendingCompletionIds") &&
      panelContent.includes("completionGraceTimer") &&
      panelContent.includes("slideStartTimer") &&
      panelContent.includes("slidingOutTaskIds") &&
      panelContent.includes("flushPendingCompletions"),
    "PanelContent must implement 600ms grace period, slideStartTimer, and pending completion dwell state"
  );
  assert.ok(
    panelContent.includes("id: rowSlideTranslate") &&
      panelContent.includes("id: justCompletedAnim") &&
      panelContent.includes("justCompletedTaskIds"),
    "PanelContent must animate completed items sliding down into the completed fold"
  );
  assert.ok(
    panelContent.includes("id: completedHeader") &&
      panelContent.includes("id: foldPill") &&
      panelContent.includes("completedFoldOpen"),
    "PanelContent must feature dedicated completed fold divider and toggle pill"
  );

  // 4c. Synchronized Row Expansion & Fluid Motion
  assert.ok(
    panelContent.includes("enabled: delegateRoot.isSlidingOut || delegateRoot.isHiddenByFold"),
    "delegateRoot Behavior on implicitHeight must be disabled during expand/collapse to prevent double-animation lag"
  );
  assert.ok(
    panelContent.includes("id: itemRowHeightAnim") &&
      panelContent.includes("clip: (itemRowHeightAnim && itemRowHeightAnim.running) || delegateRoot.isSlidingOut"),
    "itemRow must strictly clip during height animation to avoid content rendering over adjacent items"
  );
  assert.ok(
    panelContent.includes("id: expandedDetailsCol") &&
      panelContent.includes("Behavior on opacity"),
    "expandedDetailsCol must smoothly fade in with opacity transition"
  );

  // 4d. Inline Task Title Editing
  assert.ok(
    panelContent.includes("id: titleEditor") &&
      panelContent.includes("id: rowEditBtn") &&
      panelContent.includes("id: titleClickArea") &&
      panelContent.includes("property var editingTaskId: -1") &&
      panelContent.includes("startEditingTask(") &&
      panelContent.includes("commitEditingTask(") &&
      panelContent.includes("cancelEditingTask("),
    "PanelContent must implement inline title editor (titleEditor, rowEditBtn, titleClickArea, and editingTaskId state)"
  );

  // 4d. Dynamic Reminder Presets (Real-time recalculation)
  assert.ok(
    quickAddContent.includes("refreshReminderPresets") &&
      quickAddContent.includes("TodoStore.computePresetReminder"),
    "QuickAdd must support dynamic reminder preset refreshing and computePresetReminder"
  );
  assert.ok(
    panelContent.includes("refreshReminderPresets") &&
      panelContent.includes("TodoStore.computePresetReminder"),
    "PanelContent must refresh reminder presets dynamically and use computePresetReminder"
  );

  const barWidgetContent = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  assert.ok(
    barWidgetContent.includes('target: "tablerase.ardoise"') &&
      barWidgetContent.includes("function toggleTodo(") &&
      barWidgetContent.includes("function update(") &&
      barWidgetContent.includes("function remove(") &&
      barWidgetContent.includes("function gitHistory(") &&
      barWidgetContent.includes("function gitRollback(") &&
      barWidgetContent.includes("function gitRecover(") &&
      barWidgetContent.includes("function gitSync(") &&
      barWidgetContent.includes("function gitSetRemote("),
    "BarWidget must declare IpcHandler with target 'tablerase.ardoise' and Git snapshot/sync methods"
  );
  assert.ok(
    panelContent.includes("id: gitBtn") &&
      panelContent.includes("id: gitModal") &&
      panelContent.includes("id: helpModal") &&
      panelContent.includes("property bool showGitModal"),
    "PanelContent must implement Git button, GitModal, HelpModal, and showGitModal state"
  );

  // 5. Multi-Engine Context Detection Tool (Prioritizing VS Code)
  const detectScript = path.join(repoDir, "tools", "detect-context.sh");
  assert.ok(fs.existsSync(detectScript), "tools/detect-context.sh must exist");
  const detectScriptSource = fs.readFileSync(detectScript, "utf8");
  assert.ok(
    detectScriptSource.includes("get_vscode_dir") && detectScriptSource.includes("storage.json"),
    "detect-context.sh must inspect VS Code/Cursor/VSCodium storage.json"
  );
  assert.ok(
    detectScriptSource.includes("Priority 0: Default Editor in Omarchy") &&
      detectScriptSource.indexOf("Priority 0: Default Editor") < detectScriptSource.indexOf("Priority 1: VS Code"),
    "Omarchy default editor (Priority 0) must precede Priority 1 (VS Code)"
  );
  try {
    const detectOutput = execSync(`"${detectScript}"`, { encoding: "utf8" }).trim();
    assert.doesNotThrow(() => {
      const parsed = JSON.parse(detectOutput);
      assert.ok(parsed === null || typeof parsed === "object", "Output must be null or JSON object");
    }, "detect-context.sh output must be valid JSON");
  } catch (e: any) {
    if (e?.name === "NotCapable" || String(e).includes("Requires env access")) {
      // Deno test without --allow-env
    } else {
      throw e;
    }
  }
});

test("UI Tooltip Badges & Shortcut Parity: KeyBadge and ShortcutToolTip components render keyboard badges with consistent styling across buttons and help modal", () => {
  const keyBadgePath = path.join(repoDir, "ui", "KeyBadge.qml");
  const shortcutToolTipPath = path.join(repoDir, "ui", "ShortcutToolTip.qml");
  const helpModalPath = path.join(repoDir, "ui", "HelpModal.qml");
  const panelContentPath = path.join(repoDir, "PanelContent.qml");

  assert.ok(fs.existsSync(keyBadgePath), "ui/KeyBadge.qml must exist");
  assert.ok(fs.existsSync(shortcutToolTipPath), "ui/ShortcutToolTip.qml must exist");

  const keyBadgeContent = fs.readFileSync(keyBadgePath, "utf8");
  const shortcutToolTipContent = fs.readFileSync(shortcutToolTipPath, "utf8");
  const helpModalContent = fs.readFileSync(helpModalPath, "utf8");
  const panelContent = fs.readFileSync(panelContentPath, "utf8");

  // 1. KeyBadge styling invariants
  assert.ok(keyBadgeContent.includes('property string keyText: ""'), "KeyBadge must have keyText property");
  assert.ok(keyBadgeContent.includes('property color badgeColor: Color.accent'), "KeyBadge must default badgeColor to Color.accent");
  assert.ok(keyBadgeContent.includes('font.family: "monospace"'), "KeyBadge must use monospace font");

  // 2. ShortcutToolTip multi-key and styling invariants
  assert.ok(shortcutToolTipContent.includes("KeyBadge {"), "ShortcutToolTip must instantiate KeyBadge component");
  assert.ok(shortcutToolTipContent.includes('split(" / ")'), "ShortcutToolTip must split multiple key combinations for badges");
  assert.ok(shortcutToolTipContent.includes("BorderSurface {"), "ShortcutToolTip background must use BorderSurface");
  assert.ok(
    shortcutToolTipContent.includes("anchors.horizontalCenter: parent.horizontalCenter"),
    "ShortcutToolTip must center shortcut and description in its line"
  );

  // 3. HelpModal parity
  assert.ok(helpModalContent.includes("KeyBadge {"), "HelpModal must render shortcut items using KeyBadge");
  assert.ok(helpModalContent.includes("ShortcutToolTip {"), "HelpModal closeHelpBtn must use ShortcutToolTip");
  assert.ok(
    helpModalContent.includes("Keys.onPressed: function(event) {") &&
      helpModalContent.includes('event.key === Qt.Key_J || event.text === "j"') &&
      helpModalContent.includes('root.focusSection = "search"'),
    "HelpModal closeHelpBtn must support vim motion navigation down to search"
  );

  const gitModalPath = path.join(repoDir, "ui", "GitModal.qml");
  const gitModalContent = fs.readFileSync(gitModalPath, "utf8");
  const barWidgetContent = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  assert.ok(
    gitModalContent.includes("ListView {") &&
      gitModalContent.includes("id: snapshotList") &&
      gitModalContent.includes("loadMoreGitHistory") &&
      gitModalContent.includes("positionViewAtIndex"),
    "GitModal must use virtualized ListView with lazy-loaded pagination and positionViewAtIndex"
  );
  assert.ok(
    barWidgetContent.includes("function loadMoreGitHistory(") &&
      barWidgetContent.includes("property int gitLogLimit:"),
    "BarWidget must declare gitLogLimit and loadMoreGitHistory for lazy-loading snapshots"
  );
  assert.ok(
    gitModalContent.includes("syncFocusIndex") &&
      gitModalContent.includes("saveRemoteBtn") &&
      gitModalContent.includes("syncNowBtn") &&
      gitModalContent.includes("hasCursor: (root.activeTab === 1)"),
    "GitModal must support full vim motion navigation and cursor highlighting in Tab 1"
  );
  assert.ok(
    gitModalContent.includes("Keys.priority: Keys.BeforeItem") &&
      gitModalContent.includes("remoteField.focus = false") &&
      !/if\s*\(\s*remoteField\.text\.trim\(\)\.length\s*===\s*0\s*\)\s*\{\s*root\.close\(\)/.test(gitModalContent),
    "GitModal remoteField must implement two-stage escape (switch from insert to normal mode) without dismissing the modal on empty text"
  );
  assert.ok(
    gitModalContent.includes("snapshotSection") &&
      gitModalContent.includes("actionButtonIndex") &&
      gitModalContent.includes("hasCursor: (root.activeTab === 0) && (root.snapshotSection === \"actions\") && (root.actionButtonIndex === 0)") &&
      gitModalContent.includes("hasCursor: (root.activeTab === 0) && (root.snapshotSection === \"actions\") && (root.actionButtonIndex === 1)"),
    "GitModal must support full vim motion section navigation and cursor highlighting on action buttons in Tab 0"
  );
  assert.ok(
    gitModalContent.includes("GitContextMenu {") &&
      gitModalContent.includes("id: contextMenu") &&
      gitModalContent.includes("openContextMenuForSelected"),
    "GitModal must mount GitContextMenu for snapshot context actions"
  );
  const contextMenuPath = path.join(repoDir, "ui", "GitContextMenu.qml");
  assert.ok(fs.existsSync(contextMenuPath), "ui/GitContextMenu.qml must exist");
  const contextMenuContent = fs.readFileSync(contextMenuPath, "utf8");
  assert.ok(
    contextMenuContent.includes("signal rollbackRequested") &&
      contextMenuContent.includes("signal recoverRequested") &&
      contextMenuContent.includes("signal copyHashRequested"),
    "GitContextMenu must define rollbackRequested, recoverRequested, and copyHashRequested signals"
  );

  // 4. PanelContent button tooltips using ShortcutToolTip
  const expectedButtons = [
    { id: "helpBtn", shortcut: "?" },
    { id: "shortcutBtn", shortcut: "root.detectedPanelShortcut" },
    { id: "addBtn", shortcut: "Enter" },
    { id: "rowExpandBtn", shortcut: "Enter" },
    { id: "rowDeleteBtn", shortcut: "x" },
    { id: "clearBtn", shortcut: "c" },
    { id: "archiveBtn", shortcut: "d" },
    { id: "editBtn", shortcut: "e" },
    { id: "quickAddBtn", shortcut: "A / " }
  ];

  for (const btn of expectedButtons) {
    assert.ok(
      panelContent.includes(`id: ${btn.id}`) || panelContent.includes(`id: ${btn.id}\n`),
      `PanelContent must contain button ${btn.id}`
    );
  }

  assert.ok(
    panelContent.includes("Ui.ShortcutToolTip {"),
    "PanelContent must use Ui.ShortcutToolTip for rich tooltips with badges"
  );
  assert.ok(
    panelContent.includes("root.detectedPanelShortcut") && panelContent.includes("root.detectedQuickAddShortcut"),
    "PanelContent must track both panel toggle and quick add shortcuts"
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

            // Test GitContextMenu open & escape dismiss lifecycle
            gm.contextMenu.open({ hash: "abcdef1234567890", shortHash: "abcdef1", message: "Test snapshot", timestamp: Date.now() }, 100, 100);
            if (!gm.contextMenu.isOpen) {
                console.error("[TEST FAIL] contextMenu.open() failed to open GitContextMenu");
                Qt.exit(167);
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
