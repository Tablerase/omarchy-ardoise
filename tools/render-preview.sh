#!/usr/bin/env bash
# =============================================================================
# render-preview.sh
#
# Generates the marketplace preview banner (preview.png) and panel screenshot
# (screenshots/panel.png) using Quickshell in headless offscreen mode.
# Inspired by Carmine Paolino's OmaTasks preview pipeline.
# =============================================================================
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
preview_dir=$(mktemp -d /tmp/ardoise-preview.XXXXXX)
trap 'rm -rf -- "$preview_dir"' EXIT

mkdir -p "$repo_dir/screenshots"

ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell/Commons" "$preview_dir/Commons"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell/Ui" "$preview_dir/Ui"
ln -s "$repo_dir" "$preview_dir/plugin"
cp "$repo_dir/tools/preview.qml" "$preview_dir/shell.qml"

echo "Rendering Ardoise preview offscreen with Quickshell..."
ARDOISE_PREVIEW_OUT="$repo_dir" \
  QT_QPA_PLATFORM=offscreen \
  timeout 10s quickshell -p "$preview_dir" --no-color >/dev/null 2>&1 || true

if [[ -f "$repo_dir/preview.png" ]]; then
  echo "✓ Successfully generated: preview.png ($(du -h "$repo_dir/preview.png" | cut -f1))"
fi
if [[ -f "$repo_dir/screenshots/panel.png" ]]; then
  echo "✓ Successfully generated: screenshots/panel.png ($(du -h "$repo_dir/screenshots/panel.png" | cut -f1))"
fi
