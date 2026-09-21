// =============================================================================
// TodoStore.js
//
// Core data store, schema v1 management, profile handling, and reminder logic
// for the Omarchy Quattro Todo plugin (tablerase.todo).
// =============================================================================
.pragma library

function defaultStore() {
  return {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal", "work"],
    todos: []
  }
}

function cleanProfileName(name) {
  if (!name) return "personal"
  var cleaned = String(name).trim().toLowerCase().replace(/^#+/, "").replace(/[^a-z0-9_-]/g, "")
  if (cleaned === "perso") cleaned = "personal"
  return cleaned || "personal"
}

function normalizeTask(raw) {
  if (!raw || typeof raw !== "object") return null
  var now = Date.now()
  var id = raw.id !== undefined && raw.id !== null ? raw.id : now
  var title = String(raw.title || raw.text || "").trim()
  var description = String(raw.description || "")
  var profile = cleanProfileName(raw.profile)
  var done = Boolean(raw.done)
  var createdAt = Number(raw.createdAt) || (typeof id === "number" ? id : now)
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
    dueDate: dueDate,
    reminder: reminder,
    notified: notified
  }
}

function normalize(raw) {
  var data = raw
  if (typeof raw === "string") {
    try {
      data = JSON.parse(raw || "{}")
    } catch (e) {
      return defaultStore()
    }
  }

  if (!data || typeof data !== "object") {
    return defaultStore()
  }

  // Legacy format: raw array of todos
  if (Array.isArray(data)) {
    var legacyTodos = []
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
  var profiles = ["personal", "work"]
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

// Parses input text for #hashtag profile syntax (e.g. "#work Fix bug" or "Deploy code #project1")
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

function cloneStore(store) {
  return JSON.parse(JSON.stringify(store || defaultStore()))
}

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
  var newTask = {
    id: now,
    title: title,
    description: String(description || ""),
    profile: profile,
    done: false,
    createdAt: now,
    dueDate: null,
    reminder: reminderTime ? String(reminderTime) : null,
    notified: false
  }

  s.todos.unshift(newTask)
  return s
}

function toggleTodo(store, id) {
  var s = cloneStore(store)
  for (var i = 0; i < s.todos.length; i++) {
    if (s.todos[i].id == id) {
      s.todos[i].done = !s.todos[i].done
      // If unmarked as done and reminder is in the future, allow notification again
      if (!s.todos[i].done && s.todos[i].reminder) {
        var remTime = new Date(s.todos[i].reminder).getTime()
        if (remTime > Date.now()) {
          s.todos[i].notified = false
        }
      }
      break
    }
  }
  return s
}

function removeTodo(store, id) {
  var s = cloneStore(store)
  s.todos = s.todos.filter(function(t) { return t.id != id })
  return s
}

function updateTodo(store, id, fields) {
  var s = cloneStore(store)
  for (var i = 0; i < s.todos.length; i++) {
    if (s.todos[i].id == id) {
      var t = s.todos[i]
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

function addProfile(store, name) {
  var s = cloneStore(store)
  var p = cleanProfileName(name)
  if (p && s.profiles.indexOf(p) === -1) {
    s.profiles.push(p)
  }
  return s
}

function removeProfile(store, name) {
  var s = cloneStore(store)
  var p = cleanProfileName(name)
  if (p === "personal") return s // Protected default profile

  s.profiles = s.profiles.filter(function(item) { return item !== p })
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

function clearCompleted(store, profileFilter) {
  var s = cloneStore(store)
  if (profileFilter && profileFilter !== "all") {
    s.todos = s.todos.filter(function(t) {
      return !t.done || t.profile !== profileFilter
    })
  } else {
    s.todos = s.todos.filter(function(t) { return !t.done })
  }
  return s
}

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

function getFilteredTodos(store, profileFilter) {
  if (!store || !Array.isArray(store.todos)) return []
  if (!profileFilter || profileFilter === "all") return store.todos
  return store.todos.filter(function(t) {
    return t.profile === profileFilter
  })
}

function pendingReminders(store) {
  if (!store || !Array.isArray(store.todos)) return []
  var now = Date.now()
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

function getProfileGlyph(profile) {
  switch (String(profile).toLowerCase()) {
    case "personal": return "󰀉"
    case "work": return "󰈚"
    case "shopping": return "󰄞"
    case "study": return "󰑴"
    default: return "󰲉"
  }
}

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

