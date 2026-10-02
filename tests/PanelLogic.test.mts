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
  handleKeyRelease,
  handleTextKey,
  DEFAULT_BINDINGS,
  normalizeKey,
  resolveBindings
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
  assert.ok(defaultList.some((item: any) => item.key === "r / F2" && item.desc.includes("Edit title")), "includes r / F2 title edit shortcut");

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

  // 5. While editing title: Esc cancels editing without closing drawer or panel
  let editingCancelled = false;
  mockRoot.editingTaskId = 101;
  mockRoot.cancelEditingTask = () => {
    editingCancelled = true;
    mockRoot.editingTaskId = -1;
  };
  const handledEditCancel = handleEscape(mockRoot);
  assert.equal(handledEditCancel, true);
  assert.equal(editingCancelled, true);
  assert.equal(mockRoot.editingTaskId, -1);
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

test("handleTextKey: 'r' / 'F2' triggers title editing on focused task", () => {
  let startedEditingTaskId: any = null;

  const mockRoot: any = {
    focusSection: "tasks",
    cursorIndex: 0,
    cursorActive: true,
    filteredTodos: [{ id: 42, title: "Sample task", done: false }],
    expandedTaskId: -1,
    expandedSubSection: "header",
    startEditingTask: (id: any) => {
      startedEditingTaskId = id;
    }
  };

  // 1. Pressing 'r' on collapsed task triggers editing
  handleTextKey(mockRoot, "r", TodoStore);
  assert.equal(startedEditingTaskId, 42);

  // 2. While editing, other text keys are ignored
  startedEditingTaskId = null;
  mockRoot.editingTaskId = 42;
  handleTextKey(mockRoot, "j", TodoStore);
  assert.equal(startedEditingTaskId, null);

  // 3. Pressing 'r' while expanded on header triggers editing
  mockRoot.editingTaskId = -1;
  mockRoot.expandedTaskId = 42;
  mockRoot.expandedSubSection = "header";
  handleTextKey(mockRoot, "r", TodoStore);
  assert.equal(startedEditingTaskId, 42);

  // 4. Pressing 'r' while on reminders does not trigger editing
  startedEditingTaskId = null;
  mockRoot.expandedSubSection = "reminders";
  handleTextKey(mockRoot, "r", TodoStore);
  assert.equal(startedEditingTaskId, null);
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

test("handleTextKey: 'c' / 'C' triggers startClearHold when available or clearCompleted fallback", () => {
  let clearedFilter: string | null = null;
  let holdStarted = false;
  const mockRoot: any = {
    focusSection: "tasks",
    currentFilter: "work",
    clearCompleted: (filter: string) => {
      clearedFilter = filter;
    }
  };

  // Fallback when startClearHold is not provided
  handleTextKey(mockRoot, "c");
  assert.equal(clearedFilter, "work");

  // Uses startClearHold when provided
  mockRoot.startClearHold = () => {
    holdStarted = true;
  };
  handleTextKey(mockRoot, "c");
  assert.equal(holdStarted, true);
});

test("handleDelete: triggers startDeleteHold when available or removeTodo fallback", () => {
  let removedId: number | null = null;
  let deleteHoldId: number | null = null;
  const mockRoot: any = {
    focusSection: "tasks",
    cursorIndex: 0,
    filteredTodos: [{ id: 42, title: "Test task" }],
    removeTodo: (id: number) => {
      removedId = id;
    }
  };

  // Direct fallback
  handleDelete(mockRoot);
  assert.equal(removedId, 42);

  // Uses startDeleteHold when provided
  mockRoot.startDeleteHold = (id: number) => {
    deleteHoldId = id;
  };
  handleDelete(mockRoot);
  assert.equal(deleteHoldId, 42);
});

test("handleKeyRelease: stops active holds for x, c, and footer action", () => {
  let stopDeleteCalled = false;
  let stopClearCalled = false;
  const mockRoot: any = {
    focusSection: "tasks",
    stopDeleteHold: () => {
      stopDeleteCalled = true;
    },
    stopClearHold: () => {
      stopClearCalled = true;
    }
  };

  handleKeyRelease(mockRoot, "x");
  assert.equal(stopDeleteCalled, true);

  handleKeyRelease(mockRoot, "c");
  assert.equal(stopClearCalled, true);

  stopClearCalled = false;
  mockRoot.focusSection = "footer";
  mockRoot.footerButtonIndex = 0;
  handleKeyRelease(mockRoot, "action");
  assert.equal(stopClearCalled, true);
});

test("footer activation: Space and Enter on button 0 trigger clearCompleted", () => {
  let triggeredIndex = -1;
  const mockRoot: any = {
    focusSection: "footer",
    footerButtonIndex: 0,
    cursorActive: true,
    triggerFooterButton: (idx: number) => {
      triggeredIndex = idx;
    }
  };

  // Space (handleActivate)
  handleActivate(mockRoot, TodoStore);
  assert.equal(triggeredIndex, 0);

  // Enter (handleReturn)
  triggeredIndex = -1;
  handleReturn(mockRoot, TodoStore);
  assert.equal(triggeredIndex, 0);
});

test("search activation & keybindings: '/' triggers search, and catalog lists '/ / Ctrl+F'", () => {
  let searchActivated = false;
  let focusedInput = false;

  const mockRoot: any = {
    focusSection: "tasks",
    cursorActive: true,
    activateSearch: () => {
      searchActivated = true;
    },
    focusInputField: () => {
      focusedInput = true;
    }
  };

  // '/' triggers activateSearch
  handleTextKey(mockRoot, "/");
  assert.equal(searchActivated, true);
  assert.equal(focusedInput, false);

  // 'i' and 'a' still focus new task input
  searchActivated = false;
  handleTextKey(mockRoot, "i");
  assert.equal(focusedInput, true);
  assert.equal(searchActivated, false);

  // Keybindings catalog includes '/ / Ctrl+F'
  const list = getKeybindingsList();
  const searchItem = list.find((item: any) => item.key === "/ / Ctrl+F");
  assert.ok(searchItem, "Catalog must list '/ / Ctrl+F'");
  assert.equal(searchItem.desc, "Search tasks, notes & profiles");
});

test("handleEscape: two-stage escape for in-panel search", () => {
  let clearedTextCalled = false;
  let closedSearchCalled = false;

  const mockRoot: any = {
    expandedTaskId: -1,
    searchActive: true,
    searchQuery: "auth flow",
    clearSearchText: () => {
      clearedTextCalled = true;
    },
    closeSearch: () => {
      closedSearchCalled = true;
    }
  };

  // Stage 1: non-empty query clears search query
  const res1 = handleEscape(mockRoot);
  assert.equal(res1, true);
  assert.equal(mockRoot.searchQuery, "");
  assert.equal(clearedTextCalled, true);
  assert.equal(closedSearchCalled, false);

  // Stage 2: empty query collapses search bar
  const res2 = handleEscape(mockRoot);
  assert.equal(res2, true);
  assert.equal(closedSearchCalled, true);
});

test("normalizeKey: standardizes key representation and aliases", () => {
  assert.equal(normalizeKey("escape"), "Escape");
  assert.equal(normalizeKey("Esc"), "Escape");
  assert.equal(normalizeKey("space"), "Space");
  assert.equal(normalizeKey("return"), "Return");
  assert.equal(normalizeKey("enter"), "Return");
  assert.equal(normalizeKey("ctrl+f"), "Ctrl+F");
  assert.equal(normalizeKey("control+f"), "Ctrl+F");
  assert.equal(normalizeKey("up"), "Up");
  assert.equal(normalizeKey("down"), "Down");
  assert.equal(normalizeKey("left"), "Left");
  assert.equal(normalizeKey("right"), "Right");
  assert.equal(normalizeKey("o"), "o");
  assert.equal(normalizeKey("O"), "O");
});

test("resolveBindings: defaults match DEFAULT_BINDINGS and fall back safely", () => {
  const resolved = resolveBindings({});
  assert.deepEqual(resolved.bindings.next_task, ["j", "Down"]);
  assert.deepEqual(resolved.bindings.prev_task, ["k", "Up"]);
  assert.deepEqual(resolved.bindings.focus_input, ["i", "a"]);
  assert.deepEqual(resolved.bindings.open_editor, ["e"]);
  assert.equal(resolved.keyToAction["j"], "next_task");
  assert.equal(resolved.keyToAction["k"], "prev_task");
  assert.equal(resolved.keyToAction["i"], "focus_input");
  assert.equal(resolved.keyToAction["e"], "open_editor");
});

test("resolveBindings: custom overrides and alias normalization", () => {
  const resolved = resolveBindings({
    open_editor: "o",
    jump_top: ["t", "home"],
    search: "ctrl+s",
    unknown_action: "z"
  });
  assert.deepEqual(resolved.bindings.open_editor, ["o"]);
  assert.deepEqual(resolved.bindings.jump_top, ["t", "Home"]);
  assert.deepEqual(resolved.bindings.search, ["Ctrl+S"]);
  assert.equal(resolved.keyToAction["o"], "open_editor");
  assert.equal(resolved.keyToAction["t"], "jump_top");
  assert.equal(resolved.keyToAction["Home"], "jump_top");
  assert.equal(resolved.keyToAction["Ctrl+S"], "search");
  // Default for unaffected actions remains
  assert.deepEqual(resolved.bindings.next_task, ["j", "Down"]);
});

test("resolveBindings: invariant protection rejects remapping Escape", () => {
  const resolved = resolveBindings({
    open_editor: "Escape",
    delete_task: "esc"
  });
  // Escape must not be bound to open_editor or delete_task
  assert.notEqual(resolved.bindings.open_editor, ["Escape"]);
  assert.notEqual(resolved.bindings.delete_task, ["Escape"]);
  assert.equal(resolved.keyToAction["Escape"], undefined);
});

test("handleTextKey: respects active custom bindings", () => {
  let editorOpened = false;
  let openedTaskId = null;
  const mockRoot: any = {
    focusSection: "tasks",
    cursorIndex: 0,
    filteredTodos: [{ id: 42, title: "Test" }],
    openEditor: (id: any) => {
      editorOpened = true;
      openedTaskId = id;
    }
  };

  const customBindings = resolveBindings({
    open_editor: "o"
  });

  // Default 'e' is no longer bound to open_editor if overridden
  handleTextKey(mockRoot, "e", TodoStore, customBindings);
  assert.equal(editorOpened, false);

  // 'o' triggers openEditor
  handleTextKey(mockRoot, "o", TodoStore, customBindings);
  assert.equal(editorOpened, true);
  assert.equal(openedTaskId, 42);
});

test("getKeybindingsList: formats custom keys in catalog dynamically", () => {
  const customBindings = resolveBindings({
    open_editor: "o",
    next_task: "Down",
    search: "Ctrl+S"
  });

  const list = getKeybindingsList("SUPER + ALT + T", "SUPER + SHIFT + T", customBindings);
  const editorItem = list.find((item: any) => item.desc.includes("todos.json"));
  assert.ok(editorItem);
  assert.equal(editorItem.key, "o");

  const searchItem = list.find((item: any) => item.desc.includes("Search tasks"));
  assert.ok(searchItem);
  assert.ok(searchItem.key.includes("Ctrl+S"));
});


