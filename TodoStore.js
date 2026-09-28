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
 * @typedef {Object} TaskLocation
 * @property {string|null} [repo] - Git repository identifier (e.g. "Tablerase/omarchy-ardoise")
 * @property {string|null} [subpath] - Relative subpath in repo (e.g. "ui/", "server/")
 * @property {string|null} [localPath] - Local filesystem path (e.g. "~/Work/omarchy-ardoise")
 */

/**
 * @typedef {Object} Task
 * @property {number|string} id - Unique identifier (timestamp or string)
 * @property {string} title - Task title/content
 * @property {string} description - Detailed notes or description
 * @property {string} profile - Profile/category or project name (e.g. "personal", "omarchy")
 * @property {string|null} [repo] - Specific repository or component within project (e.g. "ardoise")
 * @property {string[]} [tags] - Subsystem tags/labels (e.g. ["ui", "panel"])
 * @property {TaskLocation|null} [location] - Location information
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
 * @property {string|null} [repo] - Specific repository or component within project
 * @property {string[]} [tags] - Subsystem tags/labels
 * @property {TaskLocation|null} [location] - Location information
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
 * @property {string|null} [repo]
 * @property {string[]} [tags]
 * @property {TaskLocation|string|null} [location]
 * @property {boolean} [done]
 * @property {number} [updatedAt]
 * @property {string|null} [reminder]
 * @property {string|null} [dueDate]
 * @property {boolean} [notified]
 */

/**
 * @typedef {Object} ParsedTaskInput
 * @property {string} title
 * @property {string} profile
 * @property {string|null} repo
 * @property {string[]} tags
 */

/**
 * @typedef {Object} ReminderPreset
 * @property {string} [id]
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
 * @typedef {Object} UrgencyBreakdown
 * @property {number} total
 * @property {number} overdue
 * @property {number} dueToday
 * @property {number} upcoming
 * @property {number} noReminder
 * @property {string} earliestOverdueDiff
 * @property {string} nextDueDiff
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
 * Capitalizes the first letter of a task title while preserving the rest of the text.
 * @param {string|null|undefined} title
 * @returns {string}
 */
function capitalizeTitle(title) {
  if (!title) return ""
  return String(title).replace(/^\s*\S/, function (c) {
    return c.toUpperCase()
  })
}

/**
 * Normalizes location input (string, object, or null) into a structured TaskLocation object or null.
 * @param {any} raw
 * @returns {TaskLocation|null}
 */
function normalizeLocation(raw) {
  if (!raw) return null
  if (typeof raw === "string") {
    var str = raw.trim()
    if (!str) return null
    return {
      repo: null,
      subpath: null,
      localPath: str
    }
  }
  if (typeof raw === "object") {
    var repo = raw.repo ? String(raw.repo).trim() : null
    var subpath = raw.subpath ? String(raw.subpath).trim() : null
    var localPath = raw.localPath ? String(raw.localPath).trim() : (raw.path ? String(raw.path).trim() : null)
    if (!repo && !subpath && !localPath) return null
    return {
      repo: repo,
      subpath: subpath,
      localPath: localPath
    }
  }
  return null
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
  var title = capitalizeTitle(String(raw.title || raw.text || "").trim())
  var description = String(raw.description || "")
  var profile = cleanProfileName(raw.profile)
  var repo = raw.repo ? String(raw.repo).trim() : null
  /** @type {string[]} */
  var tags = []
  if (Array.isArray(raw.tags)) {
    for (var ti = 0; ti < raw.tags.length; ti++) {
      var cleanTag = cleanProfileName(raw.tags[ti])
      if (cleanTag && tags.indexOf(cleanTag) === -1) {
        tags.push(cleanTag)
      }
    }
  }
  var location = normalizeLocation(raw.location)
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
    repo: repo,
    tags: tags,
    location: location,
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
 * Parses user input for leading #project/repo and following #tags syntax.
 *
 * Rules:
 * 1. Normalize spaces after hashtag prefix (e.g. "# work" -> "#work").
 * 2. Only scan leading hashtag tokens until the first non-hashtag word.
 * 3. First hashtag token:
 *    - #project/repo -> profile: "project", repo: "repo"
 *    - #project -> profile: "project", repo: null
 * 4. Subsequent leading hashtag tokens:
 *    - #tag1 #tag2 -> tags: ["tag1", "tag2"]
 * 5. Remainder after leading hashtags:
 *    - Everything following is preserved as the title (even if it contains #42 or C#).
 * 6. Fallback for inputs without leading hashtags:
 *    - If no leading hashtags, but contains a hashtag (e.g. "Buy milk #shopping"),
 *      extracts the profile as fallback for backward compatibility.
 *
 * @param {string} input
 * @param {string} [defaultProfile]
 * @returns {ParsedTaskInput}
 */
function parseTaskInput(input, defaultProfile) {
  var raw = String(input || "").trim()
  var defProf = defaultProfile ? cleanProfileName(defaultProfile) : "personal"
  if (!raw) {
    return { title: "", profile: defProf, repo: null, tags: [] }
  }

  // Normalize "# name" to "#name" for leading and embedded hashtags
  var normalized = raw.replace(/#\s+([a-zA-Z0-9_\-\.\/]+)/g, "#$1")

  // Check if input begins with hashtag(s)
  if (normalized.startsWith("#")) {
    var tokens = normalized.split(/\s+/)
    var hashtagTokens = []
    var titleTokens = []
    var scanningHashtags = true

    for (var i = 0; i < tokens.length; i++) {
      var tok = tokens[i]
      if (scanningHashtags) {
        if (tok.startsWith("#")) {
          hashtagTokens.push(tok)
        } else if (tok === "") {
          // Extra whitespace token
        } else {
          scanningHashtags = false
          titleTokens.push(tok)
        }
      } else {
        titleTokens.push(tok)
      }
    }

    var profile = defProf
    var repo = null
    /** @type {string[]} */
    var tags = []

    if (hashtagTokens.length > 0) {
      var first = hashtagTokens[0].replace(/^#+/, "")
      if (first.indexOf("/") !== -1) {
        var parts = first.split("/")
        profile = cleanProfileName(parts[0])
        repo = cleanProfileName(parts.slice(1).join("-"))
      } else {
        profile = cleanProfileName(first)
      }

      for (var j = 1; j < hashtagTokens.length; j++) {
        var cleanTag = cleanProfileName(hashtagTokens[j])
        if (cleanTag && tags.indexOf(cleanTag) === -1) {
          tags.push(cleanTag)
        }
      }
    }

    return {
      title: titleTokens.join(" ").trim(),
      profile: profile,
      repo: repo,
      tags: tags
    }
  }

  // Fallback: No leading hashtags. Check for embedded hashtag (e.g. "Buy milk #shopping")
  var embedded = normalized.match(/#([a-zA-Z0-9_\-\.\/]+)/)
  if (embedded) {
    var embeddedStr = embedded[1]
    var embProfile = defProf
    var embRepo = null
    if (embeddedStr.indexOf("/") !== -1) {
      var embParts = embeddedStr.split("/")
      embProfile = cleanProfileName(embParts[0])
      embRepo = cleanProfileName(embParts.slice(1).join("-"))
    } else {
      embProfile = cleanProfileName(embeddedStr)
    }
    var cleanTitle = normalized.replace(/#[a-zA-Z0-9_\-\.\/]+/g, "").replace(/\s+/g, " ").trim()
    return {
      title: cleanTitle,
      profile: embProfile,
      repo: embRepo,
      tags: []
    }
  }

  return {
    title: normalized,
    profile: defProf,
    repo: null,
    tags: []
  }
}

/**
 * Legacy compatibility wrapper for parseTaskInput.
 * @param {string} input
 * @param {string} [defaultProfile]
 * @returns {{ title: string, profile: string, repo: string|null, tags: string[] }}
 */
function parseTitleAndProfile(input, defaultProfile) {
  var res = parseTaskInput(input, defaultProfile)
  return {
    title: res.title,
    profile: res.profile,
    repo: res.repo,
    tags: res.tags
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
 * @param {TaskLocation|string|null} [location]
 * @param {string[]} [explicitTags]
 * @returns {TodoStoreData}
 */
function addTodo(store, rawTitle, description, explicitProfile, reminderTime, location, explicitTags) {
  var s = cloneStore(store)
  var parsed = parseTaskInput(rawTitle, explicitProfile || s.activeProfile)
  var title = capitalizeTitle(parsed.title)

  var hasLeadingHashtag = String(rawTitle || "").trim().startsWith("#")
  var profile = (explicitProfile && !hasLeadingHashtag && !rawTitle.match(/#\s*([a-zA-Z0-9_-]+)/))
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

  // Combine and deduplicate tags
  /** @type {string[]} */
  var tagList = []
  var rawTags = (Array.isArray(explicitTags) ? explicitTags : []).concat(parsed.tags || [])
  for (var ti = 0; ti < rawTags.length; ti++) {
    var tg = cleanProfileName(rawTags[ti])
    if (tg && tagList.indexOf(tg) === -1) {
      tagList.push(tg)
    }
  }

  var normLocation = normalizeLocation(location)
  var repo = parsed.repo || (normLocation && normLocation.repo ? normLocation.repo : null)
  if (repo && normLocation && !normLocation.repo) {
    normLocation.repo = repo
  }

  /** @type {Task} */
  var newTask = {
    id: taskId,
    title: title,
    description: String(description || ""),
    profile: profile,
    repo: repo,
    tags: tagList,
    location: normLocation,
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
      s.todos[i].updatedAt = Date.now()
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
      if (fields.description !== undefined) t.description = String(fields.description)
      if (fields.title !== undefined) {
        var rawTitle = String(fields.title).trim()
        if (rawTitle.length > 0) {
          var parsedTitle = parseTaskInput(rawTitle, t.profile)
          if (parsedTitle.title && parsedTitle.title.trim().length > 0) {
            t.title = capitalizeTitle(parsedTitle.title)
            if (rawTitle.indexOf("#") !== -1) {
              if (parsedTitle.profile && fields.profile === undefined) {
                t.profile = parsedTitle.profile
                if (s.profiles.indexOf(parsedTitle.profile) === -1) s.profiles.push(parsedTitle.profile)
              }
              if (parsedTitle.repo && fields.repo === undefined) {
                t.repo = parsedTitle.repo
              }
              if (parsedTitle.tags && parsedTitle.tags.length > 0 && fields.tags === undefined) {
                t.tags = parsedTitle.tags
              }
            }
          }
        }
      }
      if (fields.profile !== undefined) {
        var p = cleanProfileName(fields.profile)
        t.profile = p
        if (s.profiles.indexOf(p) === -1) s.profiles.push(p)
      }
      if (fields.repo !== undefined) t.repo = fields.repo ? String(fields.repo).trim() : null
      if (fields.tags !== undefined) {
        t.tags = Array.isArray(fields.tags)
          ? fields.tags.map(function (tg) { return cleanProfileName(tg) }).filter(Boolean)
          : []
      }
      if (fields.location !== undefined) {
        t.location = normalizeLocation(fields.location)
      }
      if (fields.done !== undefined) t.done = Boolean(fields.done)
      if (fields.reminder !== undefined) {
        t.reminder = fields.reminder ? String(fields.reminder) : null
        t.notified = false
      }
      if (fields.dueDate !== undefined) t.dueDate = fields.dueDate ? String(fields.dueDate) : null
      if (fields.notified !== undefined) t.notified = Boolean(fields.notified)
      break
    }
  }
  return s
}

/**
 * Marks multiple tasks by ID as notified in a single immutable pass.
 * @param {TodoStoreData} store
 * @param {(number|string)[]} ids
 * @returns {TodoStoreData}
 */
function markTasksNotified(store, ids) {
  if (!store || !Array.isArray(store.todos) || !Array.isArray(ids) || ids.length === 0) return store
  /** @type {Record<string, boolean>} */
  var idSet = {}
  for (var k = 0; k < ids.length; k++) {
    idSet[String(ids[k])] = true
  }
  var s = cloneStore(store)
  var now = Date.now()
  for (var i = 0; i < s.todos.length; i++) {
    if (idSet[String(s.todos[i].id)]) {
      s.todos[i].notified = true
      s.todos[i].updatedAt = now
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
 * Comparator function to sort tasks according to:
 * 1. Due/reminder time (incomplete tasks with reminder/dueDate, sorted by earliest due first)
 * 2. Active incomplete tasks (without reminder/dueDate, sorted by recency descending)
 * 3. Last completed tasks (completed tasks sorted by completion recency descending)
 *
 * @param {Task} a
 * @param {Task} b
 * @returns {number}
 */
function compareTasks(a, b) {
  // 1. Completion separation: incomplete tasks come before completed tasks
  var aDone = Boolean(a && a.done)
  var bDone = Boolean(b && b.done)
  if (!aDone && bDone) return -1
  if (aDone && !bDone) return 1

  // 2. Both completed: sort by last completed first (most recent updatedAt/createdAt descending)
  if (aDone && bDone) {
    var aCompTime = Math.max(Number(a.updatedAt) || 0, Number(a.createdAt) || 0)
    var bCompTime = Math.max(Number(b.updatedAt) || 0, Number(b.createdAt) || 0)
    if (bCompTime !== aCompTime) return bCompTime - aCompTime
    return String(a.title || "").localeCompare(String(b.title || ""))
  }

  // 3. Both incomplete: check due/reminder time
  var aRem = a ? (a.reminder || a.dueDate || "") : ""
  var bRem = b ? (b.reminder || b.dueDate || "") : ""
  var aRemTime = aRem ? new Date(aRem).getTime() : NaN
  var bRemTime = bRem ? new Date(bRem).getTime() : NaN
  var aHasValidRem = !isNaN(aRemTime) && aRemTime > 0
  var bHasValidRem = !isNaN(bRemTime) && bRemTime > 0

  // 3a. Tasks with due/reminder come before tasks without
  if (aHasValidRem && !bHasValidRem) return -1
  if (!aHasValidRem && bHasValidRem) return 1

  // 3b. Both have due/reminder: earliest due/reminder time first
  if (aHasValidRem && bHasValidRem) {
    if (aRemTime !== bRemTime) return aRemTime - bRemTime
    var aActiveTime = Math.max(Number(a.updatedAt) || 0, Number(a.createdAt) || 0)
    var bActiveTime = Math.max(Number(b.updatedAt) || 0, Number(b.createdAt) || 0)
    if (bActiveTime !== aActiveTime) return bActiveTime - aActiveTime
    return String(a.title || "").localeCompare(String(b.title || ""))
  }

  // 3c. Both active (no reminder): most recently updated/created first
  var aTime = Math.max(Number(a.updatedAt) || 0, Number(a.createdAt) || 0)
  var bTime = Math.max(Number(b.updatedAt) || 0, Number(b.createdAt) || 0)
  if (bTime !== aTime) return bTime - aTime
  return String(a.title || "").localeCompare(String(b.title || ""))
}

/**
 * Filters tasks according to the active profile selection and sorts them:
 * 1. By due/reminder time ascending (earliest due first)
 * 2. Active incomplete tasks (newest first)
 * 3. Last completed tasks (most recently completed first)
 *
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @param {string} [tagFilter]
 * @param {string} [repoFilter]
 * @returns {Task[]}
 */
function getFilteredTodos(store, profileFilter, tagFilter, repoFilter) {
  if (!store || !Array.isArray(store.todos)) return []
  var list = store.todos
  if (profileFilter && profileFilter !== "all") {
    var cleanFilter = cleanProfileName(profileFilter)
    list = list.filter(function (t) {
      return cleanProfileName(t.profile) === cleanFilter
    })
  }
  if (tagFilter && tagFilter !== "all") {
    var cleanTag = cleanProfileName(tagFilter)
    list = list.filter(function (t) {
      return Array.isArray(t.tags) && t.tags.indexOf(cleanTag) !== -1
    })
  }
  if (repoFilter && repoFilter !== "all") {
    var cleanRepo = cleanProfileName(repoFilter)
    list = list.filter(function (t) {
      return (t.repo && cleanProfileName(t.repo) === cleanRepo) ||
             (t.location && t.location.repo && cleanProfileName(t.location.repo) === cleanRepo)
    })
  }
  return list.slice().sort(compareTasks)
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
 * Checks whether a task is overdue (reminder date is past now and not completed).
 * @param {Task|null|undefined} task
 * @returns {boolean}
 */
function isOverdue(task) {
  if (!task || task.done || !task.reminder) return false
  var time = new Date(task.reminder).getTime()
  return !isNaN(time) && time < Date.now()
}

/**
 * Formats a millisecond time difference into a compact relative duration label.
 * @param {number} diffMs - Difference in ms.
 * @param {boolean} isPast - True if the event is in the past.
 * @returns {string}
 */
function formatRelativeDiff(diffMs, isPast) {
  var abs = Math.abs(diffMs)
  var mins = Math.floor(abs / 60000)
  var hours = Math.floor(abs / 3600000)
  var days = Math.floor(abs / 86400000)

  if (isPast) {
    if (mins < 1) return "just now"
    if (mins < 60) return mins + "m overdue"
    if (hours < 24) return hours + "h overdue"
    return days + "d overdue"
  } else {
    if (mins < 1) return "in <1m"
    if (mins < 60) return "in " + mins + "m"
    if (hours < 24) return "in " + hours + "h"
    return "in " + days + "d"
  }
}

/**
 * Creates a text progress bar string (e.g. [████░░░░]).
 * @param {number} done
 * @param {number} total
 * @param {number} [barLen]
 * @returns {string}
 */
function makeProgressBar(done, total, barLen) {
  var len = barLen || 8
  if (!total || total <= 0) return "[" + "░".repeat(len) + "]"
  var ratio = Math.max(0, Math.min(1, done / total))
  var filled = Math.round(ratio * len)
  var empty = len - filled
  return "[" + "█".repeat(filled) + "░".repeat(empty) + "]"
}

/**
 * Calculates a detailed urgency breakdown of all pending tasks.
 * @param {TodoStoreData} store
 * @param {number} [customNow] - Optional timestamp for testing
 * @returns {UrgencyBreakdown}
 */
function getTaskUrgencyBreakdown(store, customNow) {
  var now = typeof customNow === "number" ? customNow : Date.now()
  var nowDate = new Date(now)
  var endOfToday = new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate(), 23, 59, 59, 999).getTime()

  var result = {
    total: 0,
    overdue: 0,
    dueToday: 0,
    upcoming: 0,
    noReminder: 0,
    earliestOverdueDiff: "",
    nextDueDiff: ""
  }

  if (!store || !Array.isArray(store.todos)) return result

  var minOverdueTime = Infinity
  var minFutureTime = Infinity

  for (var i = 0; i < store.todos.length; i++) {
    var t = store.todos[i]
    if (t.done) continue
    result.total++

    if (!t.reminder) {
      result.noReminder++
      continue
    }

    var time = new Date(t.reminder).getTime()
    if (isNaN(time)) {
      result.noReminder++
      continue
    }

    if (time < now) {
      result.overdue++
      if (time < minOverdueTime) {
        minOverdueTime = time
      }
    } else if (time <= endOfToday) {
      result.dueToday++
      if (time < minFutureTime) {
        minFutureTime = time
      }
    } else {
      result.upcoming++
      if (time < minFutureTime) {
        minFutureTime = time
      }
    }
  }

  if (minOverdueTime !== Infinity) {
    result.earliestOverdueDiff = formatRelativeDiff(now - minOverdueTime, true)
  }
  if (minFutureTime !== Infinity) {
    result.nextDueDiff = formatRelativeDiff(minFutureTime - now, false)
  }

  return result
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

  if (isToday) {
    return timeStr
  }

  if (diff < 0) {
    return "Due " + d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
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
 * @param {Date|number|string} [baseDate]
 * @returns {ReminderPreset[]}
 */
function getReminderPresets(baseDate) {
  var now = new Date()
  if (baseDate instanceof Date && !isNaN(baseDate.getTime())) {
    now = baseDate
  } else if (typeof baseDate === "number" && !isNaN(baseDate)) {
    now = new Date(baseDate)
  } else if (typeof baseDate === "string" && baseDate.length > 0) {
    var parsed = new Date(baseDate)
    if (!isNaN(parsed.getTime())) now = parsed
  }

  var in30m = new Date(now.getTime() + 30 * 60 * 1000)
  var in1h = new Date(now.getTime() + 60 * 60 * 1000)

  var tom9am = new Date(now.getTime())
  tom9am.setDate(tom9am.getDate() + 1)
  tom9am.setHours(9, 0, 0, 0)

  var tom6pm = new Date(now.getTime())
  tom6pm.setDate(tom6pm.getDate() + 1)
  tom6pm.setHours(18, 0, 0, 0)

  return [
    { id: "30m", label: "+30m", value: in30m.toISOString() },
    { id: "1h", label: "+1h", value: in1h.toISOString() },
    { id: "tom9am", label: "Tomorrow 9am", value: tom9am.toISOString() },
    { id: "tom6pm", label: "Tomorrow 6pm", value: tom6pm.toISOString() }
  ]
}

/**
 * Computes a fresh ISO reminder timestamp for a given preset index or identifier.
 * @param {number|string} presetIndexOrId
 * @param {Date|number|string} [baseDate]
 * @returns {string|null}
 */
function computePresetReminder(presetIndexOrId, baseDate) {
  var presets = getReminderPresets(baseDate)
  if (typeof presetIndexOrId === "number") {
    if (presetIndexOrId >= 0 && presetIndexOrId < presets.length) {
      return presets[presetIndexOrId].value
    }
  } else if (typeof presetIndexOrId === "string") {
    for (var i = 0; i < presets.length; i++) {
      if (presets[i].id === presetIndexOrId || presets[i].label === presetIndexOrId) {
        return presets[i].value
      }
    }
  }
  return null
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
  var rawList = Array.isArray(data) ? data : (Array.isArray(data.archived) ? data.archived : [])
  /** @type {ArchivedTask[]} */
  var archived = []
  var now = Date.now()
  for (var i = 0; i < rawList.length; i++) {
    var item = rawList[i]
    if (!item || typeof item !== "object") continue
    /** @type {string[]} */
    var itemTags = []
    if (Array.isArray(item.tags)) {
      for (var iti = 0; iti < item.tags.length; iti++) {
        var cleanItemTag = cleanProfileName(item.tags[iti])
        if (cleanItemTag && itemTags.indexOf(cleanItemTag) === -1) {
          itemTags.push(cleanItemTag)
        }
      }
    }
    archived.push({
      id: item.id !== undefined && item.id !== null ? item.id : now,
      title: capitalizeTitle(String(item.title || item.text || "").trim()),
      description: String(item.description || ""),
      profile: cleanProfileName(item.profile),
      repo: item.repo ? String(item.repo).trim() : null,
      tags: itemTags,
      location: normalizeLocation(item.location),
      createdAt: Number(item.createdAt) || now,
      completedAt: Number(item.completedAt) || now
    })
  }
  return {
    version: Number(data.version) || 1,
    archived: archived
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
        repo: task.repo || null,
        tags: Array.isArray(task.tags) ? task.tags : [],
        location: task.location || null,
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

/**
 * Formats Hyprland modmask and key into a human-readable shortcut string.
 * Hyprland bitmasks:
 * - Bit 6 (64): SUPER
 * - Bit 2 (4): CTRL
 * - Bit 3 (8): ALT
 * - Bit 0 (1): SHIFT
 * @param {number|null|undefined} modmask
 * @param {string|null|undefined} key
 * @returns {string}
 */
function formatKeybind(modmask, key) {
  var mask = Number(modmask) || 0
  var parts = []
  if (mask & 64) parts.push("SUPER")
  if (mask & 4) parts.push("CTRL")
  if (mask & 8) parts.push("ALT")
  if (mask & 1) parts.push("SHIFT")
  if (key) {
    parts.push(String(key).trim().toUpperCase())
  }
  return parts.join(" + ")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
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
    makeProgressBar,
    markTasksNotified,
    capitalizeTitle
  }
}

