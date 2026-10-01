import test from "node:test";
import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import { findOnPath } from "./helpers/qml-test-utils.mts";

test("Live Shell IPC [local-only]: Omarchy shell responds to summon, hide, and toggle", (t) => {
  // LOCAL-ONLY BY DESIGN. This needs a live omarchy-shell on a compositor,
  // which a CI container cannot provide. Cross-platform coverage of the same
  // contract lives in the "IPC Contract" static test, which checks the
  // documented command surface against the IpcHandler on every platform.
  if (process.env.CI) {
    t.skip("local-only: requires a live omarchy-shell; the static IPC Contract test covers this in CI");
    return;
  }

  // Check if omarchy-shell is installed
  if (!findOnPath("omarchy-shell")) {
    t.skip("omarchy-shell binary not found; skipping live shell IPC test");
    return;
  }

  // Ping running shell
  try {
    const ping = execSync("omarchy-shell shell ping 2>/dev/null", { encoding: "utf8" }).trim();
    if (ping !== "ok") {
      t.skip("Omarchy shell is not actively responding to ping; skipping live shell IPC test");
      return;
    }
  } catch {
    t.skip("Omarchy shell is not currently running; skipping live shell IPC test");
    return;
  }

  // Verify summon
  const summonResult = execSync("omarchy-shell shell summon tablerase.ardoise '{}'", {
    encoding: "utf8"
  }).trim();
  assert.equal(summonResult, "ok", "Shell summon tablerase.ardoise should return 'ok'");

  // Verify hide
  execSync("omarchy-shell shell hide tablerase.ardoise", { encoding: "utf8" });

  // Verify toggle (opens then closes)
  execSync("omarchy-shell shell toggle tablerase.ardoise '{}'", { encoding: "utf8" });
  execSync("omarchy-shell shell hide tablerase.ardoise", { encoding: "utf8" });
});
