# Agent Instructions & Project Rules for Ardoise (`tablerase.ardoise`)

## Mandatory UI & Interaction Rule: Keep `DESIGN.md` Updated
- **Sync Requirement**: Whenever modifying, adding, or refactoring UI components, layout structures, modal flows, keybindings, or focus state machine transitions, you **MUST update [`DESIGN.md`](./DESIGN.md)** to reflect those changes in the same commit.
- **User Permission for Ergonomic Changes**: If a task or proposal alters the established layout sequence, modal flow, or keybinding behaviors documented in [`DESIGN.md`](./DESIGN.md), **ask the user for explicit permission** before applying it.

## Architectural Invariants
1. **Keyboard-First**: 100% of workflows must be accessible via keyboard motions (<kbd>j</kbd>/<kbd>k</kbd>, <kbd>h</kbd>/<kbd>l</kbd>, <kbd>g</kbd>/<kbd>G</kbd>, <kbd>Tab</kbd>/<kbd>Shift+Tab</kbd>, <kbd>Space</kbd>, <kbd>Enter</kbd>, <kbd>Esc</kbd>).
2. **Two-Stage Escape**:
   - In empty text fields: <kbd>Escape</kbd> dismisses modal/panel.
   - In non-empty text fields: <kbd>Escape</kbd> blurs to normal (motion) mode on the container without closing or losing draft text.
   - In container / normal mode: <kbd>Escape</kbd> dismisses.
3. **Key Separation**:
   - In task lists: <kbd>Enter</kbd> expands/collapses task details. <kbd>Space</kbd> toggles completion (`done`).
4. **Layout Safety**: Wrap profile pills (`Flow`) and elide long strings (`Text.ElideRight`) to avoid horizontal overflow.

## Branching & Release Lifecycle Standards
- **`main` (Production Branch)**:
  - Holds exclusively verified, stable release versions.
  - End-users and Omarchy marketplace tooling (`omarchy plugin add`, `omarchy plugin update`) clone and track `main`.
  - Never commit direct feature work or work-in-progress to `main`.
- **`develop` (Integration Trunk)**:
  - The default base branch for ongoing development, integrations, and local staging.
  - All feature and task work branches off `develop` and merges back into `develop`.
- **`feat/*` and `fix/*` (Feature / Bugfix Branches)**:
  - Create short-lived branches off `develop`: `git checkout -b feat/<name> develop`.
  - All validations (`npm run check`) must pass with zero errors and zero warnings before merging back into `develop`.
- **Release Cadence**:
  - Releases are cut by merging `develop` into `main` after full validation (`npm run test:docker`).
- **Emergency Hotfixes**:
  - Critical production bugs branch directly off `main` (`fix/<issue>`), merge to `main`, and are back-merged into `develop`.

## Code Quality & Commit Standards
- **Validation**: Always run `npm run check` (which runs `deno check TodoStore.js PanelLogic.js GitSync.js`, `qmllint *.qml ui/*.qml`, `omarchy plugin validate .`, and `tests/*.test.mts`). All checks must pass with zero errors and zero warnings.
- **Fast Iteration**: Use `npm run test:fast` (< 0.8s) during active editing to run all unit and static QML tests.
- **Automated Tests**: Update and add assertions to the corresponding test file:
  - `tests/TodoStore.test.mts` for data store, urgency ladder, sorting, and storage.
  - `tests/PanelLogic.test.mts` for keyboard navigation state machine and shortcuts.
  - `tests/qml-static.test.mts` for QML AST, UI ergonomics, tooltip badges, and IPC contracts.
  - `tests/qml-core.test.mts` for Quickshell headless offscreen ladder mounting.
  - `tests/qml-theme.test.mts` for dynamic theme changes and palette switches.
  - `tests/qml-windowed.test.mts` for interactive layer-shell motion, drawer, and notes harnesses.
- **Live Reload**: After code changes pass checks, run `omarchy-restart-shell` to update the running environment.
- **Commit Signing**: All local git commits must be signed using SSH: `git commit -S -m "..."`.
- **No Remote Tags**: Do not create or push release tags (`v*`).
- **Preview Tool Conservation**: Do not execute `./tools/render-preview.sh` during development unless specifically requested by the user.

## Test Tiers

Tests are split by what they need, so CI can run the maximum that works in a bare container without pretending to cover the rest.

| Tier | Test File | Needs | Runs in CI |
|---|---|---|---|
| Unit | `tests/TodoStore`, `tests/GitSync`, `tests/PanelLogic`, `tests/detect-context` | Node only | ✅ |
| Static QML | `tests/qml-static.test.mts` — "Static QML Analysis", "IPC Contract" | repo files only | ✅ |
| QML runtime, no compositor | `tests/qml-core.test.mts` — "Quickshell Core (no compositor)" | quickshell + omarchy `shell/Commons`,`shell/Ui` | ✅ |
| Theme watch | `tests/qml-theme.test.mts` — "ArdoiseIcon: warning color …" | quickshell + `shell/Commons` | ✅ |
| QML runtime, windowed | `tests/qml-windowed.test.mts` — "Quickshell Headless Lifecycle [local-only]" | wlr-layer-shell compositor | ❌ |
| Live shell | `tests/qml-live-shell.test.mts` — "Live Shell IPC [local-only]" | running `omarchy-shell` | ❌ |

**Local-only is a hard requirement, not an oversight.** `QuickAdd.qml` is a `WlrLayer.Overlay`; with `QT_QPA_PLATFORM=offscreen` Quickshell reports `No PanelWindow backend loaded` and the config never loads. The window-free core test covers the other three top-level components plus the whole `ui/` library and asserts real resolved state (`rung=overdue count=2 role=warning` against a seeded store), so the CI ceiling is a coverage decision, not a technical limit we hit.

### Silent skips are a bug

Guards call `t.skip()` when a prerequisite is missing — but **Deno reports skips as `ok`**, and its permission model makes `execSync` throw under `--allow-read`, turning *every* subprocess-backed test into a skip. That is why CI runs the suite with **Node** (no permission model) rather than Deno.

To stop the class of bug recurring, any prerequisite **CI is expected to provide** must **throw under `CI=1`** instead of skipping. Genuinely local-only tests skip in CI with a reason naming what is missing. If you add a test that needs a new tool, decide which column it belongs in and make the guard match.

Reproduce CI exactly before pushing:

```bash
npm run test:docker    # arch container, CI=1, pinned omarchy
```

### Bumping the Omarchy pin

CI fetches `shell/Commons`, `shell/Ui` and `bin/omarchy-plugin-validate` from a **pinned commit**, defined once in [`tools/omarchy-ref`](./tools/omarchy-ref) and shared by `.github/workflows/ci.yml` and `tools/ci-local.sh`. It is pinned rather than tracking the `quattro` branch so upstream changes cannot turn this repo's CI red for reasons unrelated to the change under test.

To move it: update the SHA, then run `npm run test:docker`. Expect the newest-Omarchy path to break first — that is the signal you want.

## Task & Shell IPC Standards
- **Use `omarchy-shell` for Task State**: Never use ad-hoc Python, node, or bash scripts to inspect or mutate `~/.config/omarchy/tablerase.ardoise/todos.json`. Instead, interact directly through the plugin's native IPC handler via `omarchy-shell`:
  - List tasks: `omarchy-shell tablerase.ardoise list`
  - Get task by ID: `omarchy-shell tablerase.ardoise get "<id>"`
  - Get count: `omarchy-shell tablerase.ardoise count`
  - Add task: `omarchy-shell tablerase.ardoise add "<title> [#profile]"`
  - Add task with details: `omarchy-shell tablerase.ardoise addDetailed "<title>" "<notes>" "<reminder>"`
  - Search profiles: `omarchy-shell tablerase.ardoise searchProfiles "<query>"`
  - Toggle completion: `omarchy-shell tablerase.ardoise toggleTodo "<id>"`
  - Update task: `omarchy-shell tablerase.ardoise update "<id>" '{"reminder": "..."}'`
  - Remove task: `omarchy-shell tablerase.ardoise remove "<id>"`
  - Switch active profile: `omarchy-shell tablerase.ardoise setProfile "<profile>"`
  - List profiles: `omarchy-shell tablerase.ardoise profiles`
  - Clear completed: `omarchy-shell tablerase.ardoise clear`
  - Toggle / Open / Close UI: `omarchy-shell tablerase.ardoise toggle` (or `open` / `close`)
  - Search git snapshots: `omarchy-shell tablerase.ardoise gitSearch "<query>"`

