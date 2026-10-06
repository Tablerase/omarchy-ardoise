#!/usr/bin/env bash
# Reproduce the GitHub CI job locally in a throwaway Arch container.
#
# CI (.github/workflows/ci.yml) and this script share:
#   - the pinned Omarchy commit, read from tools/omarchy-ref
#   - the same dependency set and the same check order
#
# It differs from `npm run check` in one important way: it runs with CI=1, so
# every test that would otherwise silently skip because a prerequisite is
# missing FAILS instead. That is the point - a green local run must not be
# able to hide missing coverage that CI would have caught.
#
# Usage: npm run test:docker

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMARCHY_REF="$(tr -d '[:space:]' < "$REPO_ROOT/tools/omarchy-ref")"

exec docker run --rm \
  -v "$REPO_ROOT:/work" \
  -w /work \
  -e CI=1 \
  -e "OMARCHY_REF=$OMARCHY_REF" \
  archlinux:latest \
  bash -c '
    set -euo pipefail
    export PATH="/usr/lib/qt6/bin:$PATH"

    pacman -Sy --noconfirm git quickshell qt6-declarative deno nodejs npm jq lua

    # Same sparse checkout CI performs, at the same pinned commit.
    git init -q /tmp/omarchy
    cd /tmp/omarchy
    git remote add origin https://github.com/omacom/omarchy.git
    git sparse-checkout init --cone
    git sparse-checkout set shell/Commons shell/Ui bin
    git fetch -q --depth 1 origin "$OMARCHY_REF"
    git checkout -q FETCH_HEAD
    export OMARCHY_PATH=/tmp/omarchy
    echo "OMARCHY $(git rev-parse --short FETCH_HEAD) ready"

    cd /work
    export QT_QPA_PLATFORM=offscreen
    npm run typecheck
    npm run lint:qml
    npm run validate:plugin:ci
    npm test
  '
