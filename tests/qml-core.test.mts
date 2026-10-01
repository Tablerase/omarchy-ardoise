import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { findOnPath, repoDir } from "./helpers/qml-test-utils.mts";

test("Quickshell Core (no compositor): BarWidget, PanelContent and Service mount and resolve the icon ladder", (t) => {
  // Runs everywhere, including CI: no layer-shell, no Wayland. Only
  // QuickAdd.qml needs a compositor (it is a WlrLayer.Overlay), so this
  // harness mounts the window-free components and asserts real resolved
  // state. The windowed lifecycle is covered by the local-only test.
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    if (process.env.CI) throw new Error("quickshell must be installed in CI");
    t.skip("quickshell binary not found on system PATH");
    return;
  }

  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  const uiDir = path.join(omarchyPath, "shell", "Ui");
  if (!fs.existsSync(commonsDir) || !fs.existsSync(uiDir)) {
    if (process.env.CI) {
      throw new Error(
        "Omarchy shell Commons/Ui modules must be provided in CI (OMARCHY_PATH=" + omarchyPath + ")"
      );
    }
    t.skip("Omarchy shell Commons/Ui modules not found at " + omarchyPath);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-core-test-"));
  try {
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

    const testConfigDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
    fs.mkdirSync(testConfigDir, { recursive: true });

    // Seed two late tasks and one undated so the ladder must resolve to
    // `overdue` and the badge to the overdue subset (2), not the total (3).
    // Instants are absolute and far from any timezone edge, because
    // getTaskUrgencyBreakdown computes end-of-day in LOCAL time.
    const now = Date.now();
    const iso = (ms: number) => new Date(ms).toISOString();
    const seeded = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal", "work"],
      todos: [
        { id: 1, title: "Late", done: false, profile: "personal", reminder: iso(now - 3 * 3600 * 1000) },
        { id: 2, title: "Someday", done: false, profile: "personal", reminder: null },
        { id: 3, title: "Also late", done: false, profile: "work", reminder: iso(now - 5 * 3600 * 1000) }
      ]
    };
    fs.writeFileSync(path.join(testConfigDir, "todos.json"), JSON.stringify(seeded), "utf8");
    fs.writeFileSync(
      path.join(testConfigDir, "todos-archive.json"),
      JSON.stringify({ version: 1, archived: [] }),
      "utf8"
    );

    // No WlrLayer here, so no PanelWindow backend is required.
    const harnessQml = `
import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
    id: root

    Plugin.Service { id: svc }
    Plugin.BarWidget { id: barWidget }
    Plugin.PanelContent { id: panelContent; barWidget: barWidget }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            console.log("[TEST] pending=" + barWidget.pendingCount);
            console.log("[TEST] rung=" + barWidget.ladderState.key);
            console.log("[TEST] count=" + barWidget.ladderState.count);
            console.log("[TEST] role=" + barWidget.ladderState.role);
            console.log("[TEST] panelTasks=" + (panelContent.store.todos ? panelContent.store.todos.length : -1));
            console.log("[TEST] done=1");
            Qt.exit(0);
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    const qsResult = spawnSync(quickshellPath, ["-p", tmpDir, "--no-color"], {
      encoding: "utf8",
      timeout: 15000,
      env: {
        ...process.env,
        HOME: tmpDir,
        ARDOISE_DATA_DIR: testConfigDir,
        // Never inherit a real display: the point is to prove the core
        // mounts without a compositor.
        WAYLAND_DISPLAY: "",
        QT_QPA_PLATFORM: "offscreen"
      }
    });

    const output = (qsResult.stdout || "") + "\n" + (qsResult.stderr || "");

    // BarWidget lazily Loads Panel.qml, a wlr-layer-shell surface built on
    // Ui.KeyboardPanel. With no compositor it can only warn - it cannot
    // resolve the PanelWindow backend or the KeyboardPanel type. That is a
    // property of running without a display, not a defect, and the
    // windowed path is covered by the local-only lifecycle test.
    //
    // Isolate exactly those known-benign lines. Anything else complaining
    // about a backend or an unresolved type is still a failure.
    const isCompositorOnly = (line: string) =>
      /PanelWindow backend/i.test(line) || /KeyboardPanel/.test(line) || /@plugin\/Panel\.qml/.test(line);

    const unexpectedBackend = output
      .split("\n")
      .filter((line) => /PanelWindow backend/i.test(line))
      .filter((line) => !/KeyboardPanel|@plugin\/Panel\.qml/.test(line))
      .join("\n");
    assert.equal(
      unexpectedBackend.trim(),
      "",
      "Unexpected PanelWindow backend errors outside the known Panel.qml path:\n" + unexpectedBackend
    );

    const sanitized = output
      .split("\n")
      .filter((line) => !isCompositorOnly(line))
      .join("\n");

    assert.ok(
      !/is not a type|ReferenceError|Type .* unavailable|Cannot read property/i.test(sanitized),
      "Core harness reported QML errors:\n" + output
    );
    assert.ok(
      !/Binding loop detected for property/i.test(sanitized),
      "Core harness reported a binding loop:\n" + output
    );
    // Unconditional: a failed load must never be able to pass quietly.
    assert.equal(
      qsResult.status,
      0,
      "Core harness failed with exit code " + qsResult.status + ":\n" + output
    );

    const pick = (k: string) => new RegExp("\\[TEST\\] " + k + "=(\\S+)").exec(output)?.[1];

    assert.equal(pick("done"), "1", "core harness did not run to completion:\n" + output);
    assert.equal(pick("pending"), "3", "bar should report total pending tasks");
    assert.equal(pick("panelTasks"), "3", "PanelContent should load the seeded store");

    // The ladder invariant, asserted through live mounted components: two
    // tasks are late, so the rung is `overdue` and the badge shows that
    // subset (2) rather than the 3 pending tasks.
    assert.equal(pick("rung"), "overdue", "two late tasks should resolve to the overdue rung");
    assert.equal(pick("count"), "2", "badge must show the overdue subset, not total pending");
    assert.equal(pick("role"), "warning", "the late rung must use the warning role, never urgent red");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
