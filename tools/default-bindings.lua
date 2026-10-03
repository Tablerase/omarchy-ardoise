-- ~/.config/omarchy/tablerase.ardoise/bindings.lua
-- Custom keybindings for Ardoise task slate.
--
-- This file is watched live: saving changes updates the panel immediately
-- without restarting Omarchy or Quickshell.
--
-- Syntax Options:
-- 1. Declarative Table: Return a table mapping action names to key strings (or arrays).
-- 2. Imperative Calls: Use ardoise.bind("action_name", "key") or ardoise.bind("key", "action_name").
--
-- Modifiers: "Ctrl", "Alt", "Shift", "Super" (or "Mod").
-- Special keys: "Return", "Space", "Tab", "Backtab", "Up", "Down", "Left", "Right",
--               "Home", "End", "PageUp", "PageDown", "F1" through "F12".
-- Note: 'Escape' is strictly protected to preserve the two-stage escape navigation invariant.

local bindings = {
  -- Navigation
  -- next_task       = "j",           -- or { "j", "Down" }
  -- prev_task       = "k",           -- or { "k", "Up" }
  -- cycle_left      = "h",           -- or { "h", "Left" }
  -- cycle_right     = "l",           -- or { "l", "Right" }
  -- jump_top        = "g",
  -- jump_bottom     = "G",

  -- Task Actions
  -- toggle_done     = "Space",       -- Toggle task completion status
  -- toggle_expand   = "Return",      -- Expand / collapse task details drawer
  -- delete_task     = "x",           -- Delete selected task
  -- copy_task       = "y",           -- Copy selected task for LLM (compact markdown)
  -- edit_title      = "r",           -- or { "r", "F2" } — edit task title in place
  -- task_menu       = "K",           -- Open the task context menu (copy for LLM, edit, open, delete)
  -- open_editor     = "e",           -- Open todos.json in editor at task line

  -- Panel Actions
  -- focus_input     = "i",           -- or { "i", "a" } — focus quick input
  -- search          = "/",           -- Activate in-panel search bar
  -- quick_add       = "A",           -- Open fullscreen Quick Add overlay
  -- git_undo        = "u",           -- Open Git Snapshots & Undo modal
  -- clear_completed = "c",           -- Archive and clear completed tasks in current profile
  -- open_archive    = "d",           -- Open the Archive browser (restore completed tasks)
  -- help            = "?",           -- Toggle keyboard shortcuts help modal
}

-- Imperative style examples:
-- ardoise.bind("open_editor", "Ctrl+E")
-- ardoise.bind("delete_task", "Ctrl+D")

return bindings
