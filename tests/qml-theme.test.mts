import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { findOnPath, repoDir } from "./helpers/qml-test-utils.mts";

test("ArdoiseIcon: warning color reads the theme's yellow and follows a live theme switch", async (t) => {
  const quickshellPath = findOnPath("quickshell");
  if (!quickshellPath) {
    if (process.env.CI) throw new Error("quickshell must be installed in CI");
    t.skip("quickshell binary not found on system PATH; skipping warning-color runtime test");
    return;
  }

  const omarchyPath = process.env.OMARCHY_PATH || "/usr/share/omarchy";
  const commonsDir = path.join(omarchyPath, "shell", "Commons");
  if (!fs.existsSync(commonsDir)) {
    if (process.env.CI) {
      throw new Error("Omarchy shell Commons module must be provided in CI (OMARCHY_PATH=" + omarchyPath + ")");
    }
    t.skip("Omarchy shell Commons module not found; skipping warning-color runtime test");
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-warn-test-"));
  const currentDir = path.join(tmpDir, ".local", "state", "omarchy", "current");
  const currentThemeDir = path.join(currentDir, "theme");
  const themeNameFile = path.join(currentDir, "theme.name");

  // Mirrors omarchy-theme-set: colors.toml lives inside the swapped theme dir,
  // theme.name is a regular file written last beside it.
  const writeColors = (yellow: string) =>
    fs.writeFileSync(
      path.join(currentThemeDir, "colors.toml"),
      `mode = "light"\naccent = "#1e66f5"\nred = "#d20f39"\nyellow = "${yellow}"\nbackground = "#eff1f5"\nforeground = "#4c4f69"\n`,
      "utf8"
    );

  let child: ReturnType<typeof spawn> | null = null;
  try {
    fs.mkdirSync(currentThemeDir, { recursive: true });
    fs.symlinkSync(commonsDir, path.join(tmpDir, "Commons"));
    fs.symlinkSync(repoDir, path.join(tmpDir, "plugin"));
    writeColors("#df8e1d");
    fs.writeFileSync(themeNameFile, "catppuccin-latte", "utf8");

    // Import through the plugin module path so ArdoiseIcon's own
    // `../TodoStore.js` relative import still resolves.
    const harnessQml = `
import QtQuick
import Quickshell
import "plugin/ui" as Ui

ShellRoot {
    id: root

    Ui.ArdoiseIcon {
        id: icon
        store: null
        forcedKey: "overdue"
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: console.log("[TEST] before=" + ("" + icon.warningColor))
    }
    Timer {
        interval: 2600
        running: true
        repeat: false
        onTriggered: {
            console.log("[TEST] after=" + ("" + icon.warningColor));
            Qt.exit(0);
        }
    }
}
`;
    fs.writeFileSync(path.join(tmpDir, "shell.qml"), harnessQml, "utf8");

    let out = "";
    child = spawn(quickshellPath, ["-p", tmpDir, "--no-color"], {
      env: {
        ...process.env,
        HOME: tmpDir,
        QT_QPA_PLATFORM: process.env.WAYLAND_DISPLAY ? undefined : "offscreen"
      }
    });
    child.stdout?.on("data", (d) => { out += String(d); });
    child.stderr?.on("data", (d) => { out += String(d); });

    // While the component is live, perform a theme switch the way
    // omarchy-theme-set does: replace colors.toml, then rewrite theme.name.
    await new Promise((r) => setTimeout(r, 1400));
    writeColors("#f9e2af");
    fs.writeFileSync(themeNameFile, "catppuccin", "utf8");

    let timerId: NodeJS.Timeout | undefined;
    const closed = new Promise<void>((resolve) => child!.once("close", () => resolve()));
    const timedOut = new Promise<void>((resolve) => {
      timerId = setTimeout(resolve, 12000);
      timerId.unref?.();
    });
    await Promise.race([closed, timedOut]);
    if (timerId) clearTimeout(timerId);
    if (child.exitCode === null) child.kill("SIGKILL");

    assert.ok(!/is not a type|ReferenceError|Type .* unavailable/i.test(out),
      "warning-color harness reported QML errors:\n" + out);

    const before = /\[TEST\] before=(\S+)/.exec(out)?.[1];
    const after = /\[TEST\] after=(\S+)/.exec(out)?.[1];
    assert.ok(before, "harness did not report `before`:\n" + out);
    assert.ok(after, "harness did not report `after`:\n" + out);

    // The theme's yellow must be read verbatim - not the hardcoded #df8e1d
    // fallback, and not the theme's red.
    assert.equal(before.toLowerCase(), "#df8e1d",
      "initial warning color should equal the theme's yellow key");

    // If the theme.name watch works, the live component re-reads colors.toml.
    // This guards the failure mode where watching colors.toml directly goes
    // deaf once omarchy-theme-set replaces its inode.
    assert.equal(after.toLowerCase(), "#f9e2af",
      "warning color should follow a live theme switch (theme.name watch)");
  } finally {
    if (child && child.exitCode === null) child.kill("SIGKILL");
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
