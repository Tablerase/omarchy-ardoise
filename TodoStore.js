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
 * @property {string|null} [repoName] - Repository name or folder basename
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
 * @property {boolean} [isTutorial] - Whether this is an onboarding quest task
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
 * @property {Record<string, string>} [profileIcons] - Custom icon glyph mapping per profile name
 * @property {string[]} [recentIcons] - Most recently applied icon glyphs (capped to 18)
 * @property {boolean} [tutorialSeeded] - Whether onboarding tasks were seeded
 * @property {string} [lastSeenVersion] - Last viewed release version
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

var CURRENT_SCHEMA_VERSION = 1
var CURRENT_ARCHIVE_VERSION = 1
var CURRENT_RELEASE_VERSION = "1.0.0"

var RELEASE_HIGHLIGHTS = {
  version: CURRENT_RELEASE_VERSION,
  title: "What's new in v" + CURRENT_RELEASE_VERSION,
  summary: "Welcome to Ardoise! Keyboard-first task management with Vim motions, Quick Add, and automatic Git snapshots.",
  items: [
    { icon: "󰞔", title: "Keyboard-First Invariants", desc: "Vim motions (j/k, h/l, g/G), two-stage Escape, and non-blocking modals." },
    { icon: "󰌌", title: "Zero-Setup Global Shortcuts", desc: "Super+Alt+T to open Panel, Super+Shift+T for instant Quick Add from anywhere." },
    { icon: "󰊢", title: "Git Snapshots & Recovery", desc: "Automatic local versioning, undo checkpoints, and git remote sync." },
    { icon: "󰄬", title: "Urgency Ladder & Reminders", desc: "Smart presets, dynamic color escalation, and quiet background notifications." }
  ],
  highlights: [
    "Keyboard-First Task Slate: Full vim motions (j/k, h/l, g/G, Tab, Space, Enter)",
    "Two-Stage Escape: Blurs to container mode without losing draft notes or input text",
    "Custom Reminder Picker: Natural language parsing ('2h', '17:30', 'tomorrow 9am') & mini-calendar",
    "Intelligent 3-Tier Profile Resolution: Detects workspace context across Zed, VS Code, Neovim, and Tmux",
    "Zero-Config Git Snapshots: Automatic background backups, commit diffs, and instant rollback",
    "Hold-to-Confirm Safeguards: 800ms laser progress bar for deletions without annoying modal dialogs"
  ]
}

/**
 * Returns the sequence of 8 interactive onboarding quest tasks.
 * @param {number} [baseTime]
 * @returns {Task[]}
 */
function getTutorialTasks(baseTime) {
  var t0 = baseTime || Date.now()
  return [
    {
      id: t0 + 8,
      title: "󰞔 Navigate with j / k (or ↓ / ↑)",
      description: "Ardoise is 100% keyboard-first! Use vim motions j and k to move smoothly through your tasks.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 8,
      updatedAt: t0 + 8,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 7,
      title: "󰄬 Press Space to complete this task (not Enter!)",
      description: "Space toggles task completion. In Ardoise, Space toggles done while Enter expands details.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 7,
      updatedAt: t0 + 7,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 6,
      title: "󰭤 Press h / l (or ← / →) to switch between profiles",
      description: "Filter tasks by profile (personal, work, #projects). Use vim motions h and l (or [ and ]) to cycle profiles, or press Tab to focus the profile pills.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 6,
      updatedAt: t0 + 6,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 5,
      title: "󰅂 Press Enter to open notes & explore reminders",
      description: "Enter expands this details drawer. Try typing a note, or pick a reminder preset like '+30m' or '󰃭 Custom...'. Two-stage Escape blurs back to the list without losing your draft!",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 5,
      updatedAt: t0 + 5,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 4,
      title: "󰌌 Set up global shortcuts for Panel & QuickAdd (expand for setup)",
      description: "Summon Ardoise from anywhere in Hyprland!\n\nAdd to ~/.config/hypr/bindings.lua (or click 󰌌 in header to copy & open):\no.bind(\"SUPER + ALT + T\", \"Ardoise Panel\", \"omarchy-shell tablerase.ardoise toggle\")\no.bind(\"SUPER + SHIFT + T\", \"Ardoise Quick Add\", \"omarchy-shell shell toggle tablerase.ardoise '{}'\")",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 4,
      updatedAt: t0 + 4,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 3,
      title: "󰐕 Press Shift+A (or Super+Shift+T) to open Quick Add modal",
      description: "Quick Add is Ardoise's premier task entry surface! Press Shift+A (capital A) to open it from the panel (lowercase 'a' or 'i' focuses the in-panel input field). Try adding a task title, typing a #profile or #tag to route it, or toggling a note/reminder before pressing Enter to submit.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 3,
      updatedAt: t0 + 3,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 2,
      title: "󰋖 Press ? to view all keybindings & Lua overrides",
      description: "Opens the cheat sheet with interactive search filter, and tips for ~/.config/omarchy/tablerase.ardoise/bindings.lua.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 2,
      updatedAt: t0 + 2,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    },
    {
      id: t0 + 1,
      title: "󰅙 Hold x to permanently delete this tutorial task",
      description: "Ardoise uses an 800ms hold-to-confirm laser progress bar for permanent deletions, eliminating confirmation modals.",
      profile: "personal",
      done: false,
      isTutorial: true,
      createdAt: t0 + 1,
      updatedAt: t0 + 1,
      repo: null,
      tags: [],
      location: null,
      dueDate: null,
      reminder: null,
      notified: false
    }
  ]
}

/**
 * Creates an empty default Schema v1 store.
 * @param {boolean} [withTutorial=false]
 * @returns {TodoStoreData}
 */
function defaultStore(withTutorial) {
  return {
    version: CURRENT_SCHEMA_VERSION,
    activeProfile: "personal",
    profiles: ["personal", "work"],
    todos: withTutorial ? getTutorialTasks() : [],
    tutorialSeeded: Boolean(withTutorial),
    lastSeenVersion: CURRENT_RELEASE_VERSION
  }
}

/**
 * Creates a brand new initial store seeded with interactive onboarding quest tasks.
 * @returns {TodoStoreData}
 */
function createInitialStore() {
  return defaultStore(true)
}

/**
 * Seeds the 8 interactive onboarding tasks into the store, avoiding duplicates.
 * @param {TodoStoreData} store
 * @returns {TodoStoreData}
 */
function seedTutorialTasks(store) {
  var s = cloneStore(store)
  var tutorial = getTutorialTasks()
  /** @type {Record<string, boolean>} */
  var existingTitles = {}
  for (var i = 0; i < s.todos.length; i++) {
    if (s.todos[i] && s.todos[i].title) {
      existingTitles[s.todos[i].title] = true
    }
  }

  var toAdd = []
  for (var j = 0; j < tutorial.length; j++) {
    if (!existingTitles[tutorial[j].title]) {
      toAdd.push(tutorial[j])
    }
  }

  s.todos = toAdd.concat(s.todos)
  s.tutorialSeeded = true
  s.lastSeenVersion = CURRENT_RELEASE_VERSION
  return s
}

/**
 * Checks whether there is a new release update to highlight to the user.
 * Returns true if store is initialized and lastSeenVersion is older than CURRENT_RELEASE_VERSION.
 * @param {TodoStoreData|null|undefined} store
 * @returns {boolean}
 */
function hasNewRelease(store) {
  if (!store) return false
  if (store.lastSeenVersion === CURRENT_RELEASE_VERSION) return false
  return true
}

/**
 * Marks the current release as seen in store metadata.
 * @param {TodoStoreData} store
 * @returns {TodoStoreData}
 */
function markReleaseSeen(store) {
  var s = cloneStore(store)
  s.lastSeenVersion = CURRENT_RELEASE_VERSION
  return s
}

/**
 * Resets release highlights seen state so the banner and indicators appear again.
 * @param {TodoStoreData} store
 * @returns {TodoStoreData}
 */
function resetReleaseHighlights(store) {
  var s = cloneStore(store)
  s.lastSeenVersion = "0.9.0"
  return s
}

/**
 * Returns human-readable command reference and usage signatures for all IPC endpoints.
 * @returns {string}
 */
function getIpcHelp() {
  return [
    "Ardoise IPC Commands Reference (omarchy-shell tablerase.ardoise <command> [args])",
    "",
    "PANEL & VISIBILITY:",
    "  toggle                           Toggle main panel on compositor-focused monitor",
    "  open                             Open main panel on compositor-focused monitor",
    "  close                            Close all open panel instances",
    "  help                             Show this CLI and agent command reference",
    "",
    "TASKS & LIST LIFECYCLE:",
    "  list                             Return full JSON array of active tasks",
    "  get <id>                         Get single task JSON by ID (active or archived)",
    "  count                            Return total pending task count string",
    "  add <title>                      Add new task (supports #profile and #tags)",
    "  addDetailed <title> <notes> <r>  Add task with explicit notes and reminder (+1h, ISO)",
    "  toggleTodo <id>                  Toggle task completion (done)",
    "  update <id> <fieldsJson>         Update task properties (reminder, notes, profile)",
    "  remove <id>                      Delete task by ID",
    "  clear                            Archive and clear completed tasks in current filter",
    "",
    "PROFILES:",
    "  profiles                         Return array of configured profile names",
    "  searchProfiles <query>           Search profiles matching substring",
    "  setProfile <profile>             Switch active profile filter",
    "  setProfileIcon <p> <glyph>       Set custom Nerd Font icon for profile",
    "  getProfileIcons                  Return JSON map of custom profile icons",
    "",
    "ARCHIVE BROWSER:",
    "  archived                         Return raw archive JSON string",
    "  archiveCount                     Return count of archived tasks",
    "  unarchive <id>                   Restore archived task back to active store",
    "  purgeArchived <id>               Permanently delete task from archive",
    "",
    "GIT BACKUPS & REMOTE SYNC:",
    "  gitHistory                       Return JSON array of commit snapshots",
    "  gitSearch <query>                Search snapshots by query, #device, hash, or author",
    "  gitRollback <hash>               Revert active and archive stores to commit snapshot",
    "  gitRecover <hash>                Selectively recover missing tasks from snapshot",
    "  gitSync                          Sync tasks with remote repository (3-way merge)",
    "  gitSetRemote <url>               Configure Git remote URL",
    "  gitGetRemote                     Get configured Git remote URL",
    "  autoSetupGitRemote [name]        Create private GitHub repository via gh CLI",
    "  gitAutoSetup [name]              Alias for autoSetupGitRemote",
    "",
    "ONBOARDING & RELEASE HIGHLIGHTS:",
    "  seedTutorial                     Seed 8 interactive onboarding quest tasks into store",
    "  whatsNew                         Return release highlights metadata JSON",
    "  markReleaseSeen                  Acknowledge release highlights in store metadata",
    "  resetReleaseHighlights           Reset seen status to re-display banner & highlights"
  ].join("\n")
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
  if (profile === "all") profile = "personal"
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

  /** @type {Task & Record<string, any>} */
  var task = {
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

  // Forward compatibility: preserve unknown fields introduced by newer schemas
  for (var k in raw) {
    if (Object.prototype.hasOwnProperty.call(raw, k) && !(k in task)) {
      task[k] = raw[k]
    }
  }

  return task
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
      version: CURRENT_SCHEMA_VERSION,
      activeProfile: "personal",
      profiles: profileList,
      todos: legacyTodos
    }
  }

  // Schema format (v1 or future)
  var rawVersion = typeof data.version === "number" ? data.version : (Number(data.version) || CURRENT_SCHEMA_VERSION)
  var resolvedVersion = Math.max(CURRENT_SCHEMA_VERSION, rawVersion)
  var activeProfile = (data.activeProfile && data.activeProfile !== "all") ? cleanProfileName(data.activeProfile) : "personal"
  /** @type {string[]} */
  var profiles = ["personal", "work"]
  /** @type {Record<string, boolean>} */
  var seenProfiles = { "personal": true, "work": true, "all": true }

  if (Array.isArray(data.profiles)) {
    for (var p = 0; p < data.profiles.length; p++) {
      var c = cleanProfileName(data.profiles[p])
      if (c && c !== "all" && !seenProfiles[c]) {
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

  /** @type {Record<string, string>} */
  var profileIcons = {}
  if (data.profileIcons && typeof data.profileIcons === "object" && !Array.isArray(data.profileIcons)) {
    for (var iconKey in data.profileIcons) {
      if (Object.prototype.hasOwnProperty.call(data.profileIcons, iconKey)) {
        var cleanKey = cleanProfileName(iconKey).toLowerCase()
        var val = data.profileIcons[iconKey]
        if (cleanKey && typeof val === "string" && val.trim()) {
          profileIcons[cleanKey] = val.trim()
        }
      }
    }
  }

  /** @type {string[]} */
  var recentIcons = []
  if (Array.isArray(data.recentIcons)) {
    for (var ri = 0; ri < data.recentIcons.length; ri++) {
      var rGlyph = data.recentIcons[ri]
      if (typeof rGlyph === "string" && rGlyph.trim() && recentIcons.indexOf(rGlyph.trim()) === -1) {
        recentIcons.push(rGlyph.trim())
        if (recentIcons.length >= 18) break
      }
    }
  }

  /** @type {TodoStoreData & Record<string, any>} */
  var store = {
    version: resolvedVersion,
    activeProfile: activeProfile,
    profiles: profiles,
    todos: todos,
    profileIcons: profileIcons,
    recentIcons: recentIcons
  }

  // Forward compatibility: preserve root properties introduced by future schemas
  for (var k in data) {
    if (Object.prototype.hasOwnProperty.call(data, k) && !(k in store)) {
      store[k] = data[k]
    }
  }

  return store
}

/**
 * Parses user input for leading #project/repo and following/trailing #tags syntax.
 *
 * Rules:
 * 1. Normalize spaces after hashtag prefix (e.g. "# work" -> "#work").
 * 2. Scan leading hashtag tokens until the first non-hashtag word.
 * 3. First hashtag token:
 *    - #project/repo -> profile: "project", repo: "repo"
 *    - #project -> profile: "project", repo: null
 * 4. Subsequent leading hashtag tokens:
 *    - #tag1 #tag2 -> tags: ["tag1", "tag2"]
 * 5. Trailing hashtag tokens:
 *    - Trailing #tags placed after the title (e.g. "#work Fix navbar #ui") are extracted as tags.
 *    - Issue numbers (e.g. #42) are preserved as part of the title.
 * 6. Fallback for inputs without leading hashtags:
 *    - If no leading hashtags, but contains hashtags (e.g. "Buy milk #shopping" or "Buy milk #work #shopping"),
 *      first embedded hashtag sets the profile, subsequent ones become tags, and they are cleanly removed from title.
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

    // Extract trailing hashtag tokens from titleTokens (e.g. "#work Fix navbar #ui #urgent")
    // Preserve issue numbers (e.g. #42) as part of the title
    var trailingHashtags = []
    while (titleTokens.length > 0) {
      var lastTok = titleTokens[titleTokens.length - 1]
      if (lastTok && lastTok.startsWith("#") && !/^#\d+$/.test(lastTok)) {
        var popped = titleTokens.pop()
        if (popped) {
          trailingHashtags.unshift(popped)
        }
      } else {
        break
      }
    }
    for (var k = 0; k < trailingHashtags.length; k++) {
      var tTok = trailingHashtags[k]
      if (tTok) {
        hashtagTokens.push(tTok)
      }
    }

    var profile = defProf
    var repo = null
    /** @type {string[]} */
    var tags = []

    if (hashtagTokens.length > 0 && hashtagTokens[0]) {
      var first = hashtagTokens[0].replace(/^#+/, "")
      if (first.indexOf("/") !== -1) {
        var parts = first.split("/")
        profile = cleanProfileName(parts[0])
        repo = cleanProfileName(parts.slice(1).join("-"))
      } else {
        profile = cleanProfileName(first)
      }

      for (var j = 1; j < hashtagTokens.length; j++) {
        var hTok = hashtagTokens[j]
        if (hTok) {
          var cleanTag = cleanProfileName(hTok)
          if (cleanTag && tags.indexOf(cleanTag) === -1) {
            tags.push(cleanTag)
          }
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

  // Fallback: No leading hashtags. Check for embedded hashtag (e.g. "Buy milk #shopping" or "Fix bug #work #ui")
  var embedded = normalized.match(/#([a-zA-Z0-9_\-\.\/]+)/)
  if (embedded) {
    var rawMatches = normalized.match(/#([a-zA-Z0-9_\-\.\/]+)/g) || []
    var validHashtags = []
    for (var m = 0; m < rawMatches.length; m++) {
      var mTok = rawMatches[m]
      if (mTok && !/^#\d+$/.test(mTok)) {
        validHashtags.push(mTok)
      }
    }

    if (validHashtags.length > 0 && validHashtags[0]) {
      var embFirst = validHashtags[0].replace(/^#+/, "")
      var embProfile = defProf
      var embRepo = null
      if (embFirst.indexOf("/") !== -1) {
        var embParts = embFirst.split("/")
        embProfile = cleanProfileName(embParts[0])
        embRepo = cleanProfileName(embParts.slice(1).join("-"))
      } else {
        embProfile = cleanProfileName(embFirst)
      }

      /** @type {string[]} */
      var embTags = []
      for (var n = 1; n < validHashtags.length; n++) {
        var nTok = validHashtags[n]
        if (nTok) {
          var embTag = cleanProfileName(nTok)
          if (embTag && embTags.indexOf(embTag) === -1) {
            embTags.push(embTag)
          }
        }
      }

      // Remove valid hashtags from title while preserving issue numbers (#42)
      var cleanTitle = normalized
      for (var p = 0; p < validHashtags.length; p++) {
        var pTok = validHashtags[p]
        if (pTok) {
          var escaped = pTok.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
          cleanTitle = cleanTitle.replace(new RegExp("(^|\\s)" + escaped + "(?=\\s|$)", "g"), " ")
        }
      }
      cleanTitle = cleanTitle.replace(/\s+/g, " ").trim()

      return {
        title: cleanTitle,
        profile: embProfile,
        repo: embRepo,
        tags: embTags
      }
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
 * Looks up a task by ID in the active store.
 * @param {TodoStoreData} store
 * @param {number|string} id
 * @returns {Task|null}
 */
function getTaskById(store, id) {
  if (!store || !Array.isArray(store.todos)) return null
  var idStr = String(id)
  for (var i = 0; i < store.todos.length; i++) {
    if (store.todos[i] && String(store.todos[i].id) === idStr) {
      return store.todos[i]
    }
  }
  return null
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
  if (p && p !== "all" && s.profiles.indexOf(p) === -1) {
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
 * Sets or removes a custom icon glyph for a profile.
 * If glyph is empty, null, or undefined, the custom icon override is removed.
 * @param {TodoStoreData} store
 * @param {string} profile
 * @param {string|null|undefined} glyph
 * @returns {TodoStoreData}
 */
function setProfileIcon(store, profile, glyph) {
  var s = cloneStore(store)
  var p = cleanProfileName(profile).toLowerCase()
  if (!p || p === "all") return s

  if (!s.profileIcons || typeof s.profileIcons !== "object") {
    s.profileIcons = {}
  } else {
    s.profileIcons = Object.assign({}, s.profileIcons)
  }

  var iconStr = (typeof glyph === "string") ? glyph.trim() : ""
  if (iconStr) {
    s.profileIcons[p] = iconStr

    var rList = Array.isArray(s.recentIcons) ? s.recentIcons.slice() : []
    rList = rList.filter(function(g) { return g !== iconStr })
    rList.unshift(iconStr)
    s.recentIcons = rList.slice(0, 18)
  } else {
    delete s.profileIcons[p]
  }

  return s
}

/**
 * Returns a copy of the custom profile icon mapping.
 * @param {TodoStoreData|null|undefined} store
 * @returns {Record<string, string>}
 */
function getProfileIcons(store) {
  if (!store || !store.profileIcons || typeof store.profileIcons !== "object") {
    return {}
  }
  return Object.assign({}, store.profileIcons)
}

/**
 * Clears completed tasks matching an optional profile filter.
 * @param {TodoStoreData} store
 * @param {string} [profileFilter]
 * @returns {TodoStoreData}
 */
function clearCompleted(store, profileFilter) {
  var s = cloneStore(store)
  var cleanFilter = (profileFilter && profileFilter !== "all") ? cleanProfileName(profileFilter) : (profileFilter === "all" ? "all" : null)
  if (cleanFilter && cleanFilter !== "all") {
    s.todos = s.todos.filter(function (t) {
      return !t.done || cleanProfileName(t.profile || "personal") !== cleanFilter
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
 * @param {string} [searchFilter]
 * @returns {Task[]}
 */
function getFilteredTodos(store, profileFilter, tagFilter, repoFilter, searchFilter) {
  if (!store || !Array.isArray(store.todos)) return []
  var list = store.todos
  var rawSearch = searchFilter ? String(searchFilter).trim() : ""
  var isHashSearch = rawSearch.charAt(0) === "#"
  if (profileFilter && profileFilter !== "all" && !isHashSearch) {
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
  if (searchFilter) {
    var rawQ = String(searchFilter).trim()
    if (rawQ) {
      var isHash = rawQ.charAt(0) === "#"
      var cleanQ = rawQ.replace(/^#+/, "").toLowerCase().trim()
      list = list.filter(function (t) {
        if (isHash && cleanQ) {
          var profMatch = Boolean(t.profile && cleanProfileName(t.profile).toLowerCase().includes(cleanQ))
          var tagMatch = Boolean(Array.isArray(t.tags) && t.tags.some(function (tag) { return String(tag).toLowerCase().includes(cleanQ) }))
          return profMatch || tagMatch
        }
        var q = rawQ.toLowerCase()
        var inTitle = Boolean(t.title && t.title.toLowerCase().includes(q))
        var inDesc = Boolean(t.description && t.description.toLowerCase().includes(q))
        var inRepo = Boolean((t.repo && t.repo.toLowerCase().includes(q)) || (t.location && t.location.repo && t.location.repo.toLowerCase().includes(q)))
        var inTags = Boolean(Array.isArray(t.tags) && t.tags.some(function (tag) { return String(tag).toLowerCase().includes(q) }))
        var inProf = Boolean(t.profile && cleanProfileName(t.profile).toLowerCase().includes(q))
        return inTitle || inDesc || inRepo || inTags || inProf
      })
    }
  }
  return list.slice().sort(compareTasks)
}

/**
 * Searches and returns sorted profile names matching a query.
 * @param {TodoStoreData|null|undefined} store
 * @param {string} [query]
 * @returns {string[]}
 */
function searchProfiles(store, query) {
  var profs = getSortedProfiles(store, false)
  if (!query) return profs
  var cleanQuery = String(query).replace(/^#+/, "").toLowerCase().trim()
  if (!cleanQuery) return profs
  return profs.filter(function (p) {
    return p.toLowerCase().includes(cleanQuery)
  })
}

/**
 * Returns all unique tags used across tasks in the store, sorted by usage frequency descending, then alphabetical.
 * @param {TodoStoreData|null|undefined} store
 * @returns {string[]}
 */
function getAllTags(store) {
  if (!store || !Array.isArray(store.todos)) return []
  /** @type {Record<string, number>} */
  var counts = {}
  for (var i = 0; i < store.todos.length; i++) {
    var t = store.todos[i]
    if (Array.isArray(t.tags)) {
      for (var j = 0; j < t.tags.length; j++) {
        var tag = t.tags[j]
        if (tag && typeof tag === "string") {
          counts[tag] = (counts[tag] || 0) + 1
        }
      }
    }
  }
  return Object.keys(counts).sort(function (a, b) {
    var diff = counts[b] - counts[a]
    if (diff !== 0) return diff
    return a.localeCompare(b)
  })
}

/**
 * Searches and returns sorted tags matching a query.
 * @param {TodoStoreData|null|undefined} store
 * @param {string} [query]
 * @returns {string[]}
 */
function searchTags(store, query) {
  var tags = getAllTags(store)
  if (!query) return tags
  var cleanQuery = String(query).replace(/^#+/, "").toLowerCase().trim()
  if (!cleanQuery) return tags
  return tags.filter(function (t) {
    return t.toLowerCase().includes(cleanQuery)
  })
}

/**
 * Resolves the intelligent default profile using a 3-tier hierarchy:
 * 1. Last profile used for this location (matching repo or localPath), or matching candidate name
 * 2. Last profile used globally across the store (by latest task activity)
 * 3. Default fallback (store.activeProfile || "personal")
 *
 * @param {TodoStoreData|null|undefined} store
 * @param {TaskLocation|{ repo?: string|null, localPath?: string|null, repoName?: string|null }|null|undefined} [context]
 * @returns {string}
 */
function resolveDefaultProfile(store, context) {
  var def = (store && store.activeProfile) ? cleanProfileName(store.activeProfile) : "personal"
  if (!store || !Array.isArray(store.todos)) return def

  // If outside of any workspace context (e.g. browser, desktop apps, or no active location),
  // directly fallback to the default profile (store.activeProfile || "personal"),
  // skipping global recency so non-work tasks aren't assigned to the last touched project.
  if (!context || (!context.repo && !context.localPath)) {
    return def
  }

  // Tier 1: Check tasks with matching location context (most recent first)
  var matchRepo = context.repo ? String(context.repo).toLowerCase().trim() : null
  var matchPath = context.localPath ? String(context.localPath).trim() : null

  var latestLocTime = -1
  var latestLocProfile = null

  for (var i = 0; i < store.todos.length; i++) {
    var t = store.todos[i]
    if (t && t.location) {
      var tRepo = t.location.repo ? String(t.location.repo).toLowerCase().trim() : null
      var tPath = t.location.localPath ? String(t.location.localPath).trim() : null

      var isMatch = false
      if (matchRepo && tRepo && matchRepo === tRepo) {
        isMatch = true
      } else if (matchPath && tPath && matchPath === tPath) {
        isMatch = true
      }

      if (isMatch && t.profile) {
        var time = Number(t.updatedAt || t.createdAt || 0)
        if (time > latestLocTime) {
          latestLocTime = time
          latestLocProfile = cleanProfileName(t.profile)
        }
      }
    }
  }

  if (latestLocProfile) {
    return latestLocProfile
  }

  // Tier 1b: If no existing tasks for this location, check if repo or repoName directly matches a known profile
  if (Array.isArray(store.profiles)) {
    var candidates = []
    if (context.repo) {
      var parts = String(context.repo).split("/")
      candidates.push(cleanProfileName(parts[parts.length - 1]))
      candidates.push(cleanProfileName(parts[0]))
    }
    if (context.repoName) {
      candidates.push(cleanProfileName(context.repoName))
    }
    for (var c = 0; c < candidates.length; c++) {
      var cand = candidates[c]
      if (cand && store.profiles.indexOf(cand) !== -1) {
        return cand
      }
    }
  }

  // Tier 2: Inside an unrecognized workspace without prior tasks/matching profiles:
  // Fall back to the last profile used globally across all tasks (by latest activity timestamp)
  var latestGlobalTime = -1
  var latestGlobalProfile = null

  for (var j = 0; j < store.todos.length; j++) {
    var task = store.todos[j]
    if (task && task.profile) {
      var taskTime = Number(task.updatedAt || task.createdAt || 0)
      if (taskTime > latestGlobalTime) {
        latestGlobalTime = taskTime
        latestGlobalProfile = cleanProfileName(task.profile)
      }
    }
  }

  if (latestGlobalProfile) {
    return latestGlobalProfile
  }

  // Tier 3: Default fallback
  return def
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
  var seen = { "all": true }

  var sourceProfiles = (store && Array.isArray(store.profiles)) ? store.profiles : ["personal", "work"]
  for (var i = 0; i < sourceProfiles.length; i++) {
    var p = cleanProfileName(sourceProfiles[i])
    if (p && p !== "all" && !seen[p]) {
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
    if (!prof || prof === "all") continue

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
    var activeProf = (store && store.activeProfile && store.activeProfile !== "all") ? cleanProfileName(store.activeProfile) : "personal"
    var cleanFilter = (currentFilter && currentFilter !== "all") ? cleanProfileName(currentFilter) : ""
    profList = profList.filter(function (name) {
      return (name !== "all") && ((counts[name] > 0) || (Boolean(cleanFilter) && name === cleanFilter) || (name === activeProf))
    })
    if (profList.length === 0) {
      profList.push(activeProf || "personal")
    }
  }

  return profList.filter(function (name) { return name !== "all" })
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

// Task-slate ladder. The bar widget, the panel brand header and the quick-add
// header all share this ladder, so the plugin reports load identically
// everywhere. Rungs are driven by urgency rather than raw count, matching the
// way omarchy's own battery/wifi/volume widgets swap on meaningful state.
//
// The colour ramp IS the severity channel: foreground -> accent -> warning.
// "due" is informational (a task due today is on track), so it stays accent
// and only genuinely late tasks escalate to warning. The urgent role is
// deliberately absent from every rung: red is reserved for real error
// surfaces, so an orange task is late and a red task is broken. Guarded by a
// test asserting no rung uses "urgent".
//
//   clear    0 pending                      check_circle       foreground
//   pending  nothing time-critical          format_list_checks foreground
//   due      due today, nothing overdue     list_status        accent
//   overdue  anything overdue               timer_alert        warning
/** @type {Record<string, {key: string, glyph: string, role: string}>} */
var ARDOISE_ICON_STATES = {
  clear: { key: "clear", glyph: "󰗠", role: "foreground" },
  pending: { key: "pending", glyph: "󰝖", role: "foreground" },
  due: { key: "due", glyph: "󱖫", role: "accent" },
  overdue: { key: "overdue", glyph: "󱫌", role: "warning" }
}

/**
 * Looks up a single rung of the task-slate ladder by key.
 * @param {string} key - "clear" | "pending" | "due" | "overdue"
 * @returns {{key: string, glyph: string, role: string}|null}
 */
function ardoiseIconStateForKey(key) {
  var state = ARDOISE_ICON_STATES[key]
  return state ? { key: state.key, glyph: state.glyph, role: state.role } : null
}

/**
 * Resolves which rung of the task-slate ladder a store is currently on.
 *
 * Overdue wins over due-today, which wins over plain pending; a store with
 * nothing pending is always "clear" regardless of reminder history.
 *
 * `count` is the number of tasks *in the state the glyph depicts*, so the bar
 * badge, glyph and color can never disagree. Total pending is reported
 * separately as `total` and is deliberately not what the badge shows.
 *
 * @param {TodoStoreData} store
 * @param {number} [customNow] - Optional timestamp for testing
 * @returns {{key: string, glyph: string, role: string, count: number,
 *            total: number, overdue: number, dueToday: number}}
 */
function getArdoiseIconState(store, customNow) {
  var breakdown = getTaskUrgencyBreakdown(store, customNow)
  var key = "clear"
  if (breakdown.total > 0) {
    if (breakdown.overdue > 0) {
      key = "overdue"
    } else if (breakdown.dueToday > 0) {
      key = "due"
    } else {
      key = "pending"
    }
  }

  var state = ARDOISE_ICON_STATES[key]
  var count = 0
  if (key === "pending") {
    count = breakdown.total
  } else if (key === "due") {
    count = breakdown.dueToday
  } else if (key === "overdue") {
    count = breakdown.overdue
  }

  return {
    key: state.key,
    glyph: state.glyph,
    role: state.role,
    count: count,
    total: breakdown.total,
    overdue: breakdown.overdue,
    dueToday: breakdown.dueToday
  }
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
 * Supports optional store parameter to look up custom profile icons.
 * @param {string} profile
 * @param {TodoStoreData|null|undefined} [store]
 * @returns {string}
 */
function getProfileGlyph(profile, store) {
  var p = cleanProfileName(profile).toLowerCase()
  if (store && store.profileIcons && typeof store.profileIcons === "object") {
    var custom = store.profileIcons[p]
    if (typeof custom === "string" && custom.trim()) {
      return custom.trim()
    }
  }
  switch (p) {
    case "personal": return "󰀉"
    case "work": return "󰈚"
    case "shopping": return "󰄞"
    case "study": return "󰑴"
    default: return "󰲉"
  }
}

/**
 * Curated catalog of standard Nerd Font icons with associated keywords for search.
 * @type {Array<{ glyph: string, name: string, keywords: string[] }>}
 */
var PROFILE_ICON_CATALOG = [
  // Core Profiles
  { glyph: "󰀉", name: "personal", keywords: ["person", "home", "user", "personal", "me", "profile"] },
  { glyph: "󰃖", name: "work", keywords: ["briefcase", "job", "office", "work", "business", "career"] },
  { glyph: "󰅩", name: "code", keywords: ["code", "dev", "programming", "script", "develop", "source"] },
  { glyph: "󰊤", name: "git", keywords: ["git", "github", "repo", "commit", "branch", "pr"] },
  { glyph: "󰆍", name: "terminal", keywords: ["cli", "terminal", "bash", "shell", "console", "cmd"] },
  { glyph: "󰃤", name: "bug", keywords: ["bug", "issue", "fix", "debug", "error"] },
  { glyph: "󰆼", name: "database", keywords: ["db", "database", "sql", "storage", "data"] },
  { glyph: "󱂛", name: "api", keywords: ["api", "rest", "backend", "server", "endpoint", "http"] },
  { glyph: "󰌠", name: "python", keywords: ["python", "py", "script", "django", "flask", "backend"] },

  // Web & Frontend
  { glyph: "󰖟", name: "web", keywords: ["web", "globe", "internet", "www", "site", "html", "online"] },
  { glyph: "󰇩", name: "browser", keywords: ["browser", "chrome", "firefox", "web", "navigate", "edge"] },
  { glyph: "󰘐", name: "layout", keywords: ["layout", "frontend", "ui", "view", "design", "css", "component"] },

  // DevOps & Cloud
  { glyph: "󰡨", name: "docker", keywords: ["docker", "whale", "container", "podman", "compose"] },
  { glyph: "󰠳", name: "helm", keywords: ["k8s", "kubernetes", "helm", "cluster", "orchestration", "deploy"] },
  { glyph: "󰅟", name: "cloud", keywords: ["cloud", "server", "infra", "deploy", "network", "aws"] },
  { glyph: "󰘚", name: "chip", keywords: ["hardware", "cpu", "ai", "brain", "system", "tech"] },
  { glyph: "󰒓", name: "settings", keywords: ["gear", "config", "tool", "settings", "maintenance"] },

  // Testing & QA
  { glyph: "󰙨", name: "test", keywords: ["test", "flask", "pytest", "jest", "qa", "spec", "testing", "unit"] },
  { glyph: "󰂓", name: "lab", keywords: ["lab", "flask", "experiment", "research", "science", "chemistry"] },
  { glyph: "󰓅", name: "benchmark", keywords: ["benchmark", "speed", "perf", "performance", "metrics", "speedometer"] },

  // Finance & Bills
  { glyph: "󰑉", name: "receipt", keywords: ["receipt", "invoice", "tax", "accounting", "finance", "bills", "expenses", "money"] },
  { glyph: "", name: "calculator", keywords: ["calculator", "budget", "accounting", "finance", "math", "money", "calc"] },
  { glyph: "󰕘", name: "wallet", keywords: ["wallet", "personal finance", "pay", "money", "budget", "expenses"] },

  // Productivity & Tasks
  { glyph: "󰉋", name: "folder", keywords: ["folder", "project", "dir", "directory", "files"] },
  { glyph: "󰈙", name: "notes", keywords: ["notes", "write", "doc", "article", "blog", "readme", "paper"] },
  { glyph: "󰥔", name: "clock", keywords: ["time", "clock", "reminder", "schedule", "alarm", "wait", "calendar"] },
  { glyph: "󰄬", name: "check", keywords: ["done", "check", "task", "todo", "ok", "complete", "success"] },
  { glyph: "󰓹", name: "tag", keywords: ["tag", "label", "generic", "hash", "category"] },
  { glyph: "󰓎", name: "star", keywords: ["star", "feature", "important", "priority", "key", "favorite"] },
  { glyph: "󰑣", name: "rocket", keywords: ["rocket", "launch", "ship", "startup", "release", "deploy"] },

  // Lifestyle & Media
  { glyph: "󰋑", name: "heart", keywords: ["heart", "health", "life", "favorite", "love", "fitness"] },
  { glyph: "󰄐", name: "shopping", keywords: ["cart", "shop", "buy", "store", "commerce", "groceries"] },
  { glyph: "󰑴", name: "study", keywords: ["book", "study", "learn", "read", "school", "docs", "education"] },
  { glyph: "󰏘", name: "palette", keywords: ["palette", "art", "design", "ui", "theme", "color", "paint"] },
  { glyph: "󰭹", name: "chat", keywords: ["chat", "message", "communication", "talk", "social", "inbox"] },
  { glyph: "󰇮", name: "mail", keywords: ["mail", "email", "letter", "newsletter", "inbox"] },
  { glyph: "󰝚", name: "music", keywords: ["music", "sound", "audio", "song", "media"] },
  { glyph: "󰕧", name: "video", keywords: ["video", "movie", "recording", "camera", "media"] },
  { glyph: "󰄜", name: "mobile", keywords: ["mobile", "phone", "app", "android", "ios", "cell"] },
  { glyph: "󰌾", name: "security", keywords: ["lock", "security", "auth", "key", "password", "vault"] },
  { glyph: "󰊖", name: "gaming", keywords: ["game", "gaming", "play", "fun", "leisure", "steam"] }
]

/**
 * Expansive catalog of standard verified Nerd Font glyphs for broad visual selection.
 * @type {Array<{ glyph: string, name: string, keywords: string[] }>}
 */
var ALL_GLYPHS_CATALOG = PROFILE_ICON_CATALOG.concat([
  { glyph: "", name: "prompt", keywords: ["prompt", "cli", "terminal", "console", "command"] },
  { glyph: "", name: "console", keywords: ["console", "terminal", "bash", "shell", "cmd"] },
  { glyph: "", name: "code-oct", keywords: ["code", "dev", "brackets", "syntax", "source"] },
  { glyph: "", name: "file-code", keywords: ["file", "code", "source", "script", "document"] },
  { glyph: "", name: "package", keywords: ["package", "box", "archive", "crate", "module"] },
  { glyph: "", name: "server", keywords: ["server", "rack", "infra", "backend", "host"] },
  { glyph: "", name: "apps", keywords: ["apps", "grid", "modules", "dashboard", "launcher"] },
  { glyph: "", name: "sliders", keywords: ["sliders", "tuning", "controls", "settings", "options"] },
  { glyph: "", name: "tools", keywords: ["tools", "wrench", "screwdriver", "repair", "fix", "config"] },
  { glyph: "", name: "dot", keywords: ["dot", "circle", "bullet", "point", "indicator"] },
  { glyph: "", name: "square", keywords: ["square", "block", "box", "solid", "shape"] },
  { glyph: "", name: "versions", keywords: ["versions", "git", "diff", "history", "release"] },
  { glyph: "", name: "key-oct", keywords: ["key", "auth", "token", "access", "secret"] },
  { glyph: "", name: "sync", keywords: ["sync", "reload", "refresh", "cycle", "loop"] },
  { glyph: "", name: "shield-oct", keywords: ["shield", "security", "protect", "defense", "safe"] },
  { glyph: "", name: "arrow-corner", keywords: ["arrow", "corner", "return", "enter", "down-left"] },
  { glyph: "", name: "checklist", keywords: ["checklist", "tasks", "todo", "items", "plan"] },
  { glyph: "", name: "telescope", keywords: ["telescope", "mirror", "search", "discover", "inspect"] },
  { glyph: "", name: "arrow-up-oct", keywords: ["arrow", "up", "increase", "north", "top"] },
  { glyph: "", name: "graph", keywords: ["graph", "chart", "metrics", "analytics", "stats"] },
  { glyph: "", name: "camera-oct", keywords: ["camera", "photo", "device", "snapshot"] },
  { glyph: "", name: "triangle-left", keywords: ["triangle", "left", "arrow", "play", "shape"] },
  { glyph: "", name: "clock-oct", keywords: ["clock", "time", "watch", "timer", "schedule"] },
  { glyph: "", name: "flame", keywords: ["flame", "fire", "hot", "streak", "burn"] },
  { glyph: "", name: "search", keywords: ["search", "find", "magnifier", "lookup", "query"] },
  { glyph: "", name: "heart-fa", keywords: ["heart", "like", "love", "favorite"] },
  { glyph: "", name: "star-fa", keywords: ["star", "rating", "favorite", "important"] },
  { glyph: "", name: "user", keywords: ["user", "account", "profile", "person", "member"] },
  { glyph: "", name: "film", keywords: ["film", "video", "cinema", "movie", "recording"] },
  { glyph: "", name: "grid", keywords: ["grid", "cells", "tiles", "cards", "layout"] },
  { glyph: "", name: "check-fa", keywords: ["check", "done", "ok", "complete", "success"] },
  { glyph: "", name: "close", keywords: ["close", "cross", "cancel", "x", "remove"] },
  { glyph: "", name: "power", keywords: ["power", "on", "off", "shutdown", "reboot"] },
  { glyph: "", name: "signal", keywords: ["signal", "network", "bars", "reception", "wifi"] },
  { glyph: "", name: "gear", keywords: ["gear", "cog", "settings", "options", "config"] },
  { glyph: "", name: "trash", keywords: ["trash", "bin", "delete", "remove", "garbage"] },
  { glyph: "", name: "home", keywords: ["home", "house", "main", "start", "landing"] },
  { glyph: "", name: "file", keywords: ["file", "document", "sheet", "page", "blank"] },
  { glyph: "", name: "download", keywords: ["download", "save", "fetch", "get", "inbound"] },
  { glyph: "", name: "upload", keywords: ["upload", "send", "publish", "push", "outbound"] },
  { glyph: "", name: "inbox", keywords: ["inbox", "tray", "messages", "incoming", "mail"] },
  { glyph: "", name: "rotate", keywords: ["rotate", "refresh", "repeat", "redo", "again"] },
  { glyph: "", name: "lock", keywords: ["lock", "padlock", "secure", "private", "protected"] },
  { glyph: "", name: "flag", keywords: ["flag", "mark", "milestone", "goal", "target"] },
  { glyph: "", name: "headphones", keywords: ["headphones", "audio", "listen", "sound", "music"] },
  { glyph: "", name: "volume-mute", keywords: ["volume", "mute", "sound", "silent", "off"] },
  { glyph: "", name: "volume-high", keywords: ["volume", "loud", "sound", "speaker", "audio"] },
  { glyph: "", name: "barcode", keywords: ["barcode", "scan", "code", "product", "sku"] },
  { glyph: "", name: "tags", keywords: ["tags", "labels", "categories", "price", "hash"] },
  { glyph: "", name: "book", keywords: ["book", "reading", "docs", "manual", "guide"] },
  { glyph: "", name: "bookmark", keywords: ["bookmark", "mark", "save", "favorite", "pin"] },
  { glyph: "", name: "print", keywords: ["print", "paper", "hardcopy", "printer", "output"] },
  { glyph: "", name: "camera", keywords: ["camera", "photo", "snapshot", "picture", "image"] },
  { glyph: "", name: "font", keywords: ["font", "type", "text", "typography", "letter"] },
  { glyph: "", name: "text-height", keywords: ["text", "height", "font", "size", "lines"] },
  { glyph: "", name: "align-justify", keywords: ["align", "justify", "lines", "paragraph", "text"] },
  { glyph: "", name: "pencil", keywords: ["pencil", "write", "draft", "author", "edit"] },
  { glyph: "", name: "map-pin", keywords: ["map", "pin", "location", "marker", "place"] },
  { glyph: "", name: "tint", keywords: ["tint", "drop", "water", "liquid", "color"] },
  { glyph: "", name: "edit-square", keywords: ["edit", "write", "modify", "notes", "draft"] },
  { glyph: "", name: "share", keywords: ["share", "send", "link", "export", "forward"] },
  { glyph: "", name: "checkbox", keywords: ["checkbox", "check", "task", "done", "todo"] },
  { glyph: "", name: "play", keywords: ["play", "start", "run", "begin", "execute"] },
  { glyph: "", name: "pause", keywords: ["pause", "wait", "hold", "stop", "freeze"] },
  { glyph: "", name: "stop", keywords: ["stop", "halt", "end", "kill", "terminate"] },
  { glyph: "", name: "plus-circle", keywords: ["plus", "add", "new", "create", "circle"] },
  { glyph: "", name: "minus-circle", keywords: ["minus", "remove", "subtract", "circle"] },
  { glyph: "", name: "times-circle", keywords: ["times", "cancel", "error", "close", "fail"] },
  { glyph: "", name: "check-circle", keywords: ["check", "success", "done", "ok", "sign"] },
  { glyph: "", name: "question", keywords: ["question", "help", "info", "faq", "ask"] },
  { glyph: "", name: "info", keywords: ["info", "about", "details", "notice", "hint"] },
  { glyph: "", name: "crosshairs", keywords: ["crosshairs", "target", "focus", "aim", "sniper"] },
  { glyph: "", name: "ban", keywords: ["ban", "block", "forbidden", "prohibited", "stop"] },
  { glyph: "", name: "file-pen", keywords: ["file", "pen", "write", "notes", "edit"] },
  { glyph: "", name: "arrow-right", keywords: ["arrow", "right", "next", "forward", "east"] },
  { glyph: "", name: "arrow-up", keywords: ["arrow", "up", "top", "above", "north"] },
  { glyph: "", name: "arrow-down", keywords: ["arrow", "down", "bottom", "below", "south"] },
  { glyph: "", name: "plus", keywords: ["plus", "add", "create", "insert", "new"] },
  { glyph: "", name: "minus", keywords: ["minus", "remove", "delete", "subtract"] },
  { glyph: "", name: "asterisk", keywords: ["asterisk", "star", "wildcard", "footnote"] },
  { glyph: "", name: "exclamation", keywords: ["exclamation", "alert", "notice", "warning"] },
  { glyph: "", name: "gift", keywords: ["gift", "present", "reward", "surprise", "box"] },
  { glyph: "", name: "leaf", keywords: ["leaf", "nature", "green", "eco", "plant"] },
  { glyph: "", name: "fire", keywords: ["fire", "hot", "streak", "trending", "burn"] },
  { glyph: "", name: "eye", keywords: ["eye", "see", "view", "watch", "visible"] },
  { glyph: "", name: "eye-slash", keywords: ["hidden", "invisible", "private", "secret"] },
  { glyph: "", name: "warning", keywords: ["warning", "caution", "alert", "danger", "notice"] },
  { glyph: "", name: "plane", keywords: ["plane", "travel", "flight", "trip", "vacation"] },
  { glyph: "", name: "calendar", keywords: ["calendar", "date", "event", "schedule", "month"] },
  { glyph: "", name: "random", keywords: ["random", "shuffle", "order", "mix", "swap"] },
  { glyph: "", name: "comment", keywords: ["comment", "chat", "bubble", "message", "talk"] },
  { glyph: "", name: "magnet", keywords: ["magnet", "attract", "pull", "torrent", "magnetic"] },
  { glyph: "", name: "cart", keywords: ["cart", "shop", "checkout", "buy", "store"] },
  { glyph: "", name: "folder-fa", keywords: ["folder", "directory", "files", "storage"] },
  { glyph: "", name: "bar-chart", keywords: ["chart", "metrics", "graph", "analytics", "stats"] },
  { glyph: "", name: "twitter", keywords: ["twitter", "social", "x", "tweet"] },
  { glyph: "", name: "facebook", keywords: ["facebook", "social", "fb", "meta"] },
  { glyph: "", name: "camera-retro", keywords: ["camera", "vintage", "photo", "retro", "lens"] },
  { glyph: "", name: "key-fa", keywords: ["key", "auth", "token", "password", "access"] },
  { glyph: "", name: "cogs", keywords: ["cogs", "settings", "options", "config", "gears"] },
  { glyph: "", name: "comments", keywords: ["comments", "discussion", "forum", "chat", "messages"] },
  { glyph: "", name: "thumbs-up", keywords: ["like", "approve", "good", "yes", "thumbs"] },
  { glyph: "", name: "thumbs-down", keywords: ["dislike", "reject", "bad", "no", "down"] },
  { glyph: "", name: "star-half", keywords: ["star", "half", "rating", "score"] },
  { glyph: "", name: "heart-o", keywords: ["heart", "outline", "love", "favorite"] },
  { glyph: "", name: "sign-out", keywords: ["logout", "exit", "leave", "quit"] },
  { glyph: "", name: "linkedin-square", keywords: ["linkedin", "career", "network", "job"] },
  { glyph: "", name: "thumb-tack", keywords: ["pin", "tack", "board", "attach", "post"] },
  { glyph: "", name: "external-link", keywords: ["external", "link", "url", "open", "web"] },
  { glyph: "", name: "sign-in", keywords: ["login", "enter", "auth", "access"] },
  { glyph: "", name: "trophy", keywords: ["trophy", "winner", "achievement", "award", "gold"] },
  { glyph: "", name: "github-square", keywords: ["github", "git", "repo", "hub"] },
  { glyph: "", name: "upload-fa", keywords: ["upload", "push", "publish", "outbound"] },
  { glyph: "", name: "lemon", keywords: ["lemon", "food", "citrus", "sour", "fruit"] },
  { glyph: "", name: "phone", keywords: ["phone", "call", "talk", "contact", "voice"] },
  { glyph: "", name: "phone-square", keywords: ["phone", "call", "square", "contact"] },
  { glyph: "", name: "github", keywords: ["github", "repo", "octocat", "git", "hub"] },
  { glyph: "", name: "unlock", keywords: ["unlock", "open", "free", "access", "clear"] },
  { glyph: "", name: "credit-card", keywords: ["card", "credit", "pay", "debit", "money"] },
  { glyph: "", name: "rss", keywords: ["rss", "feed", "news", "syndication", "blog"] },
  { glyph: "", name: "arrows-v", keywords: ["arrows", "vertical", "up-down", "resize", "scroll"] },
  { glyph: "", name: "bullhorn", keywords: ["announce", "broadcast", "speaker", "megaphone", "news"] },
  { glyph: "", name: "bell-outline", keywords: ["bell", "chime", "alarm", "notify", "ring"] },
  { glyph: "", name: "certificate", keywords: ["badge", "certificate", "seal", "award", "verify"] },
  { glyph: "", name: "hand-right", keywords: ["hand", "point", "right", "direction"] },
  { glyph: "", name: "hand-left", keywords: ["hand", "point", "left", "direction"] },
  { glyph: "", name: "hand-up", keywords: ["hand", "point", "up", "direction"] },
  { glyph: "", name: "hand-down", keywords: ["hand", "point", "down", "direction"] },
  { glyph: "", name: "arrow-circle-left", keywords: ["arrow", "circle", "left", "back"] },
  { glyph: "", name: "arrow-circle-right", keywords: ["arrow", "circle", "right", "next"] },
  { glyph: "", name: "arrow-circle-up", keywords: ["arrow", "circle", "up", "top"] },
  { glyph: "", name: "arrow-circle-down", keywords: ["arrow", "circle", "down", "bottom"] },
  { glyph: "", name: "cloud-fa", keywords: ["cloud", "storage", "sync", "server", "network"] },
  { glyph: "", name: "flask", keywords: ["flask", "science", "lab", "experiment", "chemistry"] },
  { glyph: "", name: "scissors", keywords: ["cut", "scissors", "clip", "crop", "trim"] },
  { glyph: "", name: "files", keywords: ["files", "documents", "copy", "pages", "stack"] },
  { glyph: "", name: "paperclip", keywords: ["paperclip", "attachment", "attach", "file"] },
  { glyph: "", name: "floppy", keywords: ["save", "disk", "store", "floppy", "record"] },
  { glyph: "", name: "square-fa", keywords: ["square", "block", "box", "solid"] },
  { glyph: "", name: "bars", keywords: ["menu", "hamburger", "bars", "reorder", "list"] },
  { glyph: "", name: "list-ul", keywords: ["list", "bullets", "todo", "items", "tasks"] },
  { glyph: "", name: "list-ol", keywords: ["ordered", "numbers", "steps", "sequence"] },
  { glyph: "", name: "strikethrough", keywords: ["strikethrough", "done", "complete", "cancelled"] },
  { glyph: "", name: "underline", keywords: ["underline", "text", "format", "style"] },
  { glyph: "", name: "table", keywords: ["table", "grid", "data", "sheet", "cells"] },
  { glyph: "", name: "magic", keywords: ["magic", "wand", "wizard", "effects", "spell"] },
  { glyph: "", name: "truck", keywords: ["truck", "delivery", "shipping", "transport", "freight"] },
  { glyph: "", name: "pinterest", keywords: ["pinterest", "pin", "board", "social"] },
  { glyph: "", name: "pinterest-square", keywords: ["pinterest", "square", "pin", "social"] },
  { glyph: "", name: "google-plus-square", keywords: ["google", "plus", "square", "social"] },
  { glyph: "", name: "google-plus", keywords: ["google", "plus", "brand", "social"] },
  { glyph: "", name: "cash", keywords: ["money", "currency", "cash", "bill", "finance", "pay"] },
  { glyph: "", name: "caret-down", keywords: ["caret", "down", "expand", "dropdown", "arrow"] },
  { glyph: "", name: "caret-up", keywords: ["caret", "up", "collapse", "dropdown", "arrow"] },
  { glyph: "", name: "caret-left", keywords: ["caret", "left", "back", "arrow"] },
  { glyph: "", name: "caret-right", keywords: ["caret", "right", "next", "arrow"] },
  { glyph: "", name: "columns", keywords: ["columns", "layout", "split", "grid", "panes"] },
  { glyph: "", name: "sort", keywords: ["sort", "arrows", "order", "unsorted", "shuffle"] },
  { glyph: "", name: "sort-down", keywords: ["sort", "down", "descending", "filter", "order"] },
  { glyph: "", name: "sort-up", keywords: ["sort", "up", "ascending", "filter", "order"] },
  { glyph: "", name: "envelope", keywords: ["envelope", "mail", "letter", "email", "message"] },
  { glyph: "", name: "linkedin", keywords: ["linkedin", "career", "network", "job", "social"] },
  { glyph: "", name: "undo", keywords: ["undo", "revert", "back", "history", "restore"] },
  { glyph: "", name: "gavel", keywords: ["gavel", "legal", "law", "judge", "court", "rules"] },
  { glyph: "", name: "tachometer", keywords: ["tachometer", "speed", "gauge", "performance", "metrics", "dashboard"] },
  { glyph: "", name: "comment-outline", keywords: ["comment", "chat", "message", "bubble", "outline"] },
  { glyph: "", name: "comments-outline", keywords: ["comments", "discussion", "chat", "forum", "outline"] },
  { glyph: "", name: "bolt", keywords: ["bolt", "flash", "lightning", "power", "electric", "energy"] },
  { glyph: "", name: "sitemap", keywords: ["sitemap", "tree", "hierarchy", "structure", "diagram", "org"] },
  { glyph: "", name: "umbrella", keywords: ["umbrella", "weather", "protect", "rain", "insurance"] },
  { glyph: "", name: "paste", keywords: ["paste", "clipboard", "copy", "insert"] },
  { glyph: "", name: "lightbulb", keywords: ["lightbulb", "idea", "creative", "tip", "solution"] },
  { glyph: "", name: "exchange", keywords: ["exchange", "transfer", "swap", "trade", "arrows"] },
  { glyph: "", name: "cloud-download", keywords: ["cloud", "download", "fetch", "sync", "get"] },
  { glyph: "", name: "cloud-upload", keywords: ["cloud", "upload", "push", "sync", "publish"] },
  { glyph: "", name: "aws", keywords: ["aws", "cloud", "amazon", "server", "infra"] },
  { glyph: "", name: "doctor", keywords: ["doctor", "physician", "medical", "health", "hospital"] },
  { glyph: "", name: "stethoscope", keywords: ["stethoscope", "medical", "health", "heart", "clinic"] },
  { glyph: "", name: "suitcase", keywords: ["suitcase", "luggage", "travel", "work", "bag", "vacation"] },
  { glyph: "", name: "bell", keywords: ["bell", "alarm", "notify", "notification", "chime"] },
  { glyph: "", name: "coffee", keywords: ["coffee", "cup", "tea", "drink", "cafe", "mug"] },
  { glyph: "", name: "utensils", keywords: ["utensils", "fork", "knife", "food", "restaurant", "dining"] },
  { glyph: "", name: "document", keywords: ["document", "file", "text", "paper", "article"] },
  { glyph: "", name: "building", keywords: ["building", "office", "company", "city", "architecture"] },
  { glyph: "", name: "hospital", keywords: ["hospital", "clinic", "emergency", "medical", "health"] },
  { glyph: "", name: "ambulance", keywords: ["ambulance", "emergency", "paramedic", "medical", "hospital"] },
  { glyph: "", name: "medkit", keywords: ["medkit", "firstaid", "emergency", "medical", "health"] },
  { glyph: "", name: "fighter-jet", keywords: ["jet", "airplane", "flight", "fast", "aviation"] },
  { glyph: "", name: "beer", keywords: ["beer", "drink", "pub", "bar", "brew", "mug"] },
  { glyph: "", name: "hospital-sign", keywords: ["hospital", "helipad", "medical", "square", "h"] },
  { glyph: "", name: "square-plus", keywords: ["square", "plus", "add", "new", "create"] },
  { glyph: "", name: "cube-3d", keywords: ["cube", "3d", "bim", "model", "box", "object"] },
  { glyph: "", name: "desktop", keywords: ["desktop", "monitor", "screen", "computer", "display"] },
  { glyph: "", name: "laptop", keywords: ["laptop", "computer", "notebook", "portable", "dev"] },
  { glyph: "", name: "tablet", keywords: ["tablet", "ipad", "device", "pad", "screen"] },
  { glyph: "", name: "mobile-device", keywords: ["mobile", "cell", "phone", "device", "smartphone"] },
  { glyph: "", name: "terminal-fa", keywords: ["terminal", "cli", "command", "prompt", "bash", "shell"] },
  { glyph: "", name: "code-fa", keywords: ["code", "brackets", "tags", "html", "syntax", "source"] },
  { glyph: "", name: "circle-fa", keywords: ["circle", "dot", "disc", "round", "bullet"] },
  { glyph: "", name: "wrench-fa", keywords: ["wrench", "tool", "fix", "repair", "maintenance", "settings"] },
  { glyph: "", name: "rocket-fa", keywords: ["rocket", "ship", "launch", "fast", "space"] }
])

/**
 * Returns a list of recently used icon objects, resolved from store.recentIcons or active profile icons.
 * Capped at 18 items.
 * @param {TodoStoreData|null|undefined} store
 * @returns {Array<{ glyph: string, name: string, keywords: string[] }>}
 */
function getRecentIcons(store) {
  var glyphs = []
  if (store && Array.isArray(store.recentIcons) && store.recentIcons.length > 0) {
    for (var i = 0; i < store.recentIcons.length; i++) {
      var g = store.recentIcons[i]
      if (typeof g === "string" && g.trim() && glyphs.indexOf(g.trim()) === -1) {
        glyphs.push(g.trim())
        if (glyphs.length >= 18) break
      }
    }
  }

  // Fallback: If no recent icons yet, extract active custom icons from profileIcons
  if (glyphs.length === 0 && store && store.profileIcons && typeof store.profileIcons === "object") {
    for (var p in store.profileIcons) {
      if (Object.prototype.hasOwnProperty.call(store.profileIcons, p)) {
        var iconVal = store.profileIcons[p]
        if (typeof iconVal === "string" && iconVal.trim() && glyphs.indexOf(iconVal.trim()) === -1) {
          glyphs.push(iconVal.trim())
          if (glyphs.length >= 18) break
        }
      }
    }
  }

  var list = []
  for (var j = 0; j < glyphs.length; j++) {
    var targetGlyph = glyphs[j]
    var found = null
    for (var k = 0; k < ALL_GLYPHS_CATALOG.length; k++) {
      if (ALL_GLYPHS_CATALOG[k].glyph === targetGlyph) {
        found = ALL_GLYPHS_CATALOG[k]
        break
      }
    }
    if (found) {
      list.push(found)
    } else {
      list.push({
        glyph: targetGlyph,
        name: "Custom (" + targetGlyph + ")",
        keywords: ["custom", "recent"]
      })
    }
  }
  return list
}

/**
 * Searches the icon catalog by query string matching name and keywords.
 * If query is non-ASCII or looks like a glyph/character, it returns a custom item prepended.
 * @param {string} [query]
 * @param {string} [category] - "recent", "presets", or "all"
 * @param {TodoStoreData|null|undefined} [store]
 * @returns {Array<{ glyph: string, name: string, keywords: string[] }>}
 */
function searchIconCatalog(query, category, store) {
  var q = String(query || "").trim().toLowerCase()
  var results = []

  // If query is a direct Unicode glyph or character (non-alphanumeric or 1-2 chars of symbol)
  if (q.length > 0) {
    var raw = String(query || "").trim()
    var isPureSymbol = /^[^a-zA-Z0-9_\-\s]+$/.test(raw)
    if (isPureSymbol || (raw.length <= 2 && raw.codePointAt(0) && (raw.codePointAt(0) || 0) > 127)) {
      results.push({
        glyph: raw,
        name: "Custom: " + raw,
        keywords: ["custom"]
      })
    }
  }

  // When query is empty, return exact category subset
  if (!q) {
    if (category === "recent") {
      return getRecentIcons(store)
    } else if (category === "all") {
      return ALL_GLYPHS_CATALOG.slice()
    } else {
      return PROFILE_ICON_CATALOG.slice()
    }
  }

  function filterItems(items) {
    var matches = []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (item.glyph === q || item.name.toLowerCase().includes(q)) {
        matches.push(item)
        continue
      }
      var kw = item.keywords || []
      for (var k = 0; k < kw.length; k++) {
        if (kw[k].toLowerCase().includes(q)) {
          matches.push(item)
          break
        }
      }
    }
    return matches
  }

  if (category === "recent") {
    // When searching from recent tab, search recent first, then search ALL_GLYPHS_CATALOG
    var recentList = getRecentIcons(store)
    var recentMatches = filterItems(recentList)
    var allMatches = filterItems(ALL_GLYPHS_CATALOG)

    var seenGlyphs = {}
    for (var r = 0; r < results.length; r++) {
      seenGlyphs[results[r].glyph] = true
    }
    for (var rm = 0; rm < recentMatches.length; rm++) {
      if (!seenGlyphs[recentMatches[rm].glyph]) {
        seenGlyphs[recentMatches[rm].glyph] = true
        results.push(recentMatches[rm])
      }
    }
    for (var am = 0; am < allMatches.length; am++) {
      if (!seenGlyphs[allMatches[am].glyph]) {
        seenGlyphs[allMatches[am].glyph] = true
        results.push(allMatches[am])
      }
    }
    return results
  }

  var source = (category === "all") ? ALL_GLYPHS_CATALOG : PROFILE_ICON_CATALOG
  var sourceMatches = filterItems(source)
  return results.concat(sourceMatches)
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
 * Formats an ISO reminder date into a user-friendly preview string with relative diff.
 * @param {string} isoDate
 * @param {Date|number|string} [baseDate]
 * @returns {string}
 */
function formatCustomPreview(isoDate, baseDate) {
  if (!isoDate) return ""
  var target = new Date(isoDate)
  if (isNaN(target.getTime())) return ""

  var now = new Date()
  if (baseDate instanceof Date && !isNaN(baseDate.getTime())) {
    now = new Date(baseDate.getTime())
  } else if (typeof baseDate === "number" && !isNaN(baseDate)) {
    now = new Date(baseDate)
  } else if (typeof baseDate === "string" && baseDate.length > 0) {
    var pb = new Date(baseDate)
    if (!isNaN(pb.getTime())) now = pb
  }

  var diff = target.getTime() - now.getTime()
  var timeStr = (target.getHours() < 10 ? "0" : "") + target.getHours() + ":" +
    (target.getMinutes() < 10 ? "0" : "") + target.getMinutes()

  var isToday = target.toDateString() === now.toDateString()
  var tomorrow = new Date(now.getTime() + 86400000)
  var isTomorrow = target.toDateString() === tomorrow.toDateString()

  var rel = diff >= 0 ? formatRelativeDiff(diff, false) : formatRelativeDiff(diff, true)

  if (isToday) {
    return "Today at " + timeStr + " (" + rel + ")"
  }
  if (isTomorrow) {
    return "Tomorrow at " + timeStr + " (" + rel + ")"
  }
  var dayStr = target.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })
  return dayStr + " at " + timeStr + " (" + rel + ")"
}

/**
 * Parses a custom or natural language reminder string into an ISO timestamp and friendly label.
 * @param {string|null|undefined} input
 * @param {Date|number|string} [baseDate]
 * @returns {{ iso: string, label: string }|null}
 */
function parseCustomReminder(input, baseDate) {
  if (!input) return null
  var raw = String(input).trim()
  if (!raw) return null
  var str = raw.toLowerCase().replace(/^\+/, "").trim()

  var now = new Date()
  if (baseDate instanceof Date && !isNaN(baseDate.getTime())) {
    now = new Date(baseDate.getTime())
  } else if (typeof baseDate === "number" && !isNaN(baseDate)) {
    now = new Date(baseDate)
  } else if (typeof baseDate === "string" && baseDate.length > 0) {
    var pb = new Date(baseDate)
    if (!isNaN(pb.getTime())) now = pb
  }

  // 1. Plain number: treat as minutes
  if (/^\d+$/.test(str)) {
    var minsNum = Number(str)
    if (minsNum > 0) {
      var dMins = new Date(now.getTime() + minsNum * 60000)
      var isoMins = dMins.toISOString()
      return { iso: isoMins, label: formatCustomPreview(isoMins, now) }
    }
  }

  // 2. Relative units compound match (e.g. "1d 2h 30m", "45m", "2h", "1.5h", "90 mins")
  var relMatch = str.match(/^(?:(\d+(?:\.\d+)?)\s*(?:d|day|days))?\s*(?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours))?\s*(?:(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes))?$/)
  if (relMatch && (relMatch[1] || relMatch[2] || relMatch[3])) {
    var dVal = relMatch[1] ? Number(relMatch[1]) : 0
    var hVal = relMatch[2] ? Number(relMatch[2]) : 0
    var mVal = relMatch[3] ? Number(relMatch[3]) : 0
    var totalMs = (dVal * 86400000) + (hVal * 3600000) + (mVal * 60000)
    if (totalMs > 0) {
      var dRel = new Date(now.getTime() + totalMs)
      var isoRel = dRel.toISOString()
      return { iso: isoRel, label: formatCustomPreview(isoRel, now) }
    }
  }

  // 3. Day keyword only
  if (str === "tomorrow" || str === "tom") {
    var dTom = new Date(now.getTime() + 86400000)
    dTom.setHours(9, 0, 0, 0)
    var isoTom = dTom.toISOString()
    return { iso: isoTom, label: formatCustomPreview(isoTom, now) }
  }
  if (str === "tonight") {
    var dTonight = new Date(now.getTime())
    dTonight.setHours(20, 0, 0, 0)
    if (dTonight.getTime() <= now.getTime()) {
      dTonight.setDate(dTonight.getDate() + 1)
    }
    var isoTonight = dTonight.toISOString()
    return { iso: isoTonight, label: formatCustomPreview(isoTonight, now) }
  }

  /**
   * @param {string} timeStr
   * @returns {{ hours: number, minutes: number }|null}
   */
  function parseTimePart(timeStr) {
    if (!timeStr) return null
    var t = timeStr.trim().toLowerCase()
    var tm = t.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/)
    if (!tm) return null
    var hh = Number(tm[1])
    var mm = tm[2] ? Number(tm[2]) : 0
    var ampm = tm[3]
    if (ampm === "pm" && hh < 12) hh += 12
    if (ampm === "am" && hh === 12) hh = 0
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null
    return { hours: hh, minutes: mm }
  }

  // 4. Day keyword + time (e.g. "tomorrow 14:00", "today 5pm", "tom 9am")
  var dayKeyMatch = str.match(/^(today|tomorrow|tom)\s+(.+)$/)
  if (dayKeyMatch) {
    var dayWord = dayKeyMatch[1]
    var tp = parseTimePart(dayKeyMatch[2])
    if (tp) {
      var dKey = new Date(now.getTime())
      if (dayWord === "tomorrow" || dayWord === "tom") {
        dKey.setDate(dKey.getDate() + 1)
      }
      dKey.setHours(tp.hours, tp.minutes, 0, 0)
      if (dayWord === "today" && dKey.getTime() <= now.getTime()) {
        dKey.setDate(dKey.getDate() + 1)
      }
      var isoKey = dKey.toISOString()
      return { iso: isoKey, label: formatCustomPreview(isoKey, now) }
    }
  }

  // 5. Plain time of day (e.g. "14:30", "9:00", "9am", "5:30pm", "21:15")
  var plainTime = parseTimePart(str)
  if (plainTime) {
    var dTime = new Date(now.getTime())
    dTime.setHours(plainTime.hours, plainTime.minutes, 0, 0)
    // If time has passed today, roll over to tomorrow
    if (dTime.getTime() <= now.getTime()) {
      dTime.setDate(dTime.getDate() + 1)
    }
    var isoTime = dTime.toISOString()
    return { iso: isoTime, label: formatCustomPreview(isoTime, now) }
  }

  // 6. ISO Date YYYY-MM-DD [HH:MM]
  var isoDateMatch = str.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ t](\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?$/)
  if (isoDateMatch) {
    var y = Number(isoDateMatch[1])
    var m = Number(isoDateMatch[2]) - 1
    var day = Number(isoDateMatch[3])
    var h = isoDateMatch[4] ? Number(isoDateMatch[4]) : 9
    var min = isoDateMatch[5] ? Number(isoDateMatch[5]) : 0
    var ap = isoDateMatch[6]
    if (ap === "pm" && h < 12) h += 12
    if (ap === "am" && h === 12) h = 0
    var dIsoParsed = new Date(y, m, day, h, min, 0, 0)
    if (!isNaN(dIsoParsed.getTime())) {
      var isoParsed = dIsoParsed.toISOString()
      return { iso: isoParsed, label: formatCustomPreview(isoParsed, now) }
    }
  }

  // 7. Month name + day (e.g. "oct 15 14:00", "15 oct 9am", "october 15")
  var monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
  var monthRegex = "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
  var mNameMatch1 = str.match(new RegExp("^(" + monthRegex + ")\\s+(\\d{1,2})(?:\\s+(.+))?$"))
  var mNameMatch2 = str.match(new RegExp("^(\\d{1,2})\\s+(" + monthRegex + ")(?:\\s+(.+))?$"))
  var mNameMonth = ""
  var mNameDay = 0
  var mNameTimePart = ""
  if (mNameMatch1) {
    mNameMonth = mNameMatch1[1].slice(0, 3)
    mNameDay = Number(mNameMatch1[2])
    mNameTimePart = mNameMatch1[3] || ""
  } else if (mNameMatch2) {
    mNameDay = Number(mNameMatch2[1])
    mNameMonth = mNameMatch2[2].slice(0, 3)
    mNameTimePart = mNameMatch2[3] || ""
  }
  if (mNameMonth && mNameDay >= 1 && mNameDay <= 31) {
    var monthIdx = monthNames.indexOf(mNameMonth)
    if (monthIdx !== -1) {
      var parsedTime = mNameTimePart ? parseTimePart(mNameTimePart) : { hours: 9, minutes: 0 }
      if (parsedTime) {
        var dMonth = new Date(now.getFullYear(), monthIdx, mNameDay, parsedTime.hours, parsedTime.minutes, 0, 0)
        // If date has already passed in current year, schedule for next year
        if (dMonth.getTime() <= now.getTime()) {
          dMonth.setFullYear(now.getFullYear() + 1)
        }
        var isoMonth = dMonth.toISOString()
        return { iso: isoMonth, label: formatCustomPreview(isoMonth, now) }
      }
    }
  }

  // 8. General Date fallback (e.g. standard ISO-8601 string)
  var fallbackDate = new Date(raw)
  if (!isNaN(fallbackDate.getTime())) {
    var isoFallback = fallbackDate.toISOString()
    return { iso: isoFallback, label: formatCustomPreview(isoFallback, now) }
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
      return { version: CURRENT_ARCHIVE_VERSION, archived: [] }
    }
  }
  if (!data || typeof data !== "object") {
    return { version: CURRENT_ARCHIVE_VERSION, archived: [] }
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
    /** @type {ArchivedTask & Record<string, any>} */
    var normItem = {
      id: item.id !== undefined && item.id !== null ? item.id : now,
      title: capitalizeTitle(String(item.title || item.text || "").trim()),
      description: String(item.description || ""),
      profile: cleanProfileName(item.profile),
      repo: item.repo ? String(item.repo).trim() : null,
      tags: itemTags,
      location: normalizeLocation(item.location),
      createdAt: Number(item.createdAt) || now,
      completedAt: Number(item.completedAt) || now
    }
    for (var k in item) {
      if (Object.prototype.hasOwnProperty.call(item, k) && !(k in normItem)) {
        normItem[k] = item[k]
      }
    }
    archived.push(normItem)
  }
  var rawArchiveVersion = typeof data.version === "number" ? data.version : (Number(data.version) || CURRENT_ARCHIVE_VERSION)
  return {
    version: Math.max(CURRENT_ARCHIVE_VERSION, rawArchiveVersion),
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
  var cleanFilter = (profileFilter && profileFilter !== "all") ? cleanProfileName(profileFilter) : (profileFilter === "all" ? "all" : null)

  /** @type {Task[]} */
  var keptTodos = []
  /** @type {ArchivedTask[]} */
  var cleared = []

  for (var i = 0; i < s.todos.length; i++) {
    var task = s.todos[i]
    var taskProfile = cleanProfileName(task.profile || "personal")
    var matchesFilter = (!cleanFilter || cleanFilter === "all" || taskProfile === cleanFilter)
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
 * Returns the normalized list of archived tasks. Parsing the whole archive is
 * the expensive step (normalizeArchive over 5,000 tasks stays under 100ms), so
 * callers should parse once and keep the result rather than re-deriving it in
 * a per-frame binding.
 * @param {string} [archiveRawText]
 * @returns {ArchivedTask[]}
 */
function getArchivedTasks(archiveRawText) {
  return normalizeArchive(archiveRawText).archived
}

/**
 * Filters archived tasks by a free-text query with multi-token AND matching
 * across title, notes, profile, repo, tags, and id. Mirrors
 * GitSync.filterSnapshots so the archive modal behaves like the snapshot list.
 * @param {ArchivedTask[]} tasks
 * @param {string} [query]
 * @returns {ArchivedTask[]}
 */
function filterArchivedTasks(tasks, query) {
  if (!Array.isArray(tasks)) return []
  if (!query || typeof query !== "string" || !query.trim()) return tasks

  var tokens = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
  if (tokens.length === 0) return tasks

  return tasks.filter(function(t) {
    if (!t || typeof t !== "object") return false
    var hay = (
      String(t.title || "") + "\n" +
      String(t.description || "") + "\n" +
      String(t.profile || "") + "\n" +
      String(t.repo || "") + "\n" +
      (Array.isArray(t.tags) ? t.tags.join(" ") : "") + "\n" +
      String(t.id || "")
    ).toLowerCase()
    return tokens.every(function(token) { return hay.indexOf(token) !== -1 })
  })
}

/**
 * Moves one archived task back into the active store, preserving its original
 * id, createdAt, notes, profile, repo, tags, and location. Completion state is
 * cleared and completedAt dropped; reminder/dueDate are not stored in the
 * archive, so they cannot be restored. The task is removed from the archive
 * (never duplicated) and the active list is re-sorted.
 * @param {TodoStoreData} store
 * @param {string} archiveRawText
 * @param {number|string} id
 * @returns {{updatedStore: TodoStoreData, updatedArchive: ArchiveData, restored: (Task|null)}}
 */
function unarchive(store, archiveRawText, id) {
  var s = cloneStore(store)
  var arc = normalizeArchive(archiveRawText)
  var key = String(id)

  /** @type {ArchivedTask|null} */
  var entry = null
  /** @type {ArchivedTask[]} */
  var kept = []
  for (var i = 0; i < arc.archived.length; i++) {
    if (entry === null && String(arc.archived[i].id) === key) {
      entry = arc.archived[i]
    } else {
      kept.push(arc.archived[i])
    }
  }

  if (entry === null) {
    return { updatedStore: s, updatedArchive: arc, restored: null }
  }

  // Rebuild as an active task, carrying forward unknown/future fields.
  var entryAny = /** @type {Record<string, any>} */ (entry)
  /** @type {Record<string, any>} */
  var raw = {}
  for (var k in entryAny) {
    if (Object.prototype.hasOwnProperty.call(entryAny, k)) raw[k] = entryAny[k]
  }
  raw.done = false
  raw.updatedAt = Date.now()
  delete raw.completedAt
  var task = normalizeTask(raw)

  var exists = false
  for (var j = 0; j < s.todos.length; j++) {
    if (String(s.todos[j].id) === key) {
      exists = true
      break
    }
  }
  if (!exists && task) {
    s.todos.push(task)
    s.todos.sort(compareTasks)
  }

  arc.archived = kept
  return { updatedStore: s, updatedArchive: arc, restored: task }
}

/**
 * Permanently removes one task from the archive. Irreversible except through
 * git history; used by the archive browser's hold-to-confirm delete.
 * @param {string} archiveRawText
 * @param {number|string} id
 * @returns {{updatedArchive: ArchiveData, purged: (ArchivedTask|null)}}
 */
function purgeArchived(archiveRawText, id) {
  var arc = normalizeArchive(archiveRawText)
  var key = String(id)
  /** @type {ArchivedTask|null} */
  var purged = null
  /** @type {ArchivedTask[]} */
  var kept = []
  for (var i = 0; i < arc.archived.length; i++) {
    if (purged === null && String(arc.archived[i].id) === key) {
      purged = arc.archived[i]
    } else {
      kept.push(arc.archived[i])
    }
  }
  arc.archived = kept
  return { updatedArchive: arc, purged: purged }
}

/**
 * Drops archive entries whose id is already active. Self-heals the duplicate a
 * crash between the two restore writes can leave behind (task in both files).
 * @param {TodoStoreData} store
 * @param {string} archiveRawText
 * @returns {{updatedArchive: ArchiveData, removedCount: number}}
 */
function reconcileArchive(store, archiveRawText) {
  var todos = (store && Array.isArray(store.todos)) ? store.todos : []
  /** @type {Record<string, boolean>} */
  var activeIds = {}
  for (var i = 0; i < todos.length; i++) {
    activeIds[String(todos[i].id)] = true
  }

  var arc = normalizeArchive(archiveRawText)
  /** @type {ArchivedTask[]} */
  var kept = []
  var removedCount = 0
  for (var j = 0; j < arc.archived.length; j++) {
    if (activeIds[String(arc.archived[j].id)]) {
      removedCount++
    } else {
      kept.push(arc.archived[j])
    }
  }
  arc.archived = kept
  return { updatedArchive: arc, removedCount: removedCount }
}

/**
 * Formats a task as a compact markdown block for pasting into an LLM. Only
 * non-empty fields are emitted, to keep the token count low.
 * @param {Task} task
 * @returns {string}
 */
function formatTaskForLLM(task) {
  if (!task || typeof task !== "object") return ""

  var lines = ["# " + capitalizeTitle(String(task.title || "").trim())]

  if (task.id !== undefined && task.id !== null) {
    if (task.done) {
      lines.push("<!-- ardoise:" + task.id + " | find: omarchy-shell tablerase.ardoise get " + task.id + " | status: completed -->")
    } else {
      lines.push("<!-- ardoise:" + task.id + " | find: omarchy-shell tablerase.ardoise get " + task.id + " | plan & complete: omarchy-shell tablerase.ardoise toggleTodo " + task.id + " -->")
    }
  }

  /** @type {string[]} */
  var meta = []
  if (task.id !== undefined && task.id !== null) meta.push("id:" + task.id)
  var profile = cleanProfileName(task.profile || "")
  if (profile) meta.push("#" + profile)
  if (task.repo) meta.push("repo:" + String(task.repo))
  if (Array.isArray(task.tags) && task.tags.length > 0) meta.push("tags:" + task.tags.join(","))
  var due = task.reminder || task.dueDate
  if (due) meta.push("due:" + String(due))
  if (meta.length > 0) lines.push(meta.join(" "))

  var notes = String(task.description || "").trim()
  if (notes) {
    lines.push("")
    lines.push(notes)
  }

  return lines.join("\n")
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

/**
 * Intelligently merges two TodoStoreData objects (e.g. from local and remote git branches).
 * Matches tasks by id, taking the newer version based on updatedAt (or createdAt).
 * Unions profile lists, preserving unique profiles.
 * @param {any} localRaw
 * @param {any} remoteRaw
 * @returns {TodoStoreData}
 */
function mergeStores(localRaw, remoteRaw) {
  var local = normalize(localRaw)
  var remote = normalize(remoteRaw)

  // Merge profile lists
  var mergedProfiles = []
  var pMap = Object.create(null)
  var allProfs = (local.profiles || []).concat(remote.profiles || [])
  for (var pi = 0; pi < allProfs.length; pi++) {
    var pName = cleanProfileName(allProfs[pi])
    if (pName && !pMap[pName]) {
      pMap[pName] = true
      mergedProfiles.push(pName)
    }
  }
  if (mergedProfiles.length === 0) {
    mergedProfiles = ["personal", "work"]
  }

  // Active profile: prefer local if valid
  var activeProfile = local.activeProfile
  if (!activeProfile || mergedProfiles.indexOf(activeProfile) === -1) {
    activeProfile = remote.activeProfile
    if (!activeProfile || mergedProfiles.indexOf(activeProfile) === -1) {
      activeProfile = mergedProfiles[0] || "personal"
    }
  }

  // Map local tasks by ID
  /** @type {Record<string, Task>} */
  var taskMap = Object.create(null)
  for (var li = 0; li < local.todos.length; li++) {
    var lt = local.todos[li]
    taskMap[String(lt.id)] = lt
  }

  // Compare/merge remote tasks
  for (var ri = 0; ri < remote.todos.length; ri++) {
    var rt = remote.todos[ri]
    var idKey = String(rt.id)
    if (taskMap[idKey]) {
      var existing = taskMap[idKey]
      var existingTime = existing.updatedAt || existing.createdAt || 0
      var remoteTime = rt.updatedAt || rt.createdAt || 0
      if (remoteTime > existingTime) {
        taskMap[idKey] = rt
      }
    } else {
      taskMap[idKey] = rt
    }
  }

  /** @type {Task[]} */
  var mergedTodos = []
  for (var k in taskMap) {
    mergedTodos.push(taskMap[k])
  }
  mergedTodos.sort(compareTasks)

  /** @type {Record<string, string>} */
  var mergedProfileIcons = Object.assign({}, local.profileIcons || {}, remote.profileIcons || {})

  // Merge recentIcons preserving MRU order, deduplicated, capped at 18
  var mergedRecent = []
  var rLocal = Array.isArray(local.recentIcons) ? local.recentIcons : []
  var rRemote = Array.isArray(remote.recentIcons) ? remote.recentIcons : []
  var combinedRecent = rLocal.concat(rRemote)
  for (var cri = 0; cri < combinedRecent.length; cri++) {
    var cGlyph = combinedRecent[cri]
    if (typeof cGlyph === "string" && cGlyph.trim() && mergedRecent.indexOf(cGlyph.trim()) === -1) {
      mergedRecent.push(cGlyph.trim())
      if (mergedRecent.length >= 18) break
    }
  }

  var maxVersion = Math.max(local.version || 1, remote.version || 1, CURRENT_SCHEMA_VERSION)
  return {
    version: maxVersion,
    activeProfile: activeProfile,
    profiles: mergedProfiles,
    todos: mergedTodos,
    profileIcons: mergedProfileIcons,
    recentIcons: mergedRecent
  }
}

/**
 * Merges two ArchiveData objects, deduplicating by task id and ordering by completedAt desc.
 * @param {any} localArchiveRaw
 * @param {any} remoteArchiveRaw
 * @returns {ArchiveData}
 */
function mergeArchives(localArchiveRaw, remoteArchiveRaw) {
  var local = normalizeArchive(localArchiveRaw)
  var remote = normalizeArchive(remoteArchiveRaw)

  /** @type {Record<string, ArchivedTask>} */
  var archMap = Object.create(null)
  var allArchived = (local.archived || []).concat(remote.archived || [])

  for (var ai = 0; ai < allArchived.length; ai++) {
    var item = allArchived[ai]
    var key = String(item.id)
    if (archMap[key]) {
      if ((item.completedAt || 0) > (archMap[key].completedAt || 0)) {
        archMap[key] = item
      }
    } else {
      archMap[key] = item
    }
  }

  /** @type {ArchivedTask[]} */
  var mergedList = []
  for (var ak in archMap) {
    mergedList.push(archMap[ak])
  }
  mergedList.sort(function(a, b) {
    return (b.completedAt || 0) - (a.completedAt || 0)
  })

  var maxArchiveVersion = Math.max(local.version || 1, remote.version || 1, CURRENT_ARCHIVE_VERSION)
  return {
    version: maxArchiveVersion,
    archived: mergedList
  }
}

/**
 * Extracts tasks from a snapshot store that are missing from currentStore.
 * Useful for selective recovery of deleted tasks.
 * @param {any} currentRaw
 * @param {any} snapshotRaw
 * @returns {Task[]}
 */
function filterMissingTasks(currentRaw, snapshotRaw) {
  var current = normalize(currentRaw)
  var snapshot = normalize(snapshotRaw)

  var currentIds = Object.create(null)
  for (var i = 0; i < current.todos.length; i++) {
    currentIds[String(current.todos[i].id)] = true
  }

  /** @type {Task[]} */
  var missing = []
  for (var j = 0; j < snapshot.todos.length; j++) {
    var task = snapshot.todos[j]
    if (!currentIds[String(task.id)]) {
      missing.push(task)
    }
  }
  return missing
}

/**
 * Parses a hex color string or QColor-like object into normalized [r, g, b, a] in [0, 1].
 * @param {any} color
 * @returns {[number, number, number, number]}
 */
function parseColorComponents(color) {
  if (!color) return [0, 0, 0, 1]
  if (typeof color === "object" && typeof color.r === "number" && typeof color.g === "number" && typeof color.b === "number") {
    var a = (typeof color.a === "number") ? color.a : 1.0
    return [color.r, color.g, color.b, a]
  }
  var str = String(color).trim()
  if (str.charAt(0) === "#") {
    var hex = str.slice(1)
    if (hex.length === 3 || hex.length === 4) {
      var r = parseInt(hex.charAt(0) + hex.charAt(0), 16) / 255
      var g = parseInt(hex.charAt(1) + hex.charAt(1), 16) / 255
      var b = parseInt(hex.charAt(2) + hex.charAt(2), 16) / 255
      var alpha = hex.length === 4 ? parseInt(hex.charAt(3) + hex.charAt(3), 16) / 255 : 1.0
      return [r, g, b, alpha]
    }
    if (hex.length === 6 || hex.length === 8) {
      var r6 = parseInt(hex.slice(0, 2), 16) / 255
      var g6 = parseInt(hex.slice(2, 4), 16) / 255
      var b6 = parseInt(hex.slice(4, 6), 16) / 255
      var alpha6 = hex.length === 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1.0
      return [r6, g6, b6, alpha6]
    }
  }
  // Check rgba(...)
  var rgbMatch = str.match(/^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$/i)
  if (rgbMatch) {
    var cr = parseFloat(rgbMatch[1]) / 255
    var cg = parseFloat(rgbMatch[2]) / 255
    var cb = parseFloat(rgbMatch[3]) / 255
    var ca = rgbMatch[4] !== undefined ? parseFloat(rgbMatch[4]) : 1.0
    return [cr, cg, cb, ca]
  }
  return [0, 0, 0, 1]
}

/**
 * Calculates WCAG 2.1 relative luminance for given RGB values in [0, 1].
 * @param {number} r
 * @param {number} g
 * @param {number} b
 * @returns {number}
 */
function getRelativeLuminance(r, g, b) {
  var rs = r <= 0.03928 ? r / 12.92 : Math.pow((r + 0.055) / 1.055, 2.4)
  var gs = g <= 0.03928 ? g / 12.92 : Math.pow((g + 0.055) / 1.055, 2.4)
  var bs = b <= 0.03928 ? b / 12.92 : Math.pow((b + 0.055) / 1.055, 2.4)
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs
}

/**
 * Calculates WCAG 2.1 contrast ratio between two colors.
 * Result is between 1.0 and 21.0.
 * @param {any} color1
 * @param {any} color2
 * @returns {number}
 */
function getContrastRatio(color1, color2) {
  var c1 = parseColorComponents(color1)
  var c2 = parseColorComponents(color2)
  var l1 = getRelativeLuminance(c1[0], c1[1], c1[2])
  var l2 = getRelativeLuminance(c2[0], c2[1], c2[2])
  var lighter = Math.max(l1, l2)
  var darker = Math.min(l1, l2)
  return (lighter + 0.05) / (darker + 0.05)
}

/**
 * Converts normalized RGB [0, 1] to hex color string (#rrggbb).
 * @param {number} r
 * @param {number} g
 * @param {number} b
 * @returns {string}
 */
function rgbToHex(r, g, b) {
  var ir = Math.round(Math.max(0, Math.min(1, r)) * 255)
  var ig = Math.round(Math.max(0, Math.min(1, g)) * 255)
  var ib = Math.round(Math.max(0, Math.min(1, b)) * 255)
  return "#" + (ir < 16 ? "0" : "") + ir.toString(16) +
               (ig < 16 ? "0" : "") + ig.toString(16) +
               (ib < 16 ? "0" : "") + ib.toString(16)
}

/**
 * Returns a readable secondary/muted color that achieves at least targetContrast (default 3.4)
 * against the provided background color. If the current muted color already has sufficient
 * contrast, it is returned. Otherwise, it blends or steps towards foreground until targetContrast
 * is reached.
 *
 * @param {any} background - The surface background color
 * @param {any} muted - The candidate muted or secondary color
 * @param {any} foreground - The primary high-contrast foreground color
 * @param {number} [targetContrast=3.4] - Target minimum contrast ratio (default 3.4 for readable secondary text distinct from titles)
 * @returns {string} Hex color string (#rrggbb)
 */
function getReadableSecondary(background, muted, foreground, targetContrast) {
  var fgRatio = getContrastRatio(foreground, background)
  var minRatio
  if (typeof targetContrast === "number" && targetContrast > 0) {
    minRatio = targetContrast
  } else {
    // Dynamic scaling: bounded between 3.15 and 3.75 based on available foreground contrast headroom
    minRatio = Math.max(3.15, Math.min(3.75, 3.0 + Math.max(0, fgRatio - 6.0) * 0.05))
  }

  var currentRatio = getContrastRatio(muted, background)
  if (currentRatio >= minRatio) {
    var mParsed = parseColorComponents(muted)
    return rgbToHex(mParsed[0], mParsed[1], mParsed[2])
  }

  var m = parseColorComponents(muted)
  var f = parseColorComponents(foreground)

  // Binary search to find the minimal blend towards foreground that meets minRatio
  var low = 0.0
  var high = 1.0
  var bestHex = rgbToHex(f[0], f[1], f[2])

  for (var i = 0; i < 20; i++) {
    var mid = (low + high) / 2
    var r = m[0] + (f[0] - m[0]) * mid
    var g = m[1] + (f[1] - m[1]) * mid
    var b = m[2] + (f[2] - m[2]) * mid
    var hex = rgbToHex(r, g, b)
    var cr = getContrastRatio(hex, background)
    if (cr >= minRatio) {
      bestHex = hex
      high = mid // seek lower blend to stay as close as possible to theme muted
    } else {
      low = mid
    }
  }

  return bestHex
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
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
    getTaskById,
    updateTodo,
    addProfile,
    removeProfile,
    setProfileIcon,
    getProfileIcons,
    clearCompleted,
    getPendingCount,
    getFilteredTodos,
    compareTasks,
    getSortedProfiles,
    isOverdue,
    pendingReminders,
    formatReminder,
    getProfileGlyph,
    PROFILE_ICON_CATALOG,
    ALL_GLYPHS_CATALOG,
    getRecentIcons,
    searchIconCatalog,
    getReminderPresets,
    computePresetReminder,
    formatCustomPreview,
    parseCustomReminder,
    normalizeArchive,
    archiveCompleted,
    getArchivedCount,
    getArchivedTasks,
    filterArchivedTasks,
    unarchive,
    purgeArchived,
    reconcileArchive,
    formatTaskForLLM,
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
    filterMissingTasks,
    searchProfiles,
    getAllTags,
    searchTags,
    resolveDefaultProfile,
    CURRENT_RELEASE_VERSION,
    RELEASE_HIGHLIGHTS,
    getTutorialTasks,
    createInitialStore,
    seedTutorialTasks,
    hasNewRelease,
    markReleaseSeen,
    resetReleaseHighlights,
    getIpcHelp,
    parseColorComponents,
    getRelativeLuminance,
    getContrastRatio,
    rgbToHex,
    getReadableSecondary
  }
}

