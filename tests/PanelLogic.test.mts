import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const PanelLogic = require("../PanelLogic.js");
const TodoStore = require("../TodoStore.js");

const {
  cleanRepoName,
  buildEditorCommand,
  buildCodebaseCommand,
  getKeybindingsList,
  filterKeybindings,
  getNextSection,
  getNextSubSection,
  getPrevSubSection,
  handleEscape,
  handleMove,
  handleTab,
  handleActivate,
  handleReturn,
  handleDelete,
  handleTextKey
} = PanelLogic;

test("cleanRepoName: strips repo owner prefix cleanly", () => {
  assert.equal(cleanRepoName("Tablerase/omarchy-ardoise"), "omarchy-ardoise");
  assert.equal(cleanRepoName("github.com/org/repo"), "repo");
  assert.equal(cleanRepoName("standalone-repo"), "standalone-repo");
  assert.equal(cleanRepoName(""), "");
  assert.equal(cleanRepoName(null), "");
  assert.equal(cleanRepoName(undefined), "");
});

test("buildEditorCommand: formats launch commands with and without taskId", () => {
  const basic = buildEditorCommand("/home/user/.config/omarchy/todos.json");
  assert.equal(basic, 'omarchy-launch-editor "/home/user/.config/omarchy/todos.json"');

  const withId = buildEditorCommand("/home/user/.config/omarchy/todos.json", 123456);
  assert.ok(withId.includes("omarchy-launch-editor"), "includes editor launch executable");
  assert.ok(withId.includes("123456"), "includes target task id");
  assert.ok(withId.includes("defaults/editor"), "inspects defaults/editor for editor variant");
});

test("buildCodebaseCommand: expands tilde and builds launch command", () => {
  assert.equal(buildCodebaseCommand(""), "");
  const cmd = buildCodebaseCommand("~/Work/ardoise", "/home/testuser");
  assert.equal(cmd, 'omarchy-launch-editor "/home/testuser/Work/ardoise"');

  const absCmd = buildCodebaseCommand("/var/log", "/home/testuser");
  assert.equal(absCmd, 'omarchy-launch-editor "/var/log"');
});

test("getKeybindingsList & filterKeybindings: lists and filters shortcuts", () => {
  const defaultList = getKeybindingsList();
  assert.ok(defaultList.length >= 15, "contains full list of shortcuts");
  assert.ok(defaultList.some((item: any) => item.key === "SUPER + ALT + T" && item.desc.includes("toggle Ardoise panel")), "includes default panel toggle shortcut");
  assert.ok(defaultList.some((item: any) => item.key === "SUPER + SHIFT + T" && item.desc.includes("Quick Add")), "includes default quick add shortcut");

  const customList = getKeybindingsList("SUPER + T");
  assert.ok(customList.some((item: any) => item.key === "SUPER + T"), "includes custom detected shortcut");

  const customDualList = getKeybindingsList("SUPER + P", "SUPER + Q");
  assert.ok(customDualList.some((item: any) => item.key === "SUPER + P" && item.desc.includes("toggle Ardoise panel")), "includes custom panel toggle shortcut");
  assert.ok(customDualList.some((item: any) => item.key === "SUPER + Q" && item.desc.includes("Quick Add")), "includes custom quick add shortcut");

  const filteredEditor = filterKeybindings(defaultList, "editor");
  assert.ok(filteredEditor.length > 0, "finds editor references");

  const filteredNav = filterKeybindings(defaultList, "Navigation");
  assert.ok(filteredNav.every((item: any) => item.category === "Navigation" || item.desc.includes("Navigation") || item.key.includes("Navigation")));

  const emptySearch = filterKeybindings(defaultList, "");
  assert.equal(emptySearch.length, defaultList.length, "returns full list on empty search query");
});

test("getNextSection: handles forward and backward focus transitions", () => {
  assert.equal(getNextSection("profiles", 1), "input");
  assert.equal(getNextSection("input", 1), "tasks");
  assert.equal(getNextSection("tasks", 1), "footer");
  assert.equal(getNextSection("footer", 1), null);

  assert.equal(getNextSection("footer", -1), "tasks");
  assert.equal(getNextSection("tasks", -1), "input");
  assert.equal(getNextSection("input", -1), "profiles");
  assert.equal(getNextSection("profiles", -1), null);
});

test("getNextSubSection & getPrevSubSection: navigates expanded task drawer hierarchy", () => {
  // Forward without codebase
  assert.equal(getNextSubSection("header", false), "notes");
  assert.equal(getNextSubSection("notes", false), "reminders");
  assert.equal(getNextSubSection("reminders", false), "profiles");
  assert.equal(getNextSubSection("profiles", false), null);

  // Forward with codebase
  assert.equal(getNextSubSection("profiles", true), "codebase");
  assert.equal(getNextSubSection("codebase", true), null);

  // Backward
  assert.equal(getPrevSubSection("codebase"), "profiles");
  assert.equal(getPrevSubSection("profiles"), "reminders");
  assert.equal(getPrevSubSection("reminders"), "notes");
  assert.equal(getPrevSubSection("notes"), "header");
  assert.equal(getPrevSubSection("header"), null);
});

test("handleEscape: handles two-stage escape state machine", () => {
  let notesSaved = false;
  const mockRoot: any = {
    showKeyHelp: false,
    focusSection: "tasks",
    expandedSubSection: "notes",
    expandedTaskId: 101,
    expandedViaKeyboard: true,
    savePendingNotes: () => { notesSaved = true; }
  };

  // 1. In sub-section: Esc returns to header without closing drawer
  const handledSub = handleEscape(mockRoot);
  assert.equal(handledSub, true);
  assert.equal(mockRoot.expandedSubSection, "header");
  assert.equal(mockRoot.expandedTaskId, 101);

  // 2. In header: Esc collapses drawer and saves notes
  const handledCollapse = handleEscape(mockRoot);
  assert.equal(handledCollapse, true);
  assert.equal(mockRoot.expandedTaskId, -1);
  assert.equal(mockRoot.expandedViaKeyboard, false);
  assert.equal(notesSaved, true);

  // 3. When nothing expanded: returns false to let parent close panel
  const handledDismiss = handleEscape(mockRoot);
  assert.equal(handledDismiss, false);

  // 4. In help modal: closes help modal
  mockRoot.showKeyHelp = true;
  const handledHelp = handleEscape(mockRoot);
  assert.equal(handledHelp, true);
  assert.equal(mockRoot.showKeyHelp, false);
});

test("handleMove: 2D navigation across tasks, sub-sections, and sections", () => {
  let inputFocused = false;
  let releaseFocused = false;
  let visibleTaskIndex = -1;
  let reassignVisibleIndex = -1;

  const store = TodoStore.defaultStore();
  const storeWithTasks = TodoStore.addTodo(
    store,
    "Task 1",
    "Notes 1",
    "personal",
    null,
    { repo: "test/repo", localPath: "/path/to/repo" }
  );

  let reminderVisibleIndex = -1;
  let cycleFilterCallCount = 0;

  const mockRoot: any = {
    store: storeWithTasks,
    filteredTodos: storeWithTasks.todos,
    cursorIndex: 0,
    cursorActive: false,
    mouseMovementDetected: false,
    focusSection: "tasks",
    expandedTaskId: -1,
    expandedViaKeyboard: false,
    expandedSubSection: "header",
    expandedReminderIndex: 0,
    expandedProfileIndex: 0,
    reminderPresets: TodoStore.getReminderPresets(),
    footerButtonIndex: 0,
    focusInputField: () => { inputFocused = true; },
    releaseFocus: () => { releaseFocused = true; },
    ensureTaskVisible: (idx: number) => { visibleTaskIndex = idx; },
    ensureReassignProfileVisible: (idx: number) => { reassignVisibleIndex = idx; },
    ensureReminderVisible: (idx: number) => { reminderVisibleIndex = idx; },
    cycleProfileFilter: () => { cycleFilterCallCount++; }
  };

  // Navigating UP from task 0 transitions to input (normal mode)
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.focusSection, "input");
  assert.equal(releaseFocused, true);

  // Activating while on input triggers focusInputField
  handleActivate(mockRoot, TodoStore);
  assert.equal(inputFocused, true);

  // Navigating DOWN from profiles transitions to input (normal mode)
  mockRoot.focusSection = "profiles";
  inputFocused = false;
  releaseFocused = false;
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.focusSection, "input");
  assert.equal(releaseFocused, true);

  // Navigating inside expanded task
  const taskId = storeWithTasks.todos[0].id;
  mockRoot.focusSection = "tasks";
  mockRoot.cursorIndex = 0;
  mockRoot.expandedTaskId = taskId;
  mockRoot.expandedViaKeyboard = true;
  mockRoot.expandedSubSection = "header";

  // Down -> notes
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "notes");

  // Horizontal motion on notes should be isolated (no cycleProfileFilter)
  handleMove(mockRoot, 1, 0, TodoStore);
  handleMove(mockRoot, -1, 0, TodoStore);
  assert.equal(cycleFilterCallCount, 0, "dx on notes should not cycle profile filter");

  // Down -> reminders (scrolls to index 0)
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "reminders");
  assert.equal(mockRoot.expandedReminderIndex, 0);
  assert.equal(reminderVisibleIndex, 0);

  // Lateral motion on reminders scrolls chips
  handleMove(mockRoot, 1, 0, TodoStore);
  assert.equal(mockRoot.expandedReminderIndex, 1);
  assert.equal(reminderVisibleIndex, 1);

  // Down -> profiles
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "profiles");
  assert.ok(reassignVisibleIndex >= 0);

  // Down -> codebase (since task has localPath)
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "codebase");

  // Horizontal motion on codebase should be isolated
  handleMove(mockRoot, 1, 0, TodoStore);
  assert.equal(cycleFilterCallCount, 0, "dx on codebase should not cycle profile filter");

  // Up -> profiles
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "profiles");

  // Up -> reminders (ensures current reminder visible)
  reminderVisibleIndex = -1;
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "reminders");
  assert.equal(reminderVisibleIndex, 1);

  // Up -> notes
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "notes");

  // Up -> header
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.expandedSubSection, "header");
});

test("handleReturn & handleActivate: toggles drawer vs completion", () => {
  let toggledTaskId: any = null;
  const store = TodoStore.defaultStore();
  const storeWithTasks = TodoStore.addTodo(store, "Return Task", "", "personal");
  const task = storeWithTasks.todos[0];

  const mockRoot: any = {
    store: storeWithTasks,
    filteredTodos: storeWithTasks.todos,
    cursorIndex: 0,
    cursorActive: false,
    focusSection: "tasks",
    expandedTaskId: -1,
    expandedViaKeyboard: false,
    expandedSubSection: "header",
    toggleTodo: (id: any) => { toggledTaskId = id; },
    savePendingNotes: () => {}
  };

  // handleReturn expands task
  handleReturn(mockRoot, TodoStore);
  assert.equal(mockRoot.expandedTaskId, task.id);
  assert.equal(mockRoot.expandedViaKeyboard, true);
  assert.equal(toggledTaskId, null, "handleReturn does not toggle task completion");

  // handleReturn collapses task
  handleReturn(mockRoot, TodoStore);
  assert.equal(mockRoot.expandedTaskId, -1);
  assert.equal(mockRoot.expandedViaKeyboard, false);

  // handleActivate toggles completion
  mockRoot._suppressActivateOnReturn = false;
  handleActivate(mockRoot, TodoStore);
  assert.equal(toggledTaskId, task.id, "handleActivate toggles task completion");
});

test("handleTextKey: focuses notes and inserts character when on notes subsection", () => {
  let notesFocused = false;
  let insertedText = "";

  const mockRoot: any = {
    focusSection: "tasks",
    expandedSubSection: "notes",
    focusNotesEditor: () => {
      notesFocused = true;
      return true;
    },
    descArea: {
      textArea: {
        cursorPosition: 0,
        insert: (_pos: number, str: string) => {
          insertedText += str;
        }
      }
    }
  };

  // 'i' or 'a' focuses editor without typing character
  handleTextKey(mockRoot, "i");
  assert.equal(notesFocused, true);
  assert.equal(insertedText, "");

  // Any other text key focuses editor AND inserts character
  notesFocused = false;
  handleTextKey(mockRoot, "H");
  assert.equal(notesFocused, true);
  assert.equal(insertedText, "H");
});

test("handleMove & handleTextKey: navigation respects completed fold collapse", () => {
  const activeTask = { id: 1, title: "Active 1", done: false };
  const doneTask1 = { id: 2, title: "Done 1", done: true };
  const doneTask2 = { id: 3, title: "Done 2", done: true };
  const todos = [activeTask, doneTask1, doneTask2];

  const mockRoot: any = {
    filteredTodos: todos,
    cursorIndex: 0,
    cursorActive: true,
    focusSection: "tasks",
    footerButtonIndex: 0,
    completedFoldOpen: false,
    pendingCompletionIds: [],
    ensureTaskVisible: () => {}
  };

  // 1. Moving down from active task when fold is closed jumps directly to footer
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.focusSection, "footer");
  assert.equal(mockRoot.footerButtonIndex, 0);

  // 2. Moving up from footer when fold is closed lands on last active task (index 0)
  handleMove(mockRoot, 0, -1, TodoStore);
  assert.equal(mockRoot.focusSection, "tasks");
  assert.equal(mockRoot.cursorIndex, 0, "lands on last active task, not folded completed task");

  // 3. 'G' key when fold is closed targets last active task (index 0)
  mockRoot.cursorIndex = 0;
  handleTextKey(mockRoot, "G");
  assert.equal(mockRoot.cursorIndex, 0, "G jumps to last active task when fold is closed");

  // 4. When fold is open, navigation traverses into completed tasks
  mockRoot.completedFoldOpen = true;
  mockRoot.cursorIndex = 0;
  handleMove(mockRoot, 0, 1, TodoStore);
  assert.equal(mockRoot.focusSection, "tasks");
  assert.equal(mockRoot.cursorIndex, 1, "moves into completed task 1");

  handleTextKey(mockRoot, "G");
  assert.equal(mockRoot.cursorIndex, 2, "G jumps to last completed task when fold is open");
});

test("handleActivate & handleReturn: apply dynamic reminder on reminder sub-section", () => {
  let updatedTodoId = -1;
  let updatedFields: any = null;

  const task = { id: 42, title: "Reminder Task", done: false };
  const mockRoot: any = {
    filteredTodos: [task],
    cursorIndex: 0,
    cursorActive: true,
    focusSection: "tasks",
    expandedTaskId: 42,
    expandedSubSection: "reminders",
    expandedReminderIndex: 0, // +30m
    reminderPresets: TodoStore.getReminderPresets(),
    updateTodo: (id: number, fields: any) => {
      updatedTodoId = id;
      updatedFields = fields;
    }
  };

  const before = Date.now();
  handleActivate(mockRoot, TodoStore);
  const after = Date.now();

  assert.equal(updatedTodoId, 42);
  assert.ok(updatedFields && updatedFields.reminder);
  const reminderTime = new Date(updatedFields.reminder).getTime();
  assert.ok(reminderTime >= before + 30 * 60 * 1000 - 500);
  assert.ok(reminderTime <= after + 30 * 60 * 1000 + 500);
});


