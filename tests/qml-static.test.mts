import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { extractHandler, repoDir } from "./helpers/qml-test-utils.mts";

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
    panelLogicContent.includes('"i / a"'),
    "keybindingsList must list 'i / a' for task input focus"
  );
  assert.ok(
    panelLogicContent.includes('"/ / Ctrl+F"'),
    "keybindingsList must list '/ / Ctrl+F' for search"
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
  assert.ok(
    panelContent.includes("id: searchBtn") && panelContent.includes('"󰍉"'),
    "Panel header must feature searchBtn with magnifying glass icon"
  );
  assert.ok(
    panelContent.includes("id: searchRow") && panelContent.includes("id: searchField"),
    "PanelContent must include expandable searchRow and searchField"
  );
  assert.ok(
    panelContent.includes('placeholderText: "Search tasks, notes, tags, #profiles..."'),
    "searchField must describe comprehensive search capabilities in placeholder"
  );
  assert.ok(
    panelContent.includes('shortcut: "/ or Ctrl+F"'),
    "searchBtn tooltip must document '/ or Ctrl+F' shortcuts"
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
  assert.ok(
    contextMenuContent.includes("implicitHeight: card.contentTopInset + card.contentBottomInset + menuContent.implicitHeight") &&
      contextMenuContent.includes("height: implicitHeight"),
    "GitContextMenu card must define explicit height derived from menuContent"
  );

  // 4. Chip variant design system and interactions
  const chipPath = path.join(repoDir, "ui", "Chip.qml");
  assert.ok(fs.existsSync(chipPath), "ui/Chip.qml must exist");
  const chipContent = fs.readFileSync(chipPath, "utf8");
  assert.ok(
    chipContent.includes('property string variant: "default"') &&
      chipContent.includes("effectiveRadius") &&
      chipContent.includes("isMonospace: variant === \"location\"") &&
      chipContent.includes('variant === "time"'),
    "Ui.Chip must support 'time' and 'location' variants with distinct radius and monospace properties"
  );
  assert.ok(
    panelContent.includes('variant: "time"') &&
      panelContent.includes('variant: "location"'),
    "PanelContent must use variant 'time' for reminders and 'location' for repositories/codebase chips"
  );
  assert.ok(
    panelContent.includes('root.expandedSubSection = "reminders"') &&
      panelContent.includes("root.openCodebase(itemRow.modelData)"),
    "PanelContent chips must provide click interactions to expand reminders and launch codebase"
  );

  // 5. PanelContent button tooltips using ShortcutToolTip
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

  // Strictly explicit drawer expansion (no hover auto-expand timers)
  assert.ok(!panelContent.includes("hoverExpandTimer"), "PanelContent must not contain hoverExpandTimer");
  assert.ok(!panelContent.includes("hoverFoldTimer"), "PanelContent must not contain hoverFoldTimer");
  assert.ok(!panelContent.includes("listFoldTimer"), "PanelContent must not contain listFoldTimer");

  // Row click-to-expand and checkbox-to-complete separation
  assert.ok(panelContent.includes("function toggleExpand()"), "itemRow must implement toggleExpand()");

  // Locate rowMouseArea's onClicked handler by brace matching. A non-greedy
  // regex would stop at the first `}`, which is an inner block (e.g. the
  // `onPositionChanged` guard) rather than the handler's own closing brace.
  const rowClick = extractHandler(panelContent, "id: rowMouseArea", "onClicked");
  assert.ok(rowClick, "PanelContent must define an onClicked handler on rowMouseArea");
  assert.ok(
    rowClick.includes("itemRow.toggleExpand()"),
    "rowMouseArea.onClicked must invoke itemRow.toggleExpand()"
  );
  assert.ok(
    !rowClick.includes("root.toggleTodo"),
    "rowMouseArea.onClicked must not call root.toggleTodo (that is the checkbox's job)"
  );
});

test("IPC Contract: every documented omarchy-shell command has a matching IpcHandler function", () => {
  // Static contract check. The live-shell IPC test can only run on a real
  // Omarchy desktop, so this catches command drift on every platform -
  // including CI - by cross-checking the two sources of truth.
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const designDoc = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");

  const handlerStart = barWidget.indexOf("IpcHandler {");
  assert.ok(handlerStart !== -1, "BarWidget must declare an IpcHandler");
  const handlerBlock = barWidget.slice(handlerStart);

  const implemented = new Set(
    [...handlerBlock.matchAll(/^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm)].map((m) => m[1])
  );

  // Documentation references commands two ways: directly after the plugin
  // prefix (`... ardoise toggleTodo "<id>"`) and as a slash list
  // (`... ardoise open` / `close` / `toggle`). Match only those two shapes so
  // payload values in the same sentence - e.g. the `done` field of
  // toggleTodo - are not mistaken for commands.
  const documented = new Set<string>();
  for (const line of designDoc.split("\n")) {
    if (!line.includes("tablerase.ardoise")) continue;
    const direct = /tablerase\.ardoise\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
    if (direct) documented.add(direct[1]);
    for (const cont of line.matchAll(/\/\s*`([A-Za-z_][A-Za-z0-9_]*)`/g)) {
      documented.add(cont[1]);
    }
  }

  assert.ok(documented.size > 0, "DESIGN.md must document the IPC command surface");

  for (const cmd of documented) {
    assert.ok(
      implemented.has(cmd),
      `DESIGN.md documents \`${cmd}\` but BarWidget's IpcHandler does not implement it`
    );
  }
  // The other direction too: an undocumented command is still live on the
  // shell bus even though users reading the docs would never find it.
  for (const cmd of implemented) {
    assert.ok(
      documented.has(cmd),
      `BarWidget implements IPC command \`${cmd}\` but DESIGN.md does not document it`
    );
  }

  assert.ok(
    implemented.has("toggle") && implemented.has("list") && implemented.has("count"),
    "Core IPC entry points (toggle/list/count) must remain available"
  );
  assert.ok(
    implemented.has("addDetailed") && implemented.has("searchProfiles"),
    "New IPC entry points (addDetailed/searchProfiles) must be available in BarWidget"
  );
});
