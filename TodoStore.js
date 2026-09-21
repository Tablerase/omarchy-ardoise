// @ts-check
// =============================================================================
// TodoStore.js
//
// Core data store, schema v1 management, profile handling, and reminder logic
// for the Omarchy Quattro Todo plugin Ardoise (tablerase.ardoise).
//
// Intentionally pure stateless library; fully typed via TypeScript JSDoc.
// =============================================================================

/**
 * @typedef {Object} Task
 * @property {number|string} id - Unique identifier (timestamp or string)
 * @property {string} title - Task title/content
 * @property {string} description - Detailed notes or description
 * @property {string} profile - Profile/category name (e.g. "personal", "work")
 * @property {boolean} done - Whether the task is completed
 * @property {number} createdAt - Creation epoch timestamp (ms)
 * @property {number} [updatedAt] - Last updated epoch timestamp (ms)
 * @property {string|null} [dueDate] - Optional due date string
 * @property {string|null} [reminder] - Optional reminder ISO timestamp string
 * @property {boolean} [notified] - Whether desktop notification was triggered
 */

/**
 * @typedef {Object} ArchivedTask
 * @property {number|string} id - Task identifier
 * @property {string} title - Task title
 * @property {string} description - Task description
 * @property {string} profile - Profile name
 * @property {number} createdAt - Creation epoch timestamp (ms)
 * @property {number} completedAt - Completion/archive epoch timestamp (ms)
 */

/**
 * @typedef {Object} TodoStoreData
 * @property {number} version - Schema version (always 1)
 * @property {string} activeProfile - Currently active profile
 * @property {string[]} profiles - List of configured profile names
 * @property {Task[]} todos - Active tasks list
 */

/**
 * @typedef {Object} ArchiveData
 * @property {number} version - Archive schema version (always 1)
 * @property {ArchivedTask[]} archived - List of archived completed tasks
 */

/**
 * @typedef {Object} TaskUpdateFields
 * @property {string} [title]
 * @property {string} [description]
 * @property {string} [profile]
 * @property {boolean} [done]
 * @property {number} [updatedAt]
 * @property {string|null} [reminder]
 * @property {string|null} [dueDate]
 * @property {boolean} [notified]
 */

/**
 * @typedef {Object} ReminderPreset
 * @property {string} label
 * @property {string} value
 */

/**
 * @typedef {Object} ArchiveResult
 * @property {TodoStoreData} updatedStore
 * @property {ArchiveData} updatedArchive
 * @property {number} clearedCount
 */

/**
 * Creates an empty default Schema v1 store.
 * @returns {TodoStoreData}
 */
function defaultStore() {
  return {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal", "work"],
    todos: []
  }
}

/**
 * Cleans and normalizes a profile name.
 * Maps aliases (e.g. "perso" -> "personal").
 * @param {string|null|undefined} name
 * @returns {string}
 */
function cleanProfileName(name) {
  if (!name) return "personal"
  var cleaned = String(name).trim().toLowerCase().replace(/^#+/, "").replace(/[^a-z0-9_-]/g, "")
  if (cleaned === "perso") cleaned = "personal"
  return cleaned || "personal"
}

/**
 * Normalizes an arbitrary raw task object into a clean Schema v1 Task.
 * @param {any} raw
 * @returns {Task|null}
 */
function normalizeTask(raw) {
  if (!raw || typeof raw !== "object") return null
  var now = Date.now()
  var id = raw.id !== undefined && raw.id !== null ? raw.id : now
  var title = String(raw.title || raw.text || "").trim()
  var description = String(raw.description || "")
  var profile = cleanProfileName(raw.profile)
  var done = Boolean(raw.done)
  var createdAt = Number(raw.createdAt) || (typeof id === "number" ? id : now)
  var updatedAt = raw.updatedAt ? (Number(raw.updatedAt) || createdAt) : undefined
  var dueDate = raw.dueDate ? String(raw.dueDate) : null
  var reminder = raw.reminder ? String(raw.reminder) : null
  var notified = Boolean(raw.notified)

  return {
    id: id,
    title: title,
    description: description,
    profile: profile,
    done: done,
    createdAt: createdAt,
    updatedAt: updatedAt,
    dueDate: dueDate,
    reminder: reminder,
    notified: notified
  }
}

/**
 * Normalizes raw JSON or object into a Schema v1 TodoStoreData structure.
 * Handles legacy raw arrays and schema migrations.
 * @param {any} raw
 * @returns {TodoStoreData}
 */
function normalize(raw) {
  var data = raw
  if (typeof raw === "string") {
    try {
      data = JSON.parse(raw || "{}")
    } catch (_e) {
      return defaultStore()
    }
  }

  if (!data || typeof data !== "object") {
    return defaultStore()
  }

  // Legacy format: raw array of todos
  if (Array.isArray(data)) {
    /** @type {Task[]} */
    var legacyTodos = []
    /** @type {Record<string, boolean>} */
    var profileSet = { "personal": true, "work": true }
    for (var i = 0; i < data.length; i++) {
      var t = normalizeTask(data[i])
      if (t && t.title) {
        legacyTodos.push(t)
        if (t.profile) profileSet[t.profile] = true
      }
    }
    var profileList = Object.keys(profileSet)
    return {
      version: 1,
      activeProfile: "personal",
      profiles: profileList,
      todos: legacyTodos
    }
  }

  // Schema v1 format
  var activeProfile = cleanProfileName(data.activeProfile)
  /** @type {string[]} */
  var profiles = ["personal", "work"]
  /** @type {Record<string, boolean>} */
  var seenProfiles = { "personal": true, "work": true }

  if (Array.isArray(data.profiles)) {
    for (var p = 0; p < data.profiles.length; p++) {
      var c = cleanProfileName(data.profiles[p])
      if (c && !seenProfiles[c]) {
        seenProfiles[c] = true
        profiles.push(c)
      }
    }
  }

  /** @type {Task[]} */
  var todos = []
  if (Array.isArray(data.todos)) {
    for (var j = 0; j < data.todos.length; j++) {
      var task = normalizeTask(data.todos[j])
      if (task && task.title) {
        todos.push(task)
        if (!seenProfiles[task.profile]) {
          seenProfiles[task.profile] = true
          profiles.push(task.profile)
        }
      }
    }
  }

  if (!seenProfiles[activeProfile]) {
    profiles.push(activeProfile)
  }

  return {
    version: 1,
    activeProfile: activeProfile,
    profiles: profiles,
    todos: todos
  }
}

/**
 * Parses input text for #hashtag profile syntax (e.g. "#work Fix bug" or "Deploy code #project1").
 * @param {string} input
 * @param {string} [defaultProfile]
 * @returns {{ title: string, profile: string }}
 */
function parseTitleAndProfile(input, defaultProfile) {
  var text = String(input || "").trim()
  var profile = defaultProfile ? cleanProfileName(defaultProfile) : "personal"

  var match = text.match(/#\s*([a-zA-Z0-9_-]+)/)
  if (match) {
    profile = cleanProfileName(match[1])
    text = text.replace(/#\s*[a-zA-Z0-9_-]+/g, "").replace(/\s+/g, " ").trim()
  }

  return {
    title: text,
    profile: profile
  }
}

/**
 * Deep clones a store object to maintain immutability.
 * @param {TodoStoreData} store
 * @returns {TodoStoreData}
 */
function cloneStore(store) {
  return JSON.parse(JSON.stringify(store || defaultStore()))
}

/**
 * Adds a new task to the store.
 * @param {TodoStoreData} store
 * @param {string} rawTitle
 * @param {string} [description]
 * @param {string} [explicitProfile]
 * @param {string|null} [reminderTime]
 * @returns {TodoStoreData}
 */
function addTodo(store, rawTitle, description, explicitProfile, reminderTime) {
  var s = cloneStore(store)
  var parsed = parseTitleAndProfile(rawTitle, explicitProfile || s.activeProfile)
  var title = parsed.title
  var profile = (explicitProfile && !rawTitle.match(/#\s*([a-zA-Z0-9_-]+)/))
    ? cleanProfileName(explicitProfile)
    : parsed.profile

  if (!title) return s

  // Ensure profile is in profiles list
  if (s.profiles.indexOf(profile) === -1) {
    s.profiles.push(profile)
  }

  var now = Date.now()
  var taskId = now
  for (var k = 0; k < s.todos.length; k++) {
    var tid = Number(s.todos[k].id)
    if (!isNaN(tid) && tid >= taskId) {
      taskId = tid + 1
    }
  }

  /** @type {Task} */
  var newTask = {
    id: taskId,
    title: title,
    description: String(description || ""),
    profile: profile,
    done: false,
    createdAt: now,
    updatedAt: now,
    dueDate: null,
    reminder: reminderTime ? String(reminderTime) : null,
    notified: false
  }

  s.todos.unshift(newTask)
  return s
}

/**
 * Toggles a task completion state.
 * @param {TodoStoreData} store
 * @param {number|string} id
 * @returns {TodoStoreData}
 */
function toggleTodo(store, id) {
  var s = cloneStore(store)
  for (var i = 0; i < s.todos.length; i++) {
    if (String(s.todos[i].id) === String(id)) {
      s.todos[i].done = !s.todos[i].done
      // If unmarked as done and reminder is in the future, allow notification again
      if (!s.todos[i].done && s.todos[i].reminder) {
        var remTime = new Date(s.todos[i].reminder || "").getTime()
        if (remTime > Date.now()) {
          s.todos[i].notified = false
        }
      }
      break
    }
  }
  return s
}

/**
 * Removes a task by ID.
 * @param {TodoStoreData} store
 * @param {number|string} id
 * @returns {TodoStoreData}
 */
function removeTodo(store, id) {
  var s = cloneStore(store)
  s.todos = s.todos.filter(function (t) { return String(t.id) !== String(id) })
  return s
}

/**
 * Updates specific fields of an existing task.
 * @param {TodoStoreData} store
 * @param {number|string} id
 * @param {TaskUpdateFields} fields
 * @returns {TodoStoreData}
 */
function updateTodo(store, id, fields) {
  var s = cloneStore(store)
  var now = Date.now()
  for (var i = 0; i < s.todos.length; i++) {
    if (String(s.todos[i].id) === String(id)) {
      var t = s.todos[i]
      t.updatedAt = (fields.updatedAt !== undefined) ? Number(fields.updatedAt) : now
      if (fields.title !== undefined) t.title = String(fields.title).trim()
      if (fields.description !== undefined) t.description = String(fields.description)
      if (fields.profile !== undefined) {
        var p = cleanProfileName(fields.profile)
        t.profile = p
        if (s.profiles.indexOf(p) === -1) s.profiles.push(p)
      }
      if (fields.done !== undefined) t.done = Boolean(fields.done)
      if (fields.reminder !== undefined) {
        t.reminder = fields.reminder ? String(fields.reminder) : null
        t.notified = false
      }
      if (fields.dueDate !== undefined) t.dueDate = fields.dueDate ? String(fields.dueDate) : null
      break
    }
  }
  return s
}

/**
 * Adds a new profile to the store.
 * @param {TodoStoreData} store
 * @param {string} name
 * @returns {TodoStoreData}
 */
function addProfile(store, name) {
  var s = cloneStore(store)
  var p = cleanProfileName(name)
  if (p && s.profiles.indexOf(p) === -1) {
    s.profiles.push(p)
  }
  return s
}

/**
 * Removes a profile (tasks re-assigned to "personal").
 * @param {TodoStoreData} store
 * @param {string} name
 * @returns {TodoStoreData}
 */
function removeProfile(store, name) {
  var s = cloneStore(store)
  var p = cleanProfileName(name)
  if (p === "personal") return s // Protected default profile

  s.profiles = s.profiles.filter(function (item) { return item !== p })
  for (var i = 0; i < s.todos.length; i++) {
    if (s.todos[i].profile === p) {
      s.todos[i].profile = "personal"
    }
  }
  if (s.activeProfile === p) {
    s.activeProfile = "personal"
  }
  return s
}

/**
 * Clears completed tasks matching an optional profile filter.
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @returns {TodoStoreData}
 */
function clearCompleted(store, profileFilter) {
  var s = cloneStore(store)
  if (profileFilter && profileFilter !== "all") {
    s.todos = s.todos.filter(function (t) {
      return !t.done || t.profile !== profileFilter
    })
  } else {
    s.todos = s.todos.filter(function (t) { return !t.done })
  }
  return s
}

/**
 * Counts pending (uncompleted) tasks matching an optional profile filter.
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @returns {number}
 */
function getPendingCount(store, profileFilter) {
  if (!store || !Array.isArray(store.todos)) return 0
  var count = 0
  for (var i = 0; i < store.todos.length; i++) {
    var t = store.todos[i]
    if (!t.done) {
      if (!profileFilter || profileFilter === "all" || t.profile === profileFilter) {
        count++
      }
    }
  }
  return count
}

/**
 * Filters tasks according to the active profile selection.
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @returns {Task[]}
 */
function getFilteredTodos(store, profileFilter) {
  if (!store || !Array.isArray(store.todos)) return []
  if (!profileFilter || profileFilter === "all") return store.todos
  return store.todos.filter(function (t) {
    return t.profile === profileFilter
  })
}

/**
 * Returns profiles sorted by:
 * 1. Descending pending task count (profiles with most pending tasks come first)
 * 2. Descending latest task activity timestamp (updatedAt || createdAt)
 * 3. Alphabetical fallback
 *
 * If onlyActive is true, only returns profiles with count > 0, matching currentFilter, or store.activeProfile.
 *
 * @param {TodoStoreData|null|undefined} store
 * @param {boolean} [onlyActive]
 * @param {string} [currentFilter]
 * @returns {string[]}
 */
function getSortedProfiles(store, onlyActive, currentFilter) {
  /** @type {string[]} */
  var profList = []
  /** @type {Record<string, boolean>} */
  var seen = {}

  var sourceProfiles = (store && Array.isArray(store.profiles)) ? store.profiles : ["personal", "work"]
  for (var i = 0; i < sourceProfiles.length; i++) {
    var p = cleanProfileName(sourceProfiles[i])
    if (p && !seen[p]) {
      seen[p] = true
      profList.push(p)
    }
  }

  /** @type {Record<string, number>} */
  var counts = {}
  /** @type {Record<string, number>} */
  var recency = {}

  for (var k = 0; k < profList.length; k++) {
    counts[profList[k]] = 0
    recency[profList[k]] = 0
  }

  var todos = (store && Array.isArray(store.todos)) ? store.todos : []
  for (var j = 0; j < todos.length; j++) {
    var task = todos[j]
    if (!task) continue
    var prof = cleanProfileName(task.profile)
    if (!prof) continue

    if (!seen[prof]) {
      seen[prof] = true
      profList.push(prof)
      counts[prof] = 0
      recency[prof] = 0
    }

    if (!task.done) {
      counts[prof] = (counts[prof] || 0) + 1
    }

    var taskTime = Math.max(Number(task.updatedAt) || 0, Number(task.createdAt) || 0)
    if (taskTime > (recency[prof] || 0)) {
      recency[prof] = taskTime
    }
  }

  profList.sort(function (a, b) {
    var countA = counts[a] || 0
    var countB = counts[b] || 0
    if (countB !== countA) {
      return countB - countA
    }
    var timeA = recency[a] || 0
    var timeB = recency[b] || 0
    if (timeB !== timeA) {
      return timeB - timeA
    }
    return a.localeCompare(b)
  })

  if (onlyActive) {
    var activeProf = (store && store.activeProfile) ? cleanProfileName(store.activeProfile) : "personal"
    var cleanFilter = (currentFilter && currentFilter !== "all") ? cleanProfileName(currentFilter) : ""
    profList = profList.filter(function (name) {
      return (counts[name] > 0) || (Boolean(cleanFilter) && name === cleanFilter) || (name === activeProf)
    })
    if (profList.length === 0) {
      profList.push(activeProf || "personal")
    }
  }

  return profList
}

/**
 * Returns all unnotified tasks with reminders due at or before now.
 * @param {TodoStoreData} store
 * @returns {Task[]}
 */
function pendingReminders(store) {
  if (!store || !Array.isArray(store.todos)) return []
  var now = Date.now()
  /** @type {Task[]} */
  var due = []
  for (var i = 0; i < store.todos.length; i++) {
    var t = store.todos[i]
    if (!t.done && t.reminder && !t.notified) {
      var time = new Date(t.reminder).getTime()
      if (!isNaN(time) && time <= now) {
        due.push(t)
      }
    }
  }
  return due
}

/**
 * Formats a reminder ISO string into a friendly user-facing label.
 * @param {string|null|undefined} reminderStr
 * @returns {string}
 */
function formatReminder(reminderStr) {
  if (!reminderStr) return ""
  var d = new Date(reminderStr)
  if (isNaN(d.getTime())) return ""

  var now = new Date()
  var diff = d.getTime() - now.getTime()

  var timeStr = (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" +
    (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()

  var isToday = d.toDateString() === now.toDateString()
  var tomorrow = new Date(now.getTime() + 86400000)
  var isTomorrow = d.toDateString() === tomorrow.toDateString()

  if (diff < 0) {
    return "Due " + (isToday ? "today at " + timeStr : d.toLocaleDateString(undefined, { month: "short", day: "numeric" }))
  }

  if (isToday) {
    return "Today " + timeStr
  }
  if (isTomorrow) {
    return "Tomorrow " + timeStr
  }

  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) + " " + timeStr
}

/**
 * Returns the Nerd Font icon glyph for a profile.
 * @param {string} profile
 * @returns {string}
 */
function getProfileGlyph(profile) {
  switch (String(profile).toLowerCase()) {
    case "personal": return "󰀉"
    case "work": return "󰈚"
    case "shopping": return "󰄞"
    case "study": return "󰑴"
    default: return "󰲉"
  }
}

/**
 * Returns preset quick reminder choices.
 * @returns {ReminderPreset[]}
 */
function getReminderPresets() {
  var now = new Date()
  var in30m = new Date(now.getTime() + 30 * 60 * 1000)
  var in1h = new Date(now.getTime() + 60 * 60 * 1000)

  var tom9am = new Date(now.getTime())
  tom9am.setDate(tom9am.getDate() + 1)
  tom9am.setHours(9, 0, 0, 0)

  var tom6pm = new Date(now.getTime())
  tom6pm.setDate(tom6pm.getDate() + 1)
  tom6pm.setHours(18, 0, 0, 0)

  return [
    { label: "+30m", value: in30m.toISOString() },
    { label: "+1h", value: in1h.toISOString() },
    { label: "Tomorrow 9am", value: tom9am.toISOString() },
    { label: "Tomorrow 6pm", value: tom6pm.toISOString() }
  ]
}

/**
 * Normalizes archive data into Schema v1 format.
 * @param {any} raw
 * @returns {ArchiveData}
 */
function normalizeArchive(raw) {
  var data = raw
  if (typeof raw === "string") {
    try {
      data = JSON.parse(raw || "{}")
    } catch (_e) {
      return { version: 1, archived: [] }
    }
  }
  if (!data || typeof data !== "object") {
    return { version: 1, archived: [] }
  }
  if (Array.isArray(data)) {
    return { version: 1, archived: data }
  }
  return {
    version: Number(data.version) || 1,
    archived: Array.isArray(data.archived) ? data.archived : []
  }
}

/**
 * Archives completed tasks matching the profile filter to todos-archive.json format.
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @param {string} [archiveRawText]
 * @returns {ArchiveResult}
 */
function archiveCompleted(store, profileFilter, archiveRawText) {
  var s = cloneStore(store)
  var arc = normalizeArchive(archiveRawText)
  var now = Date.now()

  /** @type {Task[]} */
  var keptTodos = []
  /** @type {ArchivedTask[]} */
  var cleared = []

  for (var i = 0; i < s.todos.length; i++) {
    var task = s.todos[i]
    var matchesFilter = (!profileFilter || profileFilter === "all" || task.profile === profileFilter)
    if (task.done && matchesFilter) {
      cleared.push({
        id: task.id,
        title: task.title,
        description: task.description || "",
        profile: task.profile || "personal",
        createdAt: task.createdAt || (typeof task.id === "number" ? task.id : now),
        completedAt: now
      })
    } else {
      keptTodos.push(task)
    }
  }

  s.todos = keptTodos
  arc.archived = cleared.concat(arc.archived)

  return {
    updatedStore: s,
    updatedArchive: arc,
    clearedCount: cleared.length
  }
}

/**
 * Gets the total number of tasks in the archive file.
 * @param {string} [archiveRawText]
 * @returns {number}
 */
function getArchivedCount(archiveRawText) {
  var arc = normalizeArchive(archiveRawText)
  return arc.archived.length
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
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
    pendingReminders,
    formatReminder,
    getProfileGlyph,
    getReminderPresets,
    normalizeArchive,
    archiveCompleted,
    getArchivedCount
  }
}
