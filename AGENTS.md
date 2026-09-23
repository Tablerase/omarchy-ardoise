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

## Code Quality & Commit Standards
- **Validation**: Always run `npm run check` (which runs `deno check TodoStore.js`, `qmllint *.qml`, `omarchy plugin validate .`, and `tests/*.test.mts`). All checks must pass with zero errors and zero warnings.
- **Automated Tests**: Update and add assertions to `tests/qml-runtime.test.mts` and `tests/TodoStore.test.mts` to prevent motion regressions.
- **Commit Signing**: All local git commits must be signed using SSH: `git commit -S -m "..."`.
- **No Remote Tags**: Do not create or push release tags (`v*`).
- **Preview Tool Conservation**: Do not execute `./tools/render-preview.sh` during development unless specifically requested by the user.
