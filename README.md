# DeployWatcher

A personal macOS tool that pops a dialog when **my own** GitHub Actions
deploy / E2E runs finish — so I don't have to babysit GitHub after triggering a
feature or staging deploy.

The menu UI is a [SwiftBar](https://swiftbar.app) plugin; the actual watching is
plain `zsh` + the GitHub CLI (`gh`). SwiftBar is only the front-end — every
watcher also runs as a `dw-*` shell command from a terminal.

## Design principles

- **Job-level, not run-level.** Keys on the specific job's conclusion (`deploy`,
  or the `Playwright e2e` jobs), never the run's overall conclusion — a staging
  run reports overall `failure` whenever its bundled E2E fails, even when the
  deploy itself succeeded.
- **"Mine" = runs I triggered.** Filters on `triggering_actor` via the REST API,
  **not** `gh run list --user` (which only sees `actor`, the commit author — so
  it misses deploys where I merged a colleague's PR, and includes runs others
  triggered on my commits).
- **Detached & resilient.** Watchers run detached from SwiftBar (`nohup` →
  reparented to launchd), so quitting SwiftBar doesn't kill an in-flight watch.

## Files

| File | Role |
|---|---|
| `deploywatcher.zsh` | Function library — all `dw-*` commands, popups, run-picker, status. Sourced from `~/.zshrc`. |
| `run.zsh` | SwiftBar entry point — detaches the worker and exits. |
| `worker.zsh` | The detached watcher process. |
| `status.zsh` | "Watcher status" menu action. |
| `swiftbar-plugins/deploywatcher.1h.sh` | Renders the ⏱ menu. |
| `dwcard.swift` | Source for `dwcard` — a tiny always-on-top WebView panel that shows the HTML result card. Compile locally (binary is gitignored). |
| `SECURITY.md` | Security summary for review. |
| `preview.html` | Static mockup of the HTML result screen. |

The "deploy finished" screen is a styled HTML card (`_dw_result_html` in
`deploywatcher.zsh`) shown in the `dwcard` floating window. If the `dwcard` binary
is missing, it falls back to the native `display dialog`.

## Setup on a new machine

1. Clone into `~/.config/deploywatcher`.
2. Add to `~/.zshrc`:
   ```sh
   [ -f "$HOME/.config/deploywatcher/deploywatcher.zsh" ] && source "$HOME/.config/deploywatcher/deploywatcher.zsh"
   ```
3. `brew install --cask swiftbar`, point its plugin folder at
   `~/.config/deploywatcher/swiftbar-plugins` (`defaults write com.ameba.SwiftBar PluginDirectory ...`).
4. Ensure `gh` and `jq` are installed and `gh auth status` is logged in.
5. Configure: `cp config.example.zsh config.zsh` and edit it — set `DW_ACTOR`
   (your GitHub login) and `DW_REPO` (`owner/repo`), plus the workflow file names
   and job identifiers for your project. (`config.zsh` is gitignored, per-user.
   `DW_ACTOR`/`DW_REPO` auto-detect from `gh`/git if left empty, but the menu-bar
   context has no git cwd, so setting `DW_REPO` explicitly is recommended.)
6. Compile the result-card panel (needs Xcode Command Line Tools):
   ```sh
   swiftc ~/.config/deploywatcher/dwcard.swift -o ~/.config/deploywatcher/dwcard
   ```

## Commands

| Command / menu item | Watches |
|---|---|
| `dw-feature` · Feature deploy | `deploy` job of your feature deploy run |
| `dw-staging` · Staging deploy | `deploy` job of your staging deploy run |
| `dw-e2e` · E2E (feature) | Playwright jobs in your feature deploy run (picker) |
| `dw-staging-e2e` · E2E (staging) | Playwright jobs in your staging deploy run (picker) |
| `dw-e2e-direct` · E2E (direct) | standalone `playwright.yml` dispatch (picker) |
| `dw-url <url\|id> [e2e\|deploy\|all]` · 🔗 Watch a run by URL | any run, any actor (escape hatch) |
| `dw-status` · 🔍 Watcher status | lists running watchers |
