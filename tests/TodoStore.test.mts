import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const TodoStore = require("../TodoStore.js");

const {
  defaultStore,
  cleanProfileName,
  normalizeTask,
  normalize,
  parseTitleAndProfile,
  cloneStore,
  addTodo,
  toggleTodo,
  removeTodo,
  updateTodo,
  addProfile,
  removeProfile,
  clearCompleted,
  getPendingCount,
  getFilteredTodos,
  getSortedProfiles,
  isOverdue,
  pendingReminders,
  formatReminder,
  getProfileGlyph,
  getReminderPresets,
  normalizeArchive,
  archiveCompleted,
  getArchivedCount,
  formatKeybind,
  formatRelativeDiff,
  getTaskUrgencyBreakdown,
  makeProgressBar,
  markTasksNotified,
  capitalizeTitle
} = TodoStore;

test("defaultStore: initializes schema v1 default structure", () => {
  const store = defaultStore();
  assert.equal(store.version, 1);
  assert.equal(store.activeProfile, "personal");
  assert.deepEqual(store.profiles, ["personal", "work"]);
  assert.deepEqual(store.todos, []);
});

test("cleanProfileName: handles formatting and aliases", () => {
  assert.equal(cleanProfileName("Work"), "work");
  assert.equal(cleanProfileName("#Work"), "work");
  assert.equal(cleanProfileName("##study_plan!"), "study_plan");
  assert.equal(cleanProfileName("perso"), "personal");
  assert.equal(cleanProfileName("#perso"), "personal");
  assert.equal(cleanProfileName(""), "personal");
  assert.equal(cleanProfileName(null), "personal");
  assert.equal(cleanProfileName(undefined), "personal");
});

test("parseTitleAndProfile: parses hashtag syntax and preserves title", () => {
  // Hashtag at start
  const res1 = parseTitleAndProfile("#work Review pull request", "personal");
  assert.equal(res1.title, "Review pull request");
  assert.equal(res1.profile, "work");

  // Hashtag at end
  const res2 = parseTitleAndProfile("Buy milk #shopping", "personal");
  assert.equal(res2.title, "Buy milk");
  assert.equal(res2.profile, "shopping");

  // Hashtag with space (# work)
  const res3 = parseTitleAndProfile("# work Clean room", "personal");
  assert.equal(res3.title, "Clean room");
  assert.equal(res3.profile, "work");

  // Perso alias mapping
  const res4 = parseTitleAndProfile("#perso Workout routine", "work");
  assert.equal(res4.title, "Workout routine");
  assert.equal(res4.profile, "personal");

  // No hashtag: falls back to default profile
  const res5 = parseTitleAndProfile("Simple task", "work");
  assert.equal(res5.title, "Simple task");
  assert.equal(res5.profile, "work");
});

test("addTodo: adds task and updates profiles dynamically", () => {
  let store = defaultStore();
  store = addTodo(store, "Call bank #finances", "urgent notes", null, null);

  assert.equal(store.todos.length, 1);
  const task = store.todos[0];
  assert.equal(task.title, "Call bank");
  assert.equal(task.description, "urgent notes");
  assert.equal(task.profile, "finances");
  assert.equal(task.done, false);
  assert.ok(store.profiles.includes("finances"));

  // Ignores empty title
  const store2 = addTodo(store, "   ", "", null, null);
  assert.equal(store2.todos.length, 1);
});

test("toggleTodo: toggles done status and manages reminder notification reset", () => {
  let store = defaultStore();
  const futureReminder = new Date(Date.now() + 3600000).toISOString();
  store = addTodo(store, "Meeting", "", "work", futureReminder);
  const taskId = store.todos[0].id;

  // Mark task as done
  store = toggleTodo(store, taskId);
  assert.equal(store.todos[0].done, true);

  // Mark task as undone: future reminder should reset notified to false
  store.todos[0].notified = true;
  store = toggleTodo(store, taskId);
  assert.equal(store.todos[0].done, false);
  assert.equal(store.todos[0].notified, false);
});

test("removeTodo: removes task by id", () => {
  let store = defaultStore();
  store = addTodo(store, "Task 1", "", "personal", null);
  store = addTodo(store, "Task 2", "", "personal", null);
  assert.equal(store.todos.length, 2);

  const idToRemove = store.todos[0].id;
  store = removeTodo(store, idToRemove);
  assert.equal(store.todos.length, 1);
  assert.equal(store.todos[0].title, "Task 1");
});

test("updateTodo: edits task properties and updates profile if changed", () => {
  let store = defaultStore();
  store = addTodo(store, "Original title", "Original desc", "personal", null);
  const taskId = store.todos[0].id;

  store = updateTodo(store, taskId, {
    title: "Updated title",
    description: "New desc",
    profile: "work",
    reminder: "2026-10-01T10:00:00Z"
  });

  const updated = store.todos[0];
  assert.equal(updated.title, "Updated title");
  assert.equal(updated.description, "New desc");
  assert.equal(updated.profile, "work");
  assert.equal(updated.reminder, "2026-10-01T10:00:00Z");
  assert.equal(updated.notified, false);
});

test("addProfile & removeProfile: profile lifecycle and protected personal default", () => {
  let store = defaultStore();
  store = addProfile(store, "travel");
  assert.ok(store.profiles.includes("travel"));

  store = addTodo(store, "Pack bags", "", "travel", null);
  store.activeProfile = "travel";

  // Removing "travel" reassigns tasks and activeProfile to "personal"
  store = removeProfile(store, "travel");
  assert.ok(!store.profiles.includes("travel"));
  assert.equal(store.todos[0].profile, "personal");
  assert.equal(store.activeProfile, "personal");

  // Attempting to remove "personal" is blocked
  store = removeProfile(store, "personal");
  assert.ok(store.profiles.includes("personal"));
});

test("clearCompleted: clears completed tasks per profile or all", () => {
  let store = defaultStore();
  store = addTodo(store, "Task 1", "", "personal", null);
  store = addTodo(store, "Task 2", "", "work", null);
  store = toggleTodo(store, store.todos[0].id); // Task 2 done (work)
  store = toggleTodo(store, store.todos[1].id); // Task 1 done (personal)

  // Clear only personal
  store = clearCompleted(store, "personal");
  assert.equal(store.todos.length, 1);
  assert.equal(store.todos[0].profile, "work");

  // Clear all
  store = clearCompleted(store, "all");
  assert.equal(store.todos.length, 0);
});

test("getPendingCount & getFilteredTodos: counts and filters tasks correctly", () => {
  let store = defaultStore();
  store = addTodo(store, "Personal task 1", "", "personal", null);
  store = addTodo(store, "Personal task 2", "", "personal", null);
  store = addTodo(store, "Work task 1", "", "work", null);

  // Complete one personal task
  store = toggleTodo(store, store.todos[1].id);

  assert.equal(getPendingCount(store, "all"), 2);
  assert.equal(getPendingCount(store, "personal"), 1);
  assert.equal(getPendingCount(store, "work"), 1);

  assert.equal(getFilteredTodos(store, "all").length, 3);
  assert.equal(getFilteredTodos(store, "personal").length, 2);
  assert.equal(getFilteredTodos(store, "work").length, 1);
});

test("pendingReminders: triggers only for due, unnotified, incomplete tasks", () => {
  let store = defaultStore();
  const pastReminder = new Date(Date.now() - 60000).toISOString();
  const futureReminder = new Date(Date.now() + 600000).toISOString();

  store = addTodo(store, "Due task", "", "personal", pastReminder);
  store = addTodo(store, "Future task", "", "personal", futureReminder);
  store = addTodo(store, "Done past task", "", "personal", pastReminder);
  store = toggleTodo(store, store.todos[0].id); // Mark "Done past task" as done

  const due = pendingReminders(store);
  assert.equal(due.length, 1);
  assert.equal(due[0].title, "Due task");
});

test("formatReminder: formats relative time descriptions", () => {
  assert.equal(formatReminder(null), "");
  assert.equal(formatReminder("invalid-date"), "");

  const now = new Date();
  const todayLater = new Date(now.getTime() + 7200000).toISOString(); // +2h
  const formattedToday = formatReminder(todayLater);
  assert.ok(formattedToday.startsWith("Today"));

  const tomorrow = new Date(now.getTime() + 86400000).toISOString();
  const formattedTomorrow = formatReminder(tomorrow);
  assert.ok(formattedTomorrow.startsWith("Tomorrow") || formattedTomorrow.startsWith("Due"));
});

test("getProfileGlyph: returns expected icons", () => {
  assert.equal(getProfileGlyph("personal"), "󰀉");
  assert.equal(getProfileGlyph("work"), "󰈚");
  assert.equal(getProfileGlyph("shopping"), "󰄞");
  assert.equal(getProfileGlyph("custom_tag"), "󰲉");
});

test("getReminderPresets: returns 4 valid presets", () => {
  const presets = getReminderPresets();
  assert.equal(presets.length, 4);
  for (const preset of presets) {
    assert.ok(preset.label);
    assert.ok(!isNaN(new Date(preset.value).getTime()));
  }
});

test("normalize: migrates legacy array format and invalid inputs to Schema v1", () => {
  // Invalid string input
  assert.equal(normalize("invalid json").version, 1);
  assert.equal(normalize(null).version, 1);

  // Legacy array format
  const legacyData = [
    { text: "Old task 1", done: false, profile: "hobby" },
    { text: "Old task 2", done: true, profile: "work" }
  ];
  const migrated = normalize(JSON.stringify(legacyData));
  assert.equal(migrated.version, 1);
  assert.equal(migrated.todos.length, 2);
  assert.equal(migrated.todos[0].title, "Old task 1");
  assert.ok(migrated.profiles.includes("hobby"));
  assert.ok(migrated.profiles.includes("personal"));
  assert.ok(migrated.profiles.includes("work"));
});

test("archiveCompleted & normalizeArchive: archives completed tasks with completedAt timestamps", () => {
  let store = defaultStore();
  store = addTodo(store, "Active task", "", "personal", null);
  store = addTodo(store, "Done task 1", "note 1", "work", null);
  store = addTodo(store, "Done task 2", "note 2", "personal", null);

  // Mark 2 tasks as done
  store = toggleTodo(store, store.todos[0].id);
  store = toggleTodo(store, store.todos[1].id);

  // Archive only personal completed tasks
  const emptyArchive = JSON.stringify({ version: 1, archived: [] });
  const res1 = archiveCompleted(store, "personal", emptyArchive);

  assert.equal(res1.clearedCount, 1);
  assert.equal(res1.updatedStore.todos.length, 2); // 1 active, 1 work done remaining
  assert.equal(res1.updatedArchive.archived.length, 1);
  assert.equal(res1.updatedArchive.archived[0].title, "Done task 2");
  assert.ok(typeof res1.updatedArchive.archived[0].completedAt === "number");

  // Archive all remaining
  const res2 = archiveCompleted(res1.updatedStore, "all", JSON.stringify(res1.updatedArchive));
  assert.equal(res2.clearedCount, 1);
  assert.equal(res2.updatedStore.todos.length, 1); // Only active task left
  assert.equal(res2.updatedArchive.archived.length, 2);

  // Check getArchivedCount
  assert.equal(getArchivedCount(JSON.stringify(res2.updatedArchive)), 2);
});

test("addTodo & updateTodo: tracks updatedAt timestamp", () => {
  let store = defaultStore();
  store = addTodo(store, "New task", "desc", "personal", null);
  const task = store.todos[0];
  assert.ok(typeof task.createdAt === "number");
  assert.ok(typeof task.updatedAt === "number");
  assert.equal(task.updatedAt, task.createdAt);

  const beforeUpdate = task.updatedAt;
  // Explicitly update with custom updatedAt or let it advance
  store = updateTodo(store, task.id, { title: "Updated task", updatedAt: beforeUpdate + 1000 });
  assert.equal(store.todos[0].title, "Updated task");
  assert.equal(store.todos[0].updatedAt, beforeUpdate + 1000);
});

test("getSortedProfiles: sorts descending by pending task count", () => {
  let store = defaultStore();
  // 3 tasks in work, 1 in shopping, 2 in personal
  store = addTodo(store, "Work 1", "", "work", null);
  store = addTodo(store, "Work 2", "", "work", null);
  store = addTodo(store, "Work 3", "", "work", null);
  store = addTodo(store, "Pers 1", "", "personal", null);
  store = addTodo(store, "Pers 2", "", "personal", null);
  store = addTodo(store, "Shop 1", "", "shopping", null);

  const sorted = getSortedProfiles(store, false);
  assert.deepEqual(sorted, ["work", "personal", "shopping"]);
});

test("getSortedProfiles: breaks pending count ties by latest task activity timestamp", () => {
  let store = defaultStore();
  // Both work and personal have 1 pending task, but work was updated later
  store = addTodo(store, "Pers 1", "", "personal", null);
  store.todos[0].createdAt = 1000;
  store.todos[0].updatedAt = 1000;

  store = addTodo(store, "Work 1", "", "work", null);
  store.todos[0].createdAt = 2000;
  store.todos[0].updatedAt = 5000;

  const sorted = getSortedProfiles(store, false);
  assert.deepEqual(sorted, ["work", "personal"]);

  // If personal gets updated with newer timestamp, it moves to the top
  store = updateTodo(store, store.todos[1].id, { updatedAt: 8000 });
  const sortedAfterUpdate = getSortedProfiles(store, false);
  assert.deepEqual(sortedAfterUpdate, ["personal", "work"]);
});

test("getSortedProfiles: alphabetical fallback when pending count and recency are equal", () => {
  let store = defaultStore();
  // Both have 0 tasks and 0 recency
  store.profiles = ["zebra", "apple", "banana"];
  store.todos = [];

  const sorted = getSortedProfiles(store, false);
  assert.deepEqual(sorted, ["apple", "banana", "zebra"]);
});

test("getSortedProfiles: onlyActive filters out empty profiles unless matching currentFilter or activeProfile", () => {
  let store = defaultStore();
  store.profiles = ["personal", "work", "shopping", "gaming"];
  store.activeProfile = "personal"; // 0 tasks, but is activeProfile
  store.todos = [];

  // Add tasks only to work
  store = addTodo(store, "Work task 1", "", "work", null);
  store = addTodo(store, "Work task 2", "", "work", null);

  // With currentFilter = "all", returns work (count > 0) and personal (activeProfile)
  const sortedAll = getSortedProfiles(store, true, "all");
  assert.ok(sortedAll.includes("work"));
  assert.ok(sortedAll.includes("personal"));
  assert.ok(!sortedAll.includes("shopping"));
  assert.ok(!sortedAll.includes("gaming"));
  assert.equal(sortedAll[0], "work"); // work has count 2, personal has count 0

  // With currentFilter = "gaming", gaming is kept despite having 0 tasks
  const sortedGaming = getSortedProfiles(store, true, "gaming");
  assert.ok(sortedGaming.includes("gaming"));
  assert.ok(sortedGaming.includes("work"));
  assert.ok(sortedGaming.includes("personal"));
  assert.ok(!sortedGaming.includes("shopping"));

  // Fallback when completely empty store
  const emptyStore = { version: 1, activeProfile: "custom", profiles: [], todos: [] };
  const fallback = getSortedProfiles(emptyStore, true, "");
  assert.deepEqual(fallback, ["custom"]);
});

test("isOverdue: correctly identifies overdue incomplete tasks", () => {
  const pastIso = new Date(Date.now() - 3600 * 1000).toISOString();
  const futureIso = new Date(Date.now() + 3600 * 1000).toISOString();

  assert.equal(isOverdue(null), false);
  assert.equal(isOverdue({ id: 1, title: "No reminder", done: false, reminder: null }), false);
  assert.equal(isOverdue({ id: 2, title: "Done task", done: true, reminder: pastIso }), false);
  assert.equal(isOverdue({ id: 3, title: "Future task", done: false, reminder: futureIso }), false);
  assert.equal(isOverdue({ id: 4, title: "Overdue task", done: false, reminder: pastIso }), true);
});

test("formatKeybind: formats Hyprland bitmasks and keys into readable shortcut strings", () => {
  // Single modifier
  assert.equal(formatKeybind(64, "T"), "SUPER + T");
  assert.equal(formatKeybind(4, "T"), "CTRL + T");
  assert.equal(formatKeybind(8, "T"), "ALT + T");
  assert.equal(formatKeybind(1, "T"), "SHIFT + T");

  // Combinations
  assert.equal(formatKeybind(65, "T"), "SUPER + SHIFT + T");
  assert.equal(formatKeybind(68, "T"), "SUPER + CTRL + T");
  assert.equal(formatKeybind(72, "T"), "SUPER + ALT + T");
  assert.equal(formatKeybind(73, "T"), "SUPER + ALT + SHIFT + T");
  assert.equal(formatKeybind(77, "T"), "SUPER + CTRL + ALT + SHIFT + T");

  // No modifiers
  assert.equal(formatKeybind(0, "T"), "T");
  assert.equal(formatKeybind(0, "space"), "SPACE");

  // Lowercase key conversion and whitespace trimming
  assert.equal(formatKeybind(65, "t"), "SUPER + SHIFT + T");
  assert.equal(formatKeybind(64, " return "), "SUPER + RETURN");

  // Missing or empty arguments
  assert.equal(formatKeybind(null, "T"), "T");
  assert.equal(formatKeybind(undefined, "t"), "T");
  assert.equal(formatKeybind(64, ""), "SUPER");
  assert.equal(formatKeybind(0, ""), "");
});

test("formatRelativeDiff: formats past and future time durations", () => {
  // Past (overdue)
  assert.equal(formatRelativeDiff(10 * 1000, true), "just now");
  assert.equal(formatRelativeDiff(45 * 60 * 1000, true), "45m overdue");
  assert.equal(formatRelativeDiff(2 * 3600 * 1000, true), "2h overdue");
  assert.equal(formatRelativeDiff(3 * 86400 * 1000, true), "3d overdue");

  // Future
  assert.equal(formatRelativeDiff(20 * 1000, false), "in <1m");
  assert.equal(formatRelativeDiff(30 * 60 * 1000, false), "in 30m");
  assert.equal(formatRelativeDiff(5 * 3600 * 1000, false), "in 5h");
  assert.equal(formatRelativeDiff(2 * 86400 * 1000, false), "in 2d");
});

test("getTaskUrgencyBreakdown: categorizes tasks by urgency and extracts closest diffs", () => {
  // Empty or invalid store
  assert.deepEqual(getTaskUrgencyBreakdown(null), {
    total: 0,
    overdue: 0,
    dueToday: 0,
    upcoming: 0,
    noReminder: 0,
    earliestOverdueDiff: "",
    nextDueDiff: ""
  });

  const now = new Date("2026-09-21T12:00:00.000Z").getTime();

  const store = {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal"],
    todos: [
      // Overdue 2 hours ago (earliest overdue)
      { id: 1, title: "T1", done: false, reminder: new Date(now - 2 * 3600 * 1000).toISOString() },
      // Overdue 30 mins ago
      { id: 2, title: "T2", done: false, reminder: new Date(now - 30 * 60 * 1000).toISOString() },
      // Due today in 1 hour (next due)
      { id: 3, title: "T3", done: false, reminder: new Date(now + 1 * 3600 * 1000).toISOString() },
      // Due tomorrow (upcoming)
      { id: 4, title: "T4", done: false, reminder: new Date(now + 30 * 3600 * 1000).toISOString() },
      // No reminder
      { id: 5, title: "T5", done: false, reminder: null },
      // Done task with past reminder (must be ignored)
      { id: 6, title: "T6", done: true, reminder: new Date(now - 5 * 3600 * 1000).toISOString() }
    ]
  };

  const breakdown = getTaskUrgencyBreakdown(store, now);
  assert.equal(breakdown.total, 5);
  assert.equal(breakdown.overdue, 2);
  assert.equal(breakdown.dueToday, 1);
  assert.equal(breakdown.upcoming, 1);
  assert.equal(breakdown.noReminder, 1);
  assert.equal(breakdown.earliestOverdueDiff, "2h overdue");
  assert.equal(breakdown.nextDueDiff, "in 1h");
});

test("makeProgressBar: renders visual progress block bars", () => {
  assert.equal(makeProgressBar(0, 0), "[░░░░░░░░]");
  assert.equal(makeProgressBar(0, 10), "[░░░░░░░░]");
  assert.equal(makeProgressBar(5, 10), "[████░░░░]");
  assert.equal(makeProgressBar(10, 10), "[████████]");
  assert.equal(makeProgressBar(1, 4, 4), "[█░░░]");
});

test("updateTodo: correctly updates notified flag and resets on new reminder", () => {
  const pastIso = new Date(Date.now() - 3600 * 1000).toISOString();
  let store = defaultStore();
  store = addTodo(store, "Test task", "", "personal", pastIso);
  const taskId = store.todos[0].id;
  assert.equal(store.todos[0].notified, false);

  // Update notified flag
  store = updateTodo(store, taskId, { notified: true });
  assert.equal(store.todos[0].notified, true);

  // When changing reminder, notified must reset to false
  const futureIso = new Date(Date.now() + 7200 * 1000).toISOString();
  store = updateTodo(store, taskId, { reminder: futureIso });
  assert.equal(store.todos[0].notified, false);
});

test("markTasksNotified: batch updates notified flag for multiple tasks", () => {
  let store = defaultStore();
  store = addTodo(store, "Task 1", "", "personal", "2026-09-21T10:00:00.000Z");
  store = addTodo(store, "Task 2", "", "personal", "2026-09-21T10:00:00.000Z");
  store = addTodo(store, "Task 3", "", "personal", "2026-09-21T10:00:00.000Z");

  const id1 = store.todos[0].id;
  const id3 = store.todos[2].id;

  const updated = markTasksNotified(store, [id1, id3]);
  assert.equal(updated.todos.find(t => t.id === id1)?.notified, true);
  assert.equal(updated.todos.find(t => t.id === store.todos[1].id)?.notified, false);
  assert.equal(updated.todos.find(t => t.id === id3)?.notified, true);
});

test("reminder loop prevention: pendingReminders never returns notified tasks", () => {
  const pastIso = new Date(Date.now() - 1800 * 1000).toISOString();
  let store = defaultStore();
  store = addTodo(store, "Overdue 1", "", "personal", pastIso);
  store = addTodo(store, "Overdue 2", "", "personal", pastIso);

  // Initially both are due
  const due = pendingReminders(store);
  assert.equal(due.length, 2);

  // After marking notified, pendingReminders must return 0, breaking any infinite loop
  const notifiedStore = markTasksNotified(store, due.map(t => t.id));
  const remainingDue = pendingReminders(notifiedStore);
  assert.equal(remainingDue.length, 0);
});

test("capitalizeTitle: capitalizes first letter and handles symbols/whitespace cleanly", () => {
  assert.equal(capitalizeTitle(""), "");
  assert.equal(capitalizeTitle(null), "");
  assert.equal(capitalizeTitle(undefined), "");
  assert.equal(capitalizeTitle("capitalize item title"), "Capitalize item title");
  assert.equal(capitalizeTitle("already Capitalized"), "Already Capitalized");
  assert.equal(capitalizeTitle("  spaced text"), "  Spaced text");
  assert.equal(capitalizeTitle("#hashtag first"), "#hashtag first");
  assert.equal(capitalizeTitle("123 numbers"), "123 numbers");
  assert.equal(capitalizeTitle("npm run check"), "Npm run check");
});


