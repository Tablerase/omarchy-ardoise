#!/usr/bin/env bash
# =============================================================================
# tools/check-remote-privacy.sh
#
# Validates that a git remote repository is strictly PRIVATE before allowing
# any push operation containing personal task data.
#
# Usage:
#   tools/check-remote-privacy.sh [DATA_DIR_OR_REMOTE_URL] [REMOTE_NAME]
#
# Exit code 0: Verified private (or local filesystem) -> Push allowed
# Exit code 1: Verified PUBLIC -> Push strictly blocked
# =============================================================================

set -euo pipefail
export MISE_QUIET=1

ARG1="${1:-.}"
ARG2="${2:-origin}"

# Prevent command-line option injection
if [[ "$ARG1" =~ ^- ]] || [[ "$ARG2" =~ ^- ]]; then
  echo "INVALID_ARGUMENT: Arguments cannot start with a hyphen" >&2
  exit 1
fi

REMOTE_URL=""
DATA_DIR="."

if [ -d "$ARG1" ]; then
  DATA_DIR="$ARG1"
  REMOTE_URL="$(git -C "$DATA_DIR" remote get-url -- "$ARG2" 2>/dev/null || echo "$ARG2")"
elif [[ "$ARG1" =~ ^(git@|https?://|ssh://|file://|/) ]]; then
  REMOTE_URL="$ARG1"
else
  REMOTE_URL="$(git remote get-url -- "$ARG1" 2>/dev/null || echo "$ARG1")"
fi

# Reject any remote URL starting with a hyphen (flag injection prevention)
if [[ "$REMOTE_URL" =~ ^- ]]; then
  echo "INVALID_REMOTE_URL: Remote URL cannot start with a hyphen" >&2
  exit 1
fi

if [ -z "$REMOTE_URL" ]; then
  # No remote configured, nothing to push
  exit 0
fi

# Local filesystem paths or file:// URLs are machine-local, allow
if [[ "$REMOTE_URL" =~ ^/ || "$REMOTE_URL" =~ ^file:// ]]; then
  exit 0
fi

# Resolve GitHub CLI (gh)
resolve_gh() {
  local gh="${GH_BIN:-}"
  if [ -n "$gh" ] && [ -x "$gh" ]; then
    echo "$gh"
    return 0
  fi
  if command -v mise >/dev/null 2>&1; then
    gh="$(mise which gh 2>/dev/null || true)"
  fi
  if [ -z "$gh" ] || [ ! -x "$gh" ]; then
    gh="$(command -v gh 2>/dev/null || true)"
  fi
  if [ -z "$gh" ] || [ ! -x "$gh" ]; then
    for p in "$HOME/.local/share/mise/installs/gh/latest/gh_*/bin/gh" \
             "$HOME/.local/bin/gh" \
             "/usr/local/bin/gh" \
             "/usr/bin/gh"; do
      for match in $p; do
        if [ -x "$match" ]; then
          gh="$match"
          break 2
        fi
      done
    done
  fi
  echo "$gh"
}

# 1. GitHub verification
if [[ "$REMOTE_URL" =~ github\.com ]]; then
  GH_BIN="$(resolve_gh)"
  if [ -n "$GH_BIN" ] && [ -x "$GH_BIN" ]; then
    IS_PRIVATE="$("$GH_BIN" repo view "$REMOTE_URL" --json isPrivate -q .isPrivate 2>/dev/null || true)"
    if [[ "$IS_PRIVATE" =~ ^false ]]; then
      echo "DESTINATION_NOT_PRIVATE: Remote repository '$REMOTE_URL' is public. Pushing personal tasks to a public repository is forbidden." >&2
      exit 1
    fi
  fi
fi

# 2. GitLab verification
if [[ "$REMOTE_URL" =~ gitlab\.com ]]; then
  GLAB_BIN="$(command -v glab 2>/dev/null || true)"
  if [ -n "$GLAB_BIN" ] && [ -x "$GLAB_BIN" ]; then
    VISIBILITY="$("$GLAB_BIN" repo view "$REMOTE_URL" --output json 2>/dev/null | grep -o '"visibility":"[^"]*"' | cut -d'"' -f4 || true)"
    if [ "$VISIBILITY" = "public" ]; then
      echo "DESTINATION_NOT_PRIVATE: Remote repository '$REMOTE_URL' is public. Pushing personal tasks to a public repository is forbidden." >&2
      exit 1
    fi
  fi
fi

exit 0
