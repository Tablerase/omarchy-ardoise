#!/usr/bin/env bash
# =============================================================================
# tools/setup-git-remote.sh
#
# Automates private GitHub repository creation and remote synchronization
# for Omarchy Ardoise task data (tablerase.ardoise).
# Returns structured JSON to stdout.
# =============================================================================

set -e
export MISE_QUIET=1

# 1. Resolve GitHub CLI (gh)
GH_BIN=""
if command -v mise >/dev/null 2>&1; then
  GH_BIN="$(mise which gh 2>/dev/null || true)"
fi
if [ -z "$GH_BIN" ] || [ ! -x "$GH_BIN" ]; then
  GH_BIN="$(command -v gh 2>/dev/null || true)"
fi
if [ -z "$GH_BIN" ] || [ ! -x "$GH_BIN" ]; then
  for p in "$HOME/.local/share/mise/installs/gh/latest/gh_*/bin/gh" \
           "$HOME/.local/bin/gh" \
           "/usr/local/bin/gh" \
           "/usr/bin/gh"; do
    for match in $p; do
      if [ -x "$match" ]; then
        GH_BIN="$match"
        break 2
      fi
    done
  done
fi

if [ -z "$GH_BIN" ] || [ ! -x "$GH_BIN" ]; then
  printf '{"success":false,"error":"gh_not_found","message":"GitHub CLI (gh) not installed. Please install gh to auto-create repositories."}\n'
  exit 0
fi

# 2. Check Authentication
if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  printf '{"success":false,"error":"gh_not_authenticated","message":"GitHub CLI not logged in. Run \\"gh auth login\\" in your terminal."}\n'
  exit 0
fi

# 3. Resolve Data Directory
DATA_DIR="${2:-${ARDOISE_DATA_DIR:-$HOME/.config/omarchy/tablerase.ardoise}}"
if [ ! -d "$DATA_DIR" ]; then
  mkdir -p "$DATA_DIR"
fi
chmod 700 "$DATA_DIR" 2>/dev/null || true

# Ensure local git repo is initialized if not present
if [ ! -d "$DATA_DIR/.git" ]; then
  git -C "$DATA_DIR" init -b main >/dev/null 2>&1 || git -C "$DATA_DIR" init >/dev/null 2>&1
  git -C "$DATA_DIR" add -A >/dev/null 2>&1 || true
  git -C "$DATA_DIR" commit -m "[$(hostname)] Initial task repository" >/dev/null 2>&1 || true
fi

# 4. Check if remote 'origin' already exists
EXISTING_REMOTE="$(git -C "$DATA_DIR" remote get-url origin 2>/dev/null || true)"
if [ -n "$EXISTING_REMOTE" ]; then
  # Origin exists; push any pending commits
  git -C "$DATA_DIR" push origin main >/dev/null 2>&1 || true
  printf '{"success":true,"remoteUrl":"%s","alreadyExisted":true,"message":"Remote origin already configured and synced."}\n' "$EXISTING_REMOTE"
  exit 0
fi

# 5. Resolve Repository Name
RAW_NAME="${1:-ardoise-tasks}"
# Clean repo name: only allow alphanumeric, dashes, dots, underscores
CLEAN_NAME="$(printf '%s' "$RAW_NAME" | tr -cs 'a-zA-Z0-9._-' '-' | sed 's/^-//;s/-$//')"
if [ -z "$CLEAN_NAME" ]; then
  CLEAN_NAME="ardoise-tasks"
fi

# 6. Create Private Repository via GitHub CLI
CREATE_OUTPUT=""
if CREATE_OUTPUT="$("$GH_BIN" repo create "$CLEAN_NAME" --private --source="$DATA_DIR" --remote=origin --push --description "Personal task snapshots for Omarchy Ardoise" 2>&1)"; then
  RESOLVED_URL="$(git -C "$DATA_DIR" remote get-url origin 2>/dev/null || true)"
  printf '{"success":true,"remoteUrl":"%s","repo":"%s","alreadyExisted":false,"message":"Successfully created private repository and synced."}\n' "$RESOLVED_URL" "$CLEAN_NAME"
  exit 0
fi

# If repo already exists on GitHub for this user, attempt to connect to it
SSH_URL="$("$GH_BIN" repo view "$CLEAN_NAME" --json sshUrl -q .sshUrl 2>/dev/null || true)"
if [[ "$SSH_URL" =~ ^(git@|https?://|ssh://) ]]; then
  git -C "$DATA_DIR" remote add origin "$SSH_URL" 2>/dev/null || git -C "$DATA_DIR" remote set-url origin "$SSH_URL"
  git -C "$DATA_DIR" push -u origin main >/dev/null 2>&1 || true
  printf '{"success":true,"remoteUrl":"%s","repo":"%s","alreadyExisted":true,"message":"Connected to existing GitHub repository and pushed."}\n' "$SSH_URL" "$CLEAN_NAME"
  exit 0
fi

# Otherwise, report creation failure
ESCAPED_ERR="$(printf '%s' "$CREATE_OUTPUT" | head -n2 | tr '\n' ' ' | sed 's/"/\\"/g')"
printf '{"success":false,"error":"gh_create_failed","message":"Failed to create GitHub repo: %s"}\n' "$ESCAPED_ERR"
exit 0
