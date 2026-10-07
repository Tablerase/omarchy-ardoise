#!/usr/bin/env bash
# =============================================================================
# detect-context.sh
#
# Detects the user's active/focused codebase context across:
# Priority 0: Default Editor in Omarchy (~/.local/state/omarchy/defaults/editor)
# Priority 1: VS Code / VSCodium / Cursor (prioritized for GUI IDE users)
# Priority 2: Zed Editor (~/.local/share/zed/db/*/db.sqlite)
# Priority 3: Herdr (hedr) workspace manager (socket API: focused pane)
# Priority 4: Tmux (active pane path)
# Priority 5: Neovim (instance with latest interaction on its controlling TTY)
# Priority 6: Hyprland active terminal foreground child process
# Priority 7: Fallback to most recent editor workspace (VS Code or Zed)
# =============================================================================

dir=""

urldecode() {
  local url="${1#file://}"
  printf "%b" "${url//%/\\x}"
}

# -----------------------------------------------------------------------------
# Hyprland Active Window Inspection
# -----------------------------------------------------------------------------
win_json=$(hyprctl activewindow -j 2>/dev/null)
win_class=$(echo "$win_json" | jq -r '.class // empty' | tr '[:upper:]' '[:lower:]')
win_title=$(echo "$win_json" | jq -r '.title // empty')
win_pid=$(echo "$win_json" | jq -r '.pid // empty')

# If active window is quickshell/omarchy overlay or empty, get the top non-shell application
if [[ "$win_class" =~ (quickshell|omarchy) ]] || [ -z "$win_class" ]; then
  top_client=$(hyprctl clients -j 2>/dev/null | jq -c 'sort_by(.focusHistoryID)[] | select(.class != "org.quickshell" and (.class | test("^(omarchy|quickshell)"; "i") | not))' 2>/dev/null | head -n1)
  if [ -n "$top_client" ]; then
    win_class=$(echo "$top_client" | jq -r '.class // empty' | tr '[:upper:]' '[:lower:]')
    win_title=$(echo "$top_client" | jq -r '.title // empty')
    win_pid=$(echo "$top_client" | jq -r '.pid // empty')
  fi
fi

is_terminal_win=false
if [[ "$win_class" =~ (ghostty|kitty|alacritty|foot|wezterm|xterm|st|urxvt|terminator|tilix|konsole|gnome-terminal|xfce4-terminal) ]]; then
  is_terminal_win=true
fi

# -----------------------------------------------------------------------------
# Engine: VS Code / Cursor / VSCodium
# -----------------------------------------------------------------------------
get_vscode_dir() { detect_vscode "$@"; }
detect_vscode() {
  local storages=(
    "$HOME/.config/Code/User/globalStorage/storage.json"
    "$HOME/.config/Cursor/User/globalStorage/storage.json"
    "$HOME/.config/VSCodium/User/globalStorage/storage.json"
    "$HOME/.config/Code - OSS/User/globalStorage/storage.json"
    "$HOME/.var/app/com.visualstudio.code/config/Code/User/globalStorage/storage.json"
    "$HOME/.var/app/com.vscodium.codium/config/VSCodium/User/globalStorage/storage.json"
    "$HOME/snap/code/current/.config/Code/User/globalStorage/storage.json"
  )
  for s in "${storages[@]}"; do
    if [ -f "$s" ]; then
      local raw_folder
      raw_folder=$(jq -r ".windowsState.lastActiveWindow.folder // .windowsState.openedWindows[0].folder // empty" "$s" 2>/dev/null)
      if [ -n "$raw_folder" ]; then
        local dec
        dec=$(urldecode "$raw_folder")
        if [ -d "$dec" ] && [ "$dec" != "$HOME" ]; then
          echo "$dec"
          return 0
        fi
      fi
      local raw_ws
      raw_ws=$(jq -r ".windowsState.lastActiveWindow.workspace.configPath // .windowsState.openedWindows[0].workspace.configPath // empty" "$s" 2>/dev/null)
      if [ -n "$raw_ws" ]; then
        local dec_ws
        dec_ws=$(dirname "$(urldecode "$raw_ws")")
        if [ -d "$dec_ws" ] && [ "$dec_ws" != "$HOME" ]; then
          echo "$dec_ws"
          return 0
        fi
      fi
    fi
  done
  if [[ "$win_class" =~ (code|codium|cursor) ]] && [ -n "$win_pid" ]; then
    local code_proc_cwd
    code_proc_cwd=$(readlink "/proc/$win_pid/cwd" 2>/dev/null)
    if [ -n "$code_proc_cwd" ] && [ -d "$code_proc_cwd" ] && [ "$code_proc_cwd" != "$HOME" ]; then
      echo "$code_proc_cwd"
      return 0
    fi
  fi
  return 1
}

is_vscode_running() {
  pgrep -x code >/dev/null 2>&1 || \
  pgrep -x codium >/dev/null 2>&1 || \
  pgrep -x cursor >/dev/null 2>&1 || \
  pgrep -f "electron.*code" >/dev/null 2>&1 || \
  hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | test("(code|codium|cursor)"; "i"))' >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Engine: Zed Editor
# -----------------------------------------------------------------------------
detect_zed() {
  local zed_dbs=(
    "$HOME/.local/share/zed/db/0-stable/db.sqlite"
    "$HOME/.local/share/zed/db/0-global/db.sqlite"
    "$HOME/.var/app/dev.zed.Zed/data/zed/db/0-stable/db.sqlite"
  )
  for zdb in "${zed_dbs[@]}"; do
    if [ -f "$zdb" ] && command -v sqlite3 >/dev/null 2>&1; then
      local zpath
      zpath=$(sqlite3 -csv "$zdb" "SELECT paths FROM workspaces WHERE paths IS NOT NULL AND length(paths) > 0 ORDER BY timestamp DESC LIMIT 1;" 2>/dev/null | tr -d '\r' | head -n1)
      if [ -n "$zpath" ] && [ -d "$zpath" ] && [ "$zpath" != "$HOME" ]; then
        echo "$zpath"
        return 0
      fi
    fi
  done
  if [[ "$win_class" =~ (zed|dev\.zed\.zed) ]] && [ -n "$win_pid" ]; then
    local z_cwd
    z_cwd=$(readlink "/proc/$win_pid/cwd" 2>/dev/null)
    if [ -n "$z_cwd" ] && [ -d "$z_cwd" ] && [ "$z_cwd" != "$HOME" ]; then
      echo "$z_cwd"
      return 0
    fi
  fi
  return 1
}

is_zed_running() {
  pgrep -x zed >/dev/null 2>&1 || \
  pgrep -x zed-editor >/dev/null 2>&1 || \
  hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | test("(zed|dev\\.zed\\.Zed)"; "i"))' >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Engine: Herdr (hedr) Workspace Manager
# -----------------------------------------------------------------------------
detect_herdr() {
  if command -v herdr >/dev/null 2>&1 && [ -S "$HOME/.config/herdr/herdr.sock" ]; then
    local herdr_cwd
    herdr_cwd=$(herdr pane current 2>/dev/null | jq -r '.result.pane.cwd // empty')
    if [ -n "$herdr_cwd" ] && [ -d "$herdr_cwd" ] && [ "$herdr_cwd" != "$HOME" ]; then
      echo "$herdr_cwd"
      return 0
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Engine: Tmux
# -----------------------------------------------------------------------------
detect_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    local tmux_cwd
    tmux_cwd=$(tmux display-message -p -F "#{pane_current_path}" 2>/dev/null | tr -d '\r')
    if [ -n "$tmux_cwd" ] && [ -d "$tmux_cwd" ] && [ "$tmux_cwd" != "$HOME" ]; then
      echo "$tmux_cwd"
      return 0
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Engine: Neovim (Most Recently Active Instance by TTY Activity)
# -----------------------------------------------------------------------------
detect_nvim() {
  local best_nvim_dir=""
  local best_nvim_time=0
  for np in $(pgrep -x nvim 2>/dev/null); do
    local tty_name
    tty_name=$(ps -o tty= -p "$np" 2>/dev/null | tr -d ' ')
    if [ -n "$tty_name" ] && [ "$tty_name" != "?" ] && [ -e "/dev/$tty_name" ]; then
      local t_mtime
      local t_atime
      t_mtime=$(stat -c %Y "/dev/$tty_name" 2>/dev/null || echo 0)
      t_atime=$(stat -c %X "/dev/$tty_name" 2>/dev/null || echo 0)
      local t_latest=$(( t_mtime > t_atime ? t_mtime : t_atime ))
      if [ "$t_latest" -gt "$best_nvim_time" ]; then
        local np_cwd
        np_cwd=$(readlink "/proc/$np/cwd" 2>/dev/null)
        if [ -n "$np_cwd" ] && [ -d "$np_cwd" ] && [ "$np_cwd" != "$HOME" ]; then
          best_nvim_time="$t_latest"
          best_nvim_dir="$np_cwd"
        fi
      fi
    fi
  done
  if [ -n "$best_nvim_dir" ]; then
    echo "$best_nvim_dir"
    return 0
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Engine: Terminal Foreground Process
# -----------------------------------------------------------------------------
detect_terminal() {
  if [ -n "$win_pid" ] && [ "$is_terminal_win" = true ]; then
    local best_term_dir=""
    local best_term_time=0
    for cp in $(pgrep -P "$win_pid" 2>/dev/null); do
      local tty_name
      tty_name=$(ps -o tty= -p "$cp" 2>/dev/null | tr -d ' ')
      if [ -n "$tty_name" ] && [ "$tty_name" != "?" ] && [ -e "/dev/$tty_name" ]; then
        local t_mtime
        t_mtime=$(stat -c %Y "/dev/$tty_name" 2>/dev/null || echo 0)
        if [ "$t_mtime" -gt "$best_term_time" ]; then
          local cp_cwd
          cp_cwd=$(readlink "/proc/$cp/cwd" 2>/dev/null)
          if [ -n "$cp_cwd" ] && [ -d "$cp_cwd" ] && [ "$cp_cwd" != "$HOME" ]; then
            best_term_time="$t_mtime"
            best_term_dir="$cp_cwd"
          fi
        fi
      fi
    done
    if [ -n "$best_term_dir" ]; then
      echo "$best_term_dir"
      return 0
    else
      local p_cwd
      p_cwd=$(readlink "/proc/$win_pid/cwd" 2>/dev/null)
      if [ -n "$p_cwd" ] && [ -d "$p_cwd" ] && [ "$p_cwd" != "$HOME" ]; then
        echo "$p_cwd"
        return 0
      fi
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Active Window Direct Resolution
# If the user is currently focused on an editor or terminal, that active
# window ALWAYS takes precedence over background/unfocused applications.
# If focused on a non-dev app (discord, browser, obsidian), do not auto-detect.
# -----------------------------------------------------------------------------
if [[ "$win_class" =~ (code|codium|cursor) ]]; then
  dir=$(detect_vscode)
elif [[ "$win_class" =~ (zed|dev\.zed\.zed) ]]; then
  dir=$(detect_zed)
elif [ "$is_terminal_win" = true ]; then
  dir=$(detect_herdr)
  [ -z "$dir" ] && dir=$(detect_tmux)
  [ -z "$dir" ] && dir=$(detect_nvim)
  [ -z "$dir" ] && dir=$(detect_terminal)
elif [ -n "$win_class" ]; then
  # The focused window is another application (e.g. Discord, Browser, Obsidian)
  # Do not attach an unrelated background project to avoid issues.
  echo "null"
  exit 0
fi

# -----------------------------------------------------------------------------
# Background Resolution (User is in Browser, Desktop, or non-editor application)
# -----------------------------------------------------------------------------
default_editor_raw=""
if [ -f "$HOME/.local/state/omarchy/defaults/editor" ]; then
  read -r default_editor_raw < "$HOME/.local/state/omarchy/defaults/editor"
elif [ -n "$EDITOR" ]; then
  default_editor_raw="$EDITOR"
fi
default_editor=$(basename "${default_editor_raw:-}" | tr '[:upper:]' '[:lower:]')

# Priority 0: Default Editor in Omarchy (~/.local/state/omarchy/defaults/editor)
if [ -z "$dir" ]; then
  case "$default_editor" in
    code*|codium*|cursor*)
      if is_vscode_running; then
        dir=$(detect_vscode)
      fi
      ;;
    zed*)
      if is_zed_running; then
        dir=$(detect_zed)
      fi
      ;;
    nvim*|vim*|helix*|hx*|nano*|micro*)
      dir=$(detect_herdr)
      [ -z "$dir" ] && dir=$(detect_tmux)
      [ -z "$dir" ] && dir=$(detect_nvim)
      [ -z "$dir" ] && dir=$(detect_terminal)
      ;;
  esac
fi

# Priority 1: VS Code / Cursor / VSCodium (Running in background)
if [ -z "$dir" ] && is_vscode_running; then
  dir=$(detect_vscode)
fi

# Priority 2: Zed Editor (Running in background)
if [ -z "$dir" ] && is_zed_running; then
  dir=$(detect_zed)
fi

# Priority 3: Herdr (hedr) Workspace Manager
if [ -z "$dir" ]; then
  dir=$(detect_herdr)
fi

# Priority 4: Tmux
if [ -z "$dir" ]; then
  dir=$(detect_tmux)
fi

# Priority 5: Neovim (Active instance by TTY interaction)
if [ -z "$dir" ]; then
  dir=$(detect_nvim)
fi

# Priority 6: Terminal Foreground Process
if [ -z "$dir" ]; then
  dir=$(detect_terminal)
fi

# Priority 7: Fallback to Recent VS Code or Zed Workspace
if [ -z "$dir" ]; then
  dir=$(detect_vscode)
fi
if [ -z "$dir" ]; then
  dir=$(detect_zed)
fi

# -----------------------------------------------------------------------------
# Resolve Git Root, Origin Remote, Subpath, and Repo Name
# -----------------------------------------------------------------------------
if [ -z "$dir" ] || [ ! -d "$dir" ] || [ "$dir" = "$HOME" ]; then
  echo "null"
  exit 0
fi

# Ignore sensitive system or credential directories to prevent private path extraction
case "$dir" in
  "$HOME"|"/"|"/root"|"/etc"|"/var"|"/tmp"|"/dev"|"/proc"|"/sys")
    echo "null"
    exit 0
    ;;
  "$HOME/.ssh"*|"$HOME/.gnupg"*|"$HOME/.aws"*|"$HOME/.password-store"*|"$HOME/.local/share/keyrings"*|"$HOME/.pki"*)
    echo "null"
    exit 0
    ;;
esac

repo_root=""
remote=""
subpath=""
repo_name=""

if cd -- "$dir" 2>/dev/null; then
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_root" ]; then
    remote=$(git config --get remote.origin.url 2>/dev/null | sed -E 's/^(https?:\/\/|git@)(github\.com[:\/])?//' | sed -E 's/\.git$//')
    repo_name=$(basename "$repo_root")
    if [ "$dir" != "$repo_root" ]; then
      subpath="${dir#$repo_root/}"
    fi
  fi
fi

# Tilde-normalize localPath
rel_dir="$dir"
if [[ "$dir" == "$HOME"* ]]; then
  rel_dir="~${dir#$HOME}"
fi

jq -n \
  --arg lp "$rel_dir" \
  --arg repo "$remote" \
  --arg subpath "$subpath" \
  --arg repoName "$repo_name" \
  '{localPath: $lp, repo: (if $repo == "" then null else $repo end), subpath: (if $subpath == "" then null else $subpath end), repoName: (if $repoName == "" then null else $repoName end)}'
