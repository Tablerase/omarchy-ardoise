import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const TodoStore = require("../TodoStore.js");

const {
  CURRENT_SCHEMA_VERSION,
  CURRENT_ARCHIVE_VERSION,
  defaultStore,
  cleanProfileName,
  normalizeTask,
  normalizeLocation,
  normalize,
  parseTitleAndProfile,
  parseTaskInput,
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
  compareTasks,
  getSortedProfiles,
  isOverdue,
  pendingReminders,
  formatReminder,
  getProfileGlyph,
  getReminderPresets,
  computePresetReminder,
  normalizeArchive,
  archiveCompleted,
  getArchivedCount,
  formatKeybind,
  formatRelativeDiff,
  getTaskUrgencyBreakdown,
  getArdoiseIconState,
  ardoiseIconStateForKey,
  makeProgressBar,
  markTasksNotified,
  capitalizeTitle,
  mergeStores,
  mergeArchives,
  filterMissingTasks
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

test("updateTodo: title editing validates non-empty and parses embedded hashtags", () => {
  let store = defaultStore();
  store = addTodo(store, "Original title", "Notes", "personal", null);
  const taskId = store.todos[0].id;

  // 1. Empty or whitespace title is rejected (preserves existing title)
  store = updateTodo(store, taskId, { title: "   " });
  assert.equal(store.todos[0].title, "Original title");

  // 2. Simple title rename with trimming and capitalization
  store = updateTodo(store, taskId, { title: "  renamed task title  " });
  assert.equal(store.todos[0].title, "Renamed task title");

  // 3. Embedded hashtag in title renames title and updates profile
  store = updateTodo(store, taskId, { title: "#projects Build widget" });
  assert.equal(store.todos[0].title, "Build widget");
  assert.equal(store.todos[0].profile, "projects");
  assert.ok(store.profiles.includes("projects"));

  // 4. Embedded repo and tags in title
  store = updateTodo(store, taskId, { title: "#projects/my-repo Fix bug" });
  assert.equal(store.todos[0].title, "Fix bug");
  assert.equal(store.todos[0].profile, "projects");
  assert.equal(store.todos[0].repo, "my-repo");
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
  assert.match(formattedToday, /^\d{2}:\d{2}$/);

  // Past reminder today should also format as only time (e.g. "10:30")
  const todayEarlier = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 9, 30).toISOString();
  assert.equal(formatReminder(todayEarlier), "09:30");

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

test("getReminderPresets: returns 4 valid presets and dynamically respects baseDate", () => {
  const presets = getReminderPresets();
  assert.equal(presets.length, 4);
  assert.equal(presets[0].label, "+30m");
  assert.equal(presets[1].label, "+1h");
  assert.equal(presets[2].label, "Tomorrow 9am");
  assert.equal(presets[3].label, "Tomorrow 6pm");
  for (const preset of presets) {
    assert.ok(preset.label);
    assert.ok(preset.id);
    assert.ok(!isNaN(new Date(preset.value).getTime()));
  }

  // With explicit baseDate (e.g. 12:55:00)
  const base = new Date("2026-09-25T12:55:00.000Z");
  const dynamicPresets = getReminderPresets(base);
  assert.equal(new Date(dynamicPresets[0].value).getTime(), base.getTime() + 30 * 60 * 1000);
  assert.equal(new Date(dynamicPresets[1].value).getTime(), base.getTime() + 60 * 60 * 1000);

  // computePresetReminder
  const computed30m = computePresetReminder(0, base);
  assert.equal(new Date(computed30m!).getTime(), base.getTime() + 30 * 60 * 1000);
  const computedById = computePresetReminder("30m", base);
  assert.equal(computedById, computed30m);
  const computedByLabel = computePresetReminder("+1h", base);
  assert.equal(new Date(computedByLabel!).getTime(), base.getTime() + 60 * 60 * 1000);
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

  // Archive only personal completed tasks (test resilience with # and uppercase)
  const emptyArchive = JSON.stringify({ version: 1, archived: [] });
  const res1 = archiveCompleted(store, "#PERSONAL", emptyArchive);

  assert.equal(res1.clearedCount, 1);
  assert.equal(res1.updatedStore.todos.length, 2); // 1 active, 1 work done remaining
  assert.equal(res1.updatedArchive.archived.length, 1);
  assert.equal(res1.updatedArchive.archived[0].title, "Done task 2");
  assert.ok(typeof res1.updatedArchive.archived[0].completedAt === "number");

  // Archive work completed tasks (test resilience with leading #)
  const resWork = archiveCompleted(res1.updatedStore, "#work", JSON.stringify(res1.updatedArchive));
  assert.equal(resWork.clearedCount, 1);
  assert.equal(resWork.updatedStore.todos.length, 1); // Only active task left
  assert.equal(resWork.updatedArchive.archived.length, 2);

  // Archive all remaining (no-op since 0 done remaining)
  const res2 = archiveCompleted(resWork.updatedStore, "all", JSON.stringify(resWork.updatedArchive));
  assert.equal(res2.clearedCount, 0);
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

test("getArdoiseIconState: climbs the ladder clear -> pending -> due -> overdue", () => {
  const now = new Date("2026-09-21T12:00:00.000Z").getTime();
  const at = (offsetMs) => new Date(now + offsetMs).toISOString();

  // Invalid/empty store sits on the bottom rung.
  const empty = getArdoiseIconState(null, now);
  assert.equal(empty.key, "clear");
  assert.equal(empty.role, "foreground");
  assert.equal(empty.total, 0);
  assert.equal(empty.count, 0);

  // Nothing pending but stale reminder history must still read as clear:
  // completed tasks are excluded from the breakdown.
  const doneOnly = {
    version: 1,
    todos: [{ id: 1, title: "T1", done: true, reminder: at(-3600 * 1000) }]
  };
  assert.equal(getArdoiseIconState(doneOnly, now).key, "clear");
  assert.equal(getArdoiseIconState(doneOnly, now).count, 0);

  // Pending with nothing time-critical.
  const pending = {
    version: 1,
    todos: [
      { id: 1, title: "T1", done: false, reminder: null },
      { id: 2, title: "T2", done: false, reminder: at(30 * 3600 * 1000) }
    ]
  };
  const pendingState = getArdoiseIconState(pending, now);
  assert.equal(pendingState.key, "pending");
  assert.equal(pendingState.role, "foreground");
  assert.equal(pendingState.total, 2);
  // On the pending rung the badge count IS the total.
  assert.equal(pendingState.count, 2);

  // Due today (and later) but nothing overdue yet.
  const due = {
    version: 1,
    todos: [
      { id: 1, title: "T1", done: false, reminder: at(1 * 3600 * 1000) },
      { id: 2, title: "T2", done: false, reminder: at(30 * 3600 * 1000) }
    ]
  };
  const dueState = getArdoiseIconState(due, now);
  assert.equal(dueState.key, "due");
  assert.equal(dueState.role, "accent");
  assert.equal(dueState.dueToday, 1);
  // The badge shows the due-today subset, not the total.
  assert.equal(dueState.count, 1);
  // The due rung is only reachable with nothing overdue, so the number is
  // never ambiguous ("2 due today" cannot hide a 3rd overdue task).
  assert.equal(dueState.overdue, 0);

  // Overdue outranks due-today regardless of volume.
  const overdue = {
    version: 1,
    todos: [
      { id: 1, title: "T1", done: false, reminder: at(-30 * 60 * 1000) },
      { id: 2, title: "T2", done: false, reminder: at(1 * 3600 * 1000) },
      { id: 3, title: "T3", done: false, reminder: at(2 * 3600 * 1000) }
    ]
  };
  const overdueState = getArdoiseIconState(overdue, now);
  assert.equal(overdueState.key, "overdue");
  assert.equal(overdueState.role, "warning");
  assert.equal(overdueState.overdue, 1);
  assert.equal(overdueState.dueToday, 2);
  // The badge shows only the overdue subset, even though 3 tasks are pending
  // and 2 of them are due today.
  assert.equal(overdueState.count, 1);
  assert.equal(overdueState.total, 3);
});

test("getArdoiseIconState: badge count is always the rung subset, never the total", () => {
  const now = new Date("2026-09-21T12:00:00.000Z").getTime();
  const at = (offsetMs) => new Date(now + offsetMs).toISOString();

  // A store shaped so every rung is reachable with a strict subset present.
  const scenarios = [
    {
      name: "clear",
      todos: [],
      expect: { count: 0, total: 0 }
    },
    {
      name: "pending",
      todos: [
        { id: 1, title: "T1", done: false, reminder: null },
        { id: 2, title: "T2", done: false, reminder: at(40 * 3600 * 1000) }
      ],
      expect: { count: 2, total: 2 }
    },
    {
      name: "due",
      todos: [
        { id: 1, title: "T1", done: false, reminder: null },
        { id: 2, title: "T2", done: false, reminder: at(2 * 3600 * 1000) },
        { id: 3, title: "T3", done: false, reminder: at(3 * 3600 * 1000) }
      ],
      expect: { count: 2, total: 3 }
    },
    {
      name: "overdue",
      todos: [
        { id: 1, title: "T1", done: false, reminder: at(-30 * 60 * 1000) },
        { id: 2, title: "T2", done: false, reminder: at(2 * 3600 * 1000) },
        { id: 3, title: "T3", done: false, reminder: at(3 * 3600 * 1000) }
      ],
      expect: { count: 1, total: 3 }
    }
  ];

  for (const scenario of scenarios) {
    const state = getArdoiseIconState(
      { version: 1, todos: scenario.todos },
      now
    );
    assert.equal(state.key, scenario.name, `rung for ${scenario.name}`);
    assert.equal(state.count, scenario.expect.count, `count for ${scenario.name}`);
    assert.equal(state.total, scenario.expect.total, `total for ${scenario.name}`);

    // Invariant: the badge is a subset of what is pending, never more.
    assert.ok(
      state.count <= state.total,
      `count (${state.count}) must not exceed total (${state.total}) on ${scenario.name}`
    );
    // A non-clear rung always has something to report.
    if (state.key !== "clear") {
      assert.ok(
        state.count > 0,
        `${state.key} rung must have a non-zero badge count`
      );
    }
  }
});

test("getArdoiseIconState: every rung has a distinct Nerd Font glyph and a color role", () => {
  const rungs = ["clear", "pending", "due", "overdue"].map(
    (key) => ardoiseIconStateForKey(key)
  );
  assert.equal(rungs.filter(Boolean).length, 4);

  // A stateful mark must not change identity silently: no glyph repeats.
  const glyphs = new Set(rungs.map((r) => r.glyph));
  assert.equal(glyphs.size, 4, "each ladder rung needs its own glyph");

  // The first two rungs are lists of work; the last is a distinct silhouette.
  assert.notEqual(rungs[0].glyph, rungs[1].glyph);
  assert.notEqual(rungs[2].glyph, rungs[3].glyph);

  // Severity ramp: neutral -> neutral -> informational -> warning. A task due
  // today is on track, so it stays accent; only a genuinely late task
  // escalates past accent.
  assert.deepEqual(
    rungs.map((r) => r.role),
    ["foreground", "foreground", "accent", "warning"]
  );

  // Unknown keys are rejected rather than silently rendering a wrong rung.
  assert.equal(ardoiseIconStateForKey("nope"), null);
});

test("getArdoiseIconState: no rung uses the urgent role — red is reserved for errors", () => {
  // Red is the shell's error channel. Using it for a late task would train the
  // eye to ignore it, so the task ladder must stay on the softer warning ramp
  // and leave urgent to genuine failure surfaces (QuickAdd title-required,
  // GitModal errors, invalid input). This fails loudly if someone reintroduces
  // red as a task severity.
  for (const key of ["clear", "pending", "due", "overdue"]) {
    const rung = ardoiseIconStateForKey(key);
    assert.ok(rung, `rung ${key} must exist`);
    assert.notEqual(
      rung.role,
      "urgent",
      `rung ${key} must not paint in urgent red`
    );
  }

  // Only the late rung escalates, and it escalates to warning specifically.
  // `timer_alert` (U+F1ACC) is used rather than a clock glyph so it cannot be
  // confused with the plain clock already reserved for reminders.
  const late = ardoiseIconStateForKey("overdue");
  assert.equal(late.role, "warning");
  assert.equal(late.glyph, "󱫌");

  // Due-today is informational, not a warning: a task due today is on track.
  assert.equal(ardoiseIconStateForKey("due").role, "accent");
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

test("getFilteredTodos: orders tasks by due/reminder time first, then active, then last completed", () => {
  let store = defaultStore();

  const now = Date.now();
  const pastTime = new Date(now - 3600000).toISOString(); // 1h overdue
  const futureTime1 = new Date(now + 3600000).toISOString(); // due in 1h
  const futureTime2 = new Date(now + 7200000).toISOString(); // due in 2h

  // 1. Incomplete task with future reminder 2
  store = addTodo(store, "Future Task 2", "", "work", futureTime2);
  // 2. Incomplete task with future reminder 1
  store = addTodo(store, "Future Task 1", "", "work", futureTime1);
  // 3. Incomplete task with overdue reminder
  store = addTodo(store, "Overdue Task", "", "work", pastTime);
  // 4. Incomplete task without reminder (older)
  store = addTodo(store, "Older Active Task", "", "work", null);
  const tOlder = store.todos.find(t => t.title === "Older Active Task")!;
  tOlder.createdAt = 1000;
  tOlder.updatedAt = 1000;

  // 5. Incomplete task without reminder (newer)
  store = addTodo(store, "Newer Active Task", "", "work", null);
  const tNewer = store.todos.find(t => t.title === "Newer Active Task")!;
  tNewer.createdAt = 2000;
  tNewer.updatedAt = 2000;

  // 6. Completed task (older completed)
  store = addTodo(store, "First Completed Task", "", "work", null);
  const tDone1 = store.todos.find(t => t.title === "First Completed Task")!;
  tDone1.done = true;
  tDone1.createdAt = 1000;
  tDone1.updatedAt = 3000;

  // 7. Completed task (last completed)
  store = addTodo(store, "Last Completed Task", "", "work", null);
  const tDone2 = store.todos.find(t => t.title === "Last Completed Task")!;
  tDone2.done = true;
  tDone2.createdAt = 1000;
  tDone2.updatedAt = 4000;

  const sorted = getFilteredTodos(store, "work");
  const titles = sorted.map(t => t.title);

  // Expected sequence:
  // 1. Overdue Task (earliest reminder)
  // 2. Future Task 1 (earlier than Future 2)
  // 3. Future Task 2
  // 4. Newer Active Task (recency 2000 > 1000)
  // 5. Older Active Task
  // 6. Last Completed Task (last completed: recency 4000 > 3000)
  // 7. First Completed Task
  assert.deepEqual(titles, [
    "Overdue Task",
    "Future Task 1",
    "Future Task 2",
    "Newer Active Task",
    "Older Active Task",
    "Last Completed Task",
    "First Completed Task"
  ]);
});

test("compareTasks: correctly compares task priority according to due, active, and completed rules", () => {
  const tDueSoon = { id: 1, title: "Soon", done: false, reminder: "2026-09-23T14:00:00Z", createdAt: 100, description: "", profile: "work" };
  const tDueLater = { id: 2, title: "Later", done: false, reminder: "2026-09-23T18:00:00Z", createdAt: 200, description: "", profile: "work" };
  const tActiveNew = { id: 3, title: "Active New", done: false, reminder: null, createdAt: 500, updatedAt: 500, description: "", profile: "work" };
  const tActiveOld = { id: 4, title: "Active Old", done: false, reminder: null, createdAt: 100, updatedAt: 100, description: "", profile: "work" };
  const tDoneRecent = { id: 5, title: "Done Recent", done: true, reminder: null, createdAt: 100, updatedAt: 800, description: "", profile: "work" };
  const tDoneOlder = { id: 6, title: "Done Older", done: true, reminder: null, createdAt: 100, updatedAt: 300, description: "", profile: "work" };

  // Due tasks come before active tasks
  assert.ok(compareTasks(tDueSoon, tActiveNew) < 0);
  assert.ok(compareTasks(tActiveNew, tDueSoon) > 0);

  // Earliest due task comes first
  assert.ok(compareTasks(tDueSoon, tDueLater) < 0);
  assert.ok(compareTasks(tDueLater, tDueSoon) > 0);

  // Active tasks: newest comes first
  assert.ok(compareTasks(tActiveNew, tActiveOld) < 0);
  assert.ok(compareTasks(tActiveOld, tActiveNew) > 0);

  // Active tasks come before completed tasks
  assert.ok(compareTasks(tActiveOld, tDoneRecent) < 0);
  assert.ok(compareTasks(tDoneRecent, tActiveOld) > 0);

  // Completed tasks: last completed comes first
  assert.ok(compareTasks(tDoneRecent, tDoneOlder) < 0);
  assert.ok(compareTasks(tDoneOlder, tDoneRecent) > 0);
});

test("parseTaskInput: parses leading #project/repo, #tags, and preserves title", () => {
  // Project with repo and multiple tags
  const res1 = parseTaskInput("#omarchy/ardoise #ui #drawer Fix viewport jump on expand", "personal");
  assert.equal(res1.profile, "omarchy");
  assert.equal(res1.repo, "ardoise");
  assert.deepEqual(res1.tags, ["ui", "drawer"]);
  assert.equal(res1.title, "Fix viewport jump on expand");

  // Project without repo, with tags and embedded # in title
  const res2 = parseTaskInput("#omarchy #ui #panel Fix collision with issue #42 in C#", "personal");
  assert.equal(res2.profile, "omarchy");
  assert.equal(res2.repo, null);
  assert.deepEqual(res2.tags, ["ui", "panel"]);
  assert.equal(res2.title, "Fix collision with issue #42 in C#");

  // Space after hashtag (# work)
  const res3 = parseTaskInput("# work Clean room", "personal");
  assert.equal(res3.profile, "work");
  assert.equal(res3.repo, null);
  assert.deepEqual(res3.tags, []);
  assert.equal(res3.title, "Clean room");

  // Fallback embedded hashtag
  const res4 = parseTaskInput("Buy milk #shopping", "personal");
  assert.equal(res4.profile, "shopping");
  assert.equal(res4.repo, null);
  assert.deepEqual(res4.tags, []);
  assert.equal(res4.title, "Buy milk");

  // Plain task without hashtags
  const res5 = parseTaskInput("Simple standalone task", "work");
  assert.equal(res5.profile, "work");
  assert.equal(res5.repo, null);
  assert.deepEqual(res5.tags, []);
  assert.equal(res5.title, "Simple standalone task");
});

test("parseTaskInput & addTodo: input containing only hashtags yields empty title and prevents task creation", () => {
  // Only project/repo
  const res1 = parseTaskInput("#ardoise/widget", "personal");
  assert.equal(res1.profile, "ardoise");
  assert.equal(res1.repo, "widget");
  assert.deepEqual(res1.tags, []);
  assert.equal(res1.title, "");

  // Multiple hashtags only
  const res2 = parseTaskInput("#ardoise #widget #urgent", "personal");
  assert.equal(res2.profile, "ardoise");
  assert.equal(res2.repo, null);
  assert.deepEqual(res2.tags, ["widget", "urgent"]);
  assert.equal(res2.title, "");

  // Single hashtag
  const res3 = parseTaskInput("#work", "personal");
  assert.equal(res3.profile, "work");
  assert.equal(res3.title, "");

  // Attempting addTodo with only hashtags and a description must return store unmodified
  const initial = defaultStore();
  const result = addTodo(initial, "#ardoise/widget", "Detailed notes about widget layout");
  assert.equal(result.todos.length, 0, "addTodo must not create a task when title is missing");
  assert.deepEqual(result, initial, "Store must remain untouched when title is missing");
});

test("normalizeLocation: normalizes string, object, and path formats", () => {
  // String shorthand
  assert.deepEqual(normalizeLocation("~/Work/omarchy-ardoise"), {
    repo: null,
    subpath: null,
    localPath: "~/Work/omarchy-ardoise"
  });

  // Structured object
  assert.deepEqual(normalizeLocation({
    repo: "Tablerase/omarchy-ardoise",
    subpath: "ui/",
    localPath: "~/Work/ardoise"
  }), {
    repo: "Tablerase/omarchy-ardoise",
    subpath: "ui/",
    localPath: "~/Work/ardoise"
  });

  // Path alias in object
  assert.deepEqual(normalizeLocation({ path: "/var/log" }), {
    repo: null,
    subpath: null,
    localPath: "/var/log"
  });

  // Empty or invalid
  assert.equal(normalizeLocation(null), null);
  assert.equal(normalizeLocation(""), null);
  assert.equal(normalizeLocation({}), null);
});

test("addTodo & updateTodo: stores repo, tags, and location, and supports tag/repo filtering", () => {
  let store = defaultStore();

  // Add task with #omarchy/ardoise #ui and explicit location
  store = addTodo(
    store,
    "#omarchy/ardoise #ui #panel Auto-scroll top",
    "Detailed notes",
    "personal",
    null,
    { subpath: "ui/", localPath: "~/Work/ardoise" }
  );

  assert.equal(store.todos.length, 1);
  const task = store.todos[0];
  assert.equal(task.profile, "omarchy");
  assert.equal(task.repo, "ardoise");
  assert.deepEqual(task.tags, ["ui", "panel"]);
  assert.deepEqual(task.location, {
    repo: "ardoise",
    subpath: "ui/",
    localPath: "~/Work/ardoise"
  });

  // Add second task in different repo under same project
  store = addTodo(
    store,
    "#omarchy/shell #ipc Add window hook",
    "",
    "personal"
  );
  assert.equal(store.todos.length, 2);

  // Filter by tag
  const uiTasks = getFilteredTodos(store, "all", "ui");
  assert.equal(uiTasks.length, 1);
  assert.equal(uiTasks[0].title, "Auto-scroll top");

  // Filter by repo
  const shellTasks = getFilteredTodos(store, "omarchy", undefined, "shell");
  assert.equal(shellTasks.length, 1);
  assert.equal(shellTasks[0].title, "Add window hook");

  // Update task tags and location
  store = updateTodo(store, task.id, {
    tags: ["ui", "v2"],
    location: "~/Custom/Path"
  });
  const updatedTask = store.todos.find((t: any) => t.id === task.id);
  assert.deepEqual(updatedTask?.tags, ["ui", "v2"]);
  assert.deepEqual(updatedTask?.location, {
    repo: null,
    subpath: null,
    localPath: "~/Custom/Path"
  });
});

test("mergeStores: 3-way conflict-free store merging", () => {
  const localStore = {
    version: 1,
    activeProfile: "work",
    profiles: ["personal", "work", "project-a"],
    todos: [
      {
        id: 101,
        title: "Task 1 local update",
        description: "",
        profile: "work",
        done: true,
        createdAt: 1000,
        updatedAt: 5000
      },
      {
        id: 102,
        title: "Local only task",
        description: "",
        profile: "personal",
        done: false,
        createdAt: 2000,
        updatedAt: 2000
      }
    ]
  };

  const remoteStore = {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal", "work", "project-b"],
    todos: [
      {
        id: 101,
        title: "Task 1 older remote",
        description: "remote note",
        profile: "work",
        done: false,
        createdAt: 1000,
        updatedAt: 4000
      },
      {
        id: 103,
        title: "Remote only task",
        description: "from laptop",
        profile: "project-b",
        done: false,
        createdAt: 3000,
        updatedAt: 3000
      }
    ]
  };

  const merged = mergeStores(localStore, remoteStore);

  // Profiles unioned
  assert.deepEqual(merged.profiles, ["personal", "work", "project-a", "project-b"]);
  assert.equal(merged.activeProfile, "work");

  // Todos: 3 total
  assert.equal(merged.todos.length, 3);

  // Task 101 took local because updatedAt 5000 > 4000
  const t101 = merged.todos.find((t: any) => t.id === 101);
  assert.equal(t101?.title, "Task 1 local update");
  assert.equal(t101?.done, true);

  // Both local-only and remote-only tasks preserved
  assert.ok(merged.todos.some((t: any) => t.id === 102));
  assert.ok(merged.todos.some((t: any) => t.id === 103));
});

test("mergeArchives: deduplicates by id and takes latest completedAt", () => {
  const localArchive = {
    version: 1,
    archived: [
      { id: 1, title: "Old task", completedAt: 1000 },
      { id: 2, title: "Shared task", completedAt: 2000 }
    ]
  };
  const remoteArchive = {
    version: 1,
    archived: [
      { id: 2, title: "Shared task re-completed", completedAt: 3000 },
      { id: 3, title: "Remote archived task", completedAt: 2500 }
    ]
  };

  const merged = mergeArchives(localArchive, remoteArchive);
  assert.equal(merged.archived.length, 3);
  // Sorted by completedAt descending
  assert.equal(merged.archived[0].id, 2);
  assert.equal(merged.archived[0].completedAt, 3000);
  assert.equal(merged.archived[1].id, 3);
  assert.equal(merged.archived[2].id, 1);
});

test("filterMissingTasks: finds tasks present in snapshot but absent currently", () => {
  const current = {
    version: 1,
    todos: [{ id: 10, title: "Existing" }]
  };
  const snapshot = {
    version: 1,
    todos: [
      { id: 10, title: "Existing" },
      { id: 20, title: "Deleted task" },
      { id: 30, title: "Another deleted task" }
    ]
  };

  const missing = filterMissingTasks(current, snapshot);
  assert.equal(missing.length, 2);
  assert.equal(missing[0].id, 20);
  assert.equal(missing[1].id, 30);
});

test("scale performance: handles 500 active tasks within strict latency budgets", () => {
  const now = Date.now();
  const tasks = [];
  const profiles = ["personal", "work", "project-x", "devops"];

  for (let i = 0; i < 500; i++) {
    tasks.push({
      id: now + i,
      title: `Task #${i + 1} scale test item with details and extra context`,
      description: `Task ${i + 1} description and notes.`,
      profile: profiles[i % profiles.length],
      repo: i % 3 === 0 ? "omarchy-ardoise" : null,
      tags: ["scale", `tag-${i % 5}`],
      location: i % 2 === 0 ? "/home/rcutte/Work/tries/omarchy-ardoise" : null,
      reminder: i % 10 === 0 ? new Date(now + 3600000).toISOString() : null,
      done: i % 7 === 0,
      createdAt: now - i * 60000
    });
  }

  const store = {
    version: 1,
    activeProfile: "personal",
    profiles: profiles,
    todos: tasks
  };

  const t0 = performance.now();
  const filtered = getFilteredTodos(store, "all");
  const tFilter = performance.now() - t0;

  const t1 = performance.now();
  const pendingCount = getPendingCount(store, "all");
  const tCount = performance.now() - t1;

  const t2 = performance.now();
  const urgency = getTaskUrgencyBreakdown(store);
  const tUrgency = performance.now() - t2;

  assert.equal(filtered.length, 500);
  assert.ok(pendingCount > 0, "Pending count should be greater than 0");
  assert.ok(tFilter < 50, `getFilteredTodos for 500 tasks took ${tFilter}ms (expected <50ms)`);
  assert.ok(tCount < 10, `getPendingCount for 500 tasks took ${tCount}ms (expected <10ms)`);
  assert.ok(tUrgency < 25, `getTaskUrgencyBreakdown for 500 tasks took ${tUrgency}ms (expected <25ms)`);
});

test("scale performance: handles 5,000 archived tasks and merge without degradation", () => {
  const now = Date.now();
  const archived = [];

  for (let i = 0; i < 5000; i++) {
    archived.push({
      id: now + i,
      title: `Archived task #${i + 1}`,
      description: "Archived notes",
      profile: "personal",
      tags: ["archived"],
      createdAt: now - i * 60000,
      completedAt: now - i * 1000
    });
  }

  const archiveData = { version: 1, archived };
  const rawJson = JSON.stringify(archiveData);

  const t0 = performance.now();
  const normalized = normalizeArchive(rawJson);
  const tNorm = performance.now() - t0;

  assert.equal(normalized.archived.length, 5000);
  assert.ok(tNorm < 100, `normalizeArchive for 5,000 tasks took ${tNorm}ms (expected <100ms)`);

  const dummyStore = {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal"],
    todos: [
      { id: now + 99999, title: "Just completed", done: true, profile: "personal" }
    ]
  };

  const t1 = performance.now();
  const res = archiveCompleted(dummyStore, "all", rawJson);
  const tClear = performance.now() - t1;

  assert.equal(res.clearedCount, 1);
  assert.equal(res.updatedArchive.archived.length, 5001);
  assert.ok(tClear < 100, `archiveCompleted with 5,000 tasks took ${tClear}ms (expected <100ms)`);
});

test("versioning & extensibility: normalizeTask preserves unknown/future extension fields", () => {
  const futureRaw = {
    id: 12345,
    title: "Future task",
    description: "Task from a future schema version",
    profile: "work",
    priority: "high",
    subtasks: [{ id: 1, text: "Subtask 1", done: false }],
    recurrence: { freq: "weekly", interval: 1 },
    customMetadata: { score: 99 }
  };

  const normalized = normalizeTask(futureRaw);
  assert.ok(normalized, "Task should be normalized");
  assert.equal(normalized.title, "Future task");
  assert.equal(normalized.profile, "work");
  // Assert future fields are preserved without data loss
  assert.equal(normalized.priority, "high");
  assert.deepEqual(normalized.subtasks, [{ id: 1, text: "Subtask 1", done: false }]);
  assert.deepEqual(normalized.recurrence, { freq: "weekly", interval: 1 });
  assert.deepEqual(normalized.customMetadata, { score: 99 });
});

test("versioning & extensibility: normalize preserves future schema version and root properties", () => {
  assert.equal(CURRENT_SCHEMA_VERSION, 1);
  assert.equal(CURRENT_ARCHIVE_VERSION, 1);

  const futureStore = {
    version: 2,
    activeProfile: "work",
    profiles: ["personal", "work", "research"],
    todos: [
      { id: 1, title: "v2 task", profile: "work", priority: "critical" }
    ],
    workspaceSettings: { theme: "dark", autoArchiveDays: 30 }
  };

  const normalized = normalize(JSON.stringify(futureStore));
  // Must not downgrade version 2 to version 1
  assert.equal(normalized.version, 2);
  assert.equal(normalized.activeProfile, "work");
  assert.equal(normalized.todos.length, 1);
  assert.equal(normalized.todos[0].priority, "critical");
  // Root level extension properties must be preserved
  assert.deepEqual(normalized.workspaceSettings, { theme: "dark", autoArchiveDays: 30 });
});

test("versioning & extensibility: mergeStores resolves version skew adopting the higher schema version", () => {
  const localV1 = {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal", "work"],
    todos: [
      { id: 10, title: "Local task v1", done: false, updatedAt: 1000 }
    ]
  };

  const remoteV2 = {
    version: 2,
    activeProfile: "work",
    profiles: ["personal", "work", "research"],
    todos: [
      { id: 20, title: "Remote task v2", done: false, priority: "urgent", updatedAt: 2000 }
    ]
  };

  const merged = mergeStores(localV1, remoteV2);
  // Merged store must adopt the higher version (v2) and preserve tasks and v2 fields
  assert.equal(merged.version, 2);
  assert.equal(merged.todos.length, 2);
  const v2Task = merged.todos.find((t) => t.id === 20);
  assert.ok(v2Task, "Remote v2 task should be present");
  assert.equal(v2Task.priority, "urgent");
});

test("versioning & extensibility: normalizeArchive preserves future archive versions and extra task properties", () => {
  const futureArchive = {
    version: 3,
    archived: [
      {
        id: 99,
        title: "Archived future task",
        profile: "work",
        category: "billing",
        completedAt: 50000
      }
    ]
  };

  const normArc = normalizeArchive(JSON.stringify(futureArchive));
  assert.equal(normArc.version, 3);
  assert.equal(normArc.archived.length, 1);
  assert.equal(normArc.archived[0].category, "billing");

  const localArcV1 = {
    version: 1,
    archived: [{ id: 1, title: "Old archived", completedAt: 10000 }]
  };
  const mergedArc = mergeArchives(localArcV1, futureArchive);
  assert.equal(mergedArc.version, 3);
  assert.equal(mergedArc.archived.length, 2);
  assert.equal(mergedArc.archived[0].id, 99);
  assert.equal(mergedArc.archived[0].category, "billing");
});




