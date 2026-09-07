#!/bin/zsh
# The actual watcher worker. Launched DETACHED by run.zsh (via nohup) so it
# reparents to launchd and survives SwiftBar quitting/restarting.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
umask 077   # files this worker creates (log, state) are user-only

LOG="$HOME/.config/deploywatcher/last-run.log"
fn="$1"

{
  echo "===== launch fn=$fn ====="
  echo "date: $(date)"
  echo "pid:  $$"
  echo "gh:   $(command -v gh || echo MISSING)"
  echo "--- watcher output ---"
} >"$LOG" 2>&1

[[ -z "$fn" ]] && { echo "ERROR: no fn arg" >>"$LOG"; exit 1; }

source "$HOME/.config/deploywatcher/deploywatcher.zsh"

osascript -e "display notification \"Watching for your run…\" with title \"DeployWatcher\" subtitle \"$fn\"" >/dev/null 2>&1

"$fn" >>"$LOG" 2>&1
echo "===== watcher exited: code $? =====" >>"$LOG"
