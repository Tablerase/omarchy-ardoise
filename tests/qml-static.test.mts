import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execSync, spawnSync } from "node:child_process";
import { extractHandler, findOnPath, repoDir } from "./helpers/qml-test-utils.mts";

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
  const designContent = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");
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

  // 1c. QuickAdd #profile and #tag autocomplete popup & key interception
  assert.ok(
    quickAddContent.includes("property bool autocompleteActive:") &&
      quickAddContent.includes('property string autocompleteMode: "profile"') &&
      quickAddContent.includes("readonly property var autocompleteMatches:"),
    "QuickAdd must declare autocompleteActive, autocompleteMode, and autocompleteMatches"
  );
  assert.ok(
    quickAddContent.includes("function checkAutocompleteAtCursor()") &&
      quickAddContent.includes("function applyAutocomplete(item)") &&
      quickAddContent.includes("function closeAutocomplete()"),
    "QuickAdd must declare checkAutocompleteAtCursor, applyAutocomplete, and closeAutocomplete"
  );
  assert.ok(
    quickAddContent.includes("id: autocompleteBox") &&
      quickAddContent.includes("visible: root.autocompleteActive && root.autocompleteMatches.length > 0"),
    "QuickAdd must render autocompleteBox conditionally on active state and matches"
  );
  assert.ok(
    quickAddContent.includes("if (root.autocompleteActive && root.autocompleteMatches.length > 0)"),
    "QuickAdd taskInput key handlers must intercept Down, Up, Tab, Backtab, Return, and Escape when autocomplete is active"
  );
  assert.ok(
    quickAddContent.includes("TodoStore.resolveDefaultProfile"),
    "QuickAdd must call TodoStore.resolveDefaultProfile for intelligent default profile selection"
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
  assert.ok(
    quickAddContent.includes("Ui.ReminderPicker") &&
      quickAddContent.includes("onCustomSelected") &&
      panelContent.includes("Ui.ReminderPicker") &&
      panelContent.includes("openCustomReminderPicker"),
    "QuickAdd and PanelContent must integrate Ui.ReminderPicker and handle onCustomSelected"
  );
  const reminderPillsContent = fs.readFileSync(path.join(repoDir, "ui", "ReminderPills.qml"), "utf8");
  assert.ok(
    reminderPillsContent.includes("customBtn") &&
      reminderPillsContent.includes("customBtnTrailing") &&
      reminderPillsContent.includes("getItemAtVisualIndex") &&
      reminderPillsContent.includes("customSelected") &&
      reminderPillsContent.includes("showCustomPill"),
    "ReminderPills must support custom reminder pill, leading/trailing layout, and customSelected signal"
  );
  assert.ok(
    reminderPillsContent.includes("leftPadding: Style.space(6)") &&
      reminderPillsContent.includes("rightPadding: Style.space(6)"),
    "ReminderPills must include left and right padding to avoid edge chip scale cropping"
  );
  const profileSelectorContent = fs.readFileSync(path.join(repoDir, "ui", "ProfileSelector.qml"), "utf8");
  assert.ok(
    profileSelectorContent.includes("leftPadding: Style.space(6)") &&
      profileSelectorContent.includes("rightPadding: Style.space(6)"),
    "ProfileSelector must include left and right padding to avoid edge chip scale cropping"
  );
  const reminderPickerContent = fs.readFileSync(path.join(repoDir, "ui", "ReminderPicker.qml"), "utf8");
  assert.ok(
    reminderPickerContent.includes("TodoStore.parseCustomReminder") &&
      reminderPickerContent.includes("calGrid") &&
      reminderPickerContent.includes("adjustMinutes") &&
      reminderPickerContent.includes("reminderConfirmed"),
    "ReminderPicker must implement natural language parsing, mini-calendar grid, time adjustments, and confirmation"
  );
  assert.ok(
    !reminderPickerContent.includes('text = ""') &&
      reminderPickerContent.includes("card.forceActiveFocus()") &&
      reminderPickerContent.includes("isNavFocused") &&
      reminderPickerContent.includes("manualInput.forceActiveFocus()"),
    "ReminderPicker must adhere to Two-Stage Escape: never wipe draft text on Escape, blur to card container mode, support re-entry via i/a, and provide nav focus styling"
  );

  // 4e. Expanded Drawer Title Reveal (long titles must be readable, not truncated)
  assert.ok(
    panelContent.includes("wrapMode: itemRow.isExpanded ? Text.Wrap : Text.NoWrap") &&
      panelContent.includes("elide: itemRow.isExpanded ? Text.ElideNone : Text.ElideRight") &&
      panelContent.includes("verticalAlignment: itemRow.isExpanded ? Text.AlignTop : Text.AlignVCenter"),
    "PanelContent title must stay single-line and elided when collapsed, and wrap to reveal the full title when the drawer is expanded"
  );
  assert.ok(
    panelContent.includes("readonly property bool titleWraps: titleLabel.visible && titleLabel.lineCount > 1") &&
      panelContent.includes(
        "readonly property real firstLineHeight: titleLabel.lineCount > 0 ? (titleLabel.height / titleLabel.lineCount) : Style.space(22)"
      ) &&
      panelContent.includes("readonly property real firstLineCenterY: titleLabel.y + firstLineHeight / 2"),
    "titleRowItem must derive wrap state and the first-line center from measured title geometry, never from font metrics"
  );
  assert.ok(
    (panelContent.match(/anchors\.verticalCenterOffset: titleRowItem\.firstLineCenterOffset/g) || []).length === 4,
    "Checkbox, action buttons, inline profile badge, and title editor must all align to the first title line when it wraps"
  );
  assert.ok(
    panelContent.includes("!itemRow.isExpanded && (titleHover.hovered || titleClickArea.containsMouse) && titleLabel.truncated"),
    "Title hover tooltip must be suppressed while expanded, where the full title is already visible"
  );
  assert.ok(
    panelContent.includes(
      "visible: opacity > 0.01 && root.editingTaskId !== itemRow.modelData.id && !titleRowItem.titleWraps"
    ),
    "Strikethrough must be suppressed for wrapped multi-line titles in the drawer"
  );
  assert.ok(
    designContent.includes("Expanded Drawer Title Reveal") &&
      designContent.includes("wrapMode: Text.Wrap") &&
      designContent.includes("titleRowItem.titleWraps"),
    "DESIGN.md must document the expanded drawer multi-line title reveal"
  );

  // 4f. Too-Tall Focused Row Keeps Its Top In View
  // Motion onto an expanded drawer used to bottom-align it; because the drawer
  // is taller than the list viewport, that pushed its top (and the wrapped
  // title) above the viewport where the Flickable's clip cut it off.
  assert.ok(
    panelContent.includes("var itemFitsViewport = item.height + Style.space(8) <= todoListFlickable.height") &&
      panelContent.includes("var target = itemFitsViewport") &&
      panelContent.includes("? itemBottom - todoListFlickable.height + Style.space(6)") &&
      panelContent.includes(": itemTop - Style.space(2)"),
    "ensureTaskVisible must keep the top of a focused item that is taller than the viewport in view"
  );
  assert.ok(
    designContent.includes("Too-tall focused item"),
    "DESIGN.md must document the too-tall focused item alignment rule"
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

test("IPC Contract: documented commands match the IpcHandler in DESIGN.md and README", () => {
  // Static contract check. The live-shell IPC test can only run on a real
  // Omarchy desktop, so this catches command drift on every platform -
  // including CI. Both docs are user-facing, so both are held to the handler.
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const designDoc = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");
  const readme = fs.readFileSync(path.join(repoDir, "README.md"), "utf8");

  const handlerStart = barWidget.indexOf("IpcHandler {");
  assert.ok(handlerStart !== -1, "BarWidget must declare an IpcHandler");
  const handlerBlock = barWidget.slice(handlerStart);

  const implemented = new Set(
    [...handlerBlock.matchAll(/^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm)].map((m) => m[1])
  );

  /** `... ardoise <cmd>` and slash lists (`... ardoise open` / `close`). */
  const prefixForm = (doc: string) => {
    const found = new Set<string>();
    for (const line of doc.split("\n")) {
      if (!line.includes("tablerase.ardoise")) continue;
      const direct = /tablerase\.ardoise\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
      if (direct) found.add(direct[1]);
      for (const cont of line.matchAll(/\/\s*`([A-Za-z_][A-Za-z0-9_]*)`/g)) {
        found.add(cont[1]);
      }
    }
    return found;
  };

  /** Every backticked identifier in a slice of the doc. */
  const backticked = (doc: string, from: string, to?: string) => {
    const start = doc.indexOf(from);
    assert.notEqual(start, -1, `expected to find "${from}"`);
    const slice = to ? doc.slice(start, doc.indexOf(to, start)) : doc.slice(start);
    return new Set([...slice.matchAll(/`([A-Za-z_][A-Za-z0-9_]*)`/g)].map((m) => m[1]));
  };

  // DESIGN.md documents the full contract, so it must be exhaustive in both
  // directions. Payload values in the same sentence - e.g. the `done` field of
  // toggleTodo - are deliberately not matched by prefixForm.
  const designCommands = prefixForm(designDoc);
  assert.ok(designCommands.size > 0, "DESIGN.md must document the IPC command surface");

  for (const cmd of designCommands) {
    assert.ok(
      implemented.has(cmd),
      `DESIGN.md documents \`${cmd}\` but BarWidget's IpcHandler does not implement it`
    );
  }
  for (const cmd of implemented) {
    assert.ok(
      designCommands.has(cmd),
      `BarWidget implements IPC command \`${cmd}\` but DESIGN.md does not document it`
    );
  }

  // The README is user-facing, so it must document every command too - but
  // its grouping table is prose-heavy, so it is matched by backticked token
  // rather than by the shell prefix.
  const readmeCommands = new Set<string>([
    ...backticked(readme, "### All commands", "\n---"),
    ...prefixForm(readme),
  ]);

  for (const cmd of implemented) {
    assert.ok(
      readmeCommands.has(cmd),
      `BarWidget implements IPC command \`${cmd}\` but README.md does not document it`
    );
  }

  // Reverse check for the README, scoped to the grouping table. That section
  // contains command names only, so anything backticked there is meant to be a
  // command and a typo becomes a "Function not found" for the user.
  for (const cmd of backticked(readme, "### All commands", "\n---")) {
    assert.ok(
      implemented.has(cmd),
      `README.md lists \`${cmd}\` as a command but BarWidget's IpcHandler does not implement it`
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
  assert.ok(
    implemented.has("gitSearch"),
    "gitSearch IPC entry point must be available in BarWidget (Phase 2 snapshot search)"
  );
});

test("Lua Keybindings Sandbox: tools/load-bindings.lua evaluates config and blocks unsafe calls", () => {
  const loadBindingsScript = path.join(repoDir, "tools", "load-bindings.lua");
  assert.ok(fs.existsSync(loadBindingsScript), "tools/load-bindings.lua must exist");

  const luaPath = findOnPath("lua");
  if (!luaPath) {
    if (process.env.CI) throw new Error("lua must be installed in CI");
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-lua-test-"));
  try {
    // 1. Declarative table return
    const tableFile = path.join(tmpDir, "table_bindings.lua");
    fs.writeFileSync(tableFile, 'return { open_editor = "o", search = "ctrl+s", jump_top = { "t", "Home" } }');
    const tableRes = spawnSync(luaPath, [loadBindingsScript, tableFile], { encoding: "utf8" });
    assert.equal(tableRes.status, 0);
    const tableJson = JSON.parse(tableRes.stdout.trim());
    assert.equal(tableJson.open_editor, "o");
    assert.equal(tableJson.search, "ctrl+s");
    assert.deepEqual(tableJson.jump_top, ["t", "Home"]);

    // 2. Imperative ardoise.bind syntax
    const imperativeFile = path.join(tmpDir, "imperative_bindings.lua");
    fs.writeFileSync(imperativeFile, 'ardoise.bind("o", "open_editor")\nardoise.bind("Ctrl+S", "search")');
    const impRes = spawnSync(luaPath, [loadBindingsScript, imperativeFile], { encoding: "utf8" });
    assert.equal(impRes.status, 0);
    const impJson = JSON.parse(impRes.stdout.trim());
    assert.equal(impJson.open_editor, "o");
    assert.equal(impJson.search, "Ctrl+S");

    // 3. Malicious attempt to use os.execute / io.open
    const evilFile = path.join(tmpDir, "evil.lua");
    const markerFile = path.join(tmpDir, "pwned.txt");
    fs.writeFileSync(evilFile, `os.execute("touch ${markerFile}")\nreturn { open_editor = "o" }`);
    const evilRes = spawnSync(luaPath, [loadBindingsScript, evilFile], { encoding: "utf8" });
    // Sandbox should block execution: os is nil, error caught, marker file must NOT exist
    assert.ok(!fs.existsSync(markerFile), "Sandbox must prevent os.execute from creating marker file");
    const evilJson = JSON.parse(evilRes.stdout.trim());
    assert.deepEqual(evilJson, {}, "Unsafe script execution error must safely return empty object");

    // 4. Malformed syntax
    const malformedFile = path.join(tmpDir, "syntax_error.lua");
    fs.writeFileSync(malformedFile, "return { incomplete table");
    const syntaxRes = spawnSync(luaPath, [loadBindingsScript, malformedFile], { encoding: "utf8" });
    const syntaxJson = JSON.parse(syntaxRes.stdout.trim());
    assert.deepEqual(syntaxJson, {}, "Syntax errors must safely resolve to empty object");

    // 5. Non-existent file
    const nonExistentRes = spawnSync(luaPath, [loadBindingsScript, path.join(tmpDir, "missing.lua")], { encoding: "utf8" });
    assert.equal(nonExistentRes.status, 0);
    assert.deepEqual(JSON.parse(nonExistentRes.stdout.trim()), {});
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test("Default Bindings Template: tools/default-bindings.lua is valid and documents all actions", () => {
  const templatePath = path.join(repoDir, "tools", "default-bindings.lua");
  const loadBindingsScript = path.join(repoDir, "tools", "load-bindings.lua");
  assert.ok(fs.existsSync(templatePath), "tools/default-bindings.lua must exist");

  const templateContent = fs.readFileSync(templatePath, "utf8");
  const panelLogicContent = fs.readFileSync(path.join(repoDir, "PanelLogic.js"), "utf8");

  // Extract action names from DEFAULT_BINDINGS in PanelLogic.js
  const defaultBindingsMatch = panelLogicContent.match(/var DEFAULT_BINDINGS = {([^}]+)}/s);
  assert.ok(defaultBindingsMatch, "PanelLogic.js must declare DEFAULT_BINDINGS");
  const actionKeys = [...defaultBindingsMatch[1].matchAll(/([a-z_]+)\s*:/g)].map((m) => m[1]);
  assert.ok(actionKeys.length >= 15, "DEFAULT_BINDINGS must contain expected action catalog");

  for (const action of actionKeys) {
    assert.ok(
      templateContent.includes(action),
      `default-bindings.lua template must document action '${action}'`
    );
  }

  // Ensure BarWidget and PanelContent have wired the template for auto-seeding
  const barWidgetContent = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");
  assert.ok(barWidgetContent.includes("default-bindings.lua"), "BarWidget.qml must reference default-bindings.lua");
  assert.ok(panelContent.includes("default-bindings.lua"), "PanelContent.qml must reference default-bindings.lua");

  const luaPath = findOnPath("lua");
  if (!luaPath) {
    if (process.env.CI) throw new Error("lua must be installed in CI");
    return;
  }

  const res = spawnSync(luaPath, [loadBindingsScript, templatePath], { encoding: "utf8" });
  assert.equal(res.status, 0, "Evaluation of default-bindings.lua must succeed with exit code 0");
  const parsed = JSON.parse(res.stdout.trim());
  assert.deepEqual(parsed, {}, "Default template must return an empty object so defaults remain active");
});

test("HelpModal: dynamic dismiss key hint and key handling", () => {
  const helpModalContent = fs.readFileSync(path.join(repoDir, "ui", "HelpModal.qml"), "utf8");
  assert.ok(helpModalContent.includes("helpShortcutHint"), "HelpModal must declare helpShortcutHint");
  assert.ok(helpModalContent.includes("isHelpDismissKey"), "HelpModal must declare isHelpDismissKey");
  assert.ok(
    helpModalContent.includes('"Press Esc or " + root.helpShortcutHint + " to close"'),
    "HelpModal footer prompt must dynamically use helpShortcutHint"
  );
  assert.ok(
    helpModalContent.includes("root.isHelpDismissKey(event)"),
    "HelpModal Keys.onPressed must delegate to isHelpDismissKey"
  );
});

test("Git Ignore Policy: BarWidget provisions .gitignore for bindings.lua", () => {
  const barWidgetContent = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  assert.ok(
    barWidgetContent.includes(".gitignore") && barWidgetContent.includes("bindings.lua"),
    "BarWidget must ensure .gitignore excludes bindings.lua from task git repository"
  );
});

test("Demo & Scenario Runner: tools/demo.sh exists, is executable, and supports hero scenario", () => {
  const demoScript = path.join(repoDir, "tools", "demo.sh");
  assert.ok(fs.existsSync(demoScript), "tools/demo.sh must exist");

  const stat = fs.statSync(demoScript);
  assert.ok(Boolean(stat.mode & 0o111), "tools/demo.sh must be executable");

  const listRes = spawnSync(demoScript, ["list"], { encoding: "utf8" });
  assert.equal(listRes.status, 0, "tools/demo.sh list must succeed with exit code 0");
  assert.ok(listRes.stdout.includes("hero"), "tools/demo.sh list must include hero scenario");
  assert.ok(listRes.stdout.includes("ladder"), "tools/demo.sh list must include ladder scenario");
  assert.ok(listRes.stdout.includes("empty"), "tools/demo.sh list must include empty scenario");

  const helpRes = spawnSync(demoScript, ["--help"], { encoding: "utf8" });
  assert.equal(helpRes.status, 0, "tools/demo.sh --help must succeed with exit code 0");
  assert.ok(helpRes.stdout.includes("hero"), "tools/demo.sh --help must document usage");
});

test("Automated GitHub Remote Creation: tools/setup-git-remote.sh and UI/IPC wiring", () => {
  const setupScript = path.join(repoDir, "tools", "setup-git-remote.sh");
  assert.ok(fs.existsSync(setupScript), "tools/setup-git-remote.sh must exist");

  const stat = fs.statSync(setupScript);
  assert.ok(Boolean(stat.mode & 0o111), "tools/setup-git-remote.sh must be executable");

  const scriptContent = fs.readFileSync(setupScript, "utf8");
  assert.ok(scriptContent.includes("--private"), "setup-git-remote.sh must create private repositories by default");
  assert.ok(scriptContent.includes("MISE_QUIET=1"), "setup-git-remote.sh must suppress mise output");

  const gitModalContent = fs.readFileSync(path.join(repoDir, "ui", "GitModal.qml"), "utf8");
  assert.ok(gitModalContent.includes("autoCreateRemoteBtn"), "GitModal.qml must declare autoCreateRemoteBtn");
  assert.ok(
    gitModalContent.includes("Create GitHub Repo"),
    "GitModal.qml must have 'Create GitHub Repo' button"
  );
  assert.ok(
    gitModalContent.includes("autoSetupGitRemote"),
    "GitModal.qml must invoke autoSetupGitRemote"
  );
  assert.ok(
    gitModalContent.includes("root.syncFocusIndex = (root.syncFocusIndex + 1) % 4"),
    "GitModal.qml must cycle across 4 controls in Tab 1"
  );

  const barWidgetContent = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  assert.ok(barWidgetContent.includes("setupGitRemoteProc"), "BarWidget.qml must declare setupGitRemoteProc");
  assert.ok(barWidgetContent.includes("setup-git-remote.sh"), "BarWidget.qml must invoke setup-git-remote.sh");
  assert.ok(
    barWidgetContent.includes("function autoSetupGitRemote"),
    "BarWidget.qml must define autoSetupGitRemote function"
  );
});

test("Hold-to-Confirm Deletion & Clear Integrity: HoldActionButton laser bar, card tint overlay, and key release wiring", () => {
  const holdButtonPath = path.join(repoDir, "ui", "HoldActionButton.qml");
  assert.ok(fs.existsSync(holdButtonPath), "ui/HoldActionButton.qml must exist");

  const holdBtn = fs.readFileSync(holdButtonPath, "utf8");
  assert.ok(holdBtn.includes("signal confirmed()"), "HoldActionButton must emit confirmed() signal on completion");
  assert.ok(holdBtn.includes("function startCharging()"), "HoldActionButton must implement startCharging()");
  assert.ok(holdBtn.includes("function stopCharging()"), "HoldActionButton must implement stopCharging()");
  assert.ok(holdBtn.includes("id: laserBar"), "HoldActionButton must implement bottom laser bar");
  assert.ok(holdBtn.includes("id: tintOverlay"), "HoldActionButton must implement surface tint overlay");
  assert.ok(holdBtn.includes("readonly property real progress:"), "HoldActionButton must expose progress");
  assert.ok(holdBtn.includes("drainAnim"), "HoldActionButton must implement drainAnim for 180ms cancellation drain");

  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");

  // Task row delete: laser bar and tint on itemRow, driven by rowDeleteBtn.progress
  assert.ok(panelContent.includes("id: deleteLaserBar"), "PanelContent must implement deleteLaserBar on task row");
  assert.ok(panelContent.includes("id: deleteTintOverlay"), "PanelContent must implement deleteTintOverlay on task row");
  assert.ok(panelContent.includes("rowDeleteBtn.progress"), "PanelContent laser and tint must bind to rowDeleteBtn.progress");
  assert.ok(panelContent.includes("rowShakeTranslate"), "PanelContent must include micro-shake transform on task row");

  // clearBtn is a HoldActionButton with its own laserBar via visualsEnabled
  assert.ok(
    panelContent.includes("Ui.HoldActionButton {\n          id: clearBtn"),
    "PanelContent must use HoldActionButton for clearBtn"
  );

  assert.ok(
    panelContent.includes("function startDeleteHold") && panelContent.includes("function stopDeleteHold"),
    "PanelContent must implement startDeleteHold and stopDeleteHold"
  );
  assert.ok(
    panelContent.includes("function startClearHold") && panelContent.includes("function stopClearHold"),
    "PanelContent must implement startClearHold and stopClearHold"
  );

  const panelQml = fs.readFileSync(path.join(repoDir, "Panel.qml"), "utf8");
  assert.ok(panelQml.includes("Keys.onReleased:"), "Panel.qml must implement Keys.onReleased on keyCatcher");
  assert.ok(panelQml.includes('panelContent.handleKeyRelease("x")'), "Panel.qml must dispatch key release for x");
  assert.ok(panelQml.includes('panelContent.handleKeyRelease("c")'), "Panel.qml must dispatch key release for c");
});

test("Task Context Menu & Archive Browser: contracts for components, IPC, and large-archive handling", () => {
  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");
  const panelLogic = fs.readFileSync(path.join(repoDir, "PanelLogic.js"), "utf8");
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const taskMenu = fs.readFileSync(path.join(repoDir, "ui", "ContextActionMenu.qml"), "utf8");
  const archiveModal = fs.readFileSync(path.join(repoDir, "ui", "ArchiveModal.qml"), "utf8");
  const design = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");
  const readme = fs.readFileSync(path.join(repoDir, "README.md"), "utf8");
  const bindingsTemplate = fs.readFileSync(path.join(repoDir, "tools", "default-bindings.lua"), "utf8");

  // Task context menu: rendered by the component, driven by PanelLogic.
  assert.ok(
    taskMenu.includes("function clampedX()") &&
      taskMenu.includes("function clampedY()") &&
      taskMenu.includes("x: root.clampedX()") &&
      taskMenu.includes("y: root.clampedY()") &&
      taskMenu.includes("KeyBadge"),
    "ContextMenu must clamp its card inside the panel and render key badges"
  );
  assert.ok(
    !/^\s*focus:\s*true/m.test(taskMenu),
    "ContextMenu must stay non-modal so PanelKeyCatcher keeps routing keys to PanelLogic"
  );
  assert.ok(
    panelLogic.includes("task_menu: [\"K\"]") &&
      panelLogic.includes("copy_task: [\"y\"]") &&
      panelLogic.includes("var TASK_MENU_ITEMS = [") &&
      panelLogic.includes("function getTaskMenuItems(task)") &&
      panelLogic.includes("function taskMenuActionForKey(text)"),
    "PanelLogic must own the task menu action model and key mapping"
  );
  assert.ok(
    panelLogic.includes("if (root.showTaskMenu) {") &&
      panelLogic.includes("if (root.showTaskMenu) return;") &&
      panelLogic.includes("root.activateTaskMenuItem(\"delete_task\")"),
    "PanelLogic must route move/return/delete/escape through the open task menu"
  );
  assert.ok(
    panelContent.includes("function openTaskMenu()") &&
      panelContent.includes("function copySelectedTask()") &&
      panelContent.includes("function activateTaskMenuItem(actionId)") &&
      panelContent.includes("TodoStore.formatTaskForLLM(task)") &&
      panelContent.includes("Quickshell.execDetached([\"bash\", \"-c\", \"printf %s \" + Util.shellQuote(text) + \" | wl-copy\"])") &&
      panelContent.includes("Ui.ContextActionMenu {") &&
      panelContent.includes("onItemActivated: function(actionId) { root.activateTaskMenuItem(actionId) }"),
    "PanelContent must open the menu, dispatch actions, and copy via wl-copy with feedback"
  );

  // Archive browser: virtualized list + restore IPC + large-archive strategy.
  assert.ok(
    archiveModal.includes("ListView {") &&
      archiveModal.includes("model: root.filteredArchived") &&
      archiveModal.includes("positionViewAtIndex") &&
      archiveModal.includes("cacheBuffer") &&
      !archiveModal.includes("Repeater {"),
    "ArchiveModal must render through a virtualized ListView, never a Repeater, for large archives"
  );
  assert.ok(
    archiveModal.includes("TodoStore.getArchivedTasks(raw)") &&
      archiveModal.includes("TodoStore.filterArchivedTasks(root.archivedTasks, root.searchQuery)") &&
      archiveModal.includes("barWidget.unarchiveTask(task.id)") &&
      archiveModal.includes("Splice instead of re-parsing"),
    "ArchiveModal must parse once on open, filter in memory, and splice after a restore"
  );
  assert.ok(
    barWidget.includes("function unarchiveTask(id)") &&
      barWidget.includes("function unarchive(id: string): string"),
    "BarWidget must expose the unarchive IPC that restores and commits both files"
  );
  assert.ok(
    panelContent.includes("function openArchiveModal()") &&
      panelContent.includes("Ui.ArchiveModal {") &&
      panelContent.includes("onShowArchiveModalChanged:") &&
      panelContent.includes("archiveModal.open()") &&
      panelContent.includes("root.showArchiveModal ||") &&
      panelContent.includes("onClicked: root.openArchiveModal()"),
    "PanelContent must mount the archive modal, sync onShowArchiveModalChanged, block keys while open, and wire the footer button"
  );
  assert.ok(
    archiveModal.includes("typeof purgeHold !== \"undefined\" && purgeHold") &&
      archiveModal.includes("purgeHold.startCharging") &&
      archiveModal.includes("purgeHold.stopCharging"),
    "ArchiveModal must defensively guard purgeHold access against uninitialized or missing references"
  );
  assert.ok(
    readme.includes("`unarchive`") && readme.includes("`purgeArchived`") && readme.includes("**31 shell commands**"),
    "README must document the archive commands and the updated command count"
  );
  assert.ok(
    design.includes("ui/ContextActionMenu.qml") &&
      design.includes("ui/ArchiveModal.qml") &&
      design.includes("virtualized `ListView`"),
    "DESIGN.md must document both new components and the archive virtualization strategy"
  );
  assert.ok(
    bindingsTemplate.includes("task_menu"),
    "the bindings template must document the task_menu action"
  );
});

test("Right-click, archive menu/delete, and data-loss safeguards: contracts", () => {
  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");
  const archiveModal = fs.readFileSync(path.join(repoDir, "ui", "ArchiveModal.qml"), "utf8");
  const contextMenu = fs.readFileSync(path.join(repoDir, "ui", "ContextActionMenu.qml"), "utf8");
  const gitModal = fs.readFileSync(path.join(repoDir, "ui", "GitModal.qml"), "utf8");
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const todoStore = fs.readFileSync(path.join(repoDir, "TodoStore.js"), "utf8");
  const panelLogicContent = fs.readFileSync(path.join(repoDir, "PanelLogic.js"), "utf8");
  const design = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");

  // Right-click opens the task menu; openTaskMenuAt is the single entry point.
  assert.ok(
    panelContent.includes("function openTaskMenuAt(index, x, y)") &&
      panelContent.includes("acceptedButtons: Qt.RightButton") &&
      panelContent.includes("root.openTaskMenuAt(delegateRoot.index, p.x, p.y)"),
    "PanelContent must open the task context menu on right-click at the click point"
  );

  // Reused, renamed context menu component.
  assert.ok(
    archiveModal.includes("ContextActionMenu {") &&
      contextMenu.includes("function clampedX()") &&
      contextMenu.includes("HoldActionButton {") &&
      contextMenu.includes("modelData.hold"),
    "the shared ContextActionMenu must render hold items and be reused by the archive modal"
  );

  // Archive search button for mouse users.
  assert.ok(
    archiveModal.includes("id: archiveSearchBtn") &&
      archiveModal.includes('iconText: "󰍉"') &&
      archiveModal.includes("root.activateSearch()"),
    "ArchiveModal must expose a magnifier button that activates search"
  );

  // Permanent delete: hold-to-confirm via HoldActionButton, plus x/Delete hold.
  assert.ok(
    archiveModal.includes("id: purgeHold") &&
      archiveModal.includes("purgeHold.startCharging()") &&
      !archiveModal.includes("root.purgeHold") &&
      archiveModal.includes("Keys.onReleased") &&
      archiveModal.includes("if (event.isAutoRepeat) return") &&
      archiveModal.includes("purgeHold.stopCharging()") &&
      archiveModal.includes("holdDuration: 800"),
    "ArchiveModal must wire a HoldActionButton state machine to x/Delete press and release with auto-repeat guard and 800ms duration"
  );
  assert.ok(
    barWidget.includes("root.store = result.updatedStore") &&
      barWidget.includes("root.lastArchiveText = archiveJson"),
    "BarWidget must synchronize root.store and root.lastArchiveText upon unarchive / purge operations"
  );

  // The menu-level hold is centralized in ContextActionMenu and driven by both
  // hosts for mouse and keyboard.
  assert.ok(
    contextMenu.includes("function startSelectedHold()") &&
      contextMenu.includes("function startHoldFor(actionId)") &&
      contextMenu.includes("function stopHold()") &&
      contextMenu.includes("readonly property real holdProgress") &&
      contextMenu.includes("id: holdState"),
    "ContextActionMenu must own the menu-level hold state machine"
  );
  assert.ok(
    panelLogicContent.includes("root.taskMenu.startSelectedHold()") &&
      panelLogicContent.includes("root.taskMenu.startHoldFor(\"delete_task\")") &&
      panelLogicContent.includes("root.taskMenu.stopHold()"),
    "PanelLogic must route Enter/x/release through the task menu hold"
  );
  assert.ok(
    panelLogicContent.includes('{ id: "delete_task", icon: "󰅙", label: "Delete task", shortcut: "hold x", desc: "Hold to confirm", hold: true }'),
    "the task menu's delete item must be a hold-to-confirm item"
  );
  assert.ok(
    archiveModal.includes("contextMenu.startSelectedHold()") &&
      archiveModal.includes('contextMenu.startHoldFor("delete_permanent")') &&
      archiveModal.includes("contextMenu.stopHold()"),
    "ArchiveModal must route the archive menu's hold through ContextActionMenu"
  );

  // GitModal / ArchiveModal context menus open with uppercase K only.
  // A bare `event.key === Qt.Key_K` would also match lowercase k, which is
  // list navigation - the bug this guards.
  const shiftedK = '(event.key === Qt.Key_K && (event.modifiers & Qt.ShiftModifier))';
  assert.ok(
    gitModal.includes('event.text === "K" || ' + shiftedK),
    "GitModal must open its contextual menu with uppercase K only"
  );
  assert.ok(
    archiveModal.includes('event.text === "K" || ' + shiftedK),
    "ArchiveModal must open its contextual menu with uppercase K only"
  );
  assert.ok(
    !archiveModal.includes('if (event.key === Qt.Key_K || event.text === "K")'),
    "ArchiveModal must not open the menu on lowercase k (navigation)"
  );

  // Data-loss safeguards: pure store helpers + durable BarWidget path.
  assert.ok(
    todoStore.includes("function purgeArchived(archiveRawText, id)") &&
      todoStore.includes("function reconcileArchive(store, archiveRawText)"),
    "TodoStore must expose purgeArchived and reconcileArchive"
  );
  assert.ok(
    barWidget.includes("function readFile(path, cb)") &&
      barWidget.includes("function _writeArchiveUntilGone(") &&
      barWidget.includes("function maybeReconcileArchive()") &&
      barWidget.includes("root._storeHasId(id, function(present)") &&
      barWidget.includes("function purgeArchivedTask(id)") &&
      barWidget.includes("function purgeArchived(id: string): string"),
    "BarWidget must read files fresh, confirm the active write before removing from the archive, and reconcile on load"
  );
  assert.ok(
    design.includes("purgeArchived") && design.includes("reconcileArchive"),
    "DESIGN.md must document the archive data-loss safeguards"
  );
});

test("Onboarding Tutorial Quests & Release Highlights: contracts and UI indicators", () => {
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const panelContent = fs.readFileSync(path.join(repoDir, "PanelContent.qml"), "utf8");
  const helpModal = fs.readFileSync(path.join(repoDir, "ui", "HelpModal.qml"), "utf8");
  const todoStore = fs.readFileSync(path.join(repoDir, "TodoStore.js"), "utf8");
  const design = fs.readFileSync(path.join(repoDir, "DESIGN.md"), "utf8");

  // 1. Initial Store Seeding on Install
  assert.ok(
    barWidget.includes("TodoStore.createInitialStore()") &&
      barWidget.includes("initialStoreJson") &&
      barWidget.includes("cat << 'EOF' >"),
    "BarWidget must seed the initial store using createInitialStore via heredoc on fresh install"
  );

  // 2. BarWidget IPC contracts
  assert.ok(
    barWidget.includes("function seedTutorial()") &&
      barWidget.includes("function markReleaseSeen()") &&
      barWidget.includes("function seedTutorial(): string") &&
      barWidget.includes("function whatsNew(): string") &&
      barWidget.includes("function markReleaseSeen(): string"),
    "BarWidget must expose seedTutorial, whatsNew, and markReleaseSeen methods and IPC endpoints"
  );

  // 3. PanelContent Indicators
  assert.ok(
    panelContent.includes("property bool hasNewRelease: TodoStore.hasNewRelease(root.store)") &&
      panelContent.includes("property bool dismissedReleaseBanner:") &&
      panelContent.includes("function acknowledgeRelease()") &&
      panelContent.includes("helpReleaseDot") &&
      panelContent.includes("releaseBanner"),
    "PanelContent must implement hasNewRelease, acknowledgeRelease, helpReleaseDot, and releaseBanner"
  );

  // 4. HelpModal What's New Card
  assert.ok(
    helpModal.includes('import "../TodoStore.js" as TodoStore') &&
      helpModal.includes("whatsNewCard") &&
      helpModal.includes("TodoStore.RELEASE_HIGHLIGHTS") &&
      helpModal.includes("property bool releaseNotesCollapsed:") &&
      helpModal.includes("property bool releaseNotesHidden:") &&
      helpModal.includes("toggleCollapseBtn") &&
      helpModal.includes("hideReleaseBtn") &&
      helpModal.includes('root.focusSection === "release"'),
    "HelpModal must import TodoStore and display collapsible & dismissible whatsNewCard with full keyboard navigation"
  );
  assert.ok(
    panelContent.includes("hasNewRelease: root.hasNewRelease"),
    "PanelContent must pass hasNewRelease to helpModal"
  );

  // 5. TodoStore Catalog & Seeding
  assert.ok(
    todoStore.includes("CURRENT_RELEASE_VERSION") &&
      todoStore.includes("RELEASE_HIGHLIGHTS") &&
      todoStore.includes("getTutorialTasks") &&
      todoStore.includes("createInitialStore") &&
      todoStore.includes("seedTutorialTasks") &&
      todoStore.includes("hasNewRelease") &&
      todoStore.includes("markReleaseSeen"),
    "TodoStore must export CURRENT_RELEASE_VERSION, RELEASE_HIGHLIGHTS, getTutorialTasks, createInitialStore, seedTutorialTasks, hasNewRelease, markReleaseSeen"
  );

  // 6. Documentation in DESIGN.md
  assert.ok(
    design.includes("Onboarding Tutorial & Release Highlights System") &&
      design.includes("seedTutorial") &&
      design.includes("whatsNew") &&
      design.includes("markReleaseSeen"),
    "DESIGN.md must document the onboarding tutorial and release highlights system"
  );
});

test("Security & Privacy Baseline: Git commit shell safety and notification argv hygiene", () => {
  const barWidget = fs.readFileSync(path.join(repoDir, "BarWidget.qml"), "utf8");
  const service = fs.readFileSync(path.join(repoDir, "Service.qml"), "utf8");

  // 1. Commit action must NOT append user title to actionName
  assert.ok(
    barWidget.includes('function addTodo(title, description, profile, reminder) {') &&
      barWidget.includes('saveStore(TodoStore.addTodo(root.store, title, description, profile, reminder), "Add task")') &&
      !barWidget.includes('"Add task: " + title'),
    "BarWidget.addTodo must not concatenate user task title into commit action name"
  );

  // 2. CommitProcess must pass commit message as data outside shell source and via stdin
  assert.ok(
    barWidget.includes("git commit -F -") &&
      barWidget.includes('"$1"') &&
      barWidget.includes('"$2"') &&
      barWidget.includes('"_"') &&
      barWidget.includes('root.dataDirPath') &&
      barWidget.includes('GitSync.buildCommitMessage(root.deviceName, root.lastCommitAction, root.pendingCount)'),
    "BarWidget.commitProcess must pass data outside shell source and use stdin for git commit"
  );

  // 3. Service.qml must NOT pass private titles or reminder descriptions in argv
  assert.ok(
    !service.includes('headline = "Todo: " + t.title') &&
      !service.includes('t.description') &&
      service.includes('headline = (t.profile && t.profile !== "personal" ? "[" + t.profile + "] " : "") + "Task Reminder"') &&
      service.includes('desc = "Scheduled reminder is due"'),
    "Service.qml must not expose private task titles or reminder descriptions in notification process arguments"
  );
});


