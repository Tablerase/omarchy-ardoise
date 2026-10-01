#!/usr/bin/env bash
# Ardoise Demo & Scenario Runner.
#
# Reproduce demo scenarios (such as 'hero') safely with realistic data,
# while guaranteeing 100% data safety for the user's real tasks.
#
# Usage:
#   tools/demo.sh [scenario]           Run interactive demo (hero by default)
#   tools/demo.sh start [scenario]     Seed scenario and keep active
#   tools/demo.sh restore | stop       Restore user's real task data
#   tools/demo.sh status               Check active scenario and backup state
#   tools/demo.sh list                 List available scenarios
#
# Recovery:
#   Real tasks and archives are backed up to ~/.cache/ardoise-demo/backup
#   and verified with SHA-256 digests. If interrupted (Ctrl+C, crash, reboot),
#   the next run or `tools/demo.sh restore` restores the original files automatically.
#
set -euo pipefail

DATA_DIR="${ARDOISE_DATA_DIR:-$HOME/.config/omarchy/tablerase.ardoise}"
STATE_ROOT="${ARDOISE_DEMO_STATE:-$HOME/.cache/ardoise-demo}"
BACKUP_DIR="$STATE_ROOT/backup"
STATE_FILE="$STATE_ROOT/state.json"

TODO_FILE="$DATA_DIR/todos.json"
ARCHIVE_FILE="$DATA_DIR/todos-archive.json"

_SESSION_ARMED=0

# Formatting
if [[ -t 1 ]]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_RED=$'\033[31m'
else
  C_BOLD=""; C_DIM=""; C_OFF=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_RED=""
fi

log()  { printf '%s[demo]%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
ok()   { printf '%s[demo]%s %s%s%s\n' "$C_GREEN" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
warn() { printf '%s[demo warning]%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%s[demo error]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"
  fi
}

ipc() {
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell tablerase.ardoise "$@" >/dev/null 2>&1 || true
  fi
}

notify_reload() {
  # Touch files and ping shell so Quickshell FileView detects change immediately
  if [[ -f "$TODO_FILE" ]]; then
    touch "$TODO_FILE" 2>/dev/null || true
  fi
  if [[ -f "$ARCHIVE_FILE" ]]; then
    touch "$ARCHIVE_FILE" 2>/dev/null || true
  fi
  ipc reload
}

# --- State & Data Safety -----------------------------------------------------

preflight() {
  if [[ -f "$STATE_FILE" ]]; then
    warn "An unrestored demo session from a previous run was detected!"
    warn "Restoring your original tasks from $BACKUP_DIR..."
    if restore_data; then
      ok "Original data successfully recovered."
    else
      die "Automatic recovery failed. Please inspect $BACKUP_DIR or git history in $DATA_DIR."
    fi
  fi
}

arm() {
  mkdir -p "$BACKUP_DIR"
  local real_head=""

  if [[ -d "$DATA_DIR/.git" ]]; then
    real_head="$(git -C "$DATA_DIR" rev-parse HEAD 2>/dev/null || true)"
    # Commit uncommitted real state before demo so git HEAD is consistent
    if ! git -C "$DATA_DIR" diff --quiet 2>/dev/null || ! git -C "$DATA_DIR" diff --cached --quiet 2>/dev/null; then
      git -C "$DATA_DIR" add -A >/dev/null 2>&1 || true
      git -C "$DATA_DIR" -c commit.gpgsign=false commit -q -m "[demo] Snapshot before demo session" >/dev/null 2>&1 || true
      real_head="$(git -C "$DATA_DIR" rev-parse HEAD 2>/dev/null || true)"
    fi
  fi

  # Backup files and calculate SHA-256
  python3 - "$STATE_FILE" "$DATA_DIR" "$BACKUP_DIR" "${real_head:-}" <<'PY'
import json, sys, os, hashlib, shutil, time

state_file, data_dir, backup_dir, real_head = sys.argv[1:5]
os.makedirs(backup_dir, exist_ok=True)

sums = {}
for name in ("todos.json", "todos-archive.json"):
    src = os.path.join(data_dir, name)
    dst = os.path.join(backup_dir, name)
    if os.path.isfile(src):
        shutil.copy2(src, dst)
        sums[name] = hashlib.sha256(open(dst, "rb").read()).hexdigest()

meta = {
    "armedAt": time.time(),
    "realHead": real_head,
    "sha256": sums
}
with open(state_file, "w") as f:
    json.dump(meta, f, indent=2)
PY

  _SESSION_ARMED=1
  trap '_on_exit' EXIT INT TERM HUP
  log "Backed up live tasks to $BACKUP_DIR"
}

_on_exit() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if (( _SESSION_ARMED )); then
    printf '\n'
    warn "Session interrupted or terminated (exit code $rc) - restoring real task data..."
    restore_data || warn "Restore failed! Inspect $BACKUP_DIR manually."
  fi
  exit $rc
}

disarm() {
  _SESSION_ARMED=0
  trap - EXIT INT TERM HUP
}

restore_data() {
  if [[ ! -f "$STATE_FILE" || ! -d "$BACKUP_DIR" ]]; then
    warn "No active backup found."
    return 0
  fi

  python3 - "$STATE_FILE" "$DATA_DIR" "$BACKUP_DIR" <<'PY'
import json, sys, os, hashlib, shutil

state_file, data_dir, backup_dir = sys.argv[1:4]
state = json.load(open(state_file))
expected_sums = state.get("sha256", {})

for name, expected_hash in expected_sums.items():
    backup_path = os.path.join(backup_dir, name)
    if not os.path.isfile(backup_path):
        sys.exit(f"Error: Missing backup file {backup_path}")
    actual_hash = hashlib.sha256(open(backup_path, "rb").read()).hexdigest()
    if actual_hash != expected_hash:
        sys.exit(f"Error: Checksum mismatch in backup {name}")

for name in expected_sums:
    backup_path = os.path.join(backup_dir, name)
    target_path = os.path.join(data_dir, name)
    shutil.copy2(backup_path, target_path)
PY

  # Re-sync git if repo exists
  local head
  head="$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('realHead',''))" 2>/dev/null || true)"
  if [[ -n "$head" && -d "$DATA_DIR/.git" ]]; then
    git -C "$DATA_DIR" reset "$head" --quiet 2>/dev/null || true
  fi

  rm -rf "$BACKUP_DIR" "$STATE_FILE"
  _SESSION_ARMED=0
  notify_reload
  ok "Original tasks successfully restored and verified."
}

# --- Scenarios ---------------------------------------------------------------

seed_hero() {
  local now_ts
  now_ts="$(date +%s%3N)"

  # Compute overdue reminder: 3 hours in the past
  local overdue_iso
  overdue_iso="$(date -u -d "3 hours ago" +"%Y-%m-%dT%H:%M:%S.000Z")"

  # Seed scenario JSON directly and atomically
  python3 - "$TODO_FILE" "$ARCHIVE_FILE" "$now_ts" "$overdue_iso" <<'PY'
import json, sys, os

todo_file, archive_file, now_ts_str, overdue_iso = sys.argv[1:5]
now = int(now_ts_str)

todos = [
    {
        "id": now + 1,
        "title": "Ship the v1.4 release notes",
        "description": "Cover the new severity ladder, custom Lua keybindings, and git search flow.",
        "profile": "work",
        "repo": "omarchy/ardoise",
        "tags": ["release"],
        "location": {"repo": "omarchy/ardoise", "subpath": None, "localPath": "~/Work/omarchy/ardoise"},
        "done": False,
        "createdAt": now - 14400000,
        "updatedAt": now - 7200000,
        "dueDate": None,
        "reminder": overdue_iso,
        "notified": True  # Prevent unwanted desktop notification popup during recording
    },
    {
        "id": now + 2,
        "title": "Refactor the token parser",
        "description": "Split tokenizer out; add fixtures for nested cases and benchmark throughput.",
        "profile": "work",
        "repo": "omarchy/ardoise",
        "tags": ["parser"],
        "location": {"repo": "omarchy/ardoise", "subpath": "src/tokens", "localPath": "~/Work/omarchy/ardoise"},
        "done": False,
        "createdAt": now - 28800000,
        "updatedAt": now - 28800000,
        "dueDate": None,
        "reminder": None,
        "notified": False
    },
    {
        "id": now + 3,
        "title": "Reply to the Hyprland issue thread",
        "description": "Reproduce first - the layer-shell positioning bug looks compositor specific.",
        "profile": "work",
        "repo": "hyprwm/Hyprland",
        "tags": ["hyprland", "upstream"],
        "location": None,
        "done": False,
        "createdAt": now - 86400000,
        "updatedAt": now - 86400000,
        "dueDate": None,
        "reminder": None,
        "notified": False
    },
    {
        "id": now + 4,
        "title": "Book the dentist",
        "description": "Anything before lunch on Thursday or Friday.",
        "profile": "personal",
        "repo": None,
        "tags": ["health"],
        "location": None,
        "done": False,
        "createdAt": now - 172800000,
        "updatedAt": now - 172800000,
        "dueDate": None,
        "reminder": None,
        "notified": False
    },
    {
        "id": now + 5,
        "title": "Rotate the signing keys",
        "description": "Both dev and CI environment SSH signing keys.",
        "profile": "personal",
        "repo": None,
        "tags": ["security"],
        "location": None,
        "done": False,
        "createdAt": now - 259200000,
        "updatedAt": now - 259200000,
        "dueDate": None,
        "reminder": None,
        "notified": False
    },
    {
        "id": now + 6,
        "title": "Update the README screenshots",
        "description": "Generate high-res preview assets and showcase keybindings.",
        "profile": "personal",
        "repo": "omarchy/ardoise",
        "tags": ["docs"],
        "location": None,
        "done": True,
        "createdAt": now - 360000000,
        "updatedAt": now - 3600000,
        "dueDate": None,
        "reminder": None,
        "notified": False
    }
]

store = {
    "version": 1,
    "activeProfile": "all",
    "profiles": ["personal", "work"],
    "todos": todos
}

with open(todo_file, "w") as f:
    json.dump(store, f, indent=2)

archives = {
    "version": 1,
    "todos": [
        {
            "id": now - 5000000,
            "title": "Initial v1.0 release packaging",
            "profile": "work",
            "done": True,
            "completedAt": now - 5000000
        }
    ]
}

with open(archive_file, "w") as f:
    json.dump(archives, f, indent=2)
PY

  # Add git snapshot entries in data dir so pressing 'u' opens realistic history
  if [[ -d "$DATA_DIR/.git" ]]; then
    git -C "$DATA_DIR" add todos.json todos-archive.json >/dev/null 2>&1 || true
    git -C "$DATA_DIR" -c commit.gpgsign=false commit -q \
      -m "[laptop] Completed task: Update the README screenshots" >/dev/null 2>&1 || true
  fi

  notify_reload
}

seed_ladder() {
  local now_ts
  now_ts="$(date +%s%3N)"
  local overdue_iso due_today_iso

  overdue_iso="$(date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%S.000Z")"
  due_today_iso="$(date -u -d "today 18:00" +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u -d "+2 hours" +"%Y-%m-%dT%H:%M:%S.000Z")"

  python3 - "$TODO_FILE" "$ARCHIVE_FILE" "$now_ts" "$overdue_iso" "$due_today_iso" <<'PY'
import json, sys

todo_file, archive_file, now_ts_str, overdue_iso, due_today_iso = sys.argv[1:6]
now = int(now_ts_str)

todos = [
    {
        "id": now + 1,
        "title": "Overdue server security patch",
        "description": "Urgent kernel update.",
        "profile": "work",
        "done": False,
        "createdAt": now - 1000000,
        "updatedAt": now - 1000000,
        "reminder": overdue_iso,
        "notified": True
    },
    {
        "id": now + 2,
        "title": "Prepare team sync slides",
        "description": "Quarterly progress.",
        "profile": "work",
        "done": False,
        "createdAt": now - 2000000,
        "updatedAt": now - 2000000,
        "reminder": due_today_iso,
        "notified": False
    },
    {
        "id": now + 3,
        "title": "Review pull requests",
        "description": "Pending reviews on repo.",
        "profile": "work",
        "done": False,
        "createdAt": now - 3000000,
        "updatedAt": now - 3000000,
        "reminder": None,
        "notified": False
    },
    {
        "id": now + 4,
        "title": "Plan grocery shopping",
        "description": "Weekly essentials.",
        "profile": "personal",
        "done": True,
        "createdAt": now - 4000000,
        "updatedAt": now - 500000,
        "reminder": None,
        "notified": False
    }
]

store = {
    "version": 1,
    "activeProfile": "all",
    "profiles": ["personal", "work"],
    "todos": todos
}

with open(todo_file, "w") as f:
    json.dump(store, f, indent=2)
PY

  notify_reload
}

seed_empty() {
  python3 - "$TODO_FILE" "$ARCHIVE_FILE" <<'PY'
import json, sys

todo_file, archive_file = sys.argv[1:3]
store = {
    "version": 1,
    "activeProfile": "all",
    "profiles": ["personal"],
    "todos": []
}
with open(todo_file, "w") as f:
    json.dump(store, f, indent=2)
PY
  notify_reload
}

show_scenario_card() {
  local scenario="$1"
  printf '\n'
  printf '%s========================================================================%s\n' "$C_CYAN" "$C_OFF"
  printf '  %s%sArdoise Demo Scenario: %s%s\n' "$C_BOLD" "$C_GREEN" "${scenario^^}" "$C_OFF"
  printf '%s========================================================================%s\n' "$C_CYAN" "$C_OFF"

  if [[ "$scenario" == "hero" ]]; then
    printf '  %sLadder Rung%s  : %sOVERDUE%s (1 overdue, 4 pending, 1 done)\n' "$C_BOLD" "$C_OFF" "$C_YELLOW" "$C_OFF"
    printf '  %sProfiles%s     : work (3), personal (3)\n' "$C_BOLD" "$C_OFF"
    printf '%s------------------------------------------------------------------------%s\n' "$C_DIM" "$C_OFF"
    printf '  %sSuggested Walkthrough Beats:%s\n' "$C_BOLD" "$C_OFF"
    printf '    1. %sBar icon%s     : Note warning color and overdue "1" count badge\n' "$C_CYAN" "$C_OFF"
    printf '    2. %sOpen panel%s   : Click the bar widget or press toggle shortcut\n' "$C_CYAN" "$C_OFF"
    printf '    3. %sExpand task%s  : Press %sEnter%s on "Ship the v1.4 release notes"\n' "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF"
    printf '    4. %sSearch%s       : Press %s/%s or %sCtrl+F%s, type "release", then press %sEsc%s\n' "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
    printf '    5. %sGit modal%s    : Press %su%s to view snapshots, %sq%s to dismiss\n' "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
    printf '    6. %sHelp modal%s   : Press %s?%s to view dynamic keybindings, %sEsc%s to close\n' "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
    printf '    7. %sClose panel%s  : Press %sEsc%s\n' "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF"
  elif [[ "$scenario" == "ladder" ]]; then
    printf '  %sLadder Rung%s  : Multi-urgency breakdown (overdue, due today, pending, done)\n' "$C_BOLD" "$C_OFF"
  elif [[ "$scenario" == "empty" ]]; then
    printf '  %sState%s        : Clean zero-tasks empty state\n' "$C_BOLD" "$C_OFF"
  fi

  printf '%s------------------------------------------------------------------------%s\n' "$C_DIM" "$C_OFF"
  printf '  %s✓ Demo session ACTIVE.%s Record in Recordly, OBS, or explore manually.\n' "$C_GREEN" "$C_OFF"
  printf '  %s• Real data is backed up safely at:%s %s\n' "$C_DIM" "$C_OFF" "$BACKUP_DIR"
  printf '%s========================================================================%s\n' "$C_CYAN" "$C_OFF"
}

# --- CLI Dispatch ------------------------------------------------------------

cmd_start() {
  local scenario="${1:-hero}"
  preflight
  arm

  case "$scenario" in
    hero)   seed_hero ;;
    ladder) seed_ladder ;;
    empty)  seed_empty ;;
    *)      die "Unknown scenario '$scenario'. Run 'tools/demo.sh list' for options." ;;
  esac

  show_scenario_card "$scenario"
  disarm # Keep active without exit trap
  ok "Demo mode started. When finished, run: tools/demo.sh restore"
}

cmd_restore() {
  if [[ ! -f "$STATE_FILE" ]]; then
    ok "No active demo session. Real task data is already in place."
    exit 0
  fi
  restore_data
}

cmd_status() {
  if [[ -f "$STATE_FILE" ]]; then
    printf '%sDemo session is currently ACTIVE.%s\n' "$C_YELLOW" "$C_OFF"
    printf '  Backup dir : %s\n' "$BACKUP_DIR"
    printf '  State file : %s\n' "$STATE_FILE"
    if [[ -f "$TODO_FILE" ]]; then
      python3 - "$TODO_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
todos = data.get("todos", [])
done = sum(1 for t in todos if t.get("done"))
pending = len(todos) - done
print(f"  Live tasks : {pending} pending, {done} completed")
PY
    fi
    printf '  To restore real data: %stools/demo.sh restore%s\n' "$C_BOLD" "$C_OFF"
  else
    ok "No active demo session. Live personal tasks are in place."
  fi
}

cmd_list() {
  printf '%sAvailable demo scenarios:%s\n' "$C_BOLD" "$C_OFF"
  printf '  %shero%s    (Default) Showcase scenario: overdue ladder rung, tags, rich notes, git snapshot history\n' "$C_GREEN" "$C_OFF"
  printf '  %sladder%s   Urgency progression scenario: tasks across overdue, due today, and pending rungs\n' "$C_GREEN" "$C_OFF"
  printf '  %sempty%s    Zero tasks clean empty slate\n' "$C_GREEN" "$C_OFF"
}

cmd_help() {
  printf '%sArdoise Demo & Scenario Runner%s\n' "$C_BOLD" "$C_OFF"
  printf 'Reproduce demo scenarios easily and safely.\n\n'
  printf '%sCommands:%s\n' "$C_BOLD" "$C_OFF"
  printf '  tools/demo.sh [scenario]        Run interactive demo (hero by default, auto-restores on Enter or Ctrl+C)\n'
  printf '  tools/demo.sh start [scenario]  Seed scenario and leave running\n'
  printf '  tools/demo.sh restore | stop    Restore your real task data\n'
  printf '  tools/demo.sh status            Check demo / backup status\n'
  printf '  tools/demo.sh list              List available scenarios (hero, ladder, empty)\n'
}

# Interactive mode: seeds scenario, waits for user to test/record, then restores cleanly on Enter / Ctrl+C
run_interactive() {
  local scenario="${1:-hero}"
  preflight
  arm

  case "$scenario" in
    hero)   seed_hero ;;
    ladder) seed_ladder ;;
    empty)  seed_empty ;;
    *)      die "Unknown scenario '$scenario'. Run 'tools/demo.sh list' for options." ;;
  esac

  show_scenario_card "$scenario"

  printf '\n%s==> Press [ENTER] when finished to restore your real tasks (or press Ctrl+C)...%s ' "$C_BOLD" "$C_OFF"
  read -r _ || true

  restore_data
  disarm
}

main() {
  local action="${1:-hero}"

  case "$action" in
    start)
      cmd_start "${2:-hero}"
      ;;
    restore|stop)
      cmd_restore
      ;;
    status)
      cmd_status
      ;;
    list)
      cmd_list
      ;;
    help|--help|-h)
      cmd_help
      ;;
    hero|ladder|empty)
      run_interactive "$action"
      ;;
    *)
      # Default to running interactive hero if no matching command
      run_interactive "$action"
      ;;
  esac
}

main "$@"
