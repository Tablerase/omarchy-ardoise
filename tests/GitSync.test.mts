import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const GitSync = require("../GitSync.js");

const {
  extractDeviceName,
  extractCleanMessage,
  extractPendingCount,
  parseGitLog,
  buildCommitMessage,
  formatRelativeTime,
  isValidRemoteUrl
} = GitSync;

test("extractDeviceName: extracts device bracket tag or falls back to author", () => {
  assert.equal(extractDeviceName("[omarchy] Auto-save: new task", "author-x"), "omarchy");
  assert.equal(extractDeviceName("[ThinkPad-X1] Commit title", "author-y"), "ThinkPad-X1");
  assert.equal(extractDeviceName("Plain commit message", "author-z"), "author-z");
  assert.equal(extractDeviceName("", "fallback"), "fallback");
});

test("extractCleanMessage: removes device tag from commit message", () => {
  assert.equal(extractCleanMessage("[omarchy] Auto-save: added task"), "Auto-save: added task");
  assert.equal(extractCleanMessage("[laptop] Manual backup"), "Manual backup");
  assert.equal(extractCleanMessage("No tag commit"), "No tag commit");
});

test("extractPendingCount: extracts pending task count if formatted", () => {
  assert.equal(extractPendingCount("[omarchy] Auto-save: added task (14 pending)"), 14);
  assert.equal(extractPendingCount("[laptop] Task update (0 pending)"), 0);
  assert.equal(extractPendingCount("No pending count in message"), undefined);
});

test("buildCommitMessage: constructs device-tagged commit message", () => {
  assert.equal(
    buildCommitMessage("omarchy", "Add task: buy milk", 5),
    "[omarchy] Add task: buy milk (5 pending)"
  );
  assert.equal(
    buildCommitMessage("laptop", "Clear completed"),
    "[laptop] Clear completed"
  );
  assert.equal(
    buildCommitMessage("", "Fallback test"),
    "[unknown] Fallback test"
  );
});

test("parseGitLog: parses standard git log format into structured snapshots", () => {
  const rawLog = `4a57f9876543210|omarchy|rcutte@omarchy|1790200000|[omarchy] Auto-save: add task (12 pending)
b2c3d4e56789012|thinkpad|rcutte@thinkpad|1790100000|[thinkpad] Completed 3 tasks (9 pending)
c3d4e5f67890123|dev-box|rcutte@dev|1790000000|Initial task repository`;

  const snapshots = parseGitLog(rawLog);
  assert.equal(snapshots.length, 3);

  assert.equal(snapshots[0].hash, "4a57f9876543210");
  assert.equal(snapshots[0].shortHash, "4a57f98");
  assert.equal(snapshots[0].author, "omarchy");
  assert.equal(snapshots[0].deviceName, "omarchy");
  assert.equal(snapshots[0].cleanMessage, "Auto-save: add task (12 pending)");
  assert.equal(snapshots[0].pendingCount, 12);
  assert.equal(snapshots[0].timestamp, 1790200000 * 1000);

  assert.equal(snapshots[1].deviceName, "thinkpad");
  assert.equal(snapshots[1].pendingCount, 9);

  assert.equal(snapshots[2].deviceName, "dev-box");
  assert.equal(snapshots[2].cleanMessage, "Initial task repository");
  assert.equal(snapshots[2].pendingCount, undefined);
});

test("formatRelativeTime: formats relative times correctly", () => {
  const now = 1000000000000;
  assert.equal(formatRelativeTime(now - 10000, now), "just now");
  assert.equal(formatRelativeTime(now - 5 * 60 * 1000, now), "5m ago");
  assert.equal(formatRelativeTime(now - 3 * 3600 * 1000, now), "3h ago");
  assert.equal(formatRelativeTime(now - 25 * 3600 * 1000, now), "yesterday");
  assert.equal(formatRelativeTime(now - 3 * 24 * 3600 * 1000, now), "3d ago");
});

test("isValidRemoteUrl: validates git remote URLs", () => {
  assert.ok(isValidRemoteUrl("git@github.com:tablerase/ardoise-data.git"));
  assert.ok(isValidRemoteUrl("git@gitlab.com:user/tasks.git"));
  assert.ok(isValidRemoteUrl("https://github.com/tablerase/ardoise-data.git"));
  assert.ok(isValidRemoteUrl("ssh://git@github.com/user/repo.git"));

  assert.ok(!isValidRemoteUrl("not-a-url"));
  assert.ok(!isValidRemoteUrl("ftp://invalid.com/repo.git"));
  assert.ok(!isValidRemoteUrl(""));
});
