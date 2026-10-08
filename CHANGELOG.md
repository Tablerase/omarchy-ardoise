# Changelog

All notable changes to **Ardoise** (`tablerase.ardoise`) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- *Upcoming additions will be listed here.*

### Changed
- *Upcoming changes will be listed here.*

### Fixed
- *Upcoming bug fixes will be listed here.*

---

## [1.0.1] - 2026-10-08

> **Security & Privacy Hardening Release**.
>
> This release hardens process confidentiality, sanitizes command execution pathways, prevents parameter injection, and expands path confinement safeguards.

### Fixed

#### Security & Confidentiality
- **Stdin Clipboard Streaming**: Stream clipboard write contents directly through stdin into `wl-copy` using Quickshell `Process` (`stdinEnabled = true`), completely eliminating command argument disclosure of private task titles and notes in the system process table.
- **Git Snapshot Command Safety**: Pass commit message payloads outside of Bash shell execution strings, preventing command substitution or subshell execution from task titles during automatic background snapshots.
- **Notification Privacy**: Strip private titles and reminder notes from desktop notification execution (`notify-send`), reporting generic counts and clean identifiers without process-list visibility.
- **Strict Destination Privacy Enforcement**: Require `isPrivate == true` via `gh repo view` before pushing when falling back to existing GitHub repositories in `tools/setup-git-remote.sh`, preventing accidental push of private task data to public remotes.
- **Option & Flag Injection Guards**: Add `--` parameter delimiters and reject leading hyphen arguments across `tools/check-remote-privacy.sh` and `tools/setup-git-remote.sh`.
- **Sensitive Directory Confinement**:
  - Block access to credential and cluster configuration directories (`~/.docker`, `~/.kube`, `~/.netrc`) in `tools/detect-context.sh`.
  - Disallow reading configuration files located inside `/etc` and credential subdirectories in `tools/load-bindings.lua`.
  - Enforce restrictive file permissions (`chmod 700`) on demo backup staging directories.

### Changed
- **Marketplace Discovery**: Enriched plugin description in `manifest.json` with high-intent keywords (Vim, task, todo, private Git snapshot sync) for search indexing in the Omarchy plugin marketplace.

---

## [1.0.0] - 2026-10-07

> **Initial Public Release** (Early Access Baseline).
>
> Ardoise is a keyboard-first, offline-first task slate built for the Omarchy desktop environment. All data lives in plain JSON on your machine with zero cloud dependence.

### Added

#### 1. Keyboard-First Navigation & Vim Motions
- **Vim Navigation Engine**: Smooth movement across tasks with <kbd>j</kbd>/<kbd>k</kbd> (or arrows), jump to top with <kbd>g</kbd>, jump to bottom with <kbd>G</kbd>.
- **Profile Navigation**: Fast profile switching with <kbd>[</kbd> and <kbd>]</kbd>, or <kbd>Tab</kbd>/<kbd>Shift+Tab</kbd> to cycle profile pills.
- **Strict Key Separation**:
  - <kbd>Space</kbd> strictly toggles task completion (`done`).
  - <kbd>Enter</kbd> (or <kbd>e</kbd>) expands and collapses the task details drawer (notes, reminders, profile switcher).
- **Two-Stage Escape**:
  - In empty input fields: <kbd>Escape</kbd> dismisses the panel or modal.
  - In non-empty input fields: <kbd>Escape</kbd> leaves insert mode and returns to container motion mode without closing or losing draft text.
  - In motion mode: <kbd>Escape</kbd> dismisses.
- **Hold-to-Confirm Safeguards**:
  - Destructive actions (deleting tasks with <kbd>x</kbd>, clearing completed with <kbd>c</kbd>, purging archives) charge an 800ms glowing laser bar with subtle micro-shake.
  - Releasing early drains safely, eliminating confirmation modal fatigue while preventing accidental data loss.
- **Context Action Menu (<kbd>K</kbd> / Right-Click)**:
  - Context menu with quick actions: copy task markdown for LLMs (<kbd>y</kbd>), copy title (<kbd>t</kbd>), copy notes (<kbd>n</kbd>), edit title (<kbd>r</kbd>), open codebase in editor (<kbd>o</kbd>), and hold-to-delete (<kbd>x</kbd>).
- **Customizable Lua Keybindings**:
  - Optional user overrides via `~/.config/omarchy/tablerase.ardoise/bindings.lua`.

#### 2. Omarchy Bar Widget & Urgency Ladder
- **Dynamic Urgency Ramp**:
  - `clear`: All tasks done (subtle check glyph, text muted).
  - `pending`: Tasks waiting, none due today (neutral glyph and count).
  - `due`: Tasks due today (vibrant accent color with clock glyph `󰥔`).
  - `overdue`: Tasks past due date/reminder (amber warning color with timer alert `󱫌`).
  - *Color discipline*: Amber is used for overdue work; red is reserved strictly for real system/sync errors.
- **Sub-Count Badge**: Badge count reflects the active rung (e.g. "2" means *2 overdue*, not *2 total*).
- **Rich Hover Tooltip**: Multi-section tooltip displaying total pending tasks, visual block progress bar, per-profile breakdown, and earliest overdue / next due relative countdowns.

#### 3. Main Panel & Task Slate
- **Top Profile Filter Pills**: Dynamic pills for active profiles with pending counts, auto-hiding empty profiles when inactive, and edge padding to prevent clipped squircle chips.
- **Inline Fast Add Bar**: Instant task creation directly from the panel with hashtag routing (`#work`, `#personal`, `#project/repo`).
- **Expandable Task Drawer**:
  - Inline multi-line notes editor with markdown formatting.
  - Quick reminder preset pills (`+30m`, `+2h`, `tomorrow 9am`, `Custom...`).
  - Interactive profile reassignment picker.
- **Live Search Filter (<kbd>/</kbd> or <kbd>Ctrl+F</kbd>)**: Real-time filtering across titles, notes, tags, repos, and profiles.

#### 4. Quick Add Floating Overlay
- **Instant Global Summon**: Global shortcut support (`Super+Shift+T` via Hyprland) summoning a centered capture modal from anywhere.
- **Smart Window & Codebase Detection (`tools/detect-context.sh`)**:
  - Automatically identifies the active workspace from Zed, VS Code, Neovim, Tmux, or terminal.
  - Resolves Git root directory and remote identifier, attaching `#project/repo` context to captured tasks without typing.
- **Non-Destructive Draft Retention**: Unsaved task drafts survive accidental dismissal or closing.

#### 5. Reminders & Scheduling
- **Natural Language Parsing**: Parses relative expressions (`+30m`, `2h`, `in 3 days`), clock times (`17:30`, `5pm`), and calendar targets (`tomorrow 9am`, `monday`, `2026-10-15`).
- **Visual Reminder Picker Modal (`ReminderPicker.qml`)**: Interactive grid with custom time presets, date buttons, and manual time inputs.
- **Desktop Notifications**: Background desktop notifications via Omarchy system alerts when reminders mature.

#### 6. Zero-Config Git Snapshots & Synchronization
- **Automatic Background Commits**: Every task creation, completion, update, or deletion automatically records an atomic commit to local Git history.
- **Git Snapshots Modal (`GitModal.qml` / <kbd>u</kbd>)**:
  - Virtualized commit history list with lazy loading.
  - Snapshot search filter (<kbd>/</kbd>) across commit messages, hashes, device hostnames, and authors.
  - Point-in-time state rollback (<kbd>r</kbd>).
  - Deleted task recovery (<kbd>c</kbd>).
- **Multi-Device Sync**: Conflict-free 3-way JSON store merging with device hostname tagging (`[laptop]`, `[desktop]`).
- **1-Click GitHub Repository Setup**: Automated private repository creation using GitHub CLI (`gh`).

#### 7. Archive Browser & Data Safety
- **High-Capacity Virtualized Archive (`ArchiveModal.qml` / <kbd>d</kbd>)**: Handles over 2,000 archived completed tasks with instant multi-token search.
- **Airtight Restore Pipeline**: Atomic disk-first read-write-verify pattern ensuring tasks are confirmed in the active store before being pruned from archive.
- **Self-Healing Reconciliation**: Automatically heals and dedupes entries on load.

#### 8. Interactive Help Modal & Onboarding Quests
- **Searchable Shortcut Directory (`HelpModal.qml` / <kbd>?</kbd>)**: Interactive modal listing all keyboard shortcuts categorized by workflow, with dynamic search and two-stage escape.
- **8-Step Interactive Onboarding Quest**: Pre-seeded interactive tasks on first installation guiding users through vim navigation, Space-vs-Enter, Quick Add, and drawer expansion.
- **Release Highlights Card**: Built-in visual what's-new banner in the help view.

#### 9. Native Shell IPC Interface (`omarchy-shell tablerase.ardoise`)
- Full CLI command palette:
  - `list`, `get <id>`, `count`, `add "<title>"`, `addDetailed "<title>" "<notes>" "<reminder>"`, `update <id> <json>`, `toggleTodo <id>`, `remove <id>`, `clear`.
  - `profiles`, `setProfile <name>`, `searchProfiles <query>`.
  - `toggle`, `open`, `close`, `quickAdd`.
  - `gitSnapshots`, `gitSearch <query>`, `gitRollback <hash>`, `gitRecover <hash>`, `gitSync`, `autoSetupGitRemote`.
  - `archiveList`, `unarchive <id>`, `purgeArchive <id>`, `clearArchive`.

#### 10. Theming & Design System
- **100% Theme-Aware**: Fully integrated with Omarchy theme engine across all 8 standard themes (Catppuccin Mocha, Catppuccin Latte, Nord, Gruvbox, Tokyo Night, Kanagawa, Everforest, Rosé Pine).
- **High Contrast & Light/Dark Parity**: Strict luminance ratios and warning/accent distinction.
