#!/bin/zsh
# Invoked by the SwiftBar "Watcher status" item. Pops a self-dismissing dialog
# listing any running watchers.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
source "$HOME/.config/deploywatcher/deploywatcher.zsh"
dw-status-popup
