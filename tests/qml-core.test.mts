import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { findOnPath, repoDir } from "./helpers/qml-test-utils.mts";

// Both tests in this tier need the same three prerequisites: quickshell,
// Omarchy's Commons/Ui modules, and a writable sandbox. Anything CI is
// expected to provide must THROW under CI=1 rather than skip, otherwise a
// green CI would silently stop covering the real mounted component.
function requireShellEnv(t: { skip: (msg: string) => void }) {
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    if (process.env.CI) throw new Error("quickshell must be installed in CI");
    t.skip("quickshell binary not found on system PATH");
    return null;
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
    return null;
  }

  return { quickshellPath, commonsDir, uiDir };
}

function createSandbox(commonsDir: string, uiDir: string) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-core-test-"));
  fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
  fs.symlinkSync(uiDir, path.join(tmpDir, "Ui"));
  fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));

  const dataDir = path.join(tmpDir, ".config", "omarchy", "tablerase.ardoise");
  fs.mkdirSync(dataDir, { recursive: true });
  return { tmpDir, dataDir };
}

function seedStore(dataDir: string, todos: unknown[]) {
  const store = {
    version: 1,
    activeProfile: "personal",
    profiles: ["personal", "work"],
    todos
  };
  fs.writeFileSync(path.join(dataDir, "todos.json"), JSON.stringify(store), "utf8");
  fs.writeFileSync(
    path.join(dataDir, "todos-archive.json"),
    JSON.stringify({ version: 1, archived: [] }),
    "utf8"
  );
}

function runHarness(
  quickshellPath: string,
  sandbox: { tmpDir: string; dataDir: string },
  harnessQml: string
) {
  fs.writeFileSync(path.join(sandbox.tmpDir, "shell.qml"), harnessQml, "utf8");

  const qsResult = spawnSync(quickshellPath, ["-p", sandbox.tmpDir, "--no-color"], {
    encoding: "utf8",
    timeout: 20000,
    env: {
      ...process.env,
      HOME: sandbox.tmpDir,
      ARDOISE_DATA_DIR: sandbox.dataDir,
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

  return output;
}

function pick(output: string, key: string) {
  return new RegExp("\\[TEST\\] " + key + "=(\\S+)").exec(output)?.[1];
}

test("Quickshell Core (no compositor): BarWidget, PanelContent and Service mount and resolve the icon ladder", (t) => {
  // Runs everywhere, including CI: no layer-shell, no Wayland. Only
  // QuickAdd.qml needs a compositor (it is a WlrLayer.Overlay), so this
  // harness mounts the window-free components and asserts real resolved
  // state. The windowed lifecycle is covered by the local-only test.
  const env = requireShellEnv(t);
  if (!env) return;

  const sandbox = createSandbox(env.commonsDir, env.uiDir);
  try {
    // Seed two late tasks and one undated so the ladder must resolve to
    // `overdue` and the badge to the overdue subset (2), not the total (3).
    // Instants are absolute and far from any timezone edge, because
    // getTaskUrgencyBreakdown computes end-of-day in LOCAL time.
    const now = Date.now();
    const iso = (ms: number) => new Date(ms).toISOString();
    seedStore(sandbox.dataDir, [
      { id: 1, title: "Late", done: false, profile: "personal", reminder: iso(now - 3 * 3600 * 1000) },
      { id: 2, title: "Someday", done: false, profile: "personal", reminder: null },
      { id: 3, title: "Also late", done: false, profile: "work", reminder: iso(now - 5 * 3600 * 1000) }
    ]);

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
    const output = runHarness(env.quickshellPath, sandbox, harnessQml);

    assert.equal(pick(output, "done"), "1", "core harness did not run to completion:\n" + output);
    assert.equal(pick(output, "pending"), "3", "bar should report total pending tasks");
    assert.equal(pick(output, "panelTasks"), "3", "PanelContent should load the seeded store");

    // The ladder invariant, asserted through live mounted components: two
    // tasks are late, so the rung is `overdue` and the badge shows that
    // subset (2) rather than the 3 pending tasks.
    assert.equal(pick(output, "rung"), "overdue", "two late tasks should resolve to the overdue rung");
    assert.equal(pick(output, "count"), "2", "badge must show the overdue subset, not total pending");
    assert.equal(pick(output, "role"), "warning", "the late rung must use the warning role, never urgent red");
  } finally {
    fs.rmSync(sandbox.tmpDir, { recursive: true, force: true });
  }
});

test("Quickshell Core (no compositor): the expanded drawer reveals a long title by wrapping, collapsed stays elided", (t) => {
  // The regression this pins: the drawer used to keep the title on a single
  // elided line, so a long title stayed truncated even with the task open.
  // The title now wraps only while expanded, and the checkbox has to stay on
  // the FIRST line rather than the paragraph's vertical center. All of that
  // is measured geometry, so it can only be asserted against a real mount.
  const env = requireShellEnv(t);
  if (!env) return;

  const sandbox = createSandbox(env.commonsDir, env.uiDir);
  try {
    const longTitle =
      "Reveal the whole title of this long task inside the expanded drawer instead of truncating it at the panel edge";
    seedStore(sandbox.dataDir, [
      { id: 1, title: longTitle, done: false, profile: "personal", reminder: null },
      { id: 2, title: "Short", done: false, profile: "personal", reminder: null }
    ]);

    // PanelContent is a plain Item: the real panel sizes it, so the harness
    // has to. 420px is the real panel order of magnitude.
    const harnessQml = `
import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
    id: root

    Plugin.Service { id: svc }
    Plugin.BarWidget { id: barWidget }
    Plugin.PanelContent { id: panelContent; barWidget: barWidget; width: 420 }

    function walk(item, out) {
        var kids = item.children
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (!k) continue
            out.push(k)
            if (k.children) walk(k, out)
        }
        return out
    }

    // The delegate's ids are scoped to the Repeater, so the title is found by
    // its resolved text. Only Text items expose both text and lineCount.
    function titleStartingWith(prefix) {
        var all = walk(panelContent, [])
        for (var i = 0; i < all.length; i++) {
            if (all[i].text !== undefined && all[i].lineCount !== undefined &&
                String(all[i].text).indexOf(prefix) === 0) {
                return all[i]
            }
        }
        return null
    }

    // The checkbox is the only sibling of the title that carries 'checked'.
    function checkboxOf(title) {
        if (!title || !title.parent) return null
        var kids = title.parent.children
        for (var i = 0; i < kids.length; i++) {
            if (kids[i] && kids[i].checked !== undefined) return kids[i]
        }
        return null
    }

    function report(tag) {
        var t = titleStartingWith("Reveal")
        if (!t) {
            console.log("[TEST] " + tag + "=NOT_FOUND")
            return
        }
        var c = checkboxOf(t)
        // Distance between the checkbox center and the center of the title's
        // first line. 0 means the checkbox rides the first line; a positive
        // value would mean it drifted to the wrapped block's center.
        var firstLineCenter = t.y + t.height / t.lineCount / 2
        var delta = c ? Math.round((c.y + c.height / 2) - firstLineCenter) : -99
        var short = titleStartingWith("Short")
        console.log("[TEST] " + tag + "=" + t.lineCount
            + "/" + (t.truncated ? 1 : 0)
            + "/" + delta
            + "/" + (short ? short.lineCount : -1))
    }

    Timer {
        interval: 900
        running: true
        onTriggered: report("collapsed")
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: panelContent.expandedTaskId = 1
    }

    Timer {
        interval: 2200
        running: true
        onTriggered: report("expanded")
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            console.log("[TEST] done=1")
            Qt.exit(0)
        }
    }
}
`;
    const output = runHarness(env.quickshellPath, sandbox, harnessQml);

    assert.equal(pick(output, "done"), "1", "title harness did not run to completion:\n" + output);
    // lineCount/truncated/checkboxFirstLineDelta/shortTitleLineCount
    assert.equal(
      pick(output, "collapsed"),
      "1/1/0/1",
      "collapsed row must keep the title on one elided line, centered checkbox, short title unwrapped:\n" + output
    );
    assert.match(
      pick(output, "expanded") || "",
      /^[2-9][0-9]*\/0\/0\/1$/,
      "expanded drawer must wrap the long title into several untruncated lines with the checkbox on the first line, leaving a short title on one line:\n" + output
    );
  } finally {
    fs.rmSync(sandbox.tmpDir, { recursive: true, force: true });
  }
});
