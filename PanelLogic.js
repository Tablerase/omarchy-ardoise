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
 * Returns the catalog of supported keyboard shortcuts and navigation commands.
 * @param {string} [detectedPanelShortcut]
 * @param {string} [detectedQuickAddShortcut]
 * @returns {Array<{key: string, desc: string, category: string}>}
 */
function getKeybindingsList(detectedPanelShortcut, detectedQuickAddShortcut) {
  var panelShortcut = detectedPanelShortcut || "SUPER + ALT + T";
  var quickAddShortcut = detectedQuickAddShortcut || "SUPER + SHIFT + T";
  return [
    { key: "j / ↓", desc: "Next task", category: "Navigation" },
    { key: "k / ↑", desc: "Previous task", category: "Navigation" },
    { key: "h / l / ← / →", desc: "Cycle profile filters or footer buttons", category: "Navigation" },
    { key: "Tab / Shift+Tab", desc: "Switch section (profiles ↔ input ↔ tasks ↔ footer)", category: "Navigation" },
    { key: "g / G", desc: "Jump to top / bottom of task list", category: "Navigation" },
    { key: "Space", desc: "Toggle completed status of selected task", category: "Task Actions" },
    { key: "Enter / Return", desc: "Expand or collapse task details (notes & reminders)", category: "Task Actions" },
    { key: "x", desc: "Delete selected task", category: "Task Actions" },
    { key: "r / F2", desc: "Edit title of selected task", category: "Task Actions" },
    { key: "e", desc: "Open todos.json in editor (at task line if selected)", category: "Actions & Storage" },
    { key: "u", desc: "Open Git Snapshots & Undo modal", category: "Actions & Storage" },
    { key: "c", desc: "Archive and clear completed tasks in current profile", category: "Actions & Storage" },
    { key: "d", desc: "Open todos-archive.json in editor", category: "Actions & Storage" },
    { key: "i / a / <slash>", desc: "Focus new task input field", category: "Input & Create" },
    { key: "A", desc: "Open Quick Add modal", category: "Input & Create" },
    { key: "Shift+Enter", desc: "Insert newline in task notes", category: "Input & Create" },
    { key: "Esc", desc: "Leave input / editor or close panel", category: "Global" },
    { key: "? / Backspace", desc: "Toggle or dismiss keybindings help modal", category: "Global" },
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
  if (root.expandedTaskId !== -1) {
    if (typeof root.savePendingNotes === "function") root.savePendingNotes();
    root.expandedTaskId = -1;
    root.expandedViaKeyboard = false;
    root.expandedSubSection = "header";
    return true;
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
 * @param {any} TodoStore TodoStore module
 */
function handleTextKey(root, text, TodoStore) {
  root.cursorActive = true;
  root.mouseMovementDetected = false;

  if (root.editingTaskId !== undefined && root.editingTaskId !== null && root.editingTaskId !== -1) {
    return;
  }

  if (text === "?") {
    root.showKeyHelp = !root.showKeyHelp;
    return;
  }
  if (text === "u" || text === "U") {
    root.showGitModal = !root.showGitModal;
    return;
  }
  if ((text === "r" || text === "R") && root.focusSection === "tasks") {
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
  if (text === "A") {
    if (typeof root.openQuickAdd === "function") root.openQuickAdd();
    return;
  }
  if (text === "c" || text === "C") {
    if (typeof root.clearCompleted === "function") root.clearCompleted(root.currentFilter);
    return;
  }
  if (text === "d") {
    if (typeof root.openArchive === "function") root.openArchive();
    return;
  }
  if (text === "e") {
    var currentTaskId = null;
    if (root.focusSection === "tasks" && root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var t = root.filteredTodos[root.cursorIndex];
      if (t) currentTaskId = t.id;
    }
    if (typeof root.openEditor === "function") root.openEditor(currentTaskId);
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
    if (text !== "i" && text !== "a" && text !== "/" && typeof root.insertInputText === "function") {
      root.insertInputText(text);
    }
    return;
  }
  if (text === "i" || text === "a" || text === "/") {
    root.focusSection = "input";
    if (typeof root.focusInputField === "function") root.focusInputField();
  } else if (text === "g" && root.focusSection === "tasks") {
    root.cursorIndex = 0;
    if (typeof root.ensureTaskVisible === "function") root.ensureTaskVisible(0, false);
  } else if (text === "G" && root.focusSection === "tasks") {
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
  root.cursorActive = true;
  root.mouseMovementDetected = false;
  if (root.focusSection === "tasks") {
    if (root.filteredTodos && root.filteredTodos.length > root.cursorIndex && root.cursorIndex >= 0) {
      var task = root.filteredTodos[root.cursorIndex];
      if (task) {
        if (typeof root.removeTodo === "function") root.removeTodo(task.id);
        if (root.cursorIndex >= root.filteredTodos.length) {
          root.cursorIndex = Math.max(0, root.filteredTodos.length - 1);
        }
      }
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
    handleTextKey: handleTextKey
  };
}
