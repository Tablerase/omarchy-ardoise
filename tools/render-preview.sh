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
theme="${1:-${ARDOISE_THEME:-}}"

render_single_theme() {
  local target_theme="$1"
  local target_out="$2"
  local preview_dir
  preview_dir=$(mktemp -d /tmp/ardoise-preview.XXXXXX)
  trap 'rm -rf -- "$preview_dir"' RETURN

  mkdir -p "$target_out" "$target_out/screenshots"

  ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell/Commons" "$preview_dir/Commons"
  ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell/Ui" "$preview_dir/Ui"
  ln -s "$repo_dir" "$preview_dir/plugin"
  cp "$repo_dir/tools/preview.qml" "$preview_dir/shell.qml"

  local env_cmd=(env "ARDOISE_PREVIEW_OUT=$target_out" "QT_QPA_PLATFORM=offscreen")

  if [[ -n "$target_theme" && -d "/usr/share/omarchy/themes/$target_theme" ]]; then
    local fake_home="$preview_dir/home"
    mkdir -p "$fake_home/.local/state/omarchy/current"
    ln -s "/usr/share/omarchy/themes/$target_theme" "$fake_home/.local/state/omarchy/current/theme"
    echo "$target_theme" > "$fake_home/.local/state/omarchy/current/theme.name"
    env_cmd+=("HOME=$fake_home")
    echo "Rendering Ardoise preview for theme: $target_theme..."
  else
    echo "Rendering Ardoise preview offscreen with Quickshell (current system theme)..."
  fi

  "${env_cmd[@]}" timeout 10s quickshell -p "$preview_dir" --no-color >/dev/null 2>&1 || true

  if [[ -f "$target_out/preview.png" ]]; then
    echo "✓ Generated: $target_out/preview.png ($(du -h "$target_out/preview.png" | cut -f1))"
  fi
  if [[ -f "$target_out/screenshots/panel.png" ]]; then
    echo "✓ Generated: $target_out/screenshots/panel.png ($(du -h "$target_out/screenshots/panel.png" | cut -f1))"
  fi
}

if [[ "$theme" == "--all" || "$theme" == "all" ]]; then
  popular_themes=("tokyo-night" "catppuccin" "nord" "gruvbox" "rose-pine" "catppuccin-latte" "kanagawa" "everforest")
  for t in "${popular_themes[@]}"; do
    render_single_theme "$t" "$repo_dir/screenshots/themes/$t"
  done
  echo "All theme previews generated in: $repo_dir/screenshots/themes/"
elif [[ -n "$theme" ]]; then
  render_single_theme "$theme" "$repo_dir"
else
  render_single_theme "" "$repo_dir"
fi
