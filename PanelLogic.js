// @ts-check
// =============================================================================
// PanelLogic.js
//
// Logic and navigation state machine for Ardoise panel:
// - Navigation state transitions across sections and drawer sub-sections
// - 2D navigation and key event handling (handleMove, handleTab, handleActivate,
//   handleReturn, handleEscape, handleTextKey, handleDelete)
// - Formatter and command generators (cleanRepoName, buildEditorCommand, buildCodebaseCommand)
// - Keybindings catalog and search filter
// =============================================================================

/**
 * Strips the owner/organization prefix from a git repository string for compact display.
 * Example: "Tablerase/omarchy-ardoise" -> "omarchy-ardoise"
 * @param {string|null|undefined} repo
 * @returns {string}
 */
function cleanRepoName(repo) {
  if (!repo) return "";
  var str = String(repo).trim();
  var idx = str.lastIndexOf("/");
  return (idx !== -1 && idx < str.length - 1) ? str.slice(idx + 1) : str;
}

/**
 * Builds the shell command string for launching the user's preferred editor
 * optionally jumping to a specific task line in todos.json.
 * @param {string} filePath
 * @param {number|string|null|undefined} [taskId]
 * @returns {string}
 */
function buildEditorCommand(filePath, taskId) {
  if (taskId) {
    var escapedPath = String(filePath).replace(/'/g, "'\\''");
    return "bash -c 'file=\"$1\"; tid=\"$2\"; line=$(grep -n \"\\\"id\\\": $tid\" \"$file\" 2>/dev/null | head -n1 | cut -d: -f1); ed_file=\"$HOME/.local/state/omarchy/defaults/editor\"; ed=\"\"; [ -f \"$ed_file\" ] && read -r ed < \"$ed_file\"; [ -z \"$ed\" ] && ed=\"nvim\"; if [ -n \"$line\" ]; then case \"${ed##*/}\" in hx|helix) exec omarchy-launch-editor \"$file:$line\" ;; code|codium|cursor) exec omarchy-launch-editor -g \"$file:$line\" ;; *) exec omarchy-launch-editor \"+$line\" \"$file\" ;; esac; else exec omarchy-launch-editor \"$file\"; fi' -- '" + escapedPath + "' '" + taskId + "'";
  }
  return 'omarchy-launch-editor "' + filePath + '"';
}

/**
 * Builds the shell command string for opening a local repository path in the editor.
 * @param {string} localPath
 * @param {string} [homeDir]
 * @returns {string}
 */
function buildCodebaseCommand(localPath, homeDir) {
  if (!localPath) return "";
  var p = String(localPath);
  if (p.startsWith("~")) {
    var h = homeDir || (typeof process !== "undefined" && process.env && process.env.HOME ? process.env.HOME : "");
    p = h + p.slice(1);
  }
  return 'omarchy-launch-editor "' + p + '"';
}

/**
 * Canonical default keybindings mapping actions to arrays of key tokens.
 * @type {Record<string, string[]>}
 */
var DEFAULT_BINDINGS = {
  next_task: ["j", "Down"],
  prev_task: ["k", "Up"],
  cycle_left: ["h", "Left"],
  cycle_right: ["l", "Right"],
  jump_top: ["g"],
  jump_bottom: ["G"],
  toggle_done: ["Space"],
  toggle_expand: ["Return"],
  delete_task: ["x"],
  edit_title: ["r", "F2"],
  task_menu: ["K"],
  open_editor: ["e"],
  git_undo: ["u"],
  clear_completed: ["c"],
  open_archive: ["d"],
  focus_input: ["i", "a"],
  search: ["/"],
  quick_add: ["A"],
  help: ["?"]
};

/**
 * Contextual menu actions offered on the focused task. `getTaskMenuItems`
 * drops entries that cannot apply to the task (no notes, no local path).
 * @type {Array<{id: string, icon: string, label: string, shortcut: string, desc: string}>}
 */
var TASK_MENU_ITEMS = [
  { id: "copy_llm", icon: "󰆏", label: "Copy for LLM", shortcut: "y", desc: "Compact markdown for an AI agent" },
  { id: "copy_title", icon: "󰆏", label: "Copy title", shortcut: "t", desc: "" },
  { id: "copy_notes", icon: "󰆏", label: "Copy notes", shortcut: "n", desc: "" },
  { id: "open_codebase", icon: "󰏫", label: "Open codebase", shortcut: "o", desc: "Open the task's local path in the editor" },
  { id: "edit_title", icon: "󰏫", label: "Edit title", shortcut: "e", desc: "" },
  { id: "delete_task", icon: "󰅙", label: "Delete task", shortcut: "x", desc: "" }
];

/**
 * Returns the contextual menu items that apply to a task.
 * @param {any} task
 * @returns {Array<{id: string, icon: string, label: string, shortcut: string, desc: string}>}
 */
function getTaskMenuItems(task) {
  /** @type {Array<{id: string, icon: string, label: string, shortcut: string, desc: string}>} */
  var items = [];
  for (var i = 0; i < TASK_MENU_ITEMS.length; i++) {
    var item = TASK_MENU_ITEMS[i];
    if (item.id === "copy_notes" && !(task && String(task.description || "").trim())) continue;
    if (item.id === "open_codebase" && !(task && task.location && task.location.localPath)) continue;
    items.push(item);
  }
  return items;
}

/**
 * Maps a menu keypress to a contextual menu action id, or null.
 * @param {string} text
 * @returns {string|null}
 */
function taskMenuActionForKey(text) {
  if (!text || typeof text !== "string") return null;
  var t = text.toLowerCase();
  if (t === "y") return "copy_llm";
  if (t === "t") return "copy_title";
  if (t === "n") return "copy_notes";
  if (t === "o") return "open_codebase";
  if (t === "e") return "edit_title";
  if (t === "x") return "delete_task";
  return null;
}

/**
 * Normalizes a raw key string into a standardized token.
 * @param {string} k
 * @returns {string}
 */
function normalizeKey(k) {
  if (!k || typeof k !== "string") return "";
  var trimmed = k.trim();
  var lower = trimmed.toLowerCase();
  if (lower === "space") return "Space";
  if (lower === "return" || lower === "enter") return "Return";
  if (lower === "escape" || lower === "esc") return "Escape";
  if (lower === "tab") return "Tab";
  if (lower === "backtab") return "Backtab";
  if (lower === "up" || lower === "↑") return "Up";
  if (lower === "down" || lower === "↓") return "Down";
  if (lower === "left" || lower === "←") return "Left";
  if (lower === "right" || lower === "→") return "Right";
  if (lower === "home") return "Home";
  if (lower === "end") return "End";
  if (lower === "pageup") return "PageUp";
  if (lower === "pagedown") return "PageDown";
  if (lower === "backspace") return "Backspace";
  if (lower === "f2") return "F2";
  if (lower.indexOf("+") !== -1) {
    var parts = trimmed.split("+");
    var normalizedParts = parts.map(function(p) {
      var pl = p.trim().toLowerCase();
      if (pl === "ctrl" || pl === "control") return "Ctrl";
      if (pl === "shift") return "Shift";
      if (pl === "alt") return "Alt";
      if (pl === "super" || pl === "meta" || pl === "cmd") return "Super";
      if (pl.length === 1) return pl.toUpperCase();
      return normalizeKey(p.trim());
    });
    return normalizedParts.join("+");
  }
  return trimmed;
}

/**
 * Resolves user keybindings overrides with safe defaults.
 * @param {Record<string, any>} [userConfig]
 * @returns {{bindings: Record<string, string[]>, keyToAction: Record<string, string>}}
 */
function resolveBindings(userConfig) {
  /** @type {Record<string, string[]>} */
  var resolved = {};
  /** @type {Record<string, string>} */
  var keyToAction = {};
  var user = (userConfig && typeof userConfig === "object") ? userConfig : {};

  for (var action in DEFAULT_BINDINGS) {
    if (Object.prototype.hasOwnProperty.call(DEFAULT_BINDINGS, action)) {
      resolved[action] = DEFAULT_BINDINGS[action].slice();
    }
  }

  for (var userAction in user) {
    if (Object.prototype.hasOwnProperty.call(user, userAction) && Object.prototype.hasOwnProperty.call(DEFAULT_BINDINGS, userAction)) {
      var val = user[userAction];
      /** @type {string[]} */
      var keys = [];
      if (typeof val === "string" && val.trim().length > 0) {
        keys = [normalizeKey(val)];
      } else if (Array.isArray(val)) {
        for (var i = 0; i < val.length; i++) {
          if (typeof val[i] === "string" && val[i].trim().length > 0) {
            keys.push(normalizeKey(val[i]));
          }
        }
      }
      if (keys.length > 0) {
        // Enforce invariants: "Escape" is protected and cannot be remapped to task actions
        keys = keys.filter(function(k) { return k !== "Escape"; });
        if (keys.length > 0) {
          resolved[userAction] = keys;
        }
      }
    }
  }

  for (var act in resolved) {
    var actKeys = resolved[act];
    for (var j = 0; j < actKeys.length; j++) {
      keyToAction[actKeys[j]] = act;
    }
  }

  return {
    bindings: resolved,
    keyToAction: keyToAction
  };
}

/**
 * Returns the catalog of supported keyboard shortcuts and navigation commands.
 * @param {string} [detectedPanelShortcut]
 * @param {string} [detectedQuickAddShortcut]
 * @param {any} [activeBindings] Optional resolved bindings object
 * @returns {Array<{key: string, desc: string, category: string}>}
 */
function getKeybindingsList(detectedPanelShortcut, detectedQuickAddShortcut, activeBindings) {
  var panelShortcut = detectedPanelShortcut || "SUPER + ALT + T";
  var quickAddShortcut = detectedQuickAddShortcut || "SUPER + SHIFT + T";
  var b = (activeBindings && activeBindings.bindings) ? activeBindings.bindings : DEFAULT_BINDINGS;

  /**
   * @param {string} action
   * @param {string} fallback
   * @returns {string}
   */
  function fmt(action, fallback) {
    var keys = b[action];
    if (!keys || keys.length === 0) return fallback;
    return keys.map(/** @param {string} k */ function(k) {
      if (k === "Up") return "↑";
      if (k === "Down") return "↓";
      if (k === "Left") return "←";
      if (k === "Right") return "→";
      if (k === "Return") return "Enter / Return";
      return k;
    }).join(" / ");
  }

  var searchKey = fmt("search", "/");
  var searchDisplay = (searchKey === "/") ? "/ / Ctrl+F" : (searchKey.indexOf("Ctrl+F") !== -1 ? searchKey : searchKey + " / Ctrl+F");
  var helpKey = fmt("help", "?");
  var helpDisplay = (helpKey === "?") ? "? / Backspace" : (helpKey.indexOf("Backspace") !== -1 ? helpKey : helpKey + " / Backspace");

  var cycleLeft = fmt("cycle_left", "h / ←");
  var cycleRight = fmt("cycle_right", "l / →");
  var cycleDisplay = (cycleLeft === "h / ←" && cycleRight === "l / →")
    ? "h / l / ← / →"
    : cycleLeft + " / " + cycleRight;

  return [
    { key: fmt("next_task", "j / ↓"), desc: "Next task", category: "Navigation" },
    { key: fmt("prev_task", "k / ↑"), desc: "Previous task", category: "Navigation" },
    { key: cycleDisplay, desc: "Cycle profile filters or footer buttons", category: "Navigation" },
    { key: "Tab / Shift+Tab", desc: "Switch section (profiles ↔ input ↔ tasks ↔ footer)", category: "Navigation" },
    { key: fmt("jump_top", "g") + " / " + fmt("jump_bottom", "G"), desc: "Jump to top / bottom of task list", category: "Navigation" },
    { key: fmt("toggle_done", "Space"), desc: "Toggle completed status of selected task", category: "Task Actions" },
    { key: fmt("toggle_expand", "Enter / Return"), desc: "Expand or collapse task details (notes & reminders)", category: "Task Actions" },
    { key: fmt("delete_task", "x"), desc: "Delete selected task (hold 600ms)", category: "Task Actions" },
    { key: fmt("edit_title", "r / F2"), desc: "Edit title of selected task", category: "Task Actions" },
    { key: fmt("task_menu", "K"), desc: "Open task context menu (copy, edit, open, delete)", category: "Task Actions" },
    { key: fmt("open_editor", "e"), desc: "Open todos.json in editor (at task line if selected)", category: "Actions & Storage" },
    { key: fmt("git_undo", "u"), desc: "Open Git Snapshots & Undo modal", category: "Actions & Storage" },
    { key: fmt("clear_completed", "c"), desc: "Archive and clear completed tasks in current profile (hold 600ms)", category: "Actions & Storage" },
    { key: fmt("open_archive", "d"), desc: "Open Archive browser (restore completed tasks)", category: "Actions & Storage" },
    { key: fmt("focus_input", "i / a"), desc: "Focus new task input field", category: "Input & Create" },
    { key: searchDisplay, desc: "Search tasks, notes & profiles", category: "Navigation" },
    { key: fmt("quick_add", "A"), desc: "Open Quick Add modal", category: "Input & Create" },
    { key: "Shift+Enter", desc: "Insert newline in task notes", category: "Input & Create" },
    { key: "Esc", desc: "Leave input / editor or close panel", category: "Global" },
    { key: helpDisplay, desc: "Toggle or dismiss keybindings help modal", category: "Global" },
    { key: panelShortcut, desc: "Global desktop shortcut: toggle Ardoise panel", category: "Global" },
    { key: quickAddShortcut, desc: "Global desktop shortcut: summon Quick Add modal", category: "Global" }
  ];
}

/**
 * Filters the list of keybindings based on a search query across key, desc, and category.
 * @param {Array<{key: string, desc: string, category: string}>} list
 * @param {string} search
 * @returns {Array<{key: string, desc: string, category: string}>}
 */
function filterKeybindings(list, search) {
  if (!list) return [];
  var q = String(search || "").toLowerCase().trim();
  if (!q) return list;
  return list.filter(function(item) {
    return item.key.toLowerCase().includes(q) ||
           item.desc.toLowerCase().includes(q) ||
           item.category.toLowerCase().includes(q);
  });
}

/**
 * Returns the next major focus section on Tab navigation.
 * @param {string} current
 * @param {number} direction 1 for forward, -1 for backward
 * @returns {string|null}
 */
function getNextSection(current, direction) {
  var sections = ["profiles", "input", "tasks", "footer"];
  var currentIdx = sections.indexOf(current);
  if (currentIdx === -1) return "tasks";
  var nextIdx = currentIdx + direction;
  if (nextIdx < 0 || nextIdx >= sections.length) return null;
  return sections[nextIdx];
}

/**
 * Returns the next expanded sub-section inside an expanded task.
 * @param {string} current
 * @param {boolean} hasCodebase
 * @returns {string|null}
 */
function getNextSubSection(current, hasCodebase) {
  if (current === "header") return "notes";
  if (current === "notes") return "reminders";
  if (current === "reminders") return "profiles";
  if (current === "profiles") return hasCodebase ? "codebase" : null;
  return null;
}

/**
 * Returns the previous expanded sub-section inside an expanded task.
 * @param {string} current
 * @returns {string|null}
 */
function getPrevSubSection(current) {
  if (current === "codebase") return "profiles";
  if (current === "profiles") return "reminders";
  if (current === "reminders") return "notes";
  if (current === "notes") return "header";
  return null;
}

/**
 * Handles two-stage escape state machine.
 * @param {any} root PanelContent root QML object
 * @returns {boolean} true if the escape was consumed
 */
function handleEscape(root) {
  if (root.showTaskMenu) {
    if (typeof root.closeTaskMenu === "function") root.closeTaskMenu();
    else root.showTaskMenu = false;
    return true;
  }
  if (root.showArchiveModal) {
    if (typeof root.closeArchiveModal === "function") root.closeArchiveModal();
    else root.showArchiveModal = false;
    return true;
  }
  if (root.showGitModal) {
    root.showGitModal = false;
    return true;
  }
  if (root.showKeyHelp) {
    root.showKeyHelp = false;
    return true;
  }
  if (root.editingTaskId !== undefined && root.editingTaskId !== null && root.editingTaskId !== -1) {
    if (typeof root.cancelEditingTask === "function") {
      root.cancelEditingTask();
    } else {
      root.editingTaskId = -1;
    }
    return true;
  }
  if (root.focusSection === "tasks" && root.expandedSubSection !== "header") {
    root.expandedSubSection = "header";
    return true;
  }
  if (root.expandedTaskId !== undefined && root.expandedTaskId !== null && root.expandedTaskId !== -1) {
    if (typeof root.savePendingNotes === "function") root.savePendingNotes();
    root.expandedTaskId = -1;
    root.expandedViaKeyboard = false;
    root.expandedSubSection = "header";
    return true;
  }
  if (root.searchActive) {
    if (root.searchQuery && root.searchQuery.length > 0) {
      root.searchQuery = "";
      if (typeof root.clearSearchText === "function") root.clearSearchText();
      return true;
    }
    if (typeof root.closeSearch === "function") {
      root.closeSearch();
      return true;
    }
  }
  return false;
}

/**
 * Handles 2D directional keyboard navigation (j/k, up/down, h/l, left/right).
 * @param {any} root PanelContent root QML object
 * @param {number} dx -1 for left/h, 1 for right/l
 * @param {number} dy -1 for up/k, 1 for down/j
 * @param {any} TodoStore TodoStore module
 */
function handleMove(root, dx, dy, TodoStore) {
  // While the contextual menu is open, j/k (and arrows) move its selection
  // instead of the task cursor.
  if (root.showTaskMenu) {
    var menuLen = (root.taskMenuItems && root.taskMenuItems.length) ? root.taskMenuItems.length : 0;
    if (menuLen > 0 && dy !== 0) {
      root.taskMenuIndex = Math.max(0, Math.min(menuLen - 1, (root.taskMenuIndex || 0) + dy));
    }
    return;
  }

  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (!root.expandedViaKeyboard && root.expandedTaskId !== -1) {
    if (typeof root.savePendingNotes === "function") root.savePendingNotes();
    root.expandedTaskId = -1;
  }

  if (root.focusSection === "tasks") {
    var currentTask = (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0)
      ? root.filteredTodos[root.cursorIndex]
      : null;

    if (currentTask && root.expandedTaskId === currentTask.id) {
      if (dy > 0) {
        if (root.expandedSubSection === "header") {
          root.expandedSubSection = "notes";
        } else if (root.expandedSubSection === "notes") {
          root.expandedSubSection = "reminders";
          root.expandedReminderIndex = 0;
          if (typeof root.ensureReminderVisible === "function") {
            root.ensureReminderVisible(0);
          }
        } else if (root.expandedSubSection === "reminders") {
          root.expandedSubSection = "profiles";
          var profsDown = TodoStore.getSortedProfiles(root.store, false, "");
          var curIdxDown = profsDown.indexOf(currentTask.profile);
          root.expandedProfileIndex = curIdxDown >= 0 ? curIdxDown : 0;
          if (typeof root.ensureReassignProfileVisible === "function") {
            root.ensureReassignProfileVisible(root.expandedProfileIndex);
          }
        } else if (root.expandedSubSection === "profiles") {
          if (currentTask.location && currentTask.location.localPath) {
            root.expandedSubSection = "codebase";
          } else {
            if (root.cursorIndex < root.filteredTodos.length - 1) {
              root.cursorIndex++;
              root.expandedSubSection = "header";
              if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
            } else {
              root.focusSection = "footer";
              root.footerButtonIndex = 0;
            }
          }
        } else if (root.expandedSubSection === "codebase") {
          if (root.cursorIndex < root.filteredTodos.length - 1) {
            root.cursorIndex++;
            root.expandedSubSection = "header";
            if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
          } else {
            root.focusSection = "footer";
            root.footerButtonIndex = 0;
          }
        }
        return;
      } else if (dy < 0) {
        if (root.expandedSubSection === "codebase") {
          root.expandedSubSection = "profiles";
        } else if (root.expandedSubSection === "profiles") {
          root.expandedSubSection = "reminders";
          if (typeof root.ensureReminderVisible === "function") {
            root.ensureReminderVisible(root.expandedReminderIndex);
          }
        } else if (root.expandedSubSection === "reminders") {
          root.expandedSubSection = "notes";
        } else if (root.expandedSubSection === "notes") {
          root.expandedSubSection = "header";
        } else if (root.expandedSubSection === "header") {
          if (root.cursorIndex > 0) {
            root.cursorIndex--;
            root.expandedSubSection = "header";
            if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
          } else {
            root.focusSection = "input";
            if (typeof root.releaseFocus === "function") root.releaseFocus();
          }
        }
        return;
      } else if (dx !== 0) {
        if (root.expandedSubSection === "reminders") {
          var maxRem = root.reminderPresets.length + (currentTask.reminder ? 1 : 0);
          root.expandedReminderIndex = Math.max(0, Math.min(maxRem - 1, root.expandedReminderIndex + dx));
          if (typeof root.ensureReminderVisible === "function") {
            root.ensureReminderVisible(root.expandedReminderIndex);
          }
          return;
        } else if (root.expandedSubSection === "profiles") {
          var allProfs = TodoStore.getSortedProfiles(root.store, false, "");
          root.expandedProfileIndex = Math.max(0, Math.min(allProfs.length - 1, root.expandedProfileIndex + dx));
          if (typeof root.ensureReassignProfileVisible === "function") {
            root.ensureReassignProfileVisible(root.expandedProfileIndex);
          }
          return;
        } else if (root.expandedSubSection === "notes" || root.expandedSubSection === "codebase") {
          return;
        }
      }
    }

    if (dy < 0) {
      if (root.cursorIndex > 0) {
        root.cursorIndex--;
        root.expandedSubSection = "header";
        if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
      } else {
        root.focusSection = "input";
        if (typeof root.releaseFocus === "function") root.releaseFocus();
      }
    } else if (dy > 0) {
      if (root.filteredTodos.length > 0 && root.cursorIndex < root.filteredTodos.length - 1) {
        var nextIdx = root.cursorIndex + 1;
        if (root.completedFoldOpen === false && root.filteredTodos[nextIdx].done && (!root.pendingCompletionIds || root.pendingCompletionIds.indexOf(root.filteredTodos[nextIdx].id) === -1)) {
          root.focusSection = "footer";
          root.footerButtonIndex = 0;
        } else {
          root.cursorIndex++;
          root.expandedSubSection = "header";
          if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
        }
      } else {
        root.focusSection = "footer";
        root.footerButtonIndex = 0;
      }
    } else if (dx !== 0) {
      if (typeof root.cycleProfileFilter === "function") root.cycleProfileFilter(dx);
    }
  } else if (root.focusSection === "profiles") {
    if (dx !== 0) {
      if (typeof root.cycleProfileFilter === "function") root.cycleProfileFilter(dx);
    } else if (dy > 0) {
      root.focusSection = "input";
      if (typeof root.releaseFocus === "function") root.releaseFocus();
    }
  } else if (root.focusSection === "input") {
    if (dy > 0) {
      if (root.filteredTodos.length > 0) {
        root.focusSection = "tasks";
        root.cursorIndex = 0;
        root.expandedSubSection = "header";
        if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
      } else {
        root.focusSection = "footer";
        root.footerButtonIndex = 0;
      }
    } else if (dy < 0) {
      root.focusSection = "profiles";
    }
  } else if (root.focusSection === "footer") {
    if (dx !== 0) {
      root.footerButtonIndex = Math.max(0, Math.min(3, root.footerButtonIndex + dx));
    } else if (dy < 0) {
      if (root.filteredTodos.length > 0) {
        root.focusSection = "tasks";
        var targetIdx = root.filteredTodos.length - 1;
        if (root.completedFoldOpen === false) {
          while (targetIdx >= 0 && root.filteredTodos[targetIdx].done && (!root.pendingCompletionIds || root.pendingCompletionIds.indexOf(root.filteredTodos[targetIdx].id) === -1)) {
            targetIdx--;
          }
        }
        if (targetIdx >= 0) {
          root.cursorIndex = targetIdx;
          root.expandedSubSection = "header";
          if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
        } else {
          root.focusSection = "input";
          if (typeof root.releaseFocus === "function") root.releaseFocus();
        }
      } else {
        root.focusSection = "input";
        if (typeof root.releaseFocus === "function") root.releaseFocus();
      }
    }
  }
}

/**
 * Handles Tab and Shift+Tab navigation.
 * @param {any} root PanelContent root QML object
 * @param {number} direction 1 for Tab, -1 for Shift+Tab
 * @param {any} TodoStore TodoStore module
 * @returns {boolean}
 */
function handleTab(root, direction, TodoStore) {
  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (!root.expandedViaKeyboard && root.expandedTaskId !== -1) {
    if (typeof root.savePendingNotes === "function") root.savePendingNotes();
    root.expandedTaskId = -1;
  }

  if (root.focusSection === "tasks") {
    var currentTask = (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0)
      ? root.filteredTodos[root.cursorIndex]
      : null;

    if (currentTask && root.expandedTaskId === currentTask.id) {
      if (direction > 0) {
        var nextSub = getNextSubSection(root.expandedSubSection, Boolean(currentTask.location && currentTask.location.localPath));
        if (nextSub) {
          root.expandedSubSection = nextSub;
          if (nextSub === "reminders") {
            root.expandedReminderIndex = 0;
            if (typeof root.ensureReminderVisible === "function") {
              root.ensureReminderVisible(0);
            }
          } else if (nextSub === "profiles") {
            var profsTab = TodoStore.getSortedProfiles(root.store, false, "");
            var curIdxTab = profsTab.indexOf(currentTask.profile);
            root.expandedProfileIndex = curIdxTab >= 0 ? curIdxTab : 0;
            if (typeof root.ensureReassignProfileVisible === "function") {
              root.ensureReassignProfileVisible(root.expandedProfileIndex);
            }
          }
          return true;
        }
      } else if (direction < 0) {
        var prevSub = getPrevSubSection(root.expandedSubSection);
        if (prevSub) {
          root.expandedSubSection = prevSub;
          if (prevSub === "reminders" && typeof root.ensureReminderVisible === "function") {
            root.ensureReminderVisible(root.expandedReminderIndex);
          } else if (prevSub === "profiles" && typeof root.ensureReassignProfileVisible === "function") {
            root.ensureReassignProfileVisible(root.expandedProfileIndex);
          }
          return true;
        }
      }
    }
  }

  var nextSec = getNextSection(root.focusSection, direction);
  if (!nextSec) return false;

  root.focusSection = nextSec;
  if (root.focusSection === "tasks") {
    root.expandedSubSection = "header";
  }
  if (root.focusSection === "input") {
    if (typeof root.focusInputField === "function") root.focusInputField();
  } else {
    if (typeof root.releaseFocus === "function") root.releaseFocus();
  }
  return true;
}

/**
 * Handles action keypresses (?, A, c, d, e, i, a, /, g, G).
 * @param {any} root PanelContent root QML object
 * @param {string} text
 * @param {any} [TodoStore] TodoStore module
 * @param {any} [activeBindings]
 */
function handleTextKey(root, text, TodoStore, activeBindings) {
  // While the contextual menu is open it owns printable keys: shortcut
  // actions run their item, everything else is swallowed so stray keys cannot
  // leak into task navigation.
  if (root.showTaskMenu) {
    if (text === "q" || text === "Q") {
      if (typeof root.closeTaskMenu === "function") root.closeTaskMenu();
      else root.showTaskMenu = false;
      return;
    }
    var menuAction = taskMenuActionForKey(text);
    if (menuAction && typeof root.activateTaskMenuItem === "function") {
      root.activateTaskMenuItem(menuAction);
    }
    return;
  }

  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (root.editingTaskId !== undefined && root.editingTaskId !== null && root.editingTaskId !== -1) {
    return;
  }

  if (root.focusSection === "tasks" && root.expandedSubSection === "notes") {
    if (typeof root.focusNotesEditor === "function" && root.focusNotesEditor()) {
      if (text !== "i" && text !== "a" && text && text.length === 1) {
        var area = (typeof root.getActiveDescArea === "function") ? root.getActiveDescArea() : root.descArea;
        if (area && area.textArea) {
          area.textArea.insert(area.textArea.cursorPosition, text);
        }
      }
      return;
    }
    return;
  }
  if (root.focusSection === "input") {
    if (typeof root.focusInputField === "function") root.focusInputField();
    if (text !== "i" && text !== "a" && typeof root.insertInputText === "function") {
      root.insertInputText(text);
    }
    return;
  }

  var map = (activeBindings && activeBindings.keyToAction)
    ? activeBindings.keyToAction
    : (root.activeBindings && root.activeBindings.keyToAction)
      ? root.activeBindings.keyToAction
      : null;

  var action = map ? (map[text] || map[text.toLowerCase()]) : null;

  if (action === "help" || (!map && text === "?")) {
    root.showKeyHelp = !root.showKeyHelp;
    return;
  }
  if (action === "git_undo" || (!map && (text === "u" || text === "U"))) {
    root.showGitModal = !root.showGitModal;
    return;
  }
  if ((action === "edit_title" || (!map && (text === "r" || text === "R"))) && root.focusSection === "tasks") {
    if (root.expandedTaskId === -1 || root.expandedTaskId === null || root.expandedSubSection === "header" || !root.expandedTaskId) {
      if (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
        var currentTask = root.filteredTodos[root.cursorIndex];
        if (currentTask && typeof root.startEditingTask === "function") {
          root.startEditingTask(currentTask.id);
          return;
        }
      }
    }
  }
  if (action === "delete_task") {
    handleDelete(root);
    return;
  }
  if (action === "toggle_done") {
    handleActivate(root, TodoStore);
    return;
  }
  if (action === "toggle_expand") {
    handleReturn(root, TodoStore);
    return;
  }
  if (action === "next_task") {
    handleMove(root, 0, 1, TodoStore);
    return;
  }
  if (action === "prev_task") {
    handleMove(root, 0, -1, TodoStore);
    return;
  }
  if (action === "cycle_left") {
    handleMove(root, -1, 0, TodoStore);
    return;
  }
  if (action === "cycle_right") {
    handleMove(root, 1, 0, TodoStore);
    return;
  }
  if ((action === "task_menu" || (!map && text === "K")) && root.focusSection === "tasks") {
    if (typeof root.openTaskMenu === "function") root.openTaskMenu();
    return;
  }
  if (action === "quick_add" || (!map && text === "A")) {
    if (typeof root.openQuickAdd === "function") root.openQuickAdd();
    return;
  }
  if (action === "clear_completed" || (!map && (text === "c" || text === "C"))) {
    if (typeof root.startClearHold === "function") {
      root.startClearHold();
    } else if (typeof root.clearCompleted === "function") {
      root.clearCompleted(root.currentFilter);
    }
    return;
  }
  if (action === "open_archive" || (!map && text === "d")) {
    if (typeof root.openArchiveModal === "function") root.openArchiveModal();
    else if (typeof root.openArchive === "function") root.openArchive();
    return;
  }
  if (action === "open_editor" || (!map && text === "e")) {
    var currentTaskId = null;
    if (root.focusSection === "tasks" && root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var t = root.filteredTodos[root.cursorIndex];
      if (t) currentTaskId = t.id;
    }
    if (typeof root.openEditor === "function") root.openEditor(currentTaskId);
    return;
  }
  if (action === "search" || (!map && text === "/")) {
    if (typeof root.activateSearch === "function") root.activateSearch();
    return;
  }
  if (action === "focus_input" || (!map && (text === "i" || text === "a"))) {
    root.focusSection = "input";
    if (typeof root.focusInputField === "function") root.focusInputField();
  } else if ((action === "jump_top" || (!map && text === "g")) && root.focusSection === "tasks") {
    root.cursorIndex = 0;
    if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(0, false);
  } else if ((action === "jump_bottom" || (!map && text === "G")) && root.focusSection === "tasks") {
    if (root.filteredTodos && root.filteredTodos.length > 0) {
      var lastIdx = root.filteredTodos.length - 1;
      if (root.completedFoldOpen === false) {
        while (lastIdx >= 0 && root.filteredTodos[lastIdx].done && (!root.pendingCompletionIds || root.pendingCompletionIds.indexOf(root.filteredTodos[lastIdx].id) === -1)) {
          lastIdx--;
        }
      }
      if (lastIdx >= 0) {
        root.cursorIndex = lastIdx;
        if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(root.cursorIndex, false);
      }
    }
  }
}

/**
 * Handles Space/Enter action activation.
 * @param {any} root PanelContent root QML object
 * @param {any} TodoStore TodoStore module
 */
function handleActivate(root, TodoStore) {
  if (root.showTaskMenu) {
    if (typeof root.activateTaskMenuItem === "function") root.activateTaskMenuItem();
    return;
  }
  if (root._suppressActivateOnReturn) return;
  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (root.focusSection === "tasks") {
    if (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var task = root.filteredTodos[root.cursorIndex];
      if (task) {
        if (root.expandedTaskId === task.id && root.expandedSubSection !== "header") {
          if (root.expandedSubSection === "notes") {
            if (typeof root.focusNotesEditor === "function" && root.focusNotesEditor()) return;
          } else if (root.expandedSubSection === "reminders") {
            if (root.expandedReminderIndex < root.reminderPresets.length) {
              var freshRem = (TodoStore && typeof TodoStore.computePresetReminder === "function")
                ? TodoStore.computePresetReminder(root.expandedReminderIndex)
                : root.reminderPresets[root.expandedReminderIndex].value;
              root.updateTodo(task.id, { reminder: freshRem });
            } else {
              root.updateTodo(task.id, { reminder: null });
            }
          } else if (root.expandedSubSection === "profiles") {
            var profs = TodoStore.getSortedProfiles(root.store, false, "");
            if (root.expandedProfileIndex >= 0 && root.expandedProfileIndex < profs.length) {
              root.updateTodo(task.id, { profile: profs[root.expandedProfileIndex] });
            }
          } else if (root.expandedSubSection === "codebase") {
            if (typeof root.openCodebase === "function") root.openCodebase(task);
          }
        } else {
          if (typeof root.toggleTodo === "function") root.toggleTodo(task.id);
        }
      }
    }
  } else if (root.focusSection === "input") {
    if (typeof root.focusInputField === "function") root.focusInputField();
  } else if (root.focusSection === "footer") {
    if (typeof root.triggerFooterButton === "function") root.triggerFooterButton(root.footerButtonIndex);
  }
}

/**
 * Handles Enter/Return key navigation and drawer toggle.
 * @param {any} root PanelContent root QML object
 * @param {any} TodoStore TodoStore module
 */
function handleReturn(root, TodoStore) {
  // Enter is delivered as both returnRequested and activateRequested. While
  // the contextual menu is open, let handleActivate run the selection, and do
  // NOT arm the activate-suppression flag (it would swallow that activation).
  if (root.showTaskMenu) return;

  root._suppressActivateOnReturn = true;
  var resetSuppress = function() { root._suppressActivateOnReturn = false; };
  var _qt = (typeof globalThis !== "undefined" && /** @type {any} */ (globalThis).Qt) ? /** @type {any} */ (globalThis).Qt : null;
  if (_qt && typeof _qt.callLater === "function") {
    _qt.callLater(resetSuppress);
  } else if (typeof root.callLater === "function") {
    root.callLater(resetSuppress);
  } else if (typeof setTimeout !== "undefined") {
    setTimeout(resetSuppress, 0);
  } else {
    root._suppressActivateOnReturn = false;
  }

  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (root.focusSection === "tasks") {
    if (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var task = root.filteredTodos[root.cursorIndex];
      if (task) {
        if (root.expandedTaskId === task.id && root.expandedSubSection !== "header") {
          if (root.expandedSubSection === "notes") {
            if (typeof root.focusNotesEditor === "function" && root.focusNotesEditor()) return;
          } else if (root.expandedSubSection === "reminders") {
            if (root.expandedReminderIndex < root.reminderPresets.length) {
              var freshRemReturn = (TodoStore && typeof TodoStore.computePresetReminder === "function")
                ? TodoStore.computePresetReminder(root.expandedReminderIndex)
                : root.reminderPresets[root.expandedReminderIndex].value;
              root.updateTodo(task.id, { reminder: freshRemReturn });
            } else {
              root.updateTodo(task.id, { reminder: null });
            }
          } else if (root.expandedSubSection === "profiles") {
            var profs = TodoStore.getSortedProfiles(root.store, false, "");
            if (root.expandedProfileIndex >= 0 && root.expandedProfileIndex < profs.length) {
              root.updateTodo(task.id, { profile: profs[root.expandedProfileIndex] });
            }
          } else if (root.expandedSubSection === "codebase") {
            if (typeof root.openCodebase === "function") root.openCodebase(task);
          }
        } else {
          if (typeof root.savePendingNotes === "function") root.savePendingNotes();
          if (root.expandedTaskId === task.id) {
            root.expandedTaskId = -1;
            root.expandedViaKeyboard = false;
            root.expandedSubSection = "header";
          } else {
            root.expandedTaskId = task.id;
            root.expandedViaKeyboard = true;
            root.expandedSubSection = "header";
          }
        }
      }
    }
  } else if (root.focusSection === "input") {
    if (typeof root.focusInputField === "function") root.focusInputField();
  } else if (root.focusSection === "footer") {
    if (typeof root.triggerFooterButton === "function") root.triggerFooterButton(root.footerButtonIndex);
  }
}

/**
 * Handles task deletion via x or Delete key.
 * @param {any} root PanelContent root QML object
 */
function handleDelete(root) {
  // PanelKeyCatcher routes x/X here before handleTextKey, so a menu-open x
  // must run the menu's delete item rather than acting blindly.
  if (root.showTaskMenu) {
    if (typeof root.activateTaskMenuItem === "function") root.activateTaskMenuItem("delete_task");
    return;
  }
  root.cursorActive = true;
  root.mouseMovementDetected = false;
  if (root.focusSection === "tasks") {
    if (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var task = root.filteredTodos[root.cursorIndex];
      if (task) {
        if (typeof root.startDeleteHold === "function") {
          root.startDeleteHold(task.id);
        } else if (typeof root.removeTodo === "function") {
          root.removeTodo(task.id);
          if (root.cursorIndex >= root.filteredTodos.length) {
            root.cursorIndex = Math.max(0, root.filteredTodos.length - 1);
          }
        }
      }
    }
  }
}

/**
 * Handles release of hold-action keys (x, c, action).
 * @param {any} root PanelContent root QML object
 * @param {string} key
 */
function handleKeyRelease(root, key) {
  if (key === "x" || key === "X") {
    if (typeof root.stopDeleteHold === "function") root.stopDeleteHold();
  } else if (key === "c" || key === "C") {
    if (typeof root.stopClearHold === "function") root.stopClearHold();
  } else if (key === "action") {
    if (root.focusSection === "footer" && root.footerButtonIndex === 0) {
      if (typeof root.stopClearHold === "function") root.stopClearHold();
    }
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    cleanRepoName: cleanRepoName,
    buildEditorCommand: buildEditorCommand,
    buildCodebaseCommand: buildCodebaseCommand,
    getKeybindingsList: getKeybindingsList,
    filterKeybindings: filterKeybindings,
    getNextSection: getNextSection,
    getNextSubSection: getNextSubSection,
    getPrevSubSection: getPrevSubSection,
    handleEscape: handleEscape,
    handleMove: handleMove,
    handleTab: handleTab,
    handleActivate: handleActivate,
    handleReturn: handleReturn,
    handleDelete: handleDelete,
    handleKeyRelease: handleKeyRelease,
    handleTextKey: handleTextKey,
    DEFAULT_BINDINGS: DEFAULT_BINDINGS,
    TASK_MENU_ITEMS: TASK_MENU_ITEMS,
    getTaskMenuItems: getTaskMenuItems,
    taskMenuActionForKey: taskMenuActionForKey,
    normalizeKey: normalizeKey,
    resolveBindings: resolveBindings
  };
}
