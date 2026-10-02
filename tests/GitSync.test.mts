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
  isValidRemoteUrl,
  filterSnapshots,
  diagnoseGitSyncError
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

// Shared fixture for filterSnapshots tests
const FIXTURE_SNAPSHOTS = [
  {
    hash: "aabbcc1122334455",
    shortHash: "aabbcc1",
    author: "rcutte",
    email: "rcutte@omarchy",
    timestamp: 1790200000000,
    message: "[omarchy] Auto-save: added task (12 pending)",
    cleanMessage: "Auto-save: added task (12 pending)",
    deviceName: "omarchy",
    pendingCount: 12
  },
  {
    hash: "ddeeff6677889900",
    shortHash: "ddeeff6",
    author: "pierre",
    email: "pierre@thinkpad",
    timestamp: 1790100000000,
    message: "[thinkpad] Completed 3 tasks (9 pending)",
    cleanMessage: "Completed 3 tasks (9 pending)",
    deviceName: "thinkpad",
    pendingCount: 9
  },
  {
    hash: "112233aabbccddee",
    shortHash: "112233a",
    author: "dev-box",
    email: "dev@dev-box",
    timestamp: 1790000000000,
    message: "Initial task repository",
    cleanMessage: "Initial task repository",
    deviceName: "dev-box",
    pendingCount: undefined
  }
];

test("filterSnapshots: empty / whitespace query returns original array unchanged", () => {
  assert.strictEqual(filterSnapshots(FIXTURE_SNAPSHOTS, ""), FIXTURE_SNAPSHOTS);
  assert.strictEqual(filterSnapshots(FIXTURE_SNAPSHOTS, "   "), FIXTURE_SNAPSHOTS);
  assert.strictEqual(filterSnapshots(FIXTURE_SNAPSHOTS, null as any), FIXTURE_SNAPSHOTS);
  assert.strictEqual(filterSnapshots(FIXTURE_SNAPSHOTS, undefined as any), FIXTURE_SNAPSHOTS);
});

test("filterSnapshots: returns [] safely for invalid snapshot input", () => {
  assert.deepStrictEqual(filterSnapshots(null as any, "foo"), []);
  assert.deepStrictEqual(filterSnapshots(undefined as any, "foo"), []);
  assert.deepStrictEqual(filterSnapshots("not-an-array" as any, "foo"), []);
});

test("filterSnapshots: single-token match on cleanMessage", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "auto-save");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "omarchy");
});

test("filterSnapshots: single-token match on raw message fallback", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "repository");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "dev-box");
});

test("filterSnapshots: device name match via plain token", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "thinkpad");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "thinkpad");
});

test("filterSnapshots: device name match via #device token syntax", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "#omarchy");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "omarchy");
});

test("filterSnapshots: device name match via [device] token syntax", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "[thinkpad]");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "thinkpad");
});

test("filterSnapshots: shortHash substring match", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "aabbcc1");
  assert.equal(result.length, 1);
  assert.equal(result[0].shortHash, "aabbcc1");
});

test("filterSnapshots: full hash prefix match", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "ddeeff66778");
  assert.equal(result.length, 1);
  assert.equal(result[0].shortHash, "ddeeff6");
});

test("filterSnapshots: author match", () => {
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "pierre");
  assert.equal(result.length, 1);
  assert.equal(result[0].author, "pierre");
});

test("filterSnapshots: multi-token AND matching (all tokens must match)", () => {
  // Both tokens must match the same snapshot
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "thinkpad completed");
  assert.equal(result.length, 1);
  assert.equal(result[0].deviceName, "thinkpad");
});

test("filterSnapshots: multi-token query with no matches", () => {
  // "omarchy" matches one snapshot but "completed" does not -> 0 results
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "omarchy completed");
  assert.equal(result.length, 0);
});

test("filterSnapshots: case-insensitive matching", () => {
  assert.equal(filterSnapshots(FIXTURE_SNAPSHOTS, "OMARCHY").length, 1);
  assert.equal(filterSnapshots(FIXTURE_SNAPSHOTS, "AUTO-SAVE").length, 1);
  assert.equal(filterSnapshots(FIXTURE_SNAPSHOTS, "INITIAL").length, 1);
});

test("filterSnapshots: query matching multiple snapshots", () => {
  // "pending" appears in the cleanMessage of two snapshots
  const result = filterSnapshots(FIXTURE_SNAPSHOTS, "pending");
  assert.equal(result.length, 2);
});

test("filterSnapshots: empty snapshot array returns []", () => {
  assert.deepStrictEqual(filterSnapshots([], "omarchy"), []);
});

test("diagnoseGitSyncError: handles passphrase prompt output", () => {
  const output = "Enter passphrase for key '/home/user/.ssh/id_ed25519':\nPermission denied (publickey).";
  assert.equal(
    diagnoseGitSyncError(output, 1),
    "SSH key locked. Run 'ssh-add' in terminal to load key."
  );
});

test("diagnoseGitSyncError: handles Permission denied (publickey)", () => {
  const output = "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.";
  assert.equal(
    diagnoseGitSyncError(output, 1),
    "SSH auth failed (Permission denied). Run 'ssh-add' or check GitHub keys."
  );
});

test("diagnoseGitSyncError: handles couldn't find remote ref (empty repo)", () => {
  const output = "fatal: couldn't find remote ref main";
  assert.equal(
    diagnoseGitSyncError(output, 128),
    "Remote branch not found (empty remote repository)."
  );
});

test("diagnoseGitSyncError: handles network disconnection", () => {
  const output = "fatal: Could not resolve host: github.com";
  assert.equal(
    diagnoseGitSyncError(output, 1),
    "Network offline: Could not connect to remote host."
  );
});

test("diagnoseGitSyncError: handles repository not found", () => {
  const output = "ERROR: Repository not found.\nfatal: Could not read from remote repository.";
  assert.equal(
    diagnoseGitSyncError(output, 1),
    "Remote repository not found on GitHub."
  );
});

test("diagnoseGitSyncError: handles general fatal error", () => {
  const output = "fatal: unable to access 'https://github.com/repo': Failed to connect";
  assert.equal(
    diagnoseGitSyncError(output, 1),
    "Network offline: Could not connect to remote host."
  );
});

test("diagnoseGitSyncError: falls back cleanly on empty output", () => {
  assert.equal(diagnoseGitSyncError("", 1), "Sync failed (exit code 1)");
  assert.equal(diagnoseGitSyncError("", undefined), "Sync failed (check connection/auth)");
});

