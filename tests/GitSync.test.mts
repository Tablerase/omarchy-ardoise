import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const GitSync = require("../GitSync.js");
const TodoStore = require("../TodoStore.js");

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

// =============================================================================
// Remote Sync Data Preservation & Non-Regression Tests
// =============================================================================

function runSyncShellProcess(dataDir: string): { stdout: string; status: number } {
  const syncScript = `
cd "${dataDir}" && \\
if git remote get-url origin >/dev/null 2>&1; then \\
  FETCH_OUT=$(git fetch origin main 2>&1); \\
  FETCH_CODE=$?; \\
  if [ $FETCH_CODE -ne 0 ]; then \\
    if echo "$FETCH_OUT" | grep -qE "couldn't find remote ref"; then \\
      PUSH_INIT_OUT=$(git push -u origin main 2>&1); \\
      if [ $? -eq 0 ]; then \\
        echo "INITIALIZED_AND_PUSHED"; \\
      else \\
        echo "$PUSH_INIT_OUT"; \\
        exit 2; \\
      fi; \\
    else \\
      echo "$FETCH_OUT"; \\
      exit 1; \\
    fi; \\
  else \\
    LOCAL_HEAD=$(git rev-parse HEAD); \\
    REMOTE_HEAD=$(git rev-parse origin/main 2>/dev/null || echo "$LOCAL_HEAD"); \\
    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ] && git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then \\
      PUSH_OUT=$(git push origin main 2>&1); \\
      if [ $? -eq 0 ]; then \\
        echo "UP_TO_DATE"; \\
      else \\
        echo "$PUSH_OUT"; \\
        exit 3; \\
      fi; \\
    elif [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then \\
      echo "NEEDS_MERGE"; \\
    else \\
      echo "UP_TO_DATE"; \\
    fi; \\
  fi; \\
else \\
  echo "NO_REMOTE"; \\
fi
`;
  const res = spawnSync("bash", ["-c", syncScript], { encoding: "utf8" });
  return { stdout: (res.stdout || "").trim(), status: res.status ?? -1 };
}

test("sync safety: connecting an empty remote pushes local tasks without losing any local data", () => {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-sync-test-"));
  const localDir = path.join(tmpRoot, "local");
  const remoteDir = path.join(tmpRoot, "remote.git");

  try {
    fs.mkdirSync(localDir, { recursive: true });
    fs.mkdirSync(remoteDir, { recursive: true });

    // 1. Initialize bare remote repository (simulates empty GitHub repo)
    spawnSync("git", ["init", "--bare", "-b", "main", remoteDir]);

    // 2. Initialize local repository with existing tasks
    spawnSync("git", ["init", "-b", "main", localDir]);
    spawnSync("git", ["-C", localDir, "config", "user.name", "TestUser"]);
    spawnSync("git", ["-C", localDir, "config", "user.email", "test@example.com"]);
    spawnSync("git", ["-C", localDir, "config", "commit.gpgsign", "false"]);

    const initialStore = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal", "work"],
      todos: [
        { id: 101, title: "Important Local Task 1", done: false, profile: "personal", createdAt: 1000 },
        { id: 102, title: "Important Local Task 2", done: false, profile: "work", createdAt: 1001 }
      ]
    };
    fs.writeFileSync(path.join(localDir, "todos.json"), JSON.stringify(initialStore, null, 2), "utf8");
    fs.writeFileSync(path.join(localDir, "todos-archive.json"), JSON.stringify({ version: 1, archived: [] }), "utf8");

    spawnSync("git", ["-C", localDir, "add", "-A"]);
    spawnSync("git", ["-C", localDir, "commit", "-m", "[omarchy] Initial local tasks"]);

    // 3. User configures remote origin to the new empty remote
    spawnSync("git", ["-C", localDir, "remote", "add", "origin", remoteDir]);

    // 4. Run sync process
    const syncRes = runSyncShellProcess(localDir);
    assert.equal(syncRes.status, 0, `Sync should succeed on empty remote: ${syncRes.stdout}`);
    assert.equal(syncRes.stdout, "INITIALIZED_AND_PUSHED");

    // 5. Verify local data is 100% intact (NOT wiped or corrupted)
    const localStoreAfter = JSON.parse(fs.readFileSync(path.join(localDir, "todos.json"), "utf8"));
    assert.equal(localStoreAfter.todos.length, 2, "Local tasks must not disappear when connecting remote");
    assert.equal(localStoreAfter.todos[0].title, "Important Local Task 1");
    assert.equal(localStoreAfter.todos[1].title, "Important Local Task 2");

    // 6. Verify remote repository received the exact same tasks on main
    const remoteShow = spawnSync("git", ["--git-dir", remoteDir, "show", "main:todos.json"], { encoding: "utf8" });
    assert.equal(remoteShow.status, 0, "Remote must have received main branch with todos.json");
    const remoteStore = JSON.parse(remoteShow.stdout);
    assert.equal(remoteStore.todos.length, 2, "Remote must contain both pushed tasks");
    assert.equal(remoteStore.todos[0].title, "Important Local Task 1");
    assert.equal(remoteStore.todos[1].title, "Important Local Task 2");
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
});

test("sync safety: newly added local tasks are preserved and pushed incrementally to remote", () => {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-sync-inc-"));
  const localDir = path.join(tmpRoot, "local");
  const remoteDir = path.join(tmpRoot, "remote.git");

  try {
    fs.mkdirSync(localDir, { recursive: true });
    spawnSync("git", ["init", "--bare", "-b", "main", remoteDir]);

    spawnSync("git", ["init", "-b", "main", localDir]);
    spawnSync("git", ["-C", localDir, "config", "user.name", "TestUser"]);
    spawnSync("git", ["-C", localDir, "config", "user.email", "test@example.com"]);
    spawnSync("git", ["-C", localDir, "config", "commit.gpgsign", "false"]);

    let store = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal"],
      todos: [
        { id: 201, title: "Base Task 1", done: false, profile: "personal", createdAt: 1000 }
      ]
    };
    fs.writeFileSync(path.join(localDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    fs.writeFileSync(path.join(localDir, "todos-archive.json"), JSON.stringify({ version: 1, archived: [] }), "utf8");
    spawnSync("git", ["-C", localDir, "add", "-A"]);
    spawnSync("git", ["-C", localDir, "commit", "-m", "[omarchy] Base task"]);
    spawnSync("git", ["-C", localDir, "remote", "add", "origin", remoteDir]);

    // Initial sync initializes remote
    assert.equal(runSyncShellProcess(localDir).stdout, "INITIALIZED_AND_PUSHED");

    // 1. User adds a second task locally
    store = TodoStore.addTodo(store, "Second Task Added Later #work");
    fs.writeFileSync(path.join(localDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    spawnSync("git", ["-C", localDir, "add", "todos.json"]);
    spawnSync("git", ["-C", localDir, "commit", "-m", "[omarchy] Add second task"]);

    // 2. Incremental sync
    const incSync = runSyncShellProcess(localDir);
    assert.equal(incSync.status, 0, `Incremental sync must succeed: ${incSync.stdout}`);
    assert.equal(incSync.stdout, "UP_TO_DATE");

    // 3. User adds a third task locally
    store = TodoStore.addTodo(store, "Third Task Added");
    fs.writeFileSync(path.join(localDir, "todos.json"), JSON.stringify(store, null, 2), "utf8");
    spawnSync("git", ["-C", localDir, "add", "todos.json"]);
    spawnSync("git", ["-C", localDir, "commit", "-m", "[omarchy] Add third task"]);

    const thirdSync = runSyncShellProcess(localDir);
    assert.equal(thirdSync.status, 0);
    assert.equal(thirdSync.stdout, "UP_TO_DATE");

    // 4. Assert all 3 tasks remain locally intact
    const finalLocal = JSON.parse(fs.readFileSync(path.join(localDir, "todos.json"), "utf8"));
    assert.equal(finalLocal.todos.length, 3, "All 3 tasks must remain in local store");
    assert.ok(finalLocal.todos.some((t: any) => t.title === "Base Task 1"));
    assert.ok(finalLocal.todos.some((t: any) => t.title.includes("Second Task Added Later")));
    assert.ok(finalLocal.todos.some((t: any) => t.title === "Third Task Added"));

    // 5. Assert all 3 tasks were pushed to remote
    const remoteShow = spawnSync("git", ["--git-dir", remoteDir, "show", "main:todos.json"], { encoding: "utf8" });
    const finalRemote = JSON.parse(remoteShow.stdout);
    assert.equal(finalRemote.todos.length, 3, "All 3 tasks must be present in remote store");
    assert.ok(finalRemote.todos.some((t: any) => t.title === "Base Task 1"));
    assert.ok(finalRemote.todos.some((t: any) => t.title.includes("Second Task Added Later")));
    assert.ok(finalRemote.todos.some((t: any) => t.title === "Third Task Added"));
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
});

test("sync safety: multi-device divergence merges remote changes without dropping local tasks", () => {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "ardoise-sync-div-"));
  const devADir = path.join(tmpRoot, "devA");
  const devBDir = path.join(tmpRoot, "devB");
  const remoteDir = path.join(tmpRoot, "remote.git");

  try {
    fs.mkdirSync(devADir, { recursive: true });
    spawnSync("git", ["init", "--bare", "-b", "main", remoteDir]);

    // Device A starts with shared Task 1 and unique Task 2
    spawnSync("git", ["init", "-b", "main", devADir]);
    spawnSync("git", ["-C", devADir, "config", "user.name", "DeviceA"]);
    spawnSync("git", ["-C", devADir, "config", "user.email", "a@example.com"]);
    spawnSync("git", ["-C", devADir, "config", "commit.gpgsign", "false"]);

    const devAStore = {
      version: 1,
      activeProfile: "personal",
      profiles: ["personal"],
      todos: [
        { id: 301, title: "Shared Task", done: false, profile: "personal", createdAt: 1000, updatedAt: 1000 },
        { id: 302, title: "Local Task from Device A", done: false, profile: "personal", createdAt: 1001, updatedAt: 1001 }
      ]
    };
    fs.writeFileSync(path.join(devADir, "todos.json"), JSON.stringify(devAStore, null, 2), "utf8");
    fs.writeFileSync(path.join(devADir, "todos-archive.json"), JSON.stringify({ version: 1, archived: [] }), "utf8");
    spawnSync("git", ["-C", devADir, "add", "-A"]);
    spawnSync("git", ["-C", devADir, "commit", "-m", "[deviceA] Initial tasks"]);
    spawnSync("git", ["-C", devADir, "remote", "add", "origin", remoteDir]);

    // Push base commit to remote
    assert.equal(runSyncShellProcess(devADir).stdout, "INITIALIZED_AND_PUSHED");

    // Device B clones the repo and makes independent edits
    spawnSync("git", ["clone", "-b", "main", remoteDir, devBDir]);
    spawnSync("git", ["-C", devBDir, "config", "user.name", "DeviceB"]);
    spawnSync("git", ["-C", devBDir, "config", "user.email", "b@example.com"]);
    spawnSync("git", ["-C", devBDir, "config", "commit.gpgsign", "false"]);

    let devBStore = JSON.parse(fs.readFileSync(path.join(devBDir, "todos.json"), "utf8"));
    // Device B updates Shared Task (newer timestamp) and adds Task 303
    devBStore = TodoStore.updateTodo(devBStore, 301, { description: "Updated description on Device B", updatedAt: 2000 });
    devBStore = TodoStore.addTodo(devBStore, "Task Created on Device B");
    fs.writeFileSync(path.join(devBDir, "todos.json"), JSON.stringify(devBStore, null, 2), "utf8");
    spawnSync("git", ["-C", devBDir, "add", "todos.json"]);
    spawnSync("git", ["-C", devBDir, "commit", "-m", "[deviceB] Update and add task"]);
    spawnSync("git", ["-C", devBDir, "push", "origin", "main"]);

    // Meanwhile Device A adds another local task without fetching first (divergence!)
    let devACurrent = JSON.parse(fs.readFileSync(path.join(devADir, "todos.json"), "utf8"));
    devACurrent = TodoStore.addTodo(devACurrent, "Another Local Task on Device A");
    fs.writeFileSync(path.join(devADir, "todos.json"), JSON.stringify(devACurrent, null, 2), "utf8");
    spawnSync("git", ["-C", devADir, "add", "todos.json"]);
    spawnSync("git", ["-C", devADir, "commit", "-m", "[deviceA] Another local task"]);

    // Device A runs sync: must detect divergence (NEEDS_MERGE)
    const divSync = runSyncShellProcess(devADir);
    assert.equal(divSync.stdout, "NEEDS_MERGE", "Divergent branches must trigger NEEDS_MERGE");

    // Device A runs 3-way store merge (simulating mergeRemoteChangesProc in BarWidget.qml)
    const remoteShow = spawnSync("git", ["-C", devADir, "show", "origin/main:todos.json"], { encoding: "utf8" });
    const remoteArchShow = spawnSync("git", ["-C", devADir, "show", "origin/main:todos-archive.json"], { encoding: "utf8" });
    const mergedStore = TodoStore.mergeStores(devACurrent, remoteShow.stdout);
    const mergedArch = TodoStore.mergeArchives(
      fs.readFileSync(path.join(devADir, "todos-archive.json"), "utf8"),
      remoteArchShow.stdout
    );

    spawnSync("git", ["-C", devADir, "merge", "--no-commit", "-s", "ours", "origin/main"]);
    fs.writeFileSync(path.join(devADir, "todos.json"), JSON.stringify(mergedStore, null, 2), "utf8");
    fs.writeFileSync(path.join(devADir, "todos-archive.json"), JSON.stringify(mergedArch, null, 2), "utf8");
    spawnSync("git", ["-C", devADir, "add", "todos.json", "todos-archive.json"]);
    spawnSync("git", ["-C", devADir, "commit", "-m", "[deviceA] Auto-merge remote changes"]);
    const pushRes = spawnSync("git", ["-C", devADir, "push", "origin", "main"], { encoding: "utf8" });
    assert.equal(pushRes.status, 0, `Push after auto-merge must succeed: ${pushRes.stderr || pushRes.stdout}`);

    // Run sync again: should now be clean and up-to-date
    const postMergeSync = runSyncShellProcess(devADir);
    assert.equal(postMergeSync.stdout, "UP_TO_DATE");

    // CRITICAL ASSERTION: Assert ALL tasks from both sides are preserved!
    const finalDevA = JSON.parse(fs.readFileSync(path.join(devADir, "todos.json"), "utf8"));
    assert.equal(finalDevA.todos.length, 4, "Must contain all 4 tasks without any loss");

    // 1. Shared task updated with Device B's changes
    const shared = finalDevA.todos.find((t: any) => t.id === 301);
    assert.ok(shared, "Shared task 301 must exist");
    assert.equal(shared.description, "Updated description on Device B");

    // 2. Local tasks from Device A MUST NOT HAVE DISAPPEARED
    assert.ok(finalDevA.todos.some((t: any) => t.id === 302 && t.title === "Local Task from Device A"), "Task 302 from Device A must NOT be lost");
    assert.ok(finalDevA.todos.some((t: any) => t.title === "Another Local Task on Device A"), "Local Task from Device A must NOT be lost");

    // 3. Remote task from Device B must be merged in
    assert.ok(finalDevA.todos.some((t: any) => t.title === "Task Created on Device B"), "Task from Device B must be merged in");

    // Verify remote also has all 4 tasks
    const finalRemoteShow = spawnSync("git", ["--git-dir", remoteDir, "show", "main:todos.json"], { encoding: "utf8" });
    const finalRemote = JSON.parse(finalRemoteShow.stdout);
    assert.equal(finalRemote.todos.length, 4, "Remote repository must also contain all 4 tasks");
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
});


