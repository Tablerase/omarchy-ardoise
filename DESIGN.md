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
3. **Action Separation (Expand vs. Complete)**:
   - **Expand / Collapse**: In the task list, pressing <kbd>Enter</kbd> or clicking anywhere on the item row (or title text, or the chevron button `rowExpandBtn`) strictly **expands or collapses** task details (notes, reminders, profile reassignment).
   - **Toggle Completion (`done`)**: Pressing <kbd>Space</kbd> or clicking the checkbox icon (`Ui.TaskCheck`) strictly **toggles completion**. Clicking the item row will never toggle completion.
   - In input fields, <kbd>Enter</kbd> commits / submits. In multi-line notes, <kbd>Shift+Enter</kbd> inserts a newline while <kbd>Enter</kbd> commits.
4. **Non-Destructive Draft Retention**:
   - Unsaved Quick Add modal drafts (title, description, profile, reminder) are automatically retained in state and restored if the modal is dismissed accidentally. Drafts can be cleared via <kbd>Ctrl</kbd>+<kbd>Backspace</kbd> or the "Clear" action.
5. **No Layout Overflow**:
   - Profile names, tags, and titles must gracefully wrap (`Flow`) or elide (`Text.ElideRight`) to prevent pushing buttons or cards outside visible geometry.
   - Task titles are **single-line and elided while collapsed** (full text on hover). The **expanded drawer is the single exception**: there the title wraps (`Text.Wrap` + `Text.ElideNone`) so the whole title is readable, because that is the only surface with vertical room to show it.
6. **Strictly Explicit Drawer Expansion (No Hover Auto-Expand)**:
   - **Keyboard Navigation (<kbd>Enter</kbd> / <kbd>e</kbd>)**: Explicit toggle. Opening an item via keyboard marks it `expandedViaKeyboard = true`. Navigating with <kbd>j</kbd>/<kbd>k</kbd> does not auto-expand items.
   - **Mouse Click Expansion**: Clicking anywhere on the item row (`rowMouseArea`), the title text (`titleClickArea`), or the chevron expand button (`rowExpandBtn`) explicitly expands/collapses task details without toggling completion. Clicking the time/due chip (`remBadge`) explicitly expands directly to the reminder presets row.
   - **Task Completion Boundary**: To mark a task done or undone with the mouse, the user must explicitly click the check icon (`Ui.TaskCheck`).
   - **No Hover Auto-Expansion**: Hovering over a task row or chips never auto-expands the drawer. This guarantees that inspecting tooltips (due dates, git repository paths) and resting the mouse cursor never cause accidental accordion bouncing or layout shifting.
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
- **`ui/Chip.qml`**: Reusable compact pill/badge component supporting first-class design system variants (`variant: "default"` | `"time"` | `"location"` | `"tag"`):
  - **Time / Due Variant (`"time"`)**: Squircle ticket badge (`radius: Style.space(4)` = 4px) with bold proportional typography, dynamic urgency ramp (amber warning with timer-alert `󱫌` when overdue, vibrant accent with clock `󰥔` when due today, subtle neutral-accent when scheduled in the future, muted when done). Clicking the chip directly expands the task drawer and focuses the reminder presets row.
  - **Location / Codebase Variant (`"location"`)**: Smooth pill capsule (`radius: implicitHeight / 2` = 9px) with `monospace` typography, accent git/folder icon (`󰊤`/`󰉋`), and developer code surface (`Color.menu.selectedBackground`). Clicking the chip directly launches the codebase in the configured editor via `openCodebase()`.
  - **Tag Variant (`"tag"`)**: Compact category pill capsule for user profiles and tags (`#tag`).
  - Common attributes: strictly bounded with `elide: Text.ElideRight`, capped max-width, tooltips, optional removal button (`󰅖`), and hover cursor cues.
- **`ui/HelpModal.qml`**: Fullscreen-scoped searchable keyboard shortcut directory with fuzzy filter and two-stage Backspace dismiss. Mounted inside `PanelContent` (inside `PanelKeyCatcher`) so it sits in the correct focus scope and receives keyboard events normally. Height is guaranteed by `Panel.qml` inflating `contentHeight` to at least `Style.space(380)` when the modal is open, regardless of task-list count. Features a solid opaque card background (`Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1.0)`) and hides underlying task content (`opacity: 0`) to prevent visual bleed-through. The search input opens in normal/motion mode (`isNavFocused`, 1px accent border) allowing instant <kbd>j</kbd>/<kbd>k</kbd> navigation into the shortcuts list, switches to insert mode with 2px accent border and tint on <kbd>i</kbd>/<kbd>a</kbd>/<kbd>/</kbd>/<kbd>Return</kbd>, and supports full vim motions (<kbd>g</kbd>/<kbd>G</kbd>, <kbd>Enter</kbd> to explore results, two-stage <kbd>Escape</kbd>). When the close button is reached, vim motions continue uninterrupted (<kbd>j</kbd> navigates back down to the search field in motion mode, <kbd>k</kbd> wraps to list, <kbd>Enter</kbd>/<kbd>Space</kbd>/<kbd>q</kbd>/<kbd>?</kbd> closes). Contains an unconditional full-coverage `MouseArea` (`hoverEnabled: true`, `acceptedButtons: Qt.AllButtons`) that blocks all hover and click events.
- **`ui/GitModal.qml`**: Modal overlay for reviewing local Git commit snapshots, executing point-in-time rollbacks (<kbd>r</kbd>), recovering deleted tasks (<kbd>c</kbd>), and configuring remote synchronization (GitHub / GitLab) with conflict-free 3-way JSON store merging and device tagging (`[hostname]`). Accessible via header action button (`󰊢`) or Vim <kbd>u</kbd>. Mounted inside `PanelContent` (same focus scope as `HelpModal`). Panel inflates to at least `Style.space(380)` when open. Features a solid opaque background and lazy loaded snapshots powered by a virtualized `ListView` with on-demand git pagination (`loadMoreGitHistory`), auto-scrolling `ensureSnapshotVisible()`, and full vim motion navigation across both tabs (<kbd>j</kbd>/<kbd>k</kbd>, <kbd>g</kbd>/<kbd>G</kbd> top/bottom, <kbd>h</kbd>/<kbd>l</kbd>/<kbd>Tab</kbd> tab and button switching, <kbd>u</kbd>/<kbd>q</kbd>/<kbd>Esc</kbd> dismiss). In Tab 1 (Sync & Remote), the remote URL input and action buttons (`autoCreateRemoteBtn` for 1-click GitHub repo setup, `saveRemoteBtn`, `syncNowBtn`) are fully navigable via vim motions (<kbd>Tab</kbd>/<kbd>Shift+Tab</kbd> cycling 0-3, <kbd>j</kbd>/<kbd>k</kbd>, <kbd>h</kbd>/<kbd>l</kbd>, <kbd>Enter</kbd>, <kbd>s</kbd> for quick sync) with cursor highlighting and two-stage escape (in insert mode, <kbd>Escape</kbd> blurs to normal motion mode on the remote field without closing the modal; in normal motion mode, <kbd>Escape</kbd> dismisses the modal). **Automated GitHub Remote Setup**: The `󰊤 Create GitHub Repo` button (and `omarchy-shell tablerase.ardoise autoSetupGitRemote [repoName]`) executes `tools/setup-git-remote.sh` via GitHub CLI (`gh`). Repositories are strictly private by default (`--private`) to protect user task data and filesystem paths, defaulting to name `ardoise-tasks` (or user-specified text in `remoteField`). Status area uses `Color.menu.selectedBackground` with intelligent sync diagnostics (`GitSync.diagnoseGitSyncError`) providing actionable error messages (SSH passphrase lock, network offline, permission denied) and automatically initializing empty remote repositories on first sync. Contains an unconditional full-coverage `MouseArea` to block mouse bleed-through. **Snapshot Search Filter (Tab 0)**: <kbd>/</kbd> or <kbd>Ctrl+F</kbd> or clicking the `󰍉` header button activates an inline search bar. Snapshot list binds to `filteredSnapshots` (computed via `GitSync.filterSnapshots(snapshots, searchQuery)`) providing real-time cross-field matching against commit messages (`cleanMessage` or `message`), device names (supports plain, `#device`, and `[device]` token syntax), commit hashes (7-char `shortHash` and full `hash` substring), and author names. Multi-token AND matching is supported (e.g. `laptop update`). **Two-Stage Escape**: First <kbd>Escape</kbd> clears query text (search bar stays open); second <kbd>Escape</kbd> dismisses search and restores the full unfiltered list. Header subtitle updates to `N / M snapshots` when filtering is active. Empty search results display `󰍉 No snapshots matching "<query>"` with a `Press Esc to clear` hint. Lazy-load pagination is disabled while search is active (filtered results are a subset of already-loaded data). <kbd>l</kbd> tab-switch is suppressed while search is active to prevent accidental navigation away.
- **`ui/GitContextMenu.qml`**: Contextual action menu popover for snapshots in `GitModal`. Supports point-in-time rollback (<kbd>r</kbd>), recovering deleted tasks (<kbd>c</kbd>), and copying the commit hash (<kbd>y</kbd>) to the clipboard via `wl-copy`. Accessible via mouse right-click on snapshot row, row hover options button (`󰇙`), or keyboard (<kbd>m</kbd> / <kbd>Space</kbd> / <kbd>Return</kbd>). Features a full-coverage click-away scrim, explicit height sizing derived from content insets (`card.contentTopInset + card.contentBottomInset + menuContent.implicitHeight`), bounds checking keeping the popup within the parent modal bounds, and full vim motion navigation (<kbd>j</kbd>/<kbd>k</kbd> vertical item cycling, <kbd>Enter</kbd>/<kbd>Space</kbd> activation, <kbd>Escape</kbd> dismissal without closing `GitModal`).
- **`ui/ContextActionMenu.qml`**: Contextual action menu for the focused task, opened with <kbd>K</kbd> (`PanelLogic.DEFAULT_BINDINGS.task_menu`). Items are produced by the pure `PanelLogic.getTaskMenuItems(task)` and adapt to the task (copy-notes is dropped without notes, open-codebase without a local path): <kbd>y</kbd> copy for LLM, <kbd>t</kbd> copy title, <kbd>n</kbd> copy notes, <kbd>o</kbd> open codebase, <kbd>e</kbd> edit title, <kbd>x</kbd> delete. **Non-modal by design**: it never takes focus, because `PanelKeyCatcher` routes <kbd>j</kbd>/<kbd>k</kbd>, <kbd>Enter</kbd>/<kbd>Space</kbd>, <kbd>x</kbd>, and <kbd>Esc</kbd> through the panel state machine first; selection and key handling therefore live in `PanelLogic` (`handleMove`, `handleActivate`, `handleReturn`, `handleDelete`, `handleTextKey`, `handleEscape`) while this component only renders. The card is anchored beside the focused row (`item.mapToItem(root, item.width, item.height/2)`) and clamped to the panel with an 8px margin, flipping to the row's left when there is no room on the right, so it can never overflow the monitor. A full-coverage click-away scrim dismisses it.
- **`ui/ArchiveModal.qml`**: Archive browser (opened with <kbd>d</kbd> or the footer Archive button) that restores completed tasks back into the active store. Built for large archives (>2,000 items): the archive is parsed **once on open** (`TodoStore.getArchivedTasks`, within the store's existing 100ms/5,000-item budget) and rendered through a **virtualized `ListView`** so only visible delegates instantiate; filtering (`TodoStore.filterArchivedTasks`, multi-token AND over title/notes/profile/repo/tags/id) runs over the in-memory array on query change, never per frame. Restoring calls `barWidget.unarchiveTask(id)`, which preserves the original id/createdAt/notes/profile/repo/tags/location, clears completion, removes the entry from the archive (never duplicated), and commits both files together; the modal then splices the item out of its in-memory list instead of re-parsing. Keys: <kbd>j</kbd>/<kbd>k</kbd>/<kbd>g</kbd>/<kbd>G</kbd>, <kbd>Enter</kbd>/<kbd>r</kbd> restore, <kbd>K</kbd> or right-click opens the shared `ui/ContextActionMenu.qml`, <kbd>x</kbd> (hold) permanently deletes, <kbd>y</kbd> copy for LLM, <kbd>e</kbd> open the raw JSON, <kbd>/</kbd> filter (also the header magnifier button for mouse users), two-stage <kbd>Escape</kbd>. Mounted inside `PanelContent` and counted in `activeFocusBlocked`; `Panel.qml` inflates to at least `Style.space(380)` while it is open.
  - **Data-loss safeguards (airtight restore/purge).** `BarWidget.unarchiveTask` / `purgeArchivedTask` read **both files fresh from disk** via a `cat` `Process` (never the possibly-stale `lastArchiveText`), then write in a loss-proof order: the **active store is written and confirmed** (`FileView.saved`/`saveFailed`, then a read-back asserting the id is present) **before** the archive entry is removed. The archive write is verified by reading it back and retried up to three times. Any failure leaves the archive untouched, so a task can never vanish; the worst case is a duplicate. On load, `TodoStore.reconcileArchive(store, archive)` self-heals such duplicates (an archived id that is also active is dropped from the archive), and the archive is committed immediately after a successful restore/purge. Permanent delete is hold-to-confirm via the shared `ui/HoldActionButton.qml` (menu item press-and-hold, or hold <kbd>x</kbd> on the selected row), and is irreversible except through git history (`gitRecover` / rollback in `GitModal`).
- **`ui/TaskCheck.qml`**: Circular checkbox button serving as the primary per-row status and severity indicator. Late tasks tint and border in the theme's **warning** amber (supplied by the host via `warningColor`; it has no `urgentColor` any more, so red cannot creep back into task severity), due-today stays accent, completed keeps the accent checkmark, and normal pending is a muted border.
- **`ui/ArdoiseIcon.qml`**: The shared task-slate brand mark, rendered as a Nerd Font MD glyph (Private Use Area) rather than a vector. Optically centered with `TextMetrics.tightBoundingRect` horizontal correction — the same technique omarchy's own `Ui/OpticalGlyph.qml` uses — so it sits on the same optical centre as the icons beside it in the bar. The glyph is a **stateful ladder rung** resolved by `TodoStore.getArdoiseIconState()`, and the component is used at all three brand surfaces (status bar widget, panel brand header, QuickAdd header) so the plugin reports load identically everywhere. See §5 *Task-Slate Icon Ladder* for the rung table.
  - Properties: `store` (drives the ladder), `bar` (optional shell root, supplies `foreground` / `urgent` / `fontFamily`), `iconSize` (defaults to `Style.bar.iconFont` = 13 px), `forcedKey` (pin a rung, used by `tools/preview.qml`), `colorOverride` (flat color override, used for the panel brand-row hover), `foregroundOverride` / `accentOverride` / `warningOverride` (replace only the base color of the `foreground` / `accent` / `warning` roles so a host surface can supply its own text color while escalation still reads). The `*Override` properties are typed `var`, not `color`, on purpose: a typed `color` coerces the `undefined` sentinel to a transparent QColor on every assignment and logs a warning.
  - Also owns the **theme warning lookup** (`warningColor`) described in §5 *Warning color sourcing*. It is the single reader of the theme's `colors.toml`; `PanelContent` reads it back off this component and passes it to `TaskCheck`, so no second file watch is created.
  - **Replaces** the previous `ui/InboxIcon.qml` (Canvas 2D inbox tray). It was drawn at 16 px as a 1.75/24 stroke while every other Omarchy bar widget paints a 13 px solid font glyph, so it read lighter, wider, and less optically centred than its neighbours.
- **`ui/ReminderPills.qml`**: Reusable horizontal scrollable reminder preset pill row (`+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, `Clear`) with navigation cursor scaling, dynamic timestamp recalculation at selection time, smooth auto-scroll (`ensureVisible`) keeping the active pill centered in view, single-hue alpha fade gradient overlays (`fadeColor`, `z: 1`, 24 px left / 32 px right) cleanly dissolving overflowing content, and a thin 3 px horizontal `ScrollBar` (`policy: AsNeeded`) for mouse users. `implicitHeight: Style.space(26)` (22 px pills + 4 px scrollbar zone).
- **`ui/ProfileSelector.qml`**: Horizontal scrollable profile pill selector with profile glyphs, elided labels, active pop, smooth auto-scroll (`ensureVisible`), single-hue alpha fade gradient overlays (`fadeColor`, `z: 1`, 24 px left / 32 px right), and a thin 3 px horizontal `ScrollBar` (`policy: AsNeeded`) for mouse users. `implicitHeight: Style.space(26)`.
  - In expanded task drawer, `fadeColor` must be the **opaque composite** of `Color.menu.selectedBackground` (8% alpha tint) over `Color.popups.background`, computed as `root.expandedCardColor` in `PanelContent`. Passing the semi-transparent `selectedBackground` directly results in invisible gradients.
- **`ui/KeyBadge.qml`**: Reusable keyboard shortcut badge component rendering key representations with pixel-perfect parity to the help guide (`Util.alpha(badgeColor, 0.15)` background fill, `badgeColor` border, monospace bold font, `radius: Style.space(4)`).
- **Hold-to-Confirm Deletion & Clear**: Eliminates confirmation modals for destructive and batch actions (task deletion and clear completed) without sizing anomalies or optical misalignment. Features a 800ms hold timer with hardware-timed progress charging (0.0 -> 1.0) and smooth 180ms cancellation drain. For task deletion, holding <kbd>x</kbd> or pressing the remove button charges a 2px glowing red laser bar (`deleteLaserBar`, `Color.urgent`) along the bottom edge of the task card, accompanies it with a subtle warning card tint (`deleteTintOverlay`, `opacity: deleteProgress * 0.16`), and triggers card micro-shake at >60% charge, while keeping the delete button icon (`󰅙`) cleanly centered inside a standard 22x22 `PanelActionButton`. For clear completed, holding <kbd>c</kbd> or pressing Clear charges a 2px glowing accent laser bar (`clearLaserBar`, `Color.accent`) along the bottom edge of `clearBtn` accompanied by a subtle accent surface tint (`clearTintOverlay`), keeping `clearBtn` perfectly matched to adjacent footer buttons in size and padding.

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
   - **Clean & Empty by Default**: Field opens completely empty with placeholder `"What needs to be done? (#tag or #profile optional)"`. Tasks can be typed directly (e.g. `test` or `Fix navbar`) without any mandatory `#` prefix, and will be assigned to `selectedProfile`.
   - **Intelligent 3-Tier Default Profile Resolution (`TodoStore.resolveDefaultProfile`)**:
     - **Tier 1 (Location Recency)**: If a codebase context is detected, scans `store.todos` for the most recent task matching `location.repo` or `location.localPath`, applying its profile. If no prior tasks exist for that location, checks if repo/folder name matches a known profile.
     - **Tier 2 (Global Recency)**: If no location is detected or no tasks match, uses the profile of the most recently created or updated task across the entire store.
     - **Tier 3 (Default Fallback)**: Falls back to `store.activeProfile` or `"personal"`.
     - The resolved default is pre-selected and visibly highlighted in `quickAddProfileSelector` at launch, giving instant clarity on destination before typing.
   - **Hashtag Override**: Typing an explicit `#profile` anywhere in the input dynamically overrides `selectedProfile`. Subsequent hashtags act as subsystem `#tags`.
   - <kbd>Escape</kbd>: dismisses if empty; enters normal (motion) mode on `"title"` if text is present without closing or losing draft. Pressing <kbd>j</kbd>/<kbd>Down</kbd> moves to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> re-enters edit mode.
   - **Title Validation & Error State**: When input contains only hashtags/profile/repo (e.g. `#ardoise/widget`) or when submission is attempted without an actual title, `taskInput` displays a high-contrast `Color.urgent` warning border (`Border.flat(Color.urgent, 2)` when focused, 1px when blurred) and a soft urgent background tint.
4. **Hashtag Autocomplete Suggestions (`autocompleteBox`)** (Conditional: `autocompleteActive && autocompleteMatches.length > 0`):
   - Positioned immediately below `taskInput`, seamlessly expanding the card height without overlay bleed or clipping.
   - **Semantic Role Separation**:
     - **First Hashtag Token**: Queries profiles via `TodoStore.searchProfiles(store, query)` (`autocompleteMode = "profile"`). Selecting an item sets `selectedProfile` and updates the active profile pill in `quickAddProfileSelector`.
     - **Subsequent Hashtag Tokens**: Queries tags across all store tasks via `TodoStore.searchTags(store, query)` (`autocompleteMode = "tag"`). Selecting an item inserts `#<tag> ` into the task title text without modifying `selectedProfile`.
   - **Keyboard Navigation**:
     - <kbd>↓</kbd> / <kbd>↑</kbd>: Cycle suggested matches (`autocompleteIndex`) with auto-scrolling (`Flickable`).
     - <kbd>Tab</kbd> / <kbd>Enter</kbd>: Commit suggestion (`applyAutocomplete`), replacing query with `#<item> `, advancing cursor, and keeping focus in `taskInput`.
     - <kbd>Shift+Tab</kbd>: Cycle matches backward.
     - <kbd>Escape</kbd>: Dismisses autocomplete popup without blurring `taskInput` or dismissing Quick Add.
   - **Styling & Indicators**: Opaque surface (`Color.popups.background || Color.menu.background`), mode badge (`󰭤 Profiles` / `󰓹 Tags`), profile glyph or tag icon (`󰓹`), `#name`, and right-aligned count (`N tasks` pending for profiles, `N used` for tags). Hovering highlights row; mouse click applies suggestion.
5. **Inline Validation Cue (`titleErrorRow`)**:
   - Displayed immediately below `taskInput` (or `autocompleteBox`) whenever the title is missing while hashtags/tags are present, or when submission is attempted with an empty title.
   - Renders an error icon (`󰅚`) and clear actionable message in `Color.urgent`: `"Title required: add task name after hashtag (e.g. #ardoise/widget My task)"` or `"Task title is required"`. Automatically hides as soon as a non-empty title is typed.
6. **Draft Notice Banner** (Conditional: `hasDraft === true`):
   - Glyph `󰁯` + "Draft restored" caption + clickable "Clear" action (<kbd>Ctrl+⌫</kbd>).
7. **Option Toggles Row**:
   - Button 0: **Add Note** (`󰏫`) — toggles `showNote`. When active, displays clean accent tint (`Util.alpha(Color.accent, 0.12)`), 1px accent border, and accent text/icon. During keyboard navigation (`hasCursor`), scales by 1.05 with a crisp 2px accent focus ring and prominent focus fill. When pressed via <kbd>Enter</kbd>/<kbd>Space</kbd> or clicked, auto-focuses `descNotesArea`.
   - Button 1: **Set Reminder** (`󰥔`) — toggles `showReminderOptions`. When active with a chosen reminder, displays accent tint, 1px accent border, and formatted reminder string. During keyboard navigation (`hasCursor`), scales by 1.05 with a crisp 2px accent focus ring.
   - Both buttons use `bordered: true`, scale popping, and explicit accent focus rings, ensuring navigation focus is always noticeably brighter and higher-contrast than resting active states.
8. **Notes Editor Area (`descNotesArea`)** (Conditional: `showNote === true`):
   - Multi-line `TaskNotesArea` (min 56px, max 130px, auto-scroll).
   - **Insert mode** (`activeFocus === true`): 2px solid accent border + accent tint fill — clear editing indicator.
   - **Nav mode** (`isNavFocused === true`, `activeFocus === false`): 1px solid accent border, no tint — field is selected in keyboard nav but not being edited.
   - <kbd>Escape</kbd>: blurs textarea and enters normal (motion) mode on `"notes"`, keeping draft text safe. Pressing <kbd>j</kbd>/<kbd>Down</kbd> continues navigation down to `reminders`/`profiles`; pressing <kbd>k</kbd>/<kbd>Up</kbd> navigates up to `options`; pressing <kbd>i</kbd>/<kbd>a</kbd>/<kbd>Enter</kbd> (or typing any printable character) re-enters edit mode on notes.
9. **Reminder Presets Row** (Conditional: `showReminderOptions === true`):
   - Presets: `+30m`, `+1h`, `Tomorrow 9am`, `Tomorrow 6pm`, plus "Clear". Presets and selected timestamps are dynamically recomputed at open and click/selection time relative to current local execution time rather than startup time. Bordered focus styling via `Ui.ReminderPills`.
10. **Profile Selector Container (`quickAddProfileContainer`)**:
    - Horizontal scrollable profile selector (`Ui.ProfileSelector`) with profile glyphs, active pop, and auto-scroll (`ensureVisible`).
    - <kbd>h</kbd> / <kbd>l</kbd> / arrows cycle selected profile.
11. **Auto-Detected Codebase Context Chip (`locationPill`)** (Conditional: `detectedContext && attachLocation`):
    - Positioned above actions and divider.
    - Displays repository icon (`󰊤`) or directory icon (`󰉋`) + repository identifier / subpath + clickable dismiss `󰅖` icon + `(auto-detected)` caption.
    - In normal mode, navigated via <kbd>j</kbd>/<kbd>Down</kbd> after profiles (or <kbd>k</kbd>/<kbd>Up</kbd> backward from actions). Pressing <kbd>x</kbd>, <kbd>Del</kbd>, <kbd>Backspace</kbd>, or <kbd>Enter</kbd> removes location and advances to actions.
12. **Separator**: Bottom dividing line (`PanelSeparator`).
13. **Footer Actions Item**:
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
   - Right: In-Panel Search button (`󰍉`, shortcut `/ or Ctrl+F`) + Shortcuts Help Toggle button (`?`) + Git Snapshots & Undo button (`󰊢`, `u`) + Dual Desktop Shortcuts copy pill (`󰌌`, tracking Panel Toggle and Quick Add).
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
4. **In-Panel Search Tool (`searchRow`, `/` and `Ctrl+F`)**:
   - Sleek expandable search bar positioned below the new task input row and above the task list.
   - **Activation**:
     - Pressing <kbd>/</kbd> in normal list/motion mode.
     - Pressing <kbd>Ctrl+F</kbd> globally across the panel (from tasks, input, or key catcher).
     - Clicking the search button `󰍉` in header right actions.
   - **Live Query Scope**:
     - Filters `filteredTodos` in real time as the user types without lag.
     - Matches:
       1. Task titles (`task.title`).
       2. Task notes and descriptions (`task.description`).
       3. Repository names (`task.repo` or `task.location.repo`).
       4. Subsystem tags (`task.tags`).
       5. Hashtag queries (`#profile`): searches across all profiles regardless of active profile filter. Pressing <kbd>Enter</kbd> while on a `#profile` query sets `currentFilter` to that profile and dismisses search.
   - **Two-Stage Escape**:
     - Non-empty query: Pressing <kbd>Escape</kbd> clears `searchField.text = ""` and `searchQuery = ""`, preserving the search bar in normal mode.
     - Empty query: Pressing <kbd>Escape</kbd> collapses the search bar and returns focus to the task list in normal motion mode.
   - **Quick Motion Dropdown**:
     - Pressing <kbd>Down</kbd>, <kbd>Enter</kbd>, or <kbd>Tab</kbd> drops focus cleanly onto the first filtered task in the list (`focusSection = "tasks"`, `cursorIndex = 0`).
   - **Empty State**:
     - When no tasks match the active query, displays an informative empty card:
       `󰍉 No tasks matching "<query>"` with a hint `Press Esc to clear search`.
5. **Task List View (`taskListView`)**:
   - Vertically flickable column of tasks (`itemRow`).
   - Auto-scroll viewport alignment (`ensureTaskVisible`): normal cursor motion keeps the focused task within bounds; expanding a task drawer automatically aligns the expanded task to the top of the list viewport (`alignTop: true`) so the entire drawer (notes, reminders, and profile pills) remains fully visible.
     - **Too-tall focused item**: an expanded drawer can be taller than the list viewport. Motion onto such an item (`j`/`k` and the other `ensureTaskVisible(..., false)` call sites) keeps its **top** in view instead of the generic bottom-align, because bottom-aligning a too-tall row pushes its top — and the wrapped title's first line — above the viewport where the Flickable's `clip` cuts it off. The drawer is allowed to overflow the bottom edge; the title always stays readable. Regression-guarded by the local-only "Quickshell Drawer Fit" test in `tests/qml-windowed.test.mts` (expand → move up → move back down).
   - Individual task row:
     - **OmaTasks-Inspired Item Layout**:
       - Sizing is deterministic, content-driven, and dynamically compact:
         `implicitHeight: isExpanded ? (expandedContent.implicitHeight + Style.space(16)) : (Style.space(34) + (hasNotes ? Style.space(18) : 0) + (hasBadges ? Style.space(22) : 0))`
        - **Line 1 (Title Row)**: Circular checkmark button (`checkBtn`) + Full-Width Title + Inline Profile badge (`profInlineLabel`, shown in "all" view when the task has no chips) + Action buttons on the right (Expand chevron `󰅀`/`󰅃`, Edit title `󰏫`, and Hold-to-Delete `󰅙` via standard `PanelActionButton`). Task deletion requires holding for 800ms (<kbd>Hold x</kbd> or pointer press), charging a 2px glowing red laser line (`deleteLaserBar`, `Color.urgent`) along the card's bottom edge, applying a subtle warning card tint (`deleteTintOverlay`), and initiating a horizontal micro-shake at >60% charge, canceling cleanly with smooth 180ms drain if released early.
        - **Expanded Drawer Title Reveal (`titleRowItem`)**:
          - Collapsed rows keep the title on one line (`wrapMode: Text.NoWrap`, `elide: Text.ElideRight`, `verticalAlignment: Text.AlignVCenter`) so the list stays scannable; the full text is available on hover via `PanelToolTip` and via the inline title editor.
          - Expanded rows switch the title to `wrapMode: Text.Wrap` + `elide: Text.ElideNone` + `verticalAlignment: Text.AlignTop`, so a long title is revealed in full across the drawer's width instead of being truncated. The row grows through the existing content-driven height chain (`titleLabel.implicitHeight` → `titleRowItem` → `itemHeaderCol` → `expandedContent` → `itemRow.implicitHeight`).
          - `titleRowItem.titleWraps` (`titleLabel.lineCount > 1`) drives first-line alignment: the checkbox, action buttons, inline profile badge, and title editor all carry `anchors.verticalCenterOffset: titleRowItem.firstLineCenterOffset`, so they stay pinned to the **first** line of the wrapped title instead of floating to the paragraph's vertical center. `firstLineHeight` is derived from measured geometry (`titleLabel.height / titleLabel.lineCount`), never from font metrics.
          - The hover tooltip is suppressed while expanded (`!itemRow.isExpanded && ... && titleLabel.truncated`) because the full title is already on screen.
          - The animated strikethrough (`strikeLine`) is suppressed while the title wraps: a single rule cannot strike a paragraph, so a completed multi-line title relies on the dimmed text, the filled `TaskCheck`, and the row completion tint.

       - **Line 2 (Note Preview Line)**: Rendered when collapsed and task has notes (`hasNotes === true`):
         - Single-line elided text preview (`Text.ElideRight`, italic, `Color.textMuted`), indented cleanly below the title.
         - Hover tooltip displaying the full multiline note text.
       - **Line 3 (Metadata & Chips Row)**: Sub-line rendered when chips exist (`hasBadges === hasChips === true`, i.e., has repo, tags, or reminder):
         - Bounded strictly between the checkbox margin and the right edge (with docked profile indicator when viewing "all"), with `Style.space(20)` height ensuring chip borders and pills are never cropped vertically.
         - Profile badge (`profLabel`): Docked cleanly to the right when viewing "all" (`#profile`, elided). If the task has no other chips, the profile label moves inline to Line 1 instead, eliminating the empty 3rd row.
         - Sub-line chips (`chipsRow`): Indented under title text with clear semantic differentiation between temporal deadlines and spatial codebase context:
           - **Time / Due Ticket (`variant: "time"`)**: Squircle ticket badge (`radius: Style.space(4)`) with bold proportional digits, dynamic urgency coloring (amber with `󱫌` when overdue, vibrant accent with `󰥔` when due today, subtle neutral-accent when scheduled in the future). Clicking directly expands the task drawer into the reminder presets row without toggling task completion.
           - **Repo / Location Code Capsule (`variant: "location"`)**: Rounded pill capsule (`radius: implicitHeight / 2`) with `monospace` typography, accent git icon (`󰊤`), and developer code surface (`Color.menu.selectedBackground`). Clicking directly launches the codebase in the configured editor via `openCodebase()` when a local path is detected.
           - **Tag Pills (`variant: "tag"`)**: Subtle pill capsule (`radius: implicitHeight / 2`) in muted neutral tone (`#tag`).
       - When an item has no notes or chips: Single-line layout (`Style.space(34)`), with title, checkbox, inline profile (in "all" view), and action buttons mathematically and visually centered with comfortable vertical padding.
       - Collapsed row content is vertically centered across 1-line, 2-line, and 3-line items via explicit height propagation on `expandedContent` and `itemHeaderCol`.
       - **Row Separators**: A light section separator (`PanelSeparator`, 1px, `strength: 0.08`) is rendered between adjacent item rows in the list to enhance readability.
     - **Repo Name Display Formatting**:
       - In item badges, repository strings strip any owner/organization prefix (e.g. `Tablerase/omarchy-ardoise` displays cleanly as `omarchy-ardoise`) to save space and reduce cognitive clutter, while strictly preserving the full remote repository and local path in data and hover tooltips.
       - Target codebase context chip remains strictly located within the expanded drawer to avoid crowding the collapsed task list.
   - **Item Ordering Algorithm & Satisfying Task Completion Flow**:
     - **Micro-Animation & Dwell Time (Satisfying Completion)**:
       - Toggling an active task via <kbd>Space</kbd> or clicking the checkbox icon (`Ui.TaskCheck`) triggers an immediate, rewarding micro-interaction:
         - Checkbox (`Ui.TaskCheck`): Plays a bouncy pop scale animation (`1.0 -> 1.25 -> 1.0` with `Easing.OutBack`), checkmark spring scales in from `0.2` to `1.0`, and background/border smoothly transition to accent colors.
         - Animated Strikethrough (`strikeLine`): Rather than abruptly flashing on, a custom strikethrough line sweeps smoothly from **left to right** across the task title text (`0 -> Math.min(contentWidth, width)` in 260ms with `Easing.OutCubic`). Undoing within the grace period smoothly retracts the line from right to left. Suppressed while the title wraps across several lines in the expanded drawer (see **Expanded Drawer Title Reveal**), where dimming plus the filled checkbox carry completion instead.
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
     - Strictly explicit expansion via keyboard (<kbd>Enter</kbd>), clicking the expand chevron button (`󰅀`), or clicking the time/due chip (`remBadge`) to open reminders. The legacy hover-to-expand timer mechanic has been removed entirely, ensuring that moving the mouse across tasks, reading chip tooltips, or resting the cursor never causes unexpected drawer expansion, layout shifts, or accordion bouncing.
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
   - Action buttons with `ShortcutToolTip` badges: [Clear] (<kbd>Hold c</kbd> or pointer press for 800ms, charging a 3px `Color.accent` laser line along the bottom of the button with subtle surface tint, archive and clear completed tasks in current profile) • [Archive] (<kbd>d</kbd>, open Archive browser modal `ui/ArchiveModal.qml` to browse, filter, and restore completed tasks) • [Edit] (<kbd>e</kbd>, open todos.json in editor) • [Quick Add] (<kbd>A</kbd> / detected shortcut).
6. **Searchable Help Overlay Modal (`showKeyHelp`)**:
   - Fuzzy filter text field (`keySearchField`) wrapped in `BorderSurface`.
   - **Universal Input Handling**:
     - Follows project-wide input convention: padded, custom font/color styling, and active navigation focus border (`isNavFocused`).
     - **Two-Stage Escape**:
       - When `keySearchField.text` is empty: pressing <kbd>Escape</kbd> (or <kbd>Backspace</kbd>) dismisses the modal and restores focus to the panel.
       - When `keySearchField.text` has content: pressing <kbd>Escape</kbd> blurs the field into normal motion navigation mode on `"search"` with active `BorderSurface` focus outline, preserving draft search queries.
       - In normal motion mode: pressing <kbd>Escape</kbd> dismisses; pressing <kbd>Enter</kbd>, <kbd>Space</kbd>, <kbd>i</kbd>, <kbd>a</kbd>, or typing any character re-enters text edit mode; pressing <kbd>j</kbd>/<kbd>Down</kbd>/<kbd>Tab</kbd> moves into the shortcuts list (`helpFlickable`); pressing <kbd>k</kbd>/<kbd>Up</kbd>/<kbd>Shift+Tab</kbd> moves to `closeHelpBtn`.
     - When navigating the shortcuts list: pressing <kbd>k</kbd> or <kbd>Up</kbd> at the top item moves back up to the search field in motion mode without swallowing keystrokes; typing any character redirects into search.
   - Keyboard shortcut directory grouped by category (Global, Navigation, Task Actions, Input & Create, Modals). Lists <kbd>/</kbd> / <kbd>Ctrl+F</kbd> for searching tasks, notes & profiles and <kbd>i</kbd> / <kbd>a</kbd> for focusing the new task input field, and dynamically lists the active desktop keybinding (`root.detectedShortcut`).

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
  - Right click: Opens the Quick Add modal. The bar widget closes the panel and then calls `bar.shell.summon(moduleName, "{}")` to mount the plugin's `overlay` entry point. There is **no `quickadd` IPC function** — the scripted route is the shell-level `omarchy-shell shell summon tablerase.ardoise '{}'`, not a plugin command. (An earlier revision of this document advertised a `quickadd` plugin command that resolves to `Function not found.`; the IPC contract test now guards against re-introducing it.)
  - Scroll: Cycles active profile filter.
- **Shell IPC Contract (`IpcHandler: tablerase.ardoise`)**:
  - `omarchy-shell tablerase.ardoise list`: Returns full JSON array of active tasks.
  - `omarchy-shell tablerase.ardoise count`: Returns **total** pending task count string. Deliberately *not* rung-scoped: it is a data/scripting contract, whereas the bar badge is a display signal. Do not "fix" this to match the badge — `list` already exposes the full breakdown if a script needs urgency detail.
  - `omarchy-shell tablerase.ardoise add "<title> [#profile]"`: Adds task with optional `#profile`.
  - `omarchy-shell tablerase.ardoise addDetailed "<title>" "<notes>" "<reminder>"`: Adds task with explicit notes/description and optional reminder (e.g. preset `+30m`, `+1h`, `tomorrow 9am` or ISO string; pass `""` if none).
  - `omarchy-shell tablerase.ardoise toggleTodo "<id>"`: Toggles task completion (`done`).
  - `omarchy-shell tablerase.ardoise update "<id>" '<fieldsJson>'`: Updates task properties (e.g. reminder, notes, profile).
  - `omarchy-shell tablerase.ardoise remove "<id>"`: Deletes task by ID.
  - `omarchy-shell tablerase.ardoise clear`: Archives and clears completed tasks.
  - `omarchy-shell tablerase.ardoise profiles`: Returns array of available profiles.
  - `omarchy-shell tablerase.ardoise searchProfiles "<query>"`: Returns structured JSON array of profile names matching substring query.
  - `omarchy-shell tablerase.ardoise setProfile "<profile>"`: Sets active profile filter.
  - `omarchy-shell tablerase.ardoise open` / `close` / `toggle`: Controls main panel visibility. In multi-monitor environments, `open` and `toggle` dynamically discover the `BarWidget` on the compositor-focused output via `root.bar.moduleWidgets()` and `Hyprland.focusedMonitor` to summon the panel on the active monitor, while `close` and `toggle` (when already open) target the currently open instance.
  - `omarchy-shell tablerase.ardoise archived`: Returns archived tasks JSON.
  - `omarchy-shell tablerase.ardoise archiveCount`: Returns count of archived tasks.
  - `omarchy-shell tablerase.ardoise unarchive "<id>"`: Restores one archived task to the active store (id/createdAt/notes/profile/repo preserved, removed from the archive, never duplicated). Accepted asynchronously: returns `ok` (accepted) or `busy` (another archive operation is in flight).
  - `omarchy-shell tablerase.ardoise purgeArchived "<id>"`: Permanently removes one task from the archive (irreversible except via git history). Accepted asynchronously: returns `ok` (accepted) or `busy`.
  - `omarchy-shell tablerase.ardoise gitHistory`: Returns structured JSON array of Git snapshots from `~/.config/omarchy/tablerase.ardoise/`.
  - `omarchy-shell tablerase.ardoise gitRollback "<hash>"`: Reverts `todos.json` and `todos-archive.json` to the specified commit snapshot.
  - `omarchy-shell tablerase.ardoise gitRecover "<hash>"`: Selectively recovers missing tasks from snapshot into active store.
  - `omarchy-shell tablerase.ardoise gitSync`: Fetches remote, performs conflict-free 3-way store merge if diverged, and pushes to remote.
  - `omarchy-shell tablerase.ardoise gitSetRemote "<url>"`: Configures or removes Git remote URL.
  - `omarchy-shell tablerase.ardoise gitGetRemote`: Returns configured Git remote URL.
  - `omarchy-shell tablerase.ardoise gitSearch "<query>"`: Returns filtered JSON array of snapshots matching the query against commit messages, device names (supports `#device` / `[device]` syntax), commit hashes, and author names. Multi-token AND matching; returns all snapshots on empty query.
  - `omarchy-shell tablerase.ardoise autoSetupGitRemote` / `gitAutoSetup`: Automatically creates a private GitHub repository via `gh` CLI, initializes origin, and pushes local task data. Accepts optional repo name argument (defaults to `ardoise-tasks`).

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
| **Panel** | `K` | Open the focused task's context menu (copy for LLM, copy title/notes, open codebase, edit, delete) |
| **Panel (Task Menu)** | `j` / `k` / `↓` / `↑` | Move the context menu selection |
| **Panel (Task Menu)** | `y` / `t` / `n` / `o` / `e` | Copy for LLM / copy title / copy notes / open codebase / edit title |
| **Panel (Task Menu)** | `x` (hold 600ms) | Delete the task (hold-to-confirm charge on the menu row) |
| **Panel (Task Menu)** | `Enter` / `Space` | Activate the selected item; on the delete item, hold to charge |
| **Panel (Task Menu)** | `Escape` / `q` | Dismiss the context menu |
| **Panel (Title Editor)** | `Enter` | Commit edited title (trims input; updates profile/tags if hashtag included) |
| **Panel (Title Editor)** | `Escape` | Cancel title edit, restore original title, and return to task row |
| **Panel** | `e` | Open `todos.json` in editor (jumps to selected task line if on a task) |
| **Panel** | `u` | Toggle Git Snapshots & Undo modal (`ui/GitModal.qml`) |
| **Panel** | `Hold c` / `C` | Archive and clear completed tasks in current profile (hold 800ms) |
| **Panel** | `d` | Open the Archive browser (`ui/ArchiveModal.qml`) — restore completed tasks |
| **Archive Modal** | `j` / `k` / `↓` / `↑` | Move the archived-task selection |
| **Archive Modal** | `g` / `G` | Jump to first / last archived task |
| **Archive Modal** | `Enter` / `r` | Restore the selected task to the active list |
| **Archive Modal** | `y` | Copy the selected archived task for an LLM |
| **Archive Modal** | `e` | Open `todos-archive.json` in the editor |
| **Archive Modal** | `/` / `Ctrl+F` / magnifier button | Activate the archive filter bar |
| **Archive Modal** | `K` / Right-Click / `󰇙` button | Open the archived-task contextual menu (restore, copy, open file, delete) |
| **Archive Modal (Menu)** | `j` / `k` / `Enter` | Navigate the menu and activate the selected item |
| **Archive Modal** | `x` / `Delete` (hold 600ms) | Permanently delete the selected archived task (hold-to-confirm) |
| **Archive Modal (Menu)** | `x` (hold) | Permanently delete via the menu's hold-to-confirm item |
| **Archive Modal** | `Escape` | Two-stage: close the menu/filter first, then dismiss the modal |
| **Panel** | `i`, `a`, `<slash>` | Jump focus into new task input field |
| **Panel** | `A` | Open Quick Add overlay modal |
| **Panel** | `Hold x` / `Delete` | Delete highlighted task (hold 800ms) |
| **Panel** | `g` | Jump to first task |
| **Panel** | `G` | Jump to last task |
| **Panel** | `?` / `Backspace` (empty search) | Toggle or dismiss searchable keyboard shortcuts modal |
| **Git Modal** | `1` / `2` | Switch between Snapshots (1) and Sync Settings (2) tabs |
| **Git Modal** | `Tab` / `Shift+Tab` | Advance / reverse major sections (`snapshots` list ⇄ `actions` buttons) |
| **Git Modal (Snapshots)** | `/` / `Ctrl+F` | Activate snapshot search filter bar |
| **Git Modal (Snapshots, Search)** | `Escape` (non-empty query) | Clear search query (search bar stays open) |
| **Git Modal (Snapshots, Search)** | `Escape` (empty query) | Close search bar and restore full unfiltered list |
| **Git Modal (Snapshots, Search)** | `Enter` / `↓` | Jump focus from search bar to first filtered snapshot |
| **Git Modal (Snapshots)** | `j` / `k` / `↓` / `↑` | Navigate snapshot list (at bottom of list, `j` / `↓` transitions to `actions`) |
| **Git Modal (Snapshots)** | `g` / `G` | Jump to first / last snapshot |
| **Git Modal (Snapshots)** | `K` / `Space` / `Enter` / Right-Click | Open snapshot contextual menu (Rollback, Recover, Copy Hash) |
| **Git Modal (Snapshots)** | `r` | Direct shortcut to rollback tasks to selected snapshot |
| **Git Modal (Snapshots)** | `c` | Direct shortcut to recover missing/deleted tasks from selected snapshot |
| **Git Modal (Actions)** | `h` / `l` / `←` / `→` | Cycle between Rollback and Recover Deleted buttons |
| **Git Modal (Actions)** | `k` / `↑` | Return focus to snapshot list |
| **Git Modal (Actions)** | `Enter` / `Space` | Activate focused button |
| **Git Modal (Context Menu)**| `j` / `k` / `Enter` / `Esc` | Navigate menu items, activate selection, or dismiss |
| **Git Modal (Sync Remote)** | `Tab` / `Shift+Tab` | Cycle through controls (`remoteField` ⇄ `autoCreateRemoteBtn` ⇄ `saveRemoteBtn` ⇄ `syncNowBtn`) |
| **Git Modal (Sync Remote)** | `h` / `l` / `←` / `→` | Navigate horizontally between action buttons (Create GitHub Repo ⇄ Save Remote ⇄ Sync Now) or return to tab 0 |
| **Git Modal (Sync Remote)** | `j` / `k` / `↓` / `↑` | Move vertically between remote URL field and action buttons row |
| **Git Modal (Sync Remote)** | `i` / `a` / `<slash>` / `Enter` | Enter insert mode in remote URL input field |
| **Git Modal (Sync Remote)** | `Enter` / `Space` | Activate focused button (Create GitHub Repo / Save Remote / Sync Now) or focus input |
| **Git Modal (Sync Remote)** | `s` | Quick-sync with configured remote |
| **Git Modal (Sync Remote)** | `Escape` (insert mode) | Blur remote URL field and return to normal motion mode without closing modal |
| **Git Modal** | `Escape` / `q` / `u` (normal mode) | Two-stage: if search is active, first Escape closes search; second Escape dismisses modal |
| **Panel (Input)** | `Escape` | Blur text field to normal motion mode on `input` without discarding text |
| **Panel (Input Normal)** | `i` / `a` / `Enter` / `Space` | Enter text edit mode in input field |
| **Panel (Input Normal)** | `j` / `↓` | Move down to task list |
| **Panel (Input Normal)** | `k` / `↑` | Move up to profile filter bar |
| **Quick Add (Autocomplete)** | `↓` / `↑` | Cycle suggested profile or tag matches |
| **Quick Add (Autocomplete)** | `Tab` / `Enter` | Commit selected match (`#<item> `) and advance cursor |
| **Quick Add (Autocomplete)** | `Shift + Tab` | Cycle suggested matches backward |
| **Quick Add (Autocomplete)** | `Escape` | Dismiss autocomplete popup (retains input focus and text) |
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

### Custom User Keybindings (`bindings.lua`)

Users can customize in-panel navigation and action shortcuts using a Lua file following Omarchy Quattro conventions.

#### File Location & Auto-Seeding
- Location: `~/.config/omarchy/tablerase.ardoise/bindings.lua` (or `$ARDOISE_DATA_DIR/bindings.lua` if customized).
- **Auto-Seeding**: On first run, Ardoise automatically creates `bindings.lua` by copying the self-documenting template from [`tools/default-bindings.lua`](./tools/default-bindings.lua). The template lists all supported action names, modifier tokens, and syntax examples. It returns an empty table `{}` by default so all standard shortcuts remain active until customized.

#### Sandboxing & Security Invariants
Evaluation is executed via the standalone runner [`tools/load-bindings.lua`](./tools/load-bindings.lua):
- **Hermetic Sandbox**: Evaluated in a stripped Lua 5.5 environment with no access to `os`, `io`, `debug`, `package`, `coroutine`, or `load`. Only safe deterministic primitives (`tostring`, `tonumber`, `type`, `pairs`, `ipairs`, `table.*`, `string.*`, `math.*`) are accessible.
- **Fail-Safe Fallback**: Any syntax error, execution error, or missing file automatically and silently falls back to standard `DEFAULT_BINDINGS` without UI interruption.
- **Invariant Protection**: The two-stage escape behavior is inviolable. Attempts to bind `Escape` / `esc` to other actions are rejected.

#### Supported Configuration Syntax
Both declarative table returns and imperative `ardoise.bind()` function calls are supported:

**1. Declarative Table Return**:
```lua
return {
  open_editor = "o",
  quick_add = "a",
  search = "ctrl+s",
  jump_top = { "t", "Home" },
  cycle_left = "Left",
  cycle_right = "Right"
}
```

**2. Imperative `ardoise.bind()`**:
```lua
ardoise.bind("open_editor", "o")
ardoise.bind("search", "Ctrl+S")
-- Keys and actions may be supplied in either order
ardoise.bind("a", "quick_add")
```

#### Action Catalog
| Action Name | Default Key(s) | Description |
| :--- | :--- | :--- |
| `next_task` | `j`, `Down` | Move to next task in list |
| `prev_task` | `k`, `Up` | Move to previous task in list |
| `cycle_left` | `h`, `Left` | Cycle active profiles or footer buttons left |
| `cycle_right` | `l`, `Right` | Cycle active profiles or footer buttons right |
| `jump_top` | `g` | Jump to first task |
| `jump_bottom` | `G` | Jump to last task |
| `toggle_done` | `Space` | Toggle task completion status |
| `toggle_expand` | `Return` | Expand / collapse task details drawer |
| `delete_task` | `x` | Delete selected task (hold 800ms) |
| `edit_title` | `r`, `F2` | In-place edit of task title |
| `task_menu` | `K` | Open the focused task's context menu |
| `open_editor` | `e` | Open `todos.json` in default editor |
| `git_undo` | `u` | Toggle Git Snapshots & Undo modal |
| `clear_completed` | `c` | Archive and clear completed tasks in current profile (hold 800ms) |
| `open_archive` | `d` | Open the Archive browser (restore completed tasks) |
| `focus_input` | `i`, `a` | Focus new task input field |
| `search` | `/` | Activate panel search bar |
| `quick_add` | `A` | Open Quick Add overlay modal |
| `help` | `?` | Toggle Help modal |

#### Dynamic UI Reflection & Live Reload
- Custom keybindings are watched with `FileView` (`watchChanges: true`), triggering live reload on disk save without restarting Quickshell.
- The Help Modal (`HelpModal.qml`) dynamically formats and displays active user bindings. Its bottom dismiss prompt (`Press Esc or <key> to close`) and keyboard dismiss handlers dynamically match the active `help` binding.

#### Git Tracking Strategy
`bindings.lua` is explicitly excluded from the task snapshot git repository via `.gitignore` (`bindings.lua` and `*.tmp`):
- **Conflict Prevention**: `GitSync.js` provides automatic three-way merging exclusively for structured task JSON (`todos.json` / `todos-archive.json`) based on task timestamps. Arbitrary Lua code cannot be three-way merged across machines and would produce git merge conflict markers that break parsing.
- **Hardware Independence**: Keeps keybindings machine-local, avoiding overwriting shortcuts across disparate keyboards (e.g. laptop layout vs. desktop keyboard).
- **Snapshot Isolation**: Restoring task snapshots via rollback never affects local keybinding configurations.

---

## 5. Design Tokens, Glyphs & Styling Guidelines

### Task-Slate Icon Ladder (the Ardoise brand mark)

The mark is a **stateful** Nerd Font MD glyph (Private Use Area) resolved by `TodoStore.getArdoiseIconState()` from `getTaskUrgencyBreakdown()`. Rungs are driven by **urgency, not raw count** — the same approach omarchy's own battery / wifi / volume widgets take, and the same reason: "5–9 tasks" is not actionable, "nothing is overdue" is.

| Rung | Condition | Glyph | Name | Codepoint | Color role | Badge count |
|---|---|---|---|---|---|---|
| `clear` | `total === 0` | `󰗠` | `check_circle` | `\U000f05e0` | foreground | hidden (0) |
| `pending` | nothing time-critical | `󰝖` | `format_list_checks` | `\U000f0756` | foreground | `total` |
| `due` | `dueToday > 0`, `overdue === 0` | `󱖫` | `list_status` | `\U000f15ab` | accent | `dueToday` |
| `overdue` | `overdue > 0` | `󱫌` | `timer_alert` | `\U000f1acc` | **warning** | `overdue` |

**Precedence:** `overdue` > `due` > `pending` > `clear`. A store with nothing pending is always `clear`, regardless of reminder history, because completed tasks are excluded from the breakdown.

#### Severity ramp

The **colour ramp is the severity channel**, in increasing salience:

```
foreground  →  foreground  →  accent  →  warning
 (clear)       (pending)      (due)      (overdue)
```

- A task **due today is on track**, so `due` stays informational (accent) and does *not* escalate past it. Only a genuinely **late** task escalates to warning.
- **`urgent` (red) is deliberately not a rung colour.** Red is the shell's error channel, and using it for a late task would train the eye to ignore it. Orange means *late*; red means *broken* — so red stays on real failure surfaces (QuickAdd's title-required cue, GitModal errors, invalid input). Guarded by a test asserting no rung uses `urgent`.
- `timer_alert` is used for the late rung rather than a clock glyph (`clock_alert` is U+F0955, adjacent to the plain `󰥔 clock` U+F0954 already reserved for reminders) so a late task cannot be misread as a reminder at 13 px.

#### Warning color sourcing

Omarchy exposes **no warning role**: `Color.qml` parses only `accent`, `urgent` (the theme's `red`), `muted`, and `color0/4/7/8`, and **silently ignores the `yellow` key every theme ships**. So `ui/ArdoiseIcon.qml` reads the active theme's `colors.toml` itself.

Resolution order: host `warningOverride` → user theme `bar.warning` (`Color.pick`) → the theme's own `yellow` → hardcoded `#df8e1d` fallback.

- **`yellow`, not `orange`:** several themes' `orange` is a coral/salmon that collides with urgent red (catppuccin `orange #f6b6ab` vs `red #f38ba8`; catppuccin-latte `orange #d84e2b` vs `red #d20f39`), which would collapse the warning/error distinction. Every theme's `yellow` reads as amber.
- **Why not derive or hardcode it?** Measured across all 22 shipped themes: hue-rotating `urgent` to amber lands close to the theme's own `yellow` on only 15/22 — it breaks on `lumon` (blue → brown), `lupine` (magenta → muddy), and `solitude` (grey → no contrast against foreground at all). A hardcoded amber is right for exactly one theme, since dark themes need a much lighter value (`#f9e2af` / `#e0af68` vs latte's `#df8e1d`). Reading the theme's own key is correct in all 22.
- **Known degradation:** `solitude` (`yellow #d9dbdc`, near-white) and `hackerman` (`yellow #50f7d4`, cyan) ship no usable amber, so the warning is low-salience there. That reflects the theme author's palette; do not special-case it.
- **Theme-switch freshness:** `omarchy-theme-set` swaps themes with `rm -rf current/theme` + `mv next-theme current/theme`, which destroys the watched `colors.toml` inode — a `FileView` with `watchChanges: true` on it goes deaf. The component therefore watches `current/theme.name` instead: a regular file *outside* the swapped directory, rewritten in place **last** (after the swap), so it emits a reliable inotify `MODIFY`. On change it calls `reload()` on the `colors.toml` reader, which parses in `onLoaded` — mirroring `Color.qml`'s own `onFileChanged → reload() → onLoaded` pattern, since `text()` is stale inside the change signal. `onLoadFailed` keeps the last good value rather than flashing the fallback.

#### Other design constraints (guarded by tests in `tests/TodoStore.test.mts`)
- **Glyph, color, and badge number are one resolution.** All three come from a single `getArdoiseIconState()` call, so the mark and its count cannot describe different states. Never derive the badge from a separate count call — that is exactly the drift the rung-scoped `count` field exists to prevent.
- The badge count is always the **rung's own subset**, never the total pending. A reader glancing at the bar sees "3 overdue", not "12 tasks with 3 overdue"; total pending is one hover away in the tooltip. Because the `due` rung is only reachable when `overdue === 0`, and `overdue` outranks `due`, the count is never ambiguous at any rung.
- `count <= total` always, and `count > 0` on every non-`clear` rung.
- Every rung carries a **distinct glyph** — a stateful mark must not silently repeat an icon, or the widget appears to flicker between two meanings.
- ~~The two extremes deliberately **share a filled-circle silhouette** (`check_circle` ↔ `alert_circle`) so the mark keeps a stable identity while only the interior glyph and color change. The middle rungs are lists.~~ **Void as of the warning ramp.** The late rung became `timer_alert`, which shares no silhouette with `check_circle`, so this invariant no longer holds and was replaced by the colour-ramp rule above: the ramp carries severity, and the glyphs carry *what* the state is. Do not reintroduce red as a rung colour to recover a shared silhouette.
- `check_all` (`\U000f012d`) is **rejected** as the `clear` rung: it is a bare diagonal tick with no enclosure and rasterizes to a near-invisible speck at 13 px.
- Ladder rungs must **not** be built from near-identical gray list glyphs (e.g. `format_list_bulleted` → `playlist_check` → `view_list`). At 13 px those are indistinguishable; escalation has to change shape.

**Consistency contract:** the same ladder renders at the bar (`Style.bar.iconFont` = 13 px), the panel brand header, and the QuickAdd header (`Style.font.subtitle`). Do not pin a static brand glyph at any of the three surfaces.

**Scope boundary:** the ladder governs the *brand mark and the bar badge*. The panel's "All" filter-pill count and its `"N pending"` header label stay total/filter-scoped, because they describe the active filter rather than the urgency state. The panel brand mark may escalate to warning while its header reads "12 pending"; that is acceptable because the panel body renders per-task urgency markers.

**Task rows follow the same ramp** via `ui/TaskCheck.qml`: a late task's checkbox tints and borders in the same `warningColor`, a due-today row stays `accent`, and a completed row stays accent. `PanelContent.qml` sources `root.warningColor` from the header `ArdoiseIcon` (`brandIcon.warningColor`) and passes it down, so panel rows, brand mark and bar all render one amber from a single theme lookup. `TaskCheck` intentionally has **no** `urgentColor` property any more — do not reintroduce red for late rows. `ProfileSelector.qml` and `ui/ReminderPills.qml` use `accent` for **selection and focus**, not urgency, and must stay accent.

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
2. Verify with tests in `tests/qml-windowed.test.mts` and `tests/qml-static.test.mts` that keyboard navigation did not break.
3. Test with live shell: `omarchy-restart-shell` and verify interactive motions.
4. Verify all changes are documented in this `DESIGN.md`.
5. Run `npm run test:docker` to reproduce CI exactly, including the `CI=1`
   strict guards that turn a missing prerequisite into a failure rather than a
   silent skip. See `AGENTS.md` § *Test Tiers*.

### Reloading the shell after a QML / JS change
`omarchy-shell shell rescanPlugins` exits 0 but does **not** re-instantiate an
already-mounted bar widget, so a changed ladder or color can keep rendering the
previous build. A real restart is required:

```bash
timeout 20 bash -c 'while timeout 5 quickshell kill -p /usr/share/omarchy/shell --any-display; do :; done'
hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'
omarchy-shell shell ping     # expect: ok
```

`omarchy-restart-shell` performs the same steps but can block when invoked
outside the Hyprland session; running them by hand avoids that.

### Verifying the icon ladder
Drive a rung with the plugin's own IPC and screenshot the bar. Two gotchas:
- **End of day is computed in local time** (`TodoStore.js` `getTaskUrgencyBreakdown`), so a reminder set to `23:00Z` on a CEST machine lands on the *next* local day and resolves to `upcoming`, not `due`. Pick a UTC time comfortably inside the local day.
- **Monitors may be scaled.** Screenshot rasters come out at the monitor scale (e.g. 1.6x), so a 13 px logical glyph is ~21 physical px. Compare against a reference rendered at the matching size, or the glyph identity is ambiguous at 13 px.

Theme-swap freshness is covered automatically by
`tests/qml-theme.test.mts` → *"ArdoiseIcon: warning color reads the theme's
yellow and follows a live theme switch"*, which sandboxes `HOME`, swaps
`colors.toml` on a live component, and asserts the color follows. No need to
switch the live theme to verify it.

---

## 7. Data & Integration Reference

The user-facing README links here rather than duplicating this material, so
there is a single source of truth for schemas and layout.

### 7.1 Task Schema (`todos.json`)

Stored at `~/.config/omarchy/tablerase.ardoise/todos.json` (override the
directory with the `ARDOISE_DATA_DIR` environment variable).

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
      "repo": "omarchy-ardoise",
      "tags": ["perf", "sql"],
      "location": { "repo": "Tablerase/omarchy-ardoise", "subpath": "ui/", "localPath": "~/Work/omarchy-ardoise" },
      "done": false,
      "createdAt": 1789992760433,
      "updatedAt": 1789992800000,
      "dueDate": null,
      "reminder": "2026-09-22T09:00:00.000Z",
      "notified": false
    }
  ]
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `version` | `number` | Schema version. `CURRENT_SCHEMA_VERSION` is `1` in `TodoStore.js`. |
| `activeProfile` | `string` | Currently active default profile. |
| `profiles` | `string[]` | Registered profiles. |
| `todos[].id` | `number\|string` | Unique identifier (timestamp, or string when assigned by a client). |
| `todos[].title` | `string` | Task title. |
| `todos[].description` | `string` | Notes / details. |
| `todos[].profile` | `string` | Profile or project name. |
| `todos[].repo` | `string?` | Repository or component within the project. |
| `todos[].tags` | `string[]?` | Subsystem tags / labels. |
| `todos[].location` | `object\|null` | Where the work lives — see 7.2. |
| `todos[].done` | `boolean` | Completion state. |
| `todos[].createdAt` | `number` | Creation epoch ms. |
| `todos[].updatedAt` | `number?` | Last-updated epoch ms. Drives skew resolution in `mergeStores`. |
| `todos[].dueDate` | `string\|null` | Optional due date. |
| `todos[].reminder` | `string\|null` | Scheduled reminder (ISO 8601). |
| `todos[].notified` | `boolean?` | Whether the desktop notification has fired. |

#### Versioning & forward compatibility

`normalize()` never downgrades a store it does not recognise:

```js
var resolvedVersion = Math.max(CURRENT_SCHEMA_VERSION, rawVersion)
```

A file written by a **newer** Ardoise keeps its higher `version` and passes
through untouched, so a newer build's data survives an older install. Merges
take `Math.max(local.version, remote.version, CURRENT_SCHEMA_VERSION)`, and
per-task conflicts resolve on the newer `updatedAt` (falling back to
`createdAt`), so a merge is safe even when the two sides ran different
versions. This is deliberate: a task list must not be silently truncated
because a rollback happened.

### 7.2 Task Location

`location` is nullable; every field is optional.

| Field | Type | Description |
| :--- | :--- | :--- |
| `location.repo` | `string\|null` | Git repository identifier (e.g. `Tablerase/omarchy-ardoise`). |
| `location.subpath` | `string\|null` | Relative subpath within the repo. |
| `location.localPath` | `string\|null` | Local filesystem path. |

Populated automatically by `tools/detect-context.sh` from the focused Hyprland
window, and overridable by hand.

### 7.3 Archive Schema (`todos-archive.json`)

Completed tasks are moved here by `clear` / the footer's `Clear` action
(`c`), with a `completedAt` stamp.

```json
{
  "version": 1,
  "archived": [
    {
      "id": 1789992760433,
      "title": "Fix database query performance",
      "description": "Index the user_id column on orders table",
      "profile": "work",
      "repo": "omarchy-ardoise",
      "tags": ["perf"],
      "location": { "repo": "Tablerase/omarchy-ardoise" },
      "createdAt": 1789992760433,
      "completedAt": 1789999999999
    }
  ]
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `version` | `number` | Archive schema version (`CURRENT_ARCHIVE_VERSION`). |
| `archived[].id` | `number\|string` | Original task identifier. |
| `archived[].title` | `string` | Task title. |
| `archived[].description` | `string` | Task notes. |
| `archived[].profile` | `string` | Profile at completion time. |
| `archived[].repo` | `string?` | Repository / component. |
| `archived[].tags` | `string[]?` | Subsystem tags. |
| `archived[].location` | `object\|null` | Location, per 7.2. |
| `archived[].createdAt` | `number` | Epoch ms when created. |
| `archived[].completedAt` | `number` | Epoch ms when archived. |

### 7.4 Reactive Storage

Both files are watched with `FileView` (`watchChanges: true`), so external
writers — Nextcloud, Syncthing, git hooks, AI agents, shell scripts — are
reflected in the bar and panel without a restart. Writes are atomic
(temp file + rename) to avoid a partially-read file.

### 7.5 Background Reminder Service

`Service.qml` is declared with kind `"service"` and `keepLoaded: true`.

- **Lifecycle**: loaded by `shell.qml` at startup; runs headless 24/7.
- **Monitoring**: polls `todos.json` on a 15 s `Timer` for tasks where `reminder <= now` and `notified == false`.
- **Notification**: calls `$OMARCHY_PATH/bin/omarchy-notification-send` with glyph `󰥔` (reminder clock), the title as headline, and profile + description as body. Click action: `omarchy-shell shell toggle tablerase.ardoise '{}'`.
- **Deduplication**: sets `notified: true` and writes back, so a task never alerts twice. An in-memory guard also covers the window where a write is still in flight.

### 7.6 Project Structure

```text
.
├── manifest.json          # Plugin manifest (bar-widget, overlay, service)
├── package.json           # Test & validation scripts
├── tsconfig.json
├── BarWidget.qml          # Bar readout, mouse gestures, IpcHandler, panel loader
├── Panel.qml              # Wayland layer-shell wrapper around Ui.KeyboardPanel
├── PanelContent.qml       # Panel UI: filters, search, scrollbar, task rows
├── PanelLogic.js          # Pure focus/navigation state machine
├── QuickAdd.qml           # Fullscreen overlay for keyboard capture
├── Service.qml            # Headless reminder service
├── TaskNotesArea.qml      # Notes editor surface
├── TodoStore.js           # Typed store: schema, normalization, merging, archives
├── GitSync.js             # Snapshot, rollback, recovery, remote sync
├── ui/                    # Component library
│   ├── ArdoiseIcon.qml    # Stateful task-slate mark (ladder rung, theme-aware)
│   ├── Chip.qml           # Compact pill/badge
│   ├── GitContextMenu.qml # Snapshot action popover
│   ├── GitModal.qml       # Snapshot review, rollback, remote sync
│   ├── HelpModal.qml      # Searchable shortcut directory
│   ├── KeyBadge.qml       # Keyboard shortcut badge
│   ├── ProfileSelector.qml# Scrollable profile pill row
│   ├── ReminderPills.qml  # Scrollable reminder preset row
│   ├── ShortcutToolTip.qml# Description + shortcut badges tooltip
│   └── TaskCheck.qml      # Circular checkbox / severity indicator
├── tools/
│   ├── ci-local.sh        # Reproduce CI in a container
│   ├── default-bindings.lua # Template for user keybinding customization
│   ├── demo.sh            # Reproducible demo scenario runner & data-safety manager
│   ├── detect-context.sh  # Hyprland focused-window CWD/editor detection
│   ├── load-bindings.lua  # Sandboxed Lua keybindings runner
│   ├── omarchy-ref        # Pinned Omarchy commit for CI
│   ├── preview.qml        # Offscreen render definition
│   └── render-preview.sh  # Headless capture pipeline
├── tests/                 # Tiered suite — see AGENTS.md "Test Tiers"
│   ├── helpers/qml-test-utils.mts
│   ├── TodoStore.test.mts
│   ├── PanelLogic.test.mts
│   ├── GitSync.test.mts
│   ├── detect-context.test.mts
│   ├── qml-static.test.mts
│   ├── qml-core.test.mts
│   ├── qml-theme.test.mts
│   ├── qml-windowed.test.mts
│   └── qml-live-shell.test.mts
├── .github/workflows/ci.yml
├── DESIGN.md
├── AGENTS.md
└── README.md
```

The QML tests are split **one file per tier** so each declares its own
prerequisites: `qml-static` needs only repo files, `qml-core` needs quickshell
plus `shell/Commons`/`shell/Ui`, `qml-theme` adds the theme-file watch, and
`qml-windowed` / `qml-live-shell` need a real compositor and are local-only.
