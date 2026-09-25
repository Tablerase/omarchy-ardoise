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
7. **Multi-Repo & Codebase Context Integrity**:
   - Tasks support prefix-only multi-repo hashtag syntax: `#project/repo #tag1 #tag2 Title`.
   - Projects represent high-level conceptual umbrellas (e.g. `#omarchy`), while repositories represent physical codebases (e.g. `ardoise`, `shell`).
   - Quick Add automatically queries the active Hyprland window, resolves the terminal/editor working directory, Git root, and Git remote identifier, and attaches location context without manual user input.
   - Tasks store cross-device safe Git remote identities (`location.repo`) alongside normalized local directory paths (`location.localPath`).
8. **Clean Separation of UI and Logic (`PanelLogic.js`)**:
   - `PanelContent.qml` strictly handles visual hierarchy, layout items, styling, animations, and QtQuick property bindings.
   - Core 2D navigation state machine transitions (`handleMove`, `handleTab`, `handleActivate`, `handleReturn`, `handleEscape`, `handleTextKey`, `handleDelete`), section / sub-section stepping (`getNextSection`, `getNextSubSection`, `getPrevSubSection`), editor and codebase command generation (`buildEditorCommand`, `buildCodebaseCommand`), repo name formatting (`cleanRepoName`), and keybinding catalogs/filtering (`getKeybindingsList`, `filterKeybindings`) are isolated in `PanelLogic.js`.
   - This separation facilitates rapid manual styling tweaks without risk of breaking navigation algorithms, while enabling comprehensive automated unit testing in Node and Deno.

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

### Modular Component Library (`ui/`)
To preserve long-term maintainability and visual consistency across the main panel and modal surfaces (inspired by OmaTasks), UI widgets are modularized in `ui/`:
- **`ui/Chip.qml`**: Reusable compact pill/badge component for reminders, repositories, tags, and auto-detected locations. Strictly bounded with `elide: Text.ElideRight`, capped max-width, tooltips, and optional removal button.
- **`ui/HelpModal.qml`**: Fullscreen-scoped searchable keyboard shortcut directory with fuzzy filter and two-stage Backspace dismiss.
- **`ui/TaskCheck.qml`**: Circular checkbox button serving as the primary status and urgency indicator (accent border and tint for due today, urgent border and tint for overdue, muted border with checkmark for completed, muted border for normal pending).
- **`ui/ReminderPills.qml`**: Reusable reminder preset pill row (`+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, `Clear`) with navigation cursor scaling and dynamic timestamp recalculation at selection time.
- **`ui/ProfileSelector.qml`**: Horizontal scrollable profile pill selector with profile glyphs, elided labels, active pop, and smooth auto-scroll (`ensureVisible`).

---

## 3. Surface Specifications & Component Trees

### A. Quick Add Modal (`QuickAdd.qml`)

Fullscreen overlay (`WlrLayer.Overlay`) with keyboard exclusivity. Centered card styled with `Color.menu.background`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Row**: Inbox Icon (`InboxIcon.qml`) + "Quick Add Task" Title (`Style.font.subtitle`, bold).
2. **Separator**: Top dividing line (`PanelSeparator`).
3. **Title Input Field (`taskInput`)**:
   - Autofocused on modal open with explicit `BorderSurface` focus border.
   - Supports hashtag syntax auto-detecting profiles (e.g. `#work Finish docs`).
   - <kbd>Escape</kbd>: dismisses if empty; enters normal (motion) mode on `"title"` if text is present without closing or losing draft. Pressing <kbd>j</kbd>/<kbd>Down</kbd> moves to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> re-enters edit mode.
4. **Draft Notice Banner** (Conditional: `hasDraft === true`):
   - Glyph `󰁯` + "Draft restored" caption + clickable "Clear" action (<kbd>Ctrl+⌫</kbd>).
5. **Option Toggles Row**:
   - Button 0: **Add Note** (`󰏫`) — toggles `showNote`. When pressed via <kbd>Enter</kbd>/<kbd>Space</kbd> or clicked, auto-focuses `descNotesArea`.
   - Button 1: **Set Reminder** (`󰥔`) — toggles `showReminderOptions`.
   - Both buttons use `bordered: true` for clear cursor focus framing.
6. **Notes Editor Area (`descNotesArea`)** (Conditional: `showNote === true`):
   - Multi-line `TaskNotesArea` (min 56px, max 130px, auto-scroll).
   - <kbd>Escape</kbd>: blurs textarea and enters normal (motion) mode on `"notes"`, keeping draft text safe. Pressing <kbd>j</kbd>/<kbd>Down</kbd> continues navigation down to `reminders`/`profiles`; pressing <kbd>k</kbd>/<kbd>Up</kbd> navigates up to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> (or typing any printable character) re-enters edit mode on notes.
7. **Reminder Presets Row** (Conditional: `showReminderOptions === true`):
   - Presets: `+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, plus "Clear". Presets and selected timestamps are dynamically recomputed at open and click/selection time relative to current local execution time rather than startup time. Bordered focus styling via `Ui.ReminderPills`.
8. **Profile Selector Container (`quickAddProfileContainer`)**:
   - Horizontal scrollable profile selector (`Ui.ProfileSelector`) with profile glyphs, active pop, and auto-scroll (`ensureVisible`).
   - <kbd>h</kbd> / <kbd>l</kbd> / arrows cycle selected profile.
9. **Separator**: Bottom dividing line (`PanelSeparator`).
10. **Footer Actions Item**:
    - Left: Hint shortcuts (`󰌑 Enter • Tab/Vim Nav • Esc Dismiss • Ctrl+⌫ Discard`) anchored to action buttons with automatic right elision.
    - Right: Action buttons [Cancel] and [Add]:
      - Both buttons use `bordered: true` and dynamically bind `hasCursor` and `selected` strictly to `(root.focusSection === "actions") && (root.actionIndex === ...)`.
      - When Cancel is navigated to (`actionIndex === 0`), Cancel receives `hover-cursor` border, selected fill, and an animated 1.05 scale pop, while Add remains at neutral unselected rest state.
      - When Add is navigated to (`actionIndex === 1`), Add receives `hover-cursor` border, selected fill, and an animated 1.05 scale pop.
      - At neutral rest state (e.g. while typing title or notes), neither button is selected, preventing misleading highlights.
11. **Auto-Detected Codebase Context Chip (`locationPill`)** (Conditional: `detectedContext && attachLocation`):
    - Positioned at the very end of the modal (last section).
    - Displays repository icon (`󰊤`) or directory icon (`󰉋`) + repository identifier / subpath + clickable dismiss `󰅖` icon + `(auto-detected)` caption.
    - In normal mode, navigated via <kbd>j</kbd>/<kbd>Down</kbd> after actions (or <kbd>k</kbd>/<kbd>Up</kbd> backward from title). Pressing <kbd>x</kbd>, <kbd>Del</kbd>, <kbd>Backspace</kbd>, or <kbd>Enter</kbd> removes location and advances to title.

#### Navigation State Flow (`focusSection`)
```
[title] ──Tab/Down──► [options] ──Tab/Down──► [(notes)] ──Tab/Down──► [(reminders)] ──Tab/Down──► [profiles] ──Tab/Down──► [actions] ──Tab/Down──► [(location)]
   ▲                                                                                                                                                    │
   └──────────────────────────────────────────────────Tab/Down (Loops around)───────────────────────────────────────────────────────────────────────────┘
```

---

### B. Main Panel (`PanelContent.qml` & `Panel.qml`)

Attached dropdown panel (`WlrLayer.Top`) launched from bar widget click, desktop shortcut (`SUPER + SHIFT + T` / dynamic detection), or `omarchy-shell summon`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Item**:
   - Left: Ardoise Brand Logo (`InboxIcon`) + Title ("Ardoise") + Pending Task Count badge.
     - Brand logo and title form an interactive group: hovering smoothly transitions the icon and text to `Color.accent` with a pointer cursor and a `PanelToolTip` linking to the GitHub repository (`https://github.com/Tablerase/omarchy-ardoise`). Clicking it opens the GitHub repository in the user's default browser.
   - Right: Shortcuts Help Toggle button (`?`) + Detected Desktop Shortcut copy pill.
2. **Top Filter Pills Row (`visibleProfiles`)**:
   - "All" pill + active/pending profile pills sorted by pending count and recency.
   - Auto-scrollable flickable with left/right fade gradient hints.
   - "+" button to quickly create a new profile inline.
3. **Quick Input Row**:
   - `newTodoField`: Task title entry with inline placeholder wrapped in `BorderSurface`.
   - Visual focus outline displayed when focused in normal navigation mode (`focusSection === "input"`).
   - **Universal Escape**: Pressing <kbd>Escape</kbd> while typing blurs the text field into normal motion mode on the `"input"` section without closing the panel or discarding text. In normal mode, pressing <kbd>j</kbd>/<kbd>Down</kbd> moves into `tasks`, <kbd>k</kbd>/<kbd>Up</kbd> moves into `profiles`, and pressing <kbd>Enter</kbd>, <kbd>Space</kbd>, or typing any printable character re-enters edit mode.
   - Profile badge showing currently active filter tag.
   - Add button.
4. **Task List View (`taskListView`)**:
   - Vertically flickable column of tasks (`itemRow`).
   - Auto-scroll viewport alignment (`ensureTaskVisible`): normal cursor motion keeps the focused task within bounds; expanding a task drawer automatically aligns the expanded task to the top of the list viewport (`alignTop: true`) so the entire drawer (notes, reminders, and profile pills) remains fully visible.
   - Individual task row:
     - **OmaTasks-Inspired Item Layout**:
       - Sizing is deterministic, content-driven, and dynamically compact:
         `implicitHeight: isExpanded ? (expandedContent.implicitHeight + Style.space(16)) : (Style.space(34) + (hasNotes ? Style.space(18) : 0) + (hasBadges ? Style.space(22) : 0))`
       - **Line 1 (Title Row)**: Circular checkmark button (`checkBtn`) + Full-Width Title + Inline Profile badge (`profInlineLabel`, shown in "all" view when the task has no chips) + Action buttons on the right (Expand chevron `󰅀`/`󰅃` and Delete `󰅙`). The pencil icon indicator (`󰏫`) and redundant left-side urgency stripes/gradients are removed in favor of the clean circular checkbox indicator.
       - **Line 2 (Note Preview Line)**: Rendered when collapsed and task has notes (`hasNotes === true`):
         - Single-line elided text preview (`Text.ElideRight`, italic, `Color.textMuted`), indented cleanly below the title.
         - Hover tooltip displaying the full multiline note text.
       - **Line 3 (Metadata & Chips Row)**: Sub-line rendered when chips exist (`hasBadges === hasChips === true`, i.e., has repo, tags, or reminder):
         - Bounded strictly between the checkbox margin and the right edge (with docked profile indicator when viewing "all"), with `Style.space(20)` height ensuring chip borders and pills are never cropped vertically.
         - Profile badge (`profLabel`): Docked cleanly to the right when viewing "all" (`#profile`, elided). If the task has no other chips, the profile label moves inline to Line 1 instead, eliminating the empty 3rd row.
         - Sub-line chips (`chipsRow`): Indented under title text displaying reminder pill (`󰥔 time` — tasks due today display strictly their scheduled time `HH:MM` without redundant "Due today at" or "Today" prefixes), repo badge (`󰊤 repo`), and tag chips (`#tag`).
       - When an item has no notes or chips: Single-line layout (`Style.space(34)`), with title, checkbox, inline profile (in "all" view), and action buttons mathematically and visually centered with comfortable vertical padding.
       - Collapsed row content is vertically centered across 1-line, 2-line, and 3-line items via explicit height propagation on `expandedContent` and `itemHeaderCol`.
       - **Row Separators**: A light section separator (`PanelSeparator`, 1px, `strength: 0.08`) is rendered between adjacent item rows in the list to enhance readability.
     - **Repo Name Display Formatting**:
       - In item badges, repository strings strip any owner/organization prefix (e.g. `Tablerase/omarchy-ardoise` displays cleanly as `omarchy-ardoise`) to save space and reduce cognitive clutter, while strictly preserving the full remote repository and local path in data and hover tooltips.
       - Target codebase context chip remains strictly located within the expanded drawer to avoid crowding the collapsed task list.
   - **Item Ordering Algorithm & Satisfying Task Completion Flow**:
     - **Micro-Animation & Dwell Time (Satisfying Completion)**:
       - Toggling an active task via <kbd>Space</kbd> or click triggers an immediate, rewarding micro-interaction:
         - Checkbox (`Ui.TaskCheck`): Plays a bouncy pop scale animation (`1.0 -> 1.25 -> 1.0` with `Easing.OutBack`), checkmark spring scales in from `0.2` to `1.0`, and background/border smoothly transition to accent colors.
         - Animated Strikethrough (`strikeLine`): Rather than abruptly flashing on, a custom strikethrough line sweeps smoothly from **left to right** across the task title text (`0 -> Math.min(contentWidth, width)` in 260ms with `Easing.OutCubic`). Undoing within the grace period smoothly retracts the line from right to left.
         - Task Title & Background: Title dims to `0.55` opacity with an animated transition, and row background gains a subtle accent completion tint (`alpha(Color.accent, 0.08)`).
         - **Grace Period & Downward Slide Transition**:
           - 0ms–350ms: The item stays stationary in its active list position (`pendingCompletionIds`), giving immediate confirmation without disorienting movement.
           - 350ms–600ms: The task begins smoothly **sliding down** (`y` translates +24px) while gently fading, and its container height collapses to 0 over 250ms, allowing active tasks below to glide smoothly upward into its place.
           - 600ms: `flushPendingCompletions()` commits `done: true` to the store. The task arrives in the dedicated completed fold, sliding in from above (`-16px -> 0px` with `Easing.OutBack`) with a subtle settling bounce.
       - **Instant In-Place Undo**: Pressing <kbd>Space</kbd> or clicking the checkbox again during the initial dwell window instantly reverts the task to active state without moving or reordering.
       - **Commit & Flush**: When the 600ms timer fires (or immediately when switching filter tags, closing the panel, or archiving completed tasks), `flushPendingCompletions()` commits `done: true` to the store.
     - **Dedicated Completed Fold (`── 󰅃 Completed (N) ──`)**:
       - Completed tasks reside at the bottom of the list under a dedicated fold divider with a centered interactive pill: `── 󰅃 Completed (N) ──`.
       - Clicking the fold pill toggles `completedFoldOpen` (chevron flips between `󰅃` and `󰅀`).
       - When collapsed (`completedFoldOpen === false`), completed task rows smoothly collapse to zero height, leaving only the fold header visible. Keyboard navigation (<kbd>j</kbd>/<kbd>k</kbd>/<kbd>G</kbd>) automatically respects fold collapse, skipping hidden completed tasks and transitioning directly into the footer bar.
     - **Item Partitioning**:
       1. **Due / Reminder Tasks (Top Tier)**: Incomplete tasks with scheduled reminders or due dates, sorted chronologically ascending (earliest due and most overdue appear at the very top).
       2. **Active Incomplete Tasks (Middle Tier)**: Incomplete tasks without reminders, sorted by recency descending (newest tasks appear first).
       3. **Completed Tasks (Bottom Tier / Fold)**: Completed tasks sink into the completed fold, sorted by "last completed" descending (most recently completed tasks appear at the top of the completed section).
   - **Expanded Task Drawer (`itemRow.isExpanded`)**:
     - Auto-expand via mouse hover (1500ms) only active when mouse movement is detected; auto-folds 350ms after leave or instantly on keyboard motion.
     - Explicit keyboard expansion (<kbd>Enter</kbd>) keeps drawer open until explicitly toggled or closed, auto-aligning item to the top of the viewport.
     - **Synchronized Row Expansion & Fluid Motion**: Expanding/collapsing a task drawer (`itemRowHeightAnim`, 200ms `OutCubic`) strictly clips the row (`clip: true`) and fades in drawer details (`expandedDetailsCol`, 180ms `OutCubic`). The outer delegate wrapper height updates in the exact same frame (bypassing secondary filters during expand/collapse), ensuring tasks below translate down synchronously in lockstep without visual overlap or delay.
     - Separator.
     - `TaskNotesArea` multi-line notes editor (directly placed within the column without misaligned outer wrappers, using `isNavFocused` to draw the control's native focus border when active in sub-section navigation).
     - Reminder preset row: Today, Tomorrow, In 3 Days, In 1 Week, Clear. Bordered navigation focus indicators.
     - **Compact Profile Reassignment Row (`profReassignContainer`)**: Single-line horizontal scrollable row (`Style.space(22)`) with auto-scroll (`ensureVisible`) keeping the currently navigated profile pill smoothly centered in view on <kbd>h</kbd> / <kbd>l</kbd> keypress.
     - **Location & Codebase Context Row (`locRow`)**:
       - Displays `󰉋 Target:` with repository identifier (`󰊤 repo/subpath`) or directory path (`󰉋 localPath`), along with subsystem `#tag` chips.
       - Includes a **[Codebase]** action button that launches `omarchy-launch-editor` directly in the target repository directory.
   - **Expanded Sub-Section Keyboard State Machine (`expandedSubSection`)**:
     - When a task is expanded, focus is hierarchical:
       1. `"header"` (default): Item row header is focused. <kbd>Enter</kbd> collapses the drawer; <kbd>Space</kbd> toggles `done`.
       2. `"notes"`: Notes editor area is focused. Pressing <kbd>i</kbd>, <kbd>Enter</kbd>, or typing any printable character enters insert mode and appends into the notes field; <kbd>Escape</kbd> or <kbd>Enter</kbd> leaves insert mode back to navigation mode without losing draft text. Clicking directly into the notes field focuses the editor without toggling task status.
       3. `"reminders"`: Reminder presets row is focused. <kbd>h</kbd> / <kbd>l</kbd> cycles presets; <kbd>Space</kbd> / <kbd>Enter</kbd> applies the preset.
       4. `"profiles"`: Profile reassignment row is focused. <kbd>h</kbd> / <kbd>l</kbd> cycles profiles (with auto-scroll into view); <kbd>Space</kbd> / <kbd>Enter</kbd> reassigns task profile.
       5. `"codebase"` (conditional on location): Codebase launch button is focused. <kbd>Enter</kbd> / <kbd>Space</kbd> opens editor.
     - Navigating with <kbd>Tab</kbd> / <kbd>j</kbd> / <kbd>↓</kbd> steps sequentially through sub-sections, then continues to the next task in the list.
     - Navigating with <kbd>Shift+Tab</kbd> / <kbd>k</kbd> / <kbd>↑</kbd> steps backward through sub-sections, returning to `"header"`.
     - Two-stage escape: <kbd>Escape</kbd> in any expanded sub-section returns focus to `"header"`; <kbd>Escape</kbd> on `"header"` collapses the drawer; <kbd>Escape</kbd> on a collapsed task dismisses the panel.
5. **Footer Bar**:
   - Urgency visual progress bar (overdue / due today / later).
   - Action buttons: [Clear (c)] (archive and clear completed tasks in current profile) • [Archive (d)] (open todos-archive.json in editor) • [Edit (e)] (open todos.json in editor) • [Quick Add (A)].
6. **Searchable Help Overlay Modal (`showKeyHelp`)**:
   - Fuzzy filter text field (`keySearchField`) wrapped in `BorderSurface`.
   - **Universal Input Handling**:
     - Follows project-wide input convention: padded, custom font/color styling, and active navigation focus border (`isNavFocused`).
     - **Two-Stage Escape**:
       - When `keySearchField.text` is empty: pressing <kbd>Escape</kbd> (or <kbd>Backspace</kbd>) dismisses the modal and restores focus to the panel.
       - When `keySearchField.text` has content: pressing <kbd>Escape</kbd> blurs the field into normal motion navigation mode on `"search"` with active `BorderSurface` focus outline, preserving draft search queries.
       - In normal motion mode: pressing <kbd>Escape</kbd> dismisses; pressing <kbd>Enter</kbd>, <kbd>Space</kbd>, <kbd>i</kbd>, <kbd>a</kbd>, or typing any character re-enters text edit mode; pressing <kbd>j</kbd>/<kbd>Down</kbd>/<kbd>Tab</kbd> moves into the shortcuts list (`helpFlickable`); pressing <kbd>k</kbd>/<kbd>Up</kbd>/<kbd>Shift+Tab</kbd> moves to `closeHelpBtn`.
     - When navigating the shortcuts list: pressing <kbd>k</kbd> or <kbd>Up</kbd> at the top item moves back up to the search field in motion mode without swallowing keystrokes; typing any character redirects into search.
   - Keyboard shortcut directory grouped by category (Global, Navigation, Task Actions, Modals). Uses `<slash>` instead of ambiguous `/ /` notation, and dynamically lists the active desktop keybinding (`root.detectedShortcut`).

#### Navigation State Flow (`focusSection`)
```
[profiles] ◄──Up/Down──► [input] ◄──Up/Down──► [tasks (header ◄──► notes ◄──► rem ◄──► prof ◄──► code)] ◄──Up/Down──► [footer]
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
- **Shell IPC Contract (`IpcHandler: tablerase.ardoise`)**:
  - `omarchy-shell tablerase.ardoise list`: Returns full JSON array of active tasks.
  - `omarchy-shell tablerase.ardoise count`: Returns pending task count string.
  - `omarchy-shell tablerase.ardoise add "<title> [#profile]"`: Adds task with optional `#profile`.
  - `omarchy-shell tablerase.ardoise toggleTodo "<id>"`: Toggles task completion (`done`).
  - `omarchy-shell tablerase.ardoise update "<id>" '<fieldsJson>'`: Updates task properties (e.g. reminder, notes, profile).
  - `omarchy-shell tablerase.ardoise remove "<id>"`: Deletes task by ID.
  - `omarchy-shell tablerase.ardoise clear`: Archives and clears completed tasks.
  - `omarchy-shell tablerase.ardoise profiles`: Returns array of available profiles.
  - `omarchy-shell tablerase.ardoise setProfile "<profile>"`: Sets active profile filter.
  - `omarchy-shell tablerase.ardoise open` / `close` / `toggle`: Controls main panel visibility.
  - `omarchy-shell tablerase.ardoise archived`: Returns archived tasks JSON.
  - `omarchy-shell tablerase.ardoise archiveCount`: Returns count of archived tasks.

---

## 4. Keybinding & Interaction Matrix

| Context | Key | Action |
| :--- | :--- | :--- |
| **Global Desktop** | `SUPER + SHIFT + T` (or custom hyprland bind) | Toggle Main Panel |
| **Panel** | `j` / `↓` | Move cursor down (tasks, drawer sub-sections, footer, input) |
| **Panel** | `k` / `↑` | Move cursor up (drawer sub-sections, tasks; at task 0, transitions to `input`) |
| **Panel** | `Tab` / `Shift+Tab` | Advance / reverse major sections and expanded task sub-sections |
| **Panel** | `Space` | Toggle task completion (`done`), or apply selected reminder/profile |
| **Panel** | `Enter` / `Return` | Expand / collapse task details (drawer), or enter editor on notes |
| **Panel (Drawer)** | `h` / `l` / `←` / `→` | Cycle reminder presets or profile reassignments |
| **Panel (Drawer)** | `i` / `Enter` | Enter notes text editor (insert mode) |
| **Panel (Drawer)** | `Escape` | Return from sub-section to task header, or collapse drawer |
| **Panel** | `e` | Open `todos.json` in editor (jumps to selected task line if on a task) |
| **Panel** | `c` | Archive and clear completed tasks in current profile |
| **Panel** | `d` | Open `todos-archive.json` in editor (Archive button) |
| **Panel** | `i`, `a`, `<slash>` | Jump focus into new task input field |
| **Panel** | `A` | Open Quick Add overlay modal |
| **Panel** | `x` / `Delete` | Delete highlighted task |
| **Panel** | `g` | Jump to first task |
| **Panel** | `G` | Jump to last task |
| **Panel** | `?` / `Backspace` (empty search) | Toggle or dismiss searchable keyboard shortcuts modal |
| **Panel (Input)** | `Escape` | Blur text field to normal motion mode on `input` without discarding text |
| **Panel (Input Normal)** | `i` / `a` / `Enter` / `Space` | Enter text edit mode in input field |
| **Panel (Input Normal)** | `j` / `↓` | Move down to task list |
| **Panel (Input Normal)** | `k` / `↑` | Move up to profile filter bar |
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
- Quick Add Card width: `Math.min(Style.space(560), panel.width - Style.space(32))` (expanded from 480px to accommodate bottom shortcut hints without overlapping action buttons).
- Urgency progress gradient: Maximum width capped at `35%` (approx `110px`) to prevent visual bloat.

---

## 6. Verification Checklist for UI Changes
Before committing any UI or navigation change:
1. Run `npm run check` (typecheck, `qmllint`, `omarchy plugin validate`, runtime unit tests).
2. Verify with tests in `tests/qml-runtime.test.mts` that keyboard navigation did not break.
3. Test with live shell: `omarchy-restart-shell` and verify interactive motions.
4. Verify all changes are documented in this `DESIGN.md`.
