# Ardoise — Minimalist Task Slate for Omarchy

<p align="center">
  <img src="./preview.png" alt="Ardoise Preview for Omarchy" width="960">
</p>

<p align="center">
  A keyboard-first task list that lives in your Omarchy bar, knows what is late,
  and works offline.
</p>

Everything stays in plain JSON on your machine. No account, no sync service, no
lock-in — point any tool you like at the file and it reacts instantly.

---

## Features

The essentials, then the rest. Everything under a heading is a bonus you can
ignore until you want it.

<details open>
<summary><img src="https://api.iconify.design/mdi:format-list-checks.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Core — the task slate</b></summary>

- <img src="https://api.iconify.design/mdi:timer-alert-outline.svg?color=%23df8e1d" width="13" height="13" alt="" /> **Severity-aware bar widget.** The mark escalates as work slips: neutral when
  you're on track, blue when something is due today, amber when something is
  **late**. The badge always counts the state the icon depicts, so a red-free
  "2" means *2 overdue*, not *2 of 12*. Late work never turns red — red is
  reserved for actual errors.
- <img src="https://api.iconify.design/mdi:tooltip-text-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Badge + tooltip.** Pending count on the bar; hover for a per-profile
  breakdown, completion progress, and overdue / due-today detail.
- <img src="https://api.iconify.design/mdi:card-text-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Flyout panel** with profile filters, an auto-hiding filter for empty
  profiles, and expandable rows for notes, reminders, and profile changes.
- <img src="https://api.iconify.design/mdi:lightning-bolt-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Quick Add** — a fullscreen capture bar. Type, <kbd>Enter</kbd>, gone.
- <img src="https://api.iconify.design/mdi:tag-multiple-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Profiles & tags.** `#work`, `#space work`, and custom profiles all work.
  `#perso` and `#personal` resolve to the same profile.

</details>

<details>
<summary><img src="https://api.iconify.design/mdi:keyboard-outline.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Keyboard & search</b></summary>

- <img src="https://api.iconify.design/mdi:keyboard.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Fully keyboard-driven.** <kbd>j</kbd>/<kbd>k</kbd>, <kbd>h</kbd>/<kbd>l</kbd>,
  <kbd>g</kbd>/<kbd>G</kbd>, <kbd>Tab</kbd>, <kbd>Enter</kbd>, <kbd>Space</kbd>,
  <kbd>Esc</kbd> — no mouse required for any workflow.
- <img src="https://api.iconify.design/mdi:keyboard-esc.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Two-stage <kbd>Esc</kbd>.** An empty field dismisses; a field with a draft
  returns to motion mode without losing your text.
- <img src="https://api.iconify.design/mdi:magnify.svg?color=%2358a6ff" width="13" height="13" alt="" /> **In-panel search** — <kbd>/</kbd> or <kbd>Ctrl</kbd>+<kbd>F</kbd> filters
  tasks and notes as you type.
- <img src="https://api.iconify.design/mdi:help-circle-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Shortcut directory** (<kbd>?</kbd>) listing every binding, searchable.

</details>

<details>
<summary><img src="https://api.iconify.design/mdi:clock-outline.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Reminders & notifications</b></summary>

- <img src="https://api.iconify.design/mdi:clock-fast.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Scheduled reminders** with quick presets (`+30m`, `+1h`, `Tomorrow 9am`,
  `Tomorrow 6pm`).
- <img src="https://api.iconify.design/mdi:bell-ring-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Desktop notifications** — a headless service watches your file and raises native desktop
  notifications; clicking one opens the panel.
- <img src="https://api.iconify.design/mdi:bell-check-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Loop prevention** — tasks never notify twice.

</details>

<details>
<summary><img src="https://api.iconify.design/mdi:source-branch.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Git-backed history & sync</b></summary>

Your data directory is a git repository, so every change is a snapshot.

- <img src="https://api.iconify.design/mdi:history.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Point-in-time rollback** of tasks and archives from a commit.
- <img src="https://api.iconify.design/mdi:backup-restore.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Recover deleted tasks** from any snapshot.
- <img src="https://api.iconify.design/mdi:sync.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Remote sync** with a conflict-free three-way merge — safe when two
  machines edited the same list offline.
- <img src="https://api.iconify.design/mdi:magnify.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Snapshot search & inspection** — search commits by message, device tag, or hash (<kbd>/</kbd> or <kbd>Ctrl</kbd>+<kbd>F</kbd> in Git modal, or <kbd>u</kbd>).

</details>

<details>
<summary><img src="https://api.iconify.design/mdi:folder-open-outline.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Context awareness</b></summary>

- <img src="https://api.iconify.design/mdi:code-braces.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Hyprland workspace detection** — Quick Add reads the focused window and can prefill the repository and path
  the command detected, so coding tasks are captured with their context
  already attached.

</details>

<details>
<summary><img src="https://api.iconify.design/mdi:console-line.svg?color=%2358a6ff" width="14" height="14" alt="" /> <b>Scripting & AI integration</b></summary>

- <img src="https://api.iconify.design/mdi:terminal.svg?color=%2358a6ff" width="13" height="13" alt="" /> **25 shell commands** over `omarchy-shell tablerase.ardoise` — see
  [Scripting](#scripting--automation).
- <img src="https://api.iconify.design/mdi:file-eye-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **React to writes.** The data file is watched, so external tools, git hooks,
  and AI agents can write to it and the UI updates immediately.
- <img src="https://api.iconify.design/mdi:shield-check-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Forward-compatible schema.** A file written by a newer Ardoise is never
  downgraded, so a rollback won't truncate your list.
- <img src="https://api.iconify.design/mdi:content-copy.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Copy a task for an AI agent.** Press <kbd>K</kbd> on a task for a context
  menu, then <kbd>y</kbd> to copy a compact markdown block (title, profile, repo,
  tags, due, notes) to the clipboard — token-frugal and LLM-ready.
- <img src="https://api.iconify.design/mdi:archive-arrow-up-outline.svg?color=%2358a6ff" width="13" height="13" alt="" /> **Restore from the archive.** Press <kbd>d</kbd> to browse cleared tasks
  (virtualized for large archives) and restore one back to the active list with
  its original id, notes, and profile intact. Restores are write-confirmed so a
  task is never lost, and permanent delete (<kbd>x</kbd>, hold) is protected by
  the same hold-to-confirm charge as the task list.

</details>

---

## Install

Ardoise is a shell plugin. It needs **Omarchy Quattro (Omarchy 4.x)**.

```bash
# 1. Place the plugin where Omarchy looks for it
mkdir -p ~/.config/omarchy/plugins
git clone https://github.com/Tablerase/omarchy-ardoise \
  ~/.config/omarchy/plugins/tablerase.ardoise

# 2. Let the shell discover it, then put it on the bar
omarchy-shell shell rescanPlugins
omarchy plugin enable tablerase.ardoise right

# 3. Apply
omarchy-restart-shell
```

To take it off the bar without uninstalling:

```bash
omarchy plugin disable tablerase.ardoise
```

### First 30 seconds

```bash
# Add a task from your shell
omarchy-shell tablerase.ardoise add "Ship the release #work"

# Open the panel
omarchy-shell tablerase.ardoise toggle
```

Then set up the two keybindings below so you never need the mouse again.

---

## Keybindings

Ardoise ships **no default keybinding** — you choose the combination. The panel
header has a keyboard button (`󰌌`) that copies both snippets to your clipboard
and opens the file for you. The indicator tells you where you stand:

> `✓` **Green** — both shortcuts detected in Hyprland.
> `!` **Orange** — one of two active, or the bindings are commented out.
> `✕` **Red** — not configured.

**Omarchy Quattro (Lua)** — add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Ardoise Panel", "omarchy-shell tablerase.ardoise toggle")
o.bind("SUPER + SHIFT + T", "Ardoise Quick Add", "omarchy-shell shell toggle tablerase.ardoise '{}'")
```

**Classic Omarchy (Conf)** — add to `~/.config/hypr/bindings.conf`:

```ini
bindd = SUPER ALT, T, Ardoise Panel, exec, omarchy-shell tablerase.ardoise toggle
bindd = SUPER SHIFT, T, Ardoise Quick Add, exec, omarchy-shell shell toggle tablerase.ardoise "{}"
```

Then `hyprctl reload`.

### Bar mouse shortcuts

| Gesture | Action |
| :--- | :--- |
| **Left click** | Toggle the panel |
| **Right click** | Open Quick Add |
| **Middle click** | Open `todos.json` in your editor |
| **Scroll** | Cycle the active profile filter |

### Customizing panel shortcuts (Lua)

In-panel navigation and action shortcuts can be customized via Lua to match your personal workflow.

Ardoise automatically creates a self-documenting template on first run at:
`~/.config/omarchy/tablerase.ardoise/bindings.lua`

Saving your changes live-reloads shortcuts immediately without restarting Quickshell.

#### Example

Both declarative tables and imperative `ardoise.bind()` syntax are supported:

```lua
-- Remap actions using a declarative table
local config = {
  -- Use arrow keys instead of vim motions
  move_up    = "Up",
  move_down  = "Down",

  -- Custom action shortcuts
  open_editor = "E",
}

-- Or use imperative calls (either argument order works)
ardoise.bind("delete_task", "Ctrl+D")

return config
```

> [!NOTE]
> The Two-Stage <kbd>Esc</kbd> behavior is preserved as an architectural safety invariant and cannot be overridden. Press <kbd>?</kbd> in the panel for a live cheat sheet of your active bindings, or see [`DESIGN.md`](DESIGN.md) for the full action catalog.

---

## Organising with profiles & tags

Profiles are the unit of filtering. Two are built in (`personal`, `work`) and
you can create more from the panel or from Quick Add.

```bash
omarchy-shell tablerase.ardoise add "Review PR #code"
omarchy-shell tablerase.ardoise add "Buy groceries #shopping"
```

Profiles with no pending tasks hide themselves from the filter row, so the
panel stays short no matter how many you accumulate.

---

## Scripting & automation

Everything the UI can do is available from the shell, so you can wire Ardoise
into scripts, hooks, or an AI agent.

```bash
# What's outstanding?
omarchy-shell tablerase.ardoise count
omarchy-shell tablerase.ardoise list | jq '[.[] | select(.done == false)]'

# Add work
omarchy-shell tablerase.ardoise add "Review PR #work"
omarchy-shell tablerase.ardoise addDetailed "Fix flake" "CI is red on main" "+1h"

# Query single task, update, complete, remove
omarchy-shell tablerase.ardoise get "<id>"
omarchy-shell tablerase.ardoise update "<id>" '{"reminder": "2026-09-22T09:00:00.000Z"}'
omarchy-shell tablerase.ardoise toggleTodo "<id>"
omarchy-shell tablerase.ardoise remove "<id>"
```

Two commands are built specifically for agents:

```bash
# Create a task with notes and a reminder in one call
omarchy-shell tablerase.ardoise addDetailed "Refactor parser" "Split tokenizer out" "tomorrow 9am"

# Resolve a profile from free text before using it
omarchy-shell tablerase.ardoise searchProfiles "wor"   # -> ["work"]
```

### All commands

| Group | Commands |
| :--- | :--- |
| **Tasks** | `add`, `addDetailed`, `toggleTodo`, `update`, `remove`, `clear` |
| **Queries** | `list`, `get`, `count`, `profiles`, `searchProfiles`, `archived`, `archiveCount`, `unarchive`, `purgeArchived` |
| **Profiles** | `setProfile` |
| **Panel** | `open`, `close`, `toggle` |
| **Git** | `gitHistory`, `gitRollback`, `gitRecover`, `gitSync`, `gitSetRemote`, `gitGetRemote`, `gitSearch`, `autoSetupGitRemote`, `gitAutoSetup` |

Notes:

- `count` returns **total pending**, not the number of late tasks. Use `list`
  and filter if you need urgency.
- Quick Add has no plugin command — open it with
  `omarchy-shell shell toggle tablerase.ardoise '{}'`.
- The full contract, including multi-monitor behaviour, lives in
  [`DESIGN.md`](DESIGN.md).

---

## Your data

Plain JSON, written atomically, watched live.

```json
{
  "version": 1,
  "activeProfile": "personal",
  "profiles": ["personal", "work"],
  "todos": [
    {
      "id": 1789992760433,
      "title": "Fix database query performance",
      "description": "Index the user_id column on orders table",
      "profile": "work",
      "done": false,
      "createdAt": 1789992760433,
      "reminder": "2026-09-22T09:00:00.000Z",
      "notified": false
    }
  ]
}
```

Stored at `~/.config/omarchy/tablerase.ardoise/`. Optional fields (`repo`,
`tags`, `location`, `updatedAt`, `dueDate`) let you attach coding context.

**Forward compatibility:** a file written by a newer Ardoise keeps its higher
`version` and is passed through untouched, so rolling back never truncates
your list. Merges resolve per task by the most recent `updatedAt`.

Full schema, archive format, and storage details:
[`DESIGN.md` § 7](DESIGN.md).

---

## Troubleshooting

**The widget isn't on my bar.**

```bash
omarchy plugin list                       # is it discovered?
omarchy plugin enable tablerase.ardoise right
omarchy-restart-shell
```

**My keybindings show orange or red.**
The panel detects the bindings in your Hyprland config. Red means neither was
found — check the file name for your setup (`bindings.lua` on Quattro,
`bindings.conf` on classic) and reload with `hyprctl reload`.

**Reminders aren't firing.**
Confirm the task actually has a `reminder` in the past and `notified: false`.
The service polls every 15 s, so allow a short delay after setting one.

**What did I change?**
Open the snapshot panel with the header button or <kbd>u</kbd> for a commit
history of your list.

**Reading the logs.**

```bash
journalctl --user -f | grep -i ardoise
```

**Starting over.**
Stop the shell plugin, delete `~/.config/omarchy/tablerase.ardoise/` to remove
tasks and their history, then re-enable.

---

## Development

```bash
npm install          # no dependencies; this just primes the scripts
npm run check        # typecheck, lint, validate manifest, full test suite
npm run test:fast    # unit tiers only — sub-second
npm run test:docker  # reproduce CI exactly in a container
```

Tests are tiered by what they need; some are deliberately local-only because
they require a live compositor. See [`AGENTS.md`](AGENTS.md) for the tier table
and the CI contract, and [`DESIGN.md`](DESIGN.md) for the UI specification and
data schemas.

---

## Acknowledgments

- **[OmaTasks for Todoist](https://github.com/crmne/omatasks)** by
  **Carmine Paolino** ([@crmne](https://github.com/crmne)) (MIT) — the
  multi-kind overlay pattern behind the Quick Add modal, and the headless
  preview pipeline.
- **[Planova / PlaneTxt](https://github.com/brvier/PlanovaQuickShell)** by
  **Benoît HERVIER** ([@brvier](https://github.com/brvier)) — separating a
  reactive data store from its presentation.
- **[Omarchy](https://github.com/omacom/omarchy)** — the bar widget
  architecture, theme tokens, and the desktop this lives on.

MIT licensed.
