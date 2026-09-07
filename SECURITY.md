# DeployWatcher — SwiftBar plugin security summary

A personal, self-authored SwiftBar tool that pops a macOS dialog when the
author's own GitHub Actions deploy/E2E runs finish. Prepared for security review.

## Provenance
- **SwiftBar**: installed via the official Homebrew cask (`brew install --cask swiftbar`), notarized by Apple. Not a sideloaded binary.
- **Plugin + scripts**: written by the author (Jan Vašátko). Nothing is downloaded from a third-party plugin repository. All code lives locally in `~/.config/deploywatcher/` and is listed below.

## Privileges
- Runs entirely as the logged-in user. **No `sudo`, no privilege escalation, ever.**
- Uses the GitHub CLI (`gh`), which reads the user's existing token from the macOS Keychain. Only read access to Actions is needed — scope the token to least privilege (a fine-grained token with **Actions: read-only**, or classic **`repo`** for private repos). DeployWatcher never writes.
- **The scripts issue read-only GitHub calls only** (`gh run list`, `gh run view`). They never create, update, cancel, or delete anything on GitHub, despite the token being write-capable.

## Network activity (exhaustive)
| Destination | Made by | Purpose | Direction |
|---|---|---|---|
| `api.github.com` | `gh api .../actions/workflows/*/runs`, `gh run view` | Read Actions run/job status | Authenticated GET (read-only) |
| default browser → `github.com/...` | `open <url>` | Open the run page when user clicks "Open run" | Launches browser to a github.com URL |

No other hosts are contacted. No `curl`/`fetch`/`wget`, no telemetry, no analytics, no external plugin fetches, no code is downloaded or `eval`'d from the network.

## Files (all `rwx------` / `rw-------`, user-only, in `~/.config/deploywatcher/`)
| File | Role | Notable commands |
|---|---|---|
| `deploywatcher.zsh` | Function library (sourced by `~/.zshrc`; at load it sources `config.zsh` and sets variables only — no network/commands until a `dw-*` command runs) | `gh api` (read), `gh run view`, `jq`, `osascript`, `open`, `ps`, `grep`, `awk`, `cut`, `kill -0` (liveness check), `sleep` |
| `config.zsh` (per-user, gitignored) / `config.example.zsh` (template) | Config: GitHub login, `owner/repo`, workflow file names, job identifiers. No secrets. `_dw_ensure` may auto-detect login/repo via `gh api user` / `gh repo view` if left empty. | variable assignments only |
| `run.zsh` | SwiftBar entry point — detaches the worker (`nohup`) and exits | `nohup`, `/bin/zsh`, `disown` |
| `worker.zsh` | The detached watcher process | `gh auth status` (logged, token masked), `osascript`, `source` |
| `status.zsh` | "Watcher status" menu action | `source`, `osascript` |
| `swiftbar-plugins/deploywatcher.1h.sh` | Renders the menu | `echo` only — no side effects |
| `dwcard.swift` / `dwcard` | Source + locally-compiled binary: an always-on-top WebView window that displays the result card. Loads ONLY the given local HTML file; its sole network action is opening an http(s) link the user clicks (e.g. "Open run") in the default browser. No other I/O. | `swiftc` (build), `WKWebView`, `NSWorkspace.open` |
| `results/<pid>.html` | Ephemeral result card written before display | run number, branch, times, job names, run URL |
| `watchers/<pid>.state` | Ephemeral state (label, branch, run number, start time, run URL) | written/removed by the watcher |
| `last-run.log` | Diagnostic log of the last launch | contains `gh auth status` output (token is masked by `gh`) |

## Execution triggers
- **Menu click** → runs the corresponding script (headless, `terminal=false`).
- **SwiftBar refresh** (hourly) → re-runs `deploywatcher.1h.sh`, which only `echo`s menu text (no side effects).
- **New shell** → `~/.zshrc` sources `deploywatcher.zsh`, which only defines variables and functions (nothing executes until a `dw-*` command is called).

## Data handling
- Reads: GitHub Actions run/job metadata (status, conclusion, branch, run number, start time, job names, run URL).
- Writes (local only): the diagnostic log and ephemeral per-watcher state files listed above.
- **No secrets are written or transmitted by these scripts.** The only credential involved is the `gh` token, which stays in the Keychain and is used solely for read calls.

## Hardening applied
- All files/dirs set to user-only (`700`/`600`); verified no group/world read or write.
- `umask 077` in the worker so any file it creates is user-only at birth.
- No auto-update mechanism — the scripts never modify themselves or fetch new code.

## Residual risk (stated plainly)
Because the menu actions auto-execute and invoke `gh` (write-capable token), the
**integrity of these local files matters**: any process able to overwrite them
could run code with the user's GitHub token. This is mitigated by the user-only
permissions above. SwiftBar is only the UI — the same watchers run as plain
`dw-*` shell commands from a terminal, so SwiftBar can be removed entirely
without losing functionality if that is preferred.
