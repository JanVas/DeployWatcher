#!/bin/bash
# SwiftBar plugin — DeployWatcher deploy/E2E watchers.
# Each item runs the launcher, which starts the matching dw-* watcher in
# the background and pops a dialog when the target job finishes.

LAUNCH="$HOME/.config/deploywatcher/run.zsh"
ZSH="/bin/zsh"

# --- menu bar title ---
echo "⏱"
echo "---"

# --- actions --- (terminal=false runs headless; refresh=false keeps the menu)
echo "Feature deploy | bash=$ZSH param1=$LAUNCH param2=dw-feature terminal=false refresh=false"
echo "Staging deploy | bash=$ZSH param1=$LAUNCH param2=dw-staging terminal=false refresh=false"
echo "E2E (feature)  | bash=$ZSH param1=$LAUNCH param2=dw-e2e terminal=false refresh=false"
echo "E2E (staging)  | bash=$ZSH param1=$LAUNCH param2=dw-staging-e2e terminal=false refresh=false"
echo "E2E (direct)   | bash=$ZSH param1=$LAUNCH param2=dw-e2e-direct terminal=false refresh=false"
echo "🔗 Watch a run by URL… | bash=$ZSH param1=$LAUNCH param2=dw-url-interactive terminal=false refresh=false"
echo "---"
echo "🔍 Watcher status | bash=$ZSH param1=$HOME/.config/deploywatcher/status.zsh terminal=false refresh=false"
echo "Test popup | bash=$ZSH param1=$LAUNCH param2=dw-test terminal=false refresh=false"
