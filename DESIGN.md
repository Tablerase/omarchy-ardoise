# Ardoise UI & Interaction Design Specification (`tablerase.ardoise`)

> [!IMPORTANT]
> **Maintenance Contract for AI Models & Developers**:
> Any AI model or developer modifying this plugin's UI layout, component structure, modal flow, keybindings, or focus state machine **MUST update this document** to keep it in sync with the codebase.
> If a proposed modification significantly alters established layout order, keyboard shortcuts, or visual hierarchy, **ask the user for explicit permission** before applying it.

---

## 1. Architectural Philosophy & Invariants

Ardoise is an Omarchy desktop extension designed for instant, zero-friction task capture and management. Its core principles are:

1. **Keyboard-First & Vim-Inspired Ergonomics**: Every feature, filter, section, and modal must be 100% accessible via keyboard motions (<kbd>j</kbd>/<kbd>k</kbd>, <kbd>h</kbd>/<kbd>l</kbd>, <kbd>g</kbd>/<kbd>G</kbd>, <kbd>Tab</kbd>/<kbd>Shift+Tab</kbd>, <kbd>Space</kbd>, <kbd>Enter</kbd>, <kbd>Esc</kbd>).
2. **Two-Stage Escape (Insert vs. Motion Mode)**:
   - When a text field is active:
     - If empty: <kbd>Escape</kbd> immediately dismisses the modal / panel.
     - If non-empty: <kbd>Escape</kbd> **leaves insert mode** and enters normal (motion) mode on the container without closing the window or discarding text.
   - When in normal / motion mode: <kbd>Escape</kbd> **dismisses** the modal / panel.
3. **Action Key Separation (<kbd>Enter</kbd> vs. <kbd>Space</kbd>)**:
   - In the task list, <kbd>Enter</kbd> strictly **expands or collapses** task details (notes, reminders, profile reassignment).
   - <kbd>Space</kbd> strictly **toggles completion** (`done`).
   - In input fields, <kbd>Enter</kbd> commits / submits. In multi-line notes, <kbd>Shift+Enter</kbd> inserts a newline while <kbd>Enter</kbd> commits.
4. **Non-Destructive Draft Retention**:
   - Unsaved Quick Add modal drafts (title, description, profile, reminder) are automatically retained in state and restored if the modal is dismissed accidentally. Drafts can be cleared via <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> or the "Clear" action.
5. **No Layout Overflow**:
   - Profile names, tags, and titles must gracefully wrap (`Flow`) or elide (`Text.ElideRight`) to prevent pushing buttons or cards outside visible geometry.
6. **Separation of Mouse Hover Preview vs. Keyboard Expansion**:
   - **Keyboard Navigation (<kbd>Enter</kbd> / <kbd>e</kbd>)**: Explicit toggle. Opening an item via keyboard marks it `expandedViaKeyboard = true`, preventing mouse hover fold timers (`hoverFoldTimer`, `listFoldTimer`) from collapsing the drawer when the mouse rests elsewhere. Navigating with <kbd>j</kbd>/<kbd>k</kbd> does not auto-expand items.
   - **Mouse Hover Preview**: Hovering over a task row for 1500ms auto-expands the drawer only after actual mouse movement has been detected (`mouseMovementDetected`). When the panel opens under a stationary mouse cursor, auto-expansion is suppressed to prevent center/random tasks from opening over keyboard selection. Leaving the row folds the preview after 350ms (unless notes editor is focused). Starting keyboard motion (<kbd>j</kbd>/<kbd>k</kbd>/<kbd>Tab</kbd>) immediately collapses temporary hover previews.
   - **Mouse Click Expansion**: Clicking the chevron expand button on a row explicitly expands it (`expandedViaKeyboard = true`), keeping it open while interacting with notes and controls.

---

## 2. Surfaces & Spatial Architecture

The plugin comprises 3 primary desktop surfaces rendered via Quickshell:

```
┌────────────────────────────────────────────────────────┐
│ Status Bar: [BarWidget.qml] (Dot + Pending/Due Count)   │
└────────────────────────────────────────────────────────┘
                           │
       ┌───────────────────┴───────────────────┐
       ▼                                       ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│ Main Panel: [Panel.qml]      │    │ Quick Add: [QuickAdd.qml]    │
│ Layer: Panel                 │    │ Layer: Overlay               │
│ - Top filter pills           │    │ - Dimmed Scrim               │
│ - Quick Add input field      │    │ - Centered Floating Card     │
│ - Centered task list         │    │ - Fast Capture Layout        │
│ - Drawer for notes/reminders │    │ - Draft auto-restoration     │
│ - Action footer & Help modal │    │                              │
└──────────────────────────────┘    └──────────────────────────────┘
```

---

## 3. Surface Specifications & Component Trees

### A. Quick Add Modal (`QuickAdd.qml`)

Fullscreen overlay (`WlrLayer.Overlay`) with keyboard exclusivity. Centered card styled with `Color.menu.background`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Row**: Inbox Icon (`InboxIcon.qml`) + "Quick Add Task" Title (`Style.font.subtitle`, bold).
2. **Separator**: Top dividing line (`PanelSeparator`).
3. **Title Input Field (`taskInput`)**:
   - Autofocused on modal open.
   - Supports hashtag syntax auto-detecting profiles (e.g. `#work Finish docs`).
   - <kbd>Escape</kbd>: dismisses if empty; blurs to `options` motion mode if text is present.
4. **Draft Notice Banner** (Conditional: `hasDraft === true`):
   - Glyph `󰁯` + "Draft restored" caption + clickable "Clear" action (<kbd>Ctrl+⌫</kbd>).
5. **Option Toggles Row**:
   - Button 0: **Add Note** (`󰏫`) — toggles `showNote`. When pressed via <kbd>Enter</kbd>/<kbd>Space</kbd> or clicked, auto-focuses `descNotesArea`.
   - Button 1: **Set Reminder** (`󰥔`) — toggles `showReminderOptions`.
6. **Notes Editor Area (`descNotesArea`)** (Conditional: `showNote === true`):
   - Multi-line `TaskNotesArea` (min 56px, max 130px, auto-scroll).
   - <kbd>Escape</kbd>: blurs textarea and returns focus to `options` on the card.
7. **Reminder Presets Row** (Conditional: `showReminderOptions === true`):
   - Presets: "Today" (+4h), "Tomorrow" (09:00), "In 3 Days", "In 1 Week", plus "Clear".
8. **Profile Selector Container (`profileFlow`)**:
   - Positioned at the bottom, just above the footer actions for fast writing.
   - Flow wrapping profile pills sorted by activity/count.
   - <kbd>h</kbd> / <kbd>l</kbd> / arrows cycle selected profile.
9. **Separator**: Bottom dividing line (`PanelSeparator`).
10. **Footer Actions Item**:
    - Left: Hint shortcuts (`󰌑 Enter • Tab/Vim Nav • Esc Dismiss • Ctrl+⌫ Discard`).
    - Right: [Cancel] button and [Add] primary button.

#### Navigation State Flow (`focusSection`)
```
[title] ──Tab/Down──► [options] ──Tab/Down──► [(notes)] ──Tab/Down──► [(reminders)] ──Tab/Down──► [profiles] ──Tab/Down──► [actions]
   ▲                                                                                                                            │
   └──────────────────────────────────────────────Tab/Down (Loops around)───────────────────────────────────────────────────────┘
```

---

### B. Main Panel (`PanelContent.qml` & `Panel.qml`)

Attached dropdown panel (`WlrLayer.Top`) launched from bar widget click, desktop shortcut (`SUPER + SHIFT + T` / dynamic detection), or `omarchy-shell summon`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Item**:
   - Left: Ardoise Brand Logo + Module Title + Pending Task Count badge.
   - Right: Shortcuts Help Toggle button (`?`) + Detected Desktop Shortcut copy pill.
2. **Top Filter Pills Row (`visibleProfiles`)**:
   - "All" pill + active/pending profile pills sorted by pending count and recency.
   - Auto-scrollable flickable with left/right fade gradient hints.
   - "+" button to quickly create a new profile inline.
3. **Quick Input Row**:
   - `newTodoField`: Task title entry with inline placeholder.
   - Profile badge showing currently active filter tag.
   - Add button.
4. **Task List View (`taskListView`)**:
   - Vertically flickable column of tasks (`itemRow`).
   - Auto-scroll centering (`ensureTaskVisible`) keeps the focused task in view.
   - Individual task row:
     - Checkbox: Custom animated check box (`isDone`).
     - Task Title: Strikethrough when done, urgency glow when due/overdue.
     - Profile badge: Tag glyph `󰓹` + elided name.
     - Due date badge: Clock glyph `󰥔` + relative countdown.
     - Expand button: Chevron `󰅂` explicitly toggling detailed drawer (`expandedViaKeyboard = true`), keeping drawer open across mouse motion.
     - Delete button: Trash icon `󰆴`.
   - **Item Ordering Algorithm (`TodoStore.getFilteredTodos`)**:
     Tasks are strictly partitioned and sorted across 3 priority tiers:
     1. **Due / Reminder Tasks (Top Tier)**: Incomplete tasks with scheduled reminders or due dates, sorted chronologically ascending (earliest due and most overdue appear at the very top).
     2. **Active Incomplete Tasks (Middle Tier)**: Incomplete tasks without reminders, sorted by recency descending (newest tasks appear first).
     3. **Completed Tasks (Bottom Tier)**: Completed tasks sink to the bottom, sorted by "last completed" descending (most recently completed tasks appear at the top of the completed section).
   - **Expanded Task Drawer (`itemRow.isExpanded`)**:
     - Auto-expand via mouse hover (1500ms) only active when mouse movement is detected; auto-folds 350ms after leave or instantly on keyboard motion.
     - Explicit keyboard expansion (<kbd>Enter</kbd> / <kbd>e</kbd>) keeps drawer open until explicitly toggled or closed.
     - Separator.
     - `TaskNotesArea` multi-line notes editor (press <kbd>e</kbd> to focus).
     - Reminder preset row: Today, Tomorrow, In 3 Days, In 1 Week, Clear.
     - Profile reassign flow pills.
5. **Footer Bar**:
   - Urgency visual progress bar (overdue / due today / later).
   - Action buttons: [Clean Done] [Archive Completed] [Export JSON] [Help (?)].
6. **Searchable Help Overlay Modal (`showKeyHelp`)**:
   - Fuzzy filter text field (`keySearchField`).
   - Keyboard shortcut directory grouped by category (Global, Navigation, Task Actions, Modals).

#### Navigation State Flow (`focusSection`)
```
[profiles] ◄──Up/Down──► [input] ◄──Up/Down──► [tasks] ◄──Up/Down──► [footer]
```
- At task index `0`, pressing <kbd>Up</kbd> or <kbd>k</kbd> transitions focus directly into `input`.
- In `input`, pressing <kbd>Down</kbd> or <kbd>Tab</kbd> moves into `tasks`.
- In `input`, pressing <kbd>Escape</kbd> releases focus and returns to `tasks`.

---

### C. Bar Widget (`BarWidget.qml`)

Quickshell taskbar widget placed in the status bar.
- **Urgent Dot**: Flashing accent dot if tasks are overdue.
- **Icon & Badge**: Ardoise glyph `󰄬` + pending task count.
- **Due Today Indicator**: Shows `󰥔 <count>` if tasks are due today.
- **Interactions**:
  - Left click: Toggles main panel (`tablerase.ardoise toggle`).
  - Right click: Opens Quick Add modal (`tablerase.ardoise quickadd`).
  - Scroll: Cycles active profile filter.

---

## 4. Keybinding & Interaction Matrix

| Context | Key | Action |
| :--- | :--- | :--- |
| **Global Desktop** | `SUPER + SHIFT + T` (or custom hyprland bind) | Toggle Main Panel |
| **Panel** | `j` / `↓` | Move cursor down (tasks, footer, input) |
| **Panel** | `k` / `↑` | Move cursor up (at task 0, transitions to `input`) |
| **Panel** | `Tab` / `Shift+Tab` | Advance / reverse major sections (`profiles` ↔ `input` ↔ `tasks` ↔ `footer`) |
| **Panel** | `Space` | Toggle task completion (`done`) |
| **Panel** | `Enter` / `Return` | Expand / collapse task details (drawer) |
| **Panel** | `e` | Expand task and auto-focus inline notes editor |
| **Panel** | `i`, `a`, `/` | Jump focus into new task input field |
| **Panel** | `A` | Open Quick Add overlay modal |
| **Panel** | `x` / `Delete` | Delete highlighted task |
| **Panel** | `g` | Jump to first task |
| **Panel** | `G` | Jump to last task |
| **Panel** | `?` | Toggle searchable keyboard shortcuts modal |
| **Panel (Input)** | `Escape` | Release focus back to task list (normal mode) |
| **Quick Add** | `Escape` | If title empty: dismiss modal. If non-empty: leave insert mode to `options`. |
| **Quick Add (Normal)**| `Escape` | Dismiss modal |
| **Quick Add (Normal)**| `i` / `a` | Enter insert mode into title input (or notes if on notes) |
| **Quick Add (Normal)**| `j` / `k` / `Tab` | Advance / reverse section |
| **Quick Add (Normal)**| `h` / `l` / `←` / `→` | Cycle profiles, option toggles, or action buttons |
| **Quick Add (Normal)**| `Enter` / `Space` | Activate selected section (Add Note auto-focuses notes field) |
| **Quick Add** | `Ctrl + Backspace` | Clear restored draft |
| **Notes Editor** | `Shift + Enter` | Insert newline |
| **Notes Editor** | `Enter` | Save and commit note |
| **Notes Editor** | `Escape` | Save note and blur to normal mode |

---

## 5. Design Tokens, Glyphs & Styling Guidelines

### Icon Glyphs (Nerd Font MD)
- **Clock / Reminder**: `󰥔` (`\U000f0954`) — *Never use avatar `󰀉` for reminders!*
- **Pen / Notes**: `󰏫` (`\U000f03eb`)
- **Personal Profile**: `󰀉` (`\U000f0009`) — *Reserved exclusively for user profile identity.*
- **Tag / Profile Category**: `󰓹` (`\U000f04f9`)
- **Draft Restored**: `󰁯` (`\U000f006f`)
- **Keyboard / Enter**: `󰌑` (`\U000f0311`)
- **Add / Plus**: `󰐕` (`\U000f0415`)
- **Remove / Trash**: `󰆴` (`\U000f01b4`)
- **Check Complete**: `󰄬` (`\U000f012c`)
- **Check Empty**: `󰄱` (`\U000f0131`)

### Spacing & Metrics
- Standard padding: `Style.space(8)`, `Style.space(12)`, `Style.space(16)`.
- Pill height: `Style.space(20)` (compact) to `Style.space(24)` (standard).
- Pill max-width: Elide right at `Style.space(80)` to `Style.space(90)`.
- Quick Add Card width: `Math.min(Style.space(480), panel.width - Style.space(32))`.
- Urgency progress gradient: Maximum width capped at `35%` (approx `110px`) to prevent visual bloat.

---

## 6. Verification Checklist for UI Changes
Before committing any UI or navigation change:
1. Run `npm run check` (typecheck, `qmllint`, `omarchy plugin validate`, runtime unit tests).
2. Verify with tests in `tests/qml-runtime.test.mts` that keyboard navigation did not break.
3. Test with live shell: `omarchy-restart-shell` and verify interactive motions.
4. Verify all changes are documented in this `DESIGN.md`.
