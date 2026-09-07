#!/bin/zsh
# Invoked by SwiftBar menu items. Detaches the real worker so it survives
# SwiftBar quitting/restarting, then exits immediately.

fn="$1"
[[ -z "$fn" ]] && exit 1

# nohup + background + disown → grandchild reparents to launchd, not SwiftBar.
nohup /bin/zsh "$HOME/.config/deploywatcher/worker.zsh" "$fn" >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
