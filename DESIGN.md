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
- **`ui/HelpModal.qml`**: Fullscreen-scoped searchable keyboard shortcut directory with fuzzy filter and two-stage Backspace dismiss. Mounted as a direct child of `KeyboardPanel` in `Panel.qml` (not inside `PanelContent`) so it always fills the full panel window height regardless of content count. Contains an unconditional full-coverage `MouseArea` (`hoverEnabled: true`, `acceptedButtons: Qt.AllButtons`) that blocks all hover and click events from bleeding through to the task list below.
- **`ui/GitModal.qml`**: Modal overlay for reviewing local Git commit snapshots, executing point-in-time rollbacks (<kbd>r</kbd>), recovering deleted tasks (<kbd>c</kbd>), and configuring remote synchronization (GitHub / GitLab) with conflict-free 3-way JSON store merging and device tagging (`[hostname]`). Accessible via header action button (`󰊢`) or Vim <kbd>u</kbd>. Mounted as a direct child of `KeyboardPanel` in `Panel.qml` so it fills the full panel window height. Tab navigation uses `KeyBadge` labels with accent underline. Action buttons use `bordered: true` + `ShortcutToolTip`. Remote URL field uses `BorderSurface`. Status area uses `Color.menu.selectedBackground`. Contains an unconditional full-coverage `MouseArea` to block mouse bleed-through.
- **`ui/TaskCheck.qml`**: Circular checkbox button serving as the primary status and urgency indicator (accent border and tint for due today, urgent border and tint for overdue, muted border with checkmark for completed, muted border for normal pending).
- **`ui/ArdoiseIcon.qml`**: The shared task-slate brand mark, rendered as a Nerd Font MD glyph (Private Use Area) rather than a vector. Optically centered with `TextMetrics.tightBoundingRect` horizontal correction — the same technique omarchy's own `Ui/OpticalGlyph.qml` uses — so it sits on the same optical centre as the icons beside it in the bar. The glyph is a **stateful ladder rung** resolved by `TodoStore.getArdoiseIconState()`, and the component is used at all three brand surfaces (status bar widget, panel brand header, QuickAdd header) so the plugin reports load identically everywhere. See §5 *Task-Slate Icon Ladder* for the rung table.
  - Properties: `store` (drives the ladder), `bar` (optional shell root, supplies `foreground` / `urgent` / `fontFamily`), `iconSize` (defaults to `Style.bar.iconFont` = 13 px), `forcedKey` (pin a rung, used by `tools/preview.qml`), `colorOverride` (flat color override, used for the panel brand-row hover), `foregroundOverride` / `accentOverride` (replace only the base color of the `foreground` / `accent` roles so a host surface can supply its own text color while urgency escalation still reads).
  - **Replaces** the previous `ui/InboxIcon.qml` (Canvas 2D inbox tray). It was drawn at 16 px as a 1.75/24 stroke while every other Omarchy bar widget paints a 13 px solid font glyph, so it read lighter, wider, and less optically centred than its neighbours.
- **`ui/ReminderPills.qml`**: Reusable horizontal scrollable reminder preset pill row (`+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, `Clear`) with navigation cursor scaling, dynamic timestamp recalculation at selection time, smooth auto-scroll (`ensureVisible`) keeping the active pill centered in view, single-hue alpha fade gradient overlays (`fadeColor`, `z: 1`, 24 px left / 32 px right) cleanly dissolving overflowing content, and a thin 3 px horizontal `ScrollBar` (`policy: AsNeeded`) for mouse users. `implicitHeight: Style.space(26)` (22 px pills + 4 px scrollbar zone).
- **`ui/ProfileSelector.qml`**: Horizontal scrollable profile pill selector with profile glyphs, elided labels, active pop, smooth auto-scroll (`ensureVisible`), single-hue alpha fade gradient overlays (`fadeColor`, `z: 1`, 24 px left / 32 px right), and a thin 3 px horizontal `ScrollBar` (`policy: AsNeeded`) for mouse users. `implicitHeight: Style.space(26)`.
  - In expanded task drawer, `fadeColor` must be the **opaque composite** of `Color.menu.selectedBackground` (8% alpha tint) over `Color.popups.background`, computed as `root.expandedCardColor` in `PanelContent`. Passing the semi-transparent `selectedBackground` directly results in invisible gradients.
- **`ui/KeyBadge.qml`**: Reusable keyboard shortcut badge component rendering key representations with pixel-perfect parity to the help guide (`Util.alpha(badgeColor, 0.15)` background fill, `badgeColor` border, monospace bold font, `radius: Style.space(4)`).
- **`ui/ShortcutToolTip.qml`**: Rich multi-line tooltip component presenting an action description on top and keyboard shortcut badges below separated by a line break, with both the description text and shortcut badge row horizontally centered in their respective lines. Supports automatic regex parsing of legacy parenthesized shortcuts `(key)` or explicit `description` and `shortcut` properties, automatically splitting multi-key combinations (e.g. `"A / SUPER + SHIFT + T"`) into distinct `KeyBadge` pills with subtle `/` separators. Applied across all button tooltips in the panel and modals (Header Help & Shortcut buttons, Input Add button, Task Row Expand & Delete buttons, Footer Action buttons, and Help Modal Close button).

---

## 3. Surface Specifications & Component Trees

### A. Quick Add Modal (`QuickAdd.qml`)

Fullscreen overlay (`WlrLayer.Overlay`) with keyboard exclusivity. Centered card styled with `Color.menu.background`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Row**: Ardoise Task-Slate Mark (`ui/ArdoiseIcon.qml`, ladder rung at `Style.font.subtitle`, `foregroundOverride: Color.menu.text`) + "Quick Add Task" Title (`Style.font.subtitle`, bold).
2. **Separator**: Top dividing line (`PanelSeparator`).
3. **Title Input Field (`taskInput`)**:
   - In **insert mode** (`activeFocus === true`): 2px solid `Color.accent` border + soft accent tint fill (`Util.alpha(Color.accent, 0.08)`) — clear "I am typing" indicator.
   - In **nav/normal mode** (`isNavFocused === true`, `activeFocus === false`): 1px solid `Color.accent` border, no fill tint — field is selected in keyboard nav but not being edited.
   - Supports hashtag syntax auto-detecting profiles (e.g. `#work Finish docs`).
   - <kbd>Escape</kbd>: dismisses if empty; enters normal (motion) mode on `"title"` if text is present without closing or losing draft. Pressing <kbd>j</kbd>/<kbd>Down</kbd> moves to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> re-enters edit mode.
   - **Title Validation & Error State**: When input contains only hashtags/profile/repo (e.g. `#ardoise/widget`) or when submission is attempted without an actual title, `taskInput` displays a high-contrast `Color.urgent` warning border (`Border.flat(Color.urgent, 2)` when focused, 1px when blurred) and a soft urgent background tint.
4. **Inline Validation Cue (`titleErrorRow`)**:
   - Displayed immediately below `taskInput` whenever the title is missing while hashtags/tags are present, or when submission is attempted with an empty title.
   - Renders an error icon (`󰅚`) and clear actionable message in `Color.urgent`: `"Title required: add task name after hashtag (e.g. #ardoise/widget My task)"` or `"Task title is required"`. Automatically hides as soon as a non-empty title is typed.
5. **Draft Notice Banner** (Conditional: `hasDraft === true`):
   - Glyph `󰁯` + "Draft restored" caption + clickable "Clear" action (<kbd>Ctrl+⌫</kbd>).
6. **Option Toggles Row**:
   - Button 0: **Add Note** (`󰏫`) — toggles `showNote`. When active, displays clean accent tint (`Util.alpha(Color.accent, 0.12)`), 1px accent border, and accent text/icon. During keyboard navigation (`hasCursor`), scales by 1.05 with a crisp 2px accent focus ring and prominent focus fill. When pressed via <kbd>Enter</kbd>/<kbd>Space</kbd> or clicked, auto-focuses `descNotesArea`.
   - Button 1: **Set Reminder** (`󰥔`) — toggles `showReminderOptions`. When active with a chosen reminder, displays accent tint, 1px accent border, and formatted reminder string. During keyboard navigation (`hasCursor`), scales by 1.05 with a crisp 2px accent focus ring.
   - Both buttons use `bordered: true`, scale popping, and explicit accent focus rings, ensuring navigation focus is always noticeably brighter and higher-contrast than resting active states.
7. **Notes Editor Area (`descNotesArea`)** (Conditional: `showNote === true`):
   - Multi-line `TaskNotesArea` (min 56px, max 130px, auto-scroll).
   - **Insert mode** (`activeFocus === true`): 2px solid accent border + accent tint fill — clear editing indicator.
   - **Nav mode** (`isNavFocused === true`, `activeFocus === false`): 1px solid accent border, no tint — field is selected in keyboard nav but not being edited.
   - <kbd>Escape</kbd>: blurs textarea and enters normal (motion) mode on `"notes"`, keeping draft text safe. Pressing <kbd>j</kbd>/<kbd>Down</kbd> continues navigation down to `reminders`/`profiles`; pressing <kbd>k</kbd>/<kbd>Up</kbd> navigates up to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> (or typing any printable character) re-enters edit mode on notes.
8. **Reminder Presets Row** (Conditional: `showReminderOptions === true`):
   - Presets: `+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, plus "Clear". Presets and selected timestamps are dynamically recomputed at open and click/selection time relative to current local execution time rather than startup time. Bordered focus styling via `Ui.ReminderPills`.
9. **Profile Selector Container (`quickAddProfileContainer`)**:
   - Horizontal scrollable profile selector (`Ui.ProfileSelector`) with profile glyphs, active pop, and auto-scroll (`ensureVisible`).
   - <kbd>h</kbd> / <kbd>l</kbd> / arrows cycle selected profile.
10. **Auto-Detected Codebase Context Chip (`locationPill`)** (Conditional: `detectedContext && attachLocation`):
    - Positioned above actions and divider.
    - Displays repository icon (`󰊤`) or directory icon (`󰉋`) + repository identifier / subpath + clickable dismiss `󰅖` icon + `(auto-detected)` caption.
    - In normal mode, navigated via <kbd>j</kbd>/<kbd>Down</kbd> after profiles (or <kbd>k</kbd>/<kbd>Up</kbd> backward from actions). Pressing <kbd>x</kbd>, <kbd>Del</kbd>, <kbd>Backspace</kbd>, or <kbd>Enter</kbd> removes location and advances to actions.
11. **Separator**: Bottom dividing line (`PanelSeparator`).
12. **Footer Actions Item**:
    - Left: Hint shortcuts (`󰌑 Enter • Tab/Vim Nav • Esc Dismiss • Ctrl+⌫ Discard`) anchored to action buttons with automatic right elision. When title is missing or error state is active, hints update to `"⚠ Title required before sending • Esc Cancel"`.
    - Right: Action buttons [Cancel] and [Add]:
      - Both buttons use `bordered: true`, 2px `Color.accent` focus border on navigation, and dynamically bind `hasCursor` and `selected` strictly to `(root.focusSection === "actions") && (root.actionIndex === ...)`.
      - When Cancel is navigated to (`actionIndex === 0`), Cancel receives 2px accent focus border, selected fill, and an animated 1.05 scale pop, while Add remains at neutral unselected rest state.
      - When Add is navigated to (`actionIndex === 1`), Add receives 2px accent focus border, selected fill, and an animated 1.05 scale pop.
      - At neutral rest state (e.g. while typing title or notes), neither button is selected, preventing misleading highlights.
      - **Add Button Disabled State**: When the task title is missing (`canSubmit === false`), the [Add] button is visibly disabled (`enabled: false`, `opacity: 0.4`), preventing accidental submission. Clicking or pressing <kbd>Enter</kbd> on a disabled Add button blocks creation, sets `showTitleError: true`, and refocuses `taskInput`.

#### Navigation State Flow (`focusSection`)
```
[title] ──Tab/Down──► [options] ──Tab/Down──► [(notes)] ──Tab/Down──► [(reminders)] ──Tab/Down──► [profiles] ──Tab/Down──► [(location)] ──Tab/Down──► [actions]
   ▲                                                                                                                                                    │
   └──────────────────────────────────────────────────Tab/Down (Loops around)───────────────────────────────────────────────────────────────────────────┘
```

---

### B. Main Panel (`PanelContent.qml` & `Panel.qml`)

Attached dropdown panel (`WlrLayer.Top`) launched from bar widget click, desktop shortcut (`SUPER + ALT + T` / dynamic detection), or `omarchy-shell tablerase.ardoise toggle`.

#### Visual Hierarchy (Top to Bottom)
1. **Header Item**:
   - Left: Ardoise Task-Slate Mark (`ui/ArdoiseIcon.qml` at `Style.font.subtitle`, ladder rung) + Title ("Ardoise") + Pending Task Count badge.
     - Brand mark and title form an interactive group: hovering smoothly transitions both to `Color.accent` with a pointer cursor and a `PanelToolTip` linking to the GitHub repository (`https://github.com/Tablerase/omarchy-ardoise`). Clicking it opens the GitHub repository in the user's default browser. The hover accent is applied via the component's `colorOverride`, which suppresses the ladder role for that frame only.
   - Right: Shortcuts Help Toggle button (`?`) + Dual Desktop Shortcuts copy pill (`󰌌`, tracking Panel Toggle and Quick Add).
2. **Top Filter Pills Row (`visibleProfiles`)**:
   - "All" pill + active/pending profile pills sorted by pending count and recency.
   - Auto-scrollable flickable with clean single-hue alpha edge fade gradients (`Qt.rgba(r, g, b, 0)`).
   - "+" button to quickly create a new profile inline.
3. **Quick Input Row**:
   - `newTodoField`: Task title entry with high-contrast 2px `Color.accent` focus ring and soft accent tint wrapped in `BorderSurface`.
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
     - **In-Place List Synchronization (`syncFilteredTodos`)**: When saving notes, reminders, or profiles on an expanded task, `PanelContent` detects if the list structure (item count, IDs, and completion states) is unchanged. If identical, metadata is synced in-place on existing model objects and delegates without reassigning `filteredTodos` or rebuilding `Repeater` delegates. This preserves the delegate's active lifecycle, prevents jarring drawer collapse/re-expansion visual glitches, and ensures keyboard focus cleanly returns to `PanelKeyCatcher` without losing navigation motions.
     - `TaskNotesArea` multi-line notes editor (directly placed within the column without misaligned outer wrappers, using `isNavFocused` to draw the control's native focus border when active in sub-section navigation).
     - **Compact Reminder Presets Row (`reminderContainer`)**: Single-line horizontal scrollable row (`Style.space(22)`) with auto-scroll (`ensureVisible`) matching profile selector ergonomics, keeping the active reminder preset pill smoothly centered in view on <kbd>h</kbd> / <kbd>l</kbd> keypress and eliminating horizontal layout overflow past the panel card borders.
     - **Compact Profile Reassignment Row (`profReassignContainer`)**: Single-line horizontal scrollable row (`Style.space(22)`) with auto-scroll (`ensureVisible`) keeping the currently navigated profile pill smoothly centered in view on <kbd>h</kbd> / <kbd>l</kbd> keypress.
     - **Location & Codebase Context Row (`locRow`)**:
       - Displays `󰉋 Target:` with repository identifier (`󰊤 repo/subpath`) or directory path (`󰉋 localPath`), along with subsystem `#tag` chips.
       - Includes a **[Codebase]** action button that launches `omarchy-launch-editor` directly in the target repository directory.
   - **Expanded Sub-Section Keyboard State Machine (`expandedSubSection`)**:
     - When a task is expanded, focus is hierarchical:
       1. `"header"` (default): Item row header is focused. <kbd>Enter</kbd> collapses the drawer; <kbd>Space</kbd> toggles `done`.
       2. `"notes"`: Notes editor area is focused. Pressing <kbd>i</kbd>, <kbd>Enter</kbd>, or typing any printable character enters insert mode and appends into the notes field; <kbd>Escape</kbd> or <kbd>Enter</kbd> commits text, cleanly releases `activeFocus`, unblocks the panel's keyboard dispatcher (`PanelKeyCatcher.blocked = false`), stops hover fold timers, sets `expandedViaKeyboard = true`, and returns to normal motion mode on the `"notes"` sub-section without losing draft text. Clicking directly into the notes field focuses the editor without toggling task status. Subsequent navigation motions (<kbd>j</kbd>/<kbd>k</kbd>/<kbd>Tab</kbd>) immediately resume normal drawer navigation.
       3. `"reminders"`: Reminder presets row is focused. <kbd>h</kbd> / <kbd>l</kbd> cycles presets (with smooth auto-scroll into view via `ensureVisible`); <kbd>Space</kbd> / <kbd>Enter</kbd> applies the preset.
       4. `"profiles"`: Profile reassignment row is focused. <kbd>h</kbd> / <kbd>l</kbd> cycles profiles (with smooth auto-scroll into view via `ensureVisible`); <kbd>Space</kbd> / <kbd>Enter</kbd> reassigns task profile.
       5. `"codebase"` (conditional on location): Codebase launch button is focused. <kbd>Enter</kbd> / <kbd>Space</kbd> opens editor.
     - Navigating with <kbd>Tab</kbd> / <kbd>j</kbd> / <kbd>↓</kbd> steps sequentially through sub-sections, then continues to the next task in the list.
     - **Inline Title Editor (`titleEditor`)**:
       - Initiated by pressing <kbd>r</kbd> or <kbd>F2</kbd> while focused on a task (or the `"header"` sub-section of an expanded task), double-clicking the title text (`titleClickArea`), or clicking the dedicated edit button (`rowEditBtn` `󰏫`) in `rowActions`.
       - Text field replaces static `titleLabel` in-place, styled with 1.5px accent `BorderSurface`, auto-focused, and text pre-selected.
       - While editing, `activeFocusBlocked` sets `PanelKeyCatcher.blocked = true` to allow freeform text entry without triggering vim motion keys.
       - Committing (<kbd>Enter</kbd> or blur) trims input and saves via `updateTodo`. If hashtags are embedded (e.g. `#work Title` or `#repo/tag Title`), `parseTaskInput` updates the profile, repository, and tags simultaneously. Empty titles are rejected, preserving the existing title.
       - Two-Stage Escape: pressing <kbd>Escape</kbd> while editing cancels editing, restores the original title, clears `editingTaskId`, unblocks `PanelKeyCatcher`, and returns focus to the task row in normal motion mode without closing the drawer or dismissing the panel.
     - Two-stage escape: <kbd>Escape</kbd> in any expanded sub-section returns focus to `"header"`; <kbd>Escape</kbd> on `"header"` collapses the drawer; <kbd>Escape</kbd> on a collapsed task dismisses the panel.
5. **Footer Bar**:
   - Urgency visual progress bar (overdue / due today / later).
   - Action buttons with `ShortcutToolTip` badges: [Clear] (<kbd>c</kbd>, archive and clear completed tasks in current profile) • [Archive] (<kbd>d</kbd>, open todos-archive.json in editor) • [Edit] (<kbd>e</kbd>, open todos.json in editor) • [Quick Add] (<kbd>A</kbd> / detected shortcut).
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
- **Icon, Color & Badge (one signal)**: The whole readout — glyph, color, and count — is a single `TodoStore.getArdoiseIconState()` resolution. The mark renders at `Style.bar.iconFont` and the badge count takes the *same* rung subset and the *same* color role as the glyph, so the number always answers "how many tasks are in the state this icon depicts". The badge is hidden when the rung count is 0 and on vertical bars. See §5 *Task-Slate Icon Ladder* for the rung table and the invariants.
  - Total pending is deliberately **not** what the badge shows; it remains available in the tooltip and via the `count` IPC command.
- **Interactions**:
  - Left click: Toggles main panel (`tablerase.ardoise toggle`).
  - Right click: Opens Quick Add modal (`tablerase.ardoise quickadd`).
  - Scroll: Cycles active profile filter.
- **Shell IPC Contract (`IpcHandler: tablerase.ardoise`)**:
  - `omarchy-shell tablerase.ardoise list`: Returns full JSON array of active tasks.
  - `omarchy-shell tablerase.ardoise count`: Returns **total** pending task count string. Deliberately *not* rung-scoped: it is a data/scripting contract, whereas the bar badge is a display signal. Do not "fix" this to match the badge — `list` already exposes the full breakdown if a script needs urgency detail.
  - `omarchy-shell tablerase.ardoise add "<title> [#profile]"`: Adds task with optional `#profile`.
  - `omarchy-shell tablerase.ardoise toggleTodo "<id>"`: Toggles task completion (`done`).
  - `omarchy-shell tablerase.ardoise update "<id>" '<fieldsJson>'`: Updates task properties (e.g. reminder, notes, profile).
  - `omarchy-shell tablerase.ardoise remove "<id>"`: Deletes task by ID.
  - `omarchy-shell tablerase.ardoise clear`: Archives and clears completed tasks.
  - `omarchy-shell tablerase.ardoise profiles`: Returns array of available profiles.
  - `omarchy-shell tablerase.ardoise setProfile "<profile>"`: Sets active profile filter.
  - `omarchy-shell tablerase.ardoise open` / `close` / `toggle`: Controls main panel visibility. In multi-monitor environments, `open` and `toggle` dynamically discover the `BarWidget` on the compositor-focused output via `root.bar.moduleWidgets()` and `Hyprland.focusedMonitor` to summon the panel on the active monitor, while `close` and `toggle` (when already open) target the currently open instance.
  - `omarchy-shell tablerase.ardoise archived`: Returns archived tasks JSON.
  - `omarchy-shell tablerase.ardoise archiveCount`: Returns count of archived tasks.
  - `omarchy-shell tablerase.ardoise gitHistory`: Returns structured JSON array of Git snapshots from `data/`.
  - `omarchy-shell tablerase.ardoise gitRollback "<hash>"`: Reverts `todos.json` and `todos-archive.json` to the specified commit snapshot.
  - `omarchy-shell tablerase.ardoise gitRecover "<hash>"`: Selectively recovers missing tasks from snapshot into active store.
  - `omarchy-shell tablerase.ardoise gitSync`: Fetches remote, performs conflict-free 3-way store merge if diverged, and pushes to remote.
  - `omarchy-shell tablerase.ardoise gitSetRemote "<url>"`: Configures or removes Git remote URL.
  - `omarchy-shell tablerase.ardoise gitGetRemote`: Returns configured Git remote URL.

---

## 4. Keybinding & Interaction Matrix

| Context | Key | Action |
| :--- | :--- | :--- |
| **Global Desktop** | `SUPER + ALT + T` (or custom hyprland bind) | Toggle Main Panel (`omarchy-shell tablerase.ardoise toggle`) |
| **Global Desktop** | `SUPER + SHIFT + T` (or custom hyprland bind) | Summon Quick Add Modal (`omarchy-shell shell toggle tablerase.ardoise '{}'`) |
| **Panel** | `j` / `↓` | Move cursor down (tasks, drawer sub-sections, footer, input) |
| **Panel** | `k` / `↑` | Move cursor up (drawer sub-sections, tasks; at task 0, transitions to `input`) |
| **Panel** | `Tab` / `Shift+Tab` | Advance / reverse major sections and expanded task sub-sections |
| **Panel** | `Space` | Toggle task completion (`done`), or apply selected reminder/profile |
| **Panel** | `Enter` / `Return` | Expand / collapse task details (drawer), or enter editor on notes |
| **Panel (Drawer)** | `h` / `l` / `←` / `→` | Cycle reminder presets or profile reassignments |
| **Panel (Drawer)** | `i` / `Enter` | Enter notes text editor (insert mode) |
| **Panel (Drawer)** | `Escape` | Return from sub-section to task header, or collapse drawer |
| **Panel** | `r` / `F2` | Edit title of selected task in-place |
| **Panel (Title Editor)** | `Enter` | Commit edited title (trims input; updates profile/tags if hashtag included) |
| **Panel (Title Editor)** | `Escape` | Cancel title edit, restore original title, and return to task row |
| **Panel** | `e` | Open `todos.json` in editor (jumps to selected task line if on a task) |
| **Panel** | `u` | Toggle Git Snapshots & Undo modal (`ui/GitModal.qml`) |
| **Panel** | `c` | Archive and clear completed tasks in current profile |
| **Panel** | `d` | Open `todos-archive.json` in editor (Archive button) |
| **Panel** | `i`, `a`, `<slash>` | Jump focus into new task input field |
| **Panel** | `A` | Open Quick Add overlay modal |
| **Panel** | `x` / `Delete` | Delete highlighted task |
| **Panel** | `g` | Jump to first task |
| **Panel** | `G` | Jump to last task |
| **Panel** | `?` / `Backspace` (empty search) | Toggle or dismiss searchable keyboard shortcuts modal |
| **Git Modal** | `1` / `2` | Switch between Snapshots (1) and Sync Settings (2) tabs |
| **Git Modal (Snapshots)** | `j` / `k` / `↓` / `↑` | Navigate snapshot commit list |
| **Git Modal (Snapshots)** | `r` | Rollback tasks to selected snapshot |
| **Git Modal (Snapshots)** | `c` | Recover missing/deleted tasks from selected snapshot |
| **Git Modal** | `Escape` | Dismiss Git modal and restore focus to panel |
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

### Task-Slate Icon Ladder (the Ardoise brand mark)

The mark is a **stateful** Nerd Font MD glyph (Private Use Area) resolved by `TodoStore.getArdoiseIconState()` from `getTaskUrgencyBreakdown()`. Rungs are driven by **urgency, not raw count** — the same approach omarchy's own battery / wifi / volume widgets take, and the same reason: "5–9 tasks" is not actionable, "nothing is overdue" is.

| Rung | Condition | Glyph | Name | Codepoint | Color role | Badge count |
|---|---|---|---|---|---|---|
| `clear` | `total === 0` | `󰗠` | `check_circle` | `\U000f05e0` | foreground | hidden (0) |
| `pending` | nothing time-critical | `󰝖` | `format_list_checks` | `\U000f0756` | foreground | `total` |
| `due` | `dueToday > 0`, `overdue === 0` | `󱖫` | `list_status` | `\U000f15ab` | accent | `dueToday` |
| `overdue` | `overdue > 0` | `󰀨` | `alert_circle` | `\U000f0028` | **urgent** | `overdue` |

**Precedence:** `overdue` > `due` > `pending` > `clear`. A store with nothing pending is always `clear`, regardless of reminder history, because completed tasks are excluded from the breakdown.

**Design constraints (guarded by tests in `tests/TodoStore.test.mts`):**
- **Glyph, color, and badge number are one resolution.** All three come from a single `getArdoiseIconState()` call, so the mark and its count cannot describe different states. Never derive the badge from a separate count call — that is exactly the drift the rung-scoped `count` field exists to prevent.
- The badge count is always the **rung's own subset**, never the total pending. A reader glancing at the bar sees "3 overdue", not "12 tasks with 3 overdue"; total pending is one hover away in the tooltip. Because the `due` rung is only reachable when `overdue === 0`, and `overdue` outranks `due`, the count is never ambiguous at any rung.
- `count <= total` always, and `count > 0` on every non-`clear` rung.
- Every rung carries a **distinct glyph** — a stateful mark must not silently repeat an icon, or the widget appears to flicker between two meanings.
- The two extremes deliberately **share a filled-circle silhouette** (`check_circle` ↔ `alert_circle`) so the mark keeps a stable identity while only the interior glyph and color change. The middle rungs are lists.
- `check_all` (`\U000f012d`) is **rejected** as the `clear` rung: it is a bare diagonal tick with no enclosure and rasterizes to a near-invisible speck at 13 px.
- Ladder rungs must **not** be built from near-identical gray list glyphs (e.g. `format_list_bulleted` → `playlist_check` → `view_list`). At 13 px those are indistinguishable; escalation has to change shape.

**Consistency contract:** the same ladder renders at the bar (`Style.bar.iconFont` = 13 px), the panel brand header, and the QuickAdd header (`Style.font.subtitle`). Do not pin a static brand glyph at any of the three surfaces.

**Scope boundary:** the ladder governs the *brand mark and the bar badge only*. The panel's "All" filter-pill count and its `"N pending"` header label stay total/filter-scoped, because they describe the active filter rather than the urgency state. The panel brand mark may still turn urgent while its header reads "12 pending"; that is acceptable because the panel body renders per-task urgency stripes and due markers.

### Other Icon Glyphs (Nerd Font MD)
- **Clock / Reminder**: `󰥔` (`\U000f0954`) — *Never use avatar `󰀉` for reminders!*
- **Pen / Notes**: `󰏫` (`\U000f03eb`)
- **Personal Profile**: `󰀉` (`\U000f0009`) — *Reserved exclusively for user profile identity.*
- **Tag / Profile Category**: `󰓹` (`\U000f04f9`)
- **Draft Restored**: `󰁯` (`\U000f006f`)
- **Keyboard / Enter**: `󰌑` (`\U000f0311`)
- **Add / Plus**: `󰐕` (`\U000f0415`)
- **Remove / Trash**: `󰆴` (`\U000f01b4`)
- **Check Complete**: `󰄬` (`\U000f012c`) — *Task-row completion indicator only. Not the brand mark; the brand mark is the ladder above.*
- **Check Empty**: `󰄱` (`\U000f0131`)
- **Git Branch / Snapshots**: `󰊢` (`\U000f02a2`)

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
