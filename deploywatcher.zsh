#!/usr/bin/env zsh
# DeployWatcher — GitHub Actions job watchers.
#
# Pops a macOS card the instant a run YOU triggered reaches its target job.
#
# Why job-level and not run-level: a deploy run reports overall
# conclusion=failure whenever its bundled Playwright E2E fails, even when the
# deploy job itself succeeded. Keying on the specific JOB avoids that false
# "FAILED" that makes run-level notifications untrustworthy.
#
# "Only me" = runs I TRIGGERED: _dw_runs_json filters on triggering_actor
# (see there for why not `actor`). Someone else's deploy can't trigger a popup,
# and my own deploys count even when I merged a colleague's commit.

# --- config -----------------------------------------------------------------
# Personal values live in config.zsh (gitignored); copy config.example.zsh.
[ -f "$HOME/.config/deploywatcher/config.zsh" ] && source "$HOME/.config/deploywatcher/config.zsh"
: ${DW_ACTOR:=}        # your GitHub login (auto-detected via gh if empty)
: ${DW_REPO:=}         # owner/name  (auto-detected from git remote if empty)
# Workflow file names + job identifiers (override in config.zsh per project):
: ${DW_WF_FEATURE:=deploy.yml}
: ${DW_WF_STAGING:=staging.yml}
: ${DW_WF_E2E:=e2e.yml}
: ${DW_DEPLOY_JOB:=deploy}
: ${DW_E2E_PATTERN:=Playwright e2e}

# Resolve DW_ACTOR / DW_REPO (from config, else auto-detect). Returns non-zero
# and shows a card if they can't be determined.
_dw_ensure() {
  [[ -n "$DW_ACTOR" ]] || DW_ACTOR=$(gh api user -q .login 2>/dev/null)
  [[ -n "$DW_REPO"  ]] || DW_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  [[ -n "$DW_ACTOR" && -n "$DW_REPO" ]] && return 0
  _dw_alert "DeployWatcher isn't configured yet.
Set DW_ACTOR and DW_REPO in
~/.config/deploywatcher/config.zsh
(copy config.example.zsh)."
  return 1
}

# --- popup (stays on screen until dismissed; no sound) ----------------------
_dw_popup() {
  local head=$1 body=$2 url=$3 res
  # Pass strings as argv so newlines in $body need no escaping.
  # `activate` pulls the dialog to the front when launched from the menu bar.
  res=$(osascript - "$head" "$body" <<'APPLESCRIPT'
on run argv
  try
    activate
  end try
  set theHead to item 1 of argv
  set theBody to item 2 of argv
  display dialog theHead & return & return & theBody with title "DeployWatcher" buttons {"Open run", "OK"} default button "OK"
end run
APPLESCRIPT
)
  [[ "$res" == *"Open run"* ]] && open "$url"
}

# --- native single-button dialog (fallback when dwcard is unavailable) -------
_dw_alert_native() {
  osascript - "$1" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  try
    activate
  end try
  display dialog (item 1 of argv) with title "DeployWatcher" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

# --- alert (edge cases: nothing found, no matching job, timeout) → info card -
_dw_alert() {
  local body; body=$(_dw_html_escape "$1"); body=${body//$'\n'/<br>}
  _dw_show_card info "Heads up" "DeployWatcher" "$body" "" 0 "$1" 300
}

# --- confirmation that the watcher latched → info card, auto-closes in 8s ----
_dw_confirm() {
  local body; body=$(_dw_html_escape "$1"); body=${body//$'\n'/<br>}
  _dw_show_card info "Now watching" "DeployWatcher" "$body" "" 8 "$1" 320
}

# --- HTML cards (rendered in the dwcard always-on-top WebView panel) ---------
_dw_html_escape() { local s=$1; s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; print -r -- "$s"; }

# Shared stylesheet for every card (result / picker / message).
_dw_css() {
  cat <<'CSS'
:root{--bg:#f4f5f7;--card:#fff;--text:#1c2024;--muted:#6b7280;--line:#e6e8eb;--ok:#1f9d55;--ok-soft:#e7f6ee;--bad:#d64545;--bad-soft:#fcecec;--accent:#4f46e5;--shadow:0 12px 40px rgba(0,0,0,.14);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif}
@media(prefers-color-scheme:dark){:root{--bg:#16181d;--card:#21242b;--text:#e7e9ee;--muted:#9aa1ad;--line:#31353d;--ok:#46c17f;--ok-soft:#1b2f25;--bad:#f0716f;--bad-soft:#33211f;--accent:#8b85f5;--shadow:0 12px 44px rgba(0,0,0,.5)}}
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:var(--bg);color:var(--text);display:flex;align-items:center;justify-content:center;padding:20px}
.card{width:100%;max-width:420px;background:var(--card);border-radius:16px;box-shadow:var(--shadow);overflow:hidden;border:1px solid var(--line)}
.banner{display:flex;align-items:center;gap:12px;padding:20px 22px;background:var(--ok-soft);border-bottom:1px solid var(--line)}
.banner .icon{width:40px;height:40px;border-radius:50%;display:grid;place-items:center;font-size:22px;background:var(--ok);color:#fff;flex:none}
.banner .headline{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--ok)}
.banner .title{font-size:18px;font-weight:700;margin-top:1px}
.card.fail .banner{background:var(--bad-soft)}.card.fail .banner .icon{background:var(--bad)}.card.fail .banner .headline{color:var(--bad)}
.card.info .banner{background:var(--card)}.card.info .banner .icon{background:var(--accent)}.card.info .banner .headline{color:var(--accent)}
.meta{display:grid;grid-template-columns:auto 1fr;gap:6px 16px;padding:18px 22px;font-size:14px;border-bottom:1px solid var(--line)}
.meta dt{color:var(--muted)}.meta dd{margin:0;font-variant-numeric:tabular-nums;font-weight:600}
.meta .branch{font-family:ui-monospace,"SF Mono",Menlo,monospace}
.jobs{padding:14px 22px 6px}.jobs h3{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:0 0 8px}
.job{display:flex;align-items:center;gap:10px;padding:7px 0;font-size:14px;border-bottom:1px solid var(--line)}.job:last-child{border-bottom:0}
.job .dot{width:18px;text-align:center}.job .name{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:13px}
.body{padding:18px 22px;font-size:14px;line-height:1.55;color:var(--text)}.body .mono{font-family:ui-monospace,"SF Mono",Menlo,monospace}
.actions{display:flex;gap:10px;padding:16px 22px 20px}
.btn{flex:1;text-align:center;text-decoration:none;font:inherit;font-weight:600;font-size:14px;padding:10px 14px;border-radius:10px;cursor:pointer;border:1px solid var(--line)}
.btn.primary{background:var(--accent);color:#fff;border-color:transparent}.btn.secondary{background:transparent;color:var(--text)}
.btn.mini{flex:none;padding:6px 14px;font-size:13px;border-radius:8px}
.kill{flex:none;width:26px;height:26px;border-radius:50%;display:inline-grid;place-items:center;border:1px solid var(--line);color:var(--muted);text-decoration:none;font-size:12px;line-height:1}
.kill:hover{background:var(--bad-soft);color:var(--bad);border-color:var(--bad)}
.foot{text-align:center;font-size:12px;color:var(--muted);padding-bottom:8px}
.head{padding:18px 22px 6px}.head h2{margin:0;font-size:16px;font-weight:700}.head p{margin:4px 0 0;font-size:13px;color:var(--muted)}
.list{padding:8px 12px;max-height:340px;overflow-y:auto}
.row{display:flex;align-items:center;gap:10px;padding:11px 12px;border-radius:10px;text-decoration:none;color:var(--text)}
.row:hover{background:var(--ok-soft)}@media(prefers-color-scheme:dark){.row:hover{background:#2a2e37}}
.row .num{font-weight:700;font-variant-numeric:tabular-nums;min-width:54px}
.row .br{flex:1;font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .pill{font-size:11px;font-weight:700;padding:2px 8px;border-radius:999px;background:var(--line);color:var(--muted)}
.row .pill.ok{background:var(--ok-soft);color:var(--ok)}.row .pill.bad{background:var(--bad-soft);color:var(--bad)}.row .pill.run{background:#e6ecff;color:var(--accent)}
@media(prefers-color-scheme:dark){.row .pill.run{background:#23253a}}
.row .tm{font-size:12px;color:var(--muted);white-space:nowrap}
.inp{width:100%;padding:10px 12px;font:inherit;font-size:14px;border:1px solid var(--line);border-radius:10px;background:var(--bg);color:var(--text)}
.inp:focus{outline:none;border-color:var(--accent)}
.seg{display:flex;gap:16px;margin-top:12px;font-size:13px}
.seg label{display:flex;align-items:center;gap:6px;cursor:pointer}
CSS
}

# Echoes a self-contained HTML card.
# $1 ok|fail | $2 headline | $3 label | $4 num | $5 branch | $6 started
# $7 finished | $8 dur | $9 jobs_title | $10 jobs_html | $11 url
_dw_result_html() {
  local sc=$1 headline=$2 label=$3 num=$4 br=$5 started=$6 finished=$7 dur=$8 jt=$9 jobs=${10} url=${11}
  local icon; [[ "$sc" == ok ]] && icon="✓" || icon="✕"
  cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>$(_dw_html_escape "$label")</title>
<style>$(_dw_css)</style></head><body>
<div class="card ${sc}">
  <div class="banner"><div class="icon">${icon}</div>
    <div><div class="headline">$(_dw_html_escape "$headline")</div><div class="title">$(_dw_html_escape "$label")</div></div></div>
  <dl class="meta">
    <dt>Run</dt><dd>#${num}</dd>
    <dt>Branch</dt><dd class="branch">$(_dw_html_escape "$br")</dd>
    <dt>Started</dt><dd>$(_dw_html_escape "$started")</dd>
    <dt>Finished</dt><dd>$(_dw_html_escape "$finished") &nbsp;·&nbsp; ${dur}</dd>
  </dl>
  <div class="jobs"><h3>$(_dw_html_escape "$jt")</h3>${jobs}</div>
  <div class="actions"><a class="btn primary" href="${url}">Open run ↗</a>
    <a class="btn secondary" href="dwcard://close">Dismiss</a></div>
  <div class="foot">DeployWatcher</div>
</div></body></html>
HTML
}

# Run picker card. $1 = runs JSON. Rows link to dwcard://pick/<databaseId>.
_dw_picker_html() {
  local json=$1 rows
  rows=$(echo "$json" | jq -r '
    .[:12][] |
    "<a class=\"row\" href=\"dwcard://pick/\(.databaseId)\">"
    + "<span class=\"num\">#\(.number)</span>"
    + "<span class=\"br\">\(.headBranch|@html)</span>"
    + "<span class=\"pill " + (if .status!="completed" then "run" elif .conclusion=="success" then "ok" else "bad" end) + "\">"
    + (.status + (if .conclusion then "/"+.conclusion else "" end)) + "</span>"
    + "<span class=\"tm\">\(.createdAt[5:16]|sub("T";" "))</span></a>"')
  cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Pick a run</title>
<style>$(_dw_css)</style></head><body>
<div class="card info">
  <div class="head"><h2>Which run do you want to watch?</h2><p>Newest first · click one</p></div>
  <div class="list">${rows}</div>
  <div class="actions"><a class="btn secondary" href="dwcard://close">Cancel</a></div>
</div></body></html>
HTML
}

# Generic message/info card (confirm / alert / status).
# $1 sc(ok|fail|info) | $2 headline | $3 title | $4 body_html | $5 buttons_html | $6 autoclose_secs(0=none)
_dw_text_card() {
  local sc=$1 hl=$2 title=$3 body=$4 buttons=$5 auto=${6:-0}
  local icon; case "$sc" in ok) icon="✓" ;; fail) icon="✕" ;; *) icon="i" ;; esac
  local autojs=""
  [[ "$auto" != 0 ]] && autojs="<script>setTimeout(function(){location.href='dwcard://close';},$((auto*1000)));</script>"
  [[ -z "$buttons" ]] && buttons='<a class="btn secondary" href="dwcard://close">Dismiss</a>'
  cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>$(_dw_html_escape "$title")</title>
<style>$(_dw_css)</style></head><body>
<div class="card ${sc}">
  <div class="banner"><div class="icon">${icon}</div>
    <div><div class="headline">$(_dw_html_escape "$hl")</div><div class="title">$(_dw_html_escape "$title")</div></div></div>
  <div class="body">${body}</div>
  <div class="actions">${buttons}</div>
  <div class="foot">DeployWatcher</div>
</div>${autojs}</body></html>
HTML
}

# Show a message card via dwcard (fallback: native dialog). Backgrounded.
# $1 sc | $2 headline | $3 title | $4 body_html | $5 buttons_html | $6 autoclose | $7 fallback_text
_dw_show_card() {
  local card="$HOME/.config/deploywatcher/dwcard" outdir="$HOME/.config/deploywatcher/results" f
  if [[ -x "$card" ]]; then
    mkdir -p "$outdir"; f="$outdir/msg-$$-$RANDOM.html"
    _dw_text_card "$1" "$2" "$3" "$4" "$5" "$6" > "$f"
    nohup "$card" "$f" "$3" 420 "${8:-440}" >/dev/null 2>&1 &
    disown 2>/dev/null
  else
    _dw_alert_native "${7}"
  fi
}

# Write the card and show it in dwcard; fall back to the native dialog.
# $1..$11 as _dw_result_html | $12 head | $13 body (native fallback text)
_dw_show_result() {
  local card="$HOME/.config/deploywatcher/dwcard" outdir="$HOME/.config/deploywatcher/results" outfile
  mkdir -p "$outdir"
  outfile="$outdir/$$.html"
  _dw_result_html "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" > "$outfile"
  if [[ -x "$card" ]]; then
    nohup "$card" "$outfile" "$3" >/dev/null 2>&1 &
    disown 2>/dev/null
  else
    _dw_popup "${12}" "${13}" "${11}"   # fallback: native dialog
  fi
}

# --- watch a run's target jobs to completion --------------------------------
# $1 run id | $2 match mode: eq|re | $3 name/pattern | $4 label
_dw_watch_jobs() {
  local id=$1 mode=$2 pat=$3 label=$4 filter
  if [[ "$mode" == eq ]]; then filter='.name == $pat'; else filter='(.name | test($pat))'; fi
  local meta url br num created started epoch
  meta=$(gh run view "$id" -R "$DW_REPO" --json url,headBranch,number,createdAt)
  url=$(echo "$meta" | jq -r .url)
  br=$(echo "$meta" | jq -r .headBranch)
  num=$(echo "$meta" | jq -r .number)          # GitHub run number, e.g. #584
  created=$(echo "$meta" | jq -r .createdAt)   # ISO UTC
  # Convert start time to local, human-readable.
  epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" -u "$created" +%s 2>/dev/null)
  if [[ -n "$epoch" ]]; then started=$(date -r "$epoch" "+%b %-d, %H:%M" 2>/dev/null); else started="$created"; fi
  echo "👀 watching #$num ($br) — $label (Ctrl-C to stop)…"
  # Record what this watcher latched onto, so `dw-status` can show it.
  local statedir="$HOME/.config/deploywatcher/watchers"
  mkdir -p "$statedir"
  local statefile="$statedir/$$.state"
  print -r -- "${label}"$'\t'"${br}"$'\t'"${num}"$'\t'"${started}"$'\t'"${url}" > "$statefile"
  local watch_desc
  if [[ "$mode" == eq ]]; then watch_desc="the '$pat' job"; else watch_desc="the E2E jobs (matching '$pat')"; fi
  _dw_confirm "👀 Now watching — ${label}
run #${num}  ·  branch ${br}
started ${started}
target: ${watch_desc}

A dialog will pop when it finishes.
(this note closes itself)"
  local jobs total pending rstatus w=0
  while true; do
    rstatus=$(gh run view "$id" -R "$DW_REPO" --json status -q .status)
    jobs=$(gh run view "$id" -R "$DW_REPO" --json jobs)
    total=$(echo "$jobs"   | jq --arg pat "$pat" "[.jobs[] | select($filter)] | length")
    pending=$(echo "$jobs" | jq --arg pat "$pat" "[.jobs[] | select($filter) | select(.status != \"completed\")] | length")
    # Done only once the target job(s) EXIST and have all completed.
    # (Guards the queued-run case where the job isn't created yet — total=0.)
    [[ "$total" -gt 0 && "$pending" == "0" ]] && break
    # If the whole run ended without the target job ever appearing, stop too.
    [[ "$rstatus" == "completed" ]] && break
    # Safety cap: ~90 min (360 × 15s) so a stuck 'waiting' run can't zombie.
    w=$((w + 1))
    if (( w > 360 )); then
      echo "⏱ gave up after ~90 min — $label run $id still $rstatus."
      rm -f "$statefile"
      _dw_alert "⏱ ${label}: gave up after ~90 min — run #${id} still not finished (status: ${rstatus}). Check it on GitHub."
      return 1
    fi
    sleep 15
  done
  if [[ "$total" == "0" ]]; then
    echo "⚠️ run $id finished with no '$label' job."
    rm -f "$statefile"
    _dw_alert "⚠️ ${label}: run finished, but it had no matching job."
    return 1
  fi
  local jobsbody failed
  jobsbody=$(echo "$jobs" \
    | jq -r --arg pat "$pat" "[.jobs[] | select($filter) | (if .conclusion==\"success\" then \"✅ \" else \"❌ \" end) + .name] | join(\"\n\")")
  failed=$(echo "$jobs" \
    | jq --arg pat "$pat" "[.jobs[] | select($filter) | select(.conclusion != \"success\")] | length")
  local head
  if [[ "$failed" == "0" ]]; then head="✅ ${label}: DONE"; else head="❌ ${label}: ${failed} job(s) failed"; fi
  # --- fields for the HTML card ---
  local now dur finished sc headline jt jobs_html rows st jname dot esc
  now=$(date +%s)
  if [[ -n "$epoch" ]]; then
    local d=$((now - epoch))
    if (( d >= 3600 )); then dur="$((d/3600))h $(((d%3600)/60))m"; else dur="$((d/60))m $((d%60))s"; fi
  else dur="—"; fi
  finished=$(date "+%b %-d, %H:%M")
  if [[ "$failed" == "0" ]]; then sc=ok; headline="Finished successfully"; else sc=fail; headline="${failed} job(s) failed"; fi
  [[ "$mode" == eq ]] && jt="Deploy job" || jt="E2E jobs"
  # Build job rows (here-string keeps $jobs_html out of a subshell).
  rows=$(echo "$jobs" | jq -r --arg pat "$pat" "[.jobs[] | select($filter) | (if .conclusion==\"success\" then \"ok\" else \"bad\" end) + \"\t\" + .name] | .[]")
  jobs_html=""
  while IFS=$'\t' read -r st jname; do
    [[ -z "$st" ]] && continue
    esc=$(_dw_html_escape "$jname")
    [[ "$st" == ok ]] && dot="✅" || dot="❌"
    jobs_html+="<div class=\"job $st\"><span class=\"dot\">$dot</span><span class=\"name\">$esc</span></div>"
  done <<< "$rows"
  # Native-dialog fallback text (used only if dwcard is missing).
  local body="run #${num}  ·  branch ${br}
started ${started}

${jobsbody}"
  echo "$head"
  _dw_show_result "$sc" "$headline" "$label" "$num" "$br" "$started" "$finished" "$dur" "$jt" "$jobs_html" "$url" "$head" "$body"
  rm -f "$statefile"
}

# --- MY runs for a workflow -------------------------------------------------
# JSON array (newest first) of runs I TRIGGERED — matched on triggering_actor.
# Uses the REST API on purpose: `gh run list --user` only sees `actor`, which
# MISSES runs you triggered on someone else's commit (e.g. merging their PR
# into staging) and INCLUDES runs others triggered on your commit — the exact
# opposite of "runs I kicked off". $1 workflow file | $2 branch (optional).
_dw_runs_json() {
  local wf=$1 branch=$2 q="per_page=20"
  [[ -n "$branch" ]] && q="${q}&branch=${branch}"
  gh api "repos/${DW_REPO}/actions/workflows/${wf}/runs?${q}" \
    --jq "[.workflow_runs[]
           | select(.triggering_actor.login==\"${DW_ACTOR}\")
           | {databaseId:.id, status:.status, conclusion:.conclusion,
              headBranch:.head_branch, createdAt:.created_at,
              number:.run_number, url:.html_url}]" 2>/dev/null
}

# --- pick a run from a list -------------------------------------------------
# Echoes the chosen run's databaseId (empty if cancelled / none).
# $1 workflow | $2 branch (optional)
_dw_pick_run() {
  local wf=$1 branch=$2
  local json
  json=$(_dw_runs_json "$wf" "$branch")
  [[ -z "$json" || "$json" == "[]" ]] && { print ""; return; }

  local card="$HOME/.config/deploywatcher/dwcard"
  if [[ -x "$card" ]]; then
    # HTML picker card — dwcard runs in the FOREGROUND and prints the chosen
    # databaseId (via dwcard://pick/<id>) to stdout, which becomes our output.
    local outdir="$HOME/.config/deploywatcher/results" pf
    mkdir -p "$outdir"; pf="$outdir/pick-$$.html"
    _dw_picker_html "$json" > "$pf"
    "$card" "$pf" "DeployWatcher — pick a run" 470 520
    rm -f "$pf"
    return
  fi

  # Fallback: native choose-from-list (shows run number, maps back to id).
  local labels chosen picknum
  labels=$(echo "$json" | jq -r '.[:10][] | "#\(.number) · \(.headBranch) · \(.status)/\(.conclusion // "-") · \(.createdAt[5:16] | sub("T";" "))"')
  chosen=$(osascript - "$labels" <<'APPLESCRIPT'
on run argv
  set AppleScript's text item delimiters to linefeed
  set theItems to text items of (item 1 of argv)
  try
    activate
  end try
  set c to choose from list theItems with prompt "Which run do you want to watch?" with title "DeployWatcher — pick a run" default items {item 1 of theItems} OK button name "Watch" cancel button name "Cancel"
  if c is false then return ""
  return item 1 of c
end run
APPLESCRIPT
)
  picknum=$(print -r -- "$chosen" | grep -oE '^#[0-9]+' | tr -d '#')
  [[ -z "$picknum" ]] && { print ""; return; }
  echo "$json" | jq -r --arg n "$picknum" '.[] | select(.number == ($n|tonumber)) | .databaseId' | head -1
}

# --- choose the right run, then watch it ------------------------------------
# Deploy watchers: auto-watch the one in-flight run (you just triggered it).
# E2E watchers pass --pick to ALWAYS show the picker (you're usually choosing
# which run's E2E to inspect, often an already-finished one).
# $1 workflow file | $2 mode | $3 pattern | $4 label | rest: --branch X / --pick
_dw_find_and_watch() {
  local wf=$1 mode=$2 pat=$3 label=$4; shift 4
  local branch="" force_pick=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch=$2; shift 2 ;;
      --pick)   force_pick=1; shift ;;
      *)        shift ;;
    esac
  done
  local id=""
  if [[ -n "$force_pick" ]]; then
    echo "🔎 pick a '${label}' run…"
    id=$(_dw_pick_run "$wf" "$branch")   # always choose (incl. finished runs)
  else
    echo "⏳ looking for your (${DW_ACTOR}) '${label}' runs…"
    # Wait up to ~2 min for a just-triggered run to appear (click-after-merge).
    local ncids="" n=0
    while [[ -z "$ncids" && $n -lt 24 ]]; do
      ncids=$(_dw_runs_json "$wf" "$branch" \
        | jq -r '[.[] | select(.status != "completed") | .databaseId] | join("\n")')
      [[ -z "$ncids" ]] && { sleep 5; n=$((n + 1)); }
    done
    local count=0
    [[ -n "$ncids" ]] && count=$(print -r -- "$ncids" | grep -c .)
    if [[ "$count" == "1" ]]; then
      id="$ncids"                        # exactly one running → watch it
    else
      echo "… ${count} in-flight run(s) — showing picker."
      id=$(_dw_pick_run "$wf" "$branch") # 0 or many → you choose
    fi
  fi
  if [[ -z "$id" ]]; then
    echo "❌ no run selected for '${label}'."
    _dw_alert "⚠️ ${label}: nothing to watch — no run selected (or none found)."
    return 1
  fi
  _dw_watch_jobs "$id" "$mode" "$pat" "$label"
}

# --- the commands -----------------------------------------------------------
dw-feature()     {
  _dw_ensure || return
  local br; br=$(git branch --show-current 2>/dev/null)
  if [[ -n "$br" ]]; then
    _dw_find_and_watch "$DW_WF_FEATURE" eq "$DW_DEPLOY_JOB" "Feature deploy ($br)" --branch "$br"
  else
    _dw_find_and_watch "$DW_WF_FEATURE" eq "$DW_DEPLOY_JOB" "Feature deploy"
  fi
}
dw-staging()     { _dw_ensure || return; _dw_find_and_watch "$DW_WF_STAGING" eq "$DW_DEPLOY_JOB" "Staging deploy"; }
dw-e2e()         {
  # E2E on feature = the E2E jobs inside the feature deploy run
  # (gated behind approve-e2e), NOT a standalone dispatch.
  _dw_ensure || return
  local br; br=$(git branch --show-current 2>/dev/null)
  if [[ -n "$br" ]]; then
    _dw_find_and_watch "$DW_WF_FEATURE" re "$DW_E2E_PATTERN" "E2E (feature) ($br)" --branch "$br" --pick
  else
    _dw_find_and_watch "$DW_WF_FEATURE" re "$DW_E2E_PATTERN" "E2E (feature)" --pick
  fi
}
dw-staging-e2e() { _dw_ensure || return; _dw_find_and_watch "$DW_WF_STAGING" re "$DW_E2E_PATTERN" "E2E (staging)" --pick; }
# Standalone E2E dispatch (DW_WF_E2E), any branch of your choosing.
dw-e2e-direct()  { _dw_ensure || return; _dw_find_and_watch "$DW_WF_E2E" re "$DW_E2E_PATTERN" "E2E (direct)" --pick; }

# --- watch ANY run by URL/ID (no actor filter — works for colleagues' runs) --
# Terminal:  dw-url <run-url-or-id> [e2e|deploy|all]   (default e2e)
dw-url() {
  _dw_ensure || return
  local input=$1 m=${2:-e2e} id
  id=$(print -r -- "$input" | grep -oE '[0-9]{6,}' | head -1)
  if [[ -z "$id" ]]; then
    echo "usage: dw-url <run-url-or-id> [e2e|deploy|all]"
    return 1
  fi
  case "$m" in
    deploy) _dw_watch_jobs "$id" eq "$DW_DEPLOY_JOB"  "Deploy (by URL)" ;;
    all)    _dw_watch_jobs "$id" re "."               "Run (by URL)" ;;
    *)      _dw_watch_jobs "$id" re "$DW_E2E_PATTERN" "E2E (by URL)" ;;
  esac
}

# HTML prompt card: URL/ID field + mode selector. Returns "mode<TAB>value".
_dw_prompt_html() {
  cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Watch any run</title>
<style>$(_dw_css)</style></head><body>
<div class="card info">
  <div class="head"><h2>Watch any run</h2><p>Paste a GitHub Actions run URL or ID</p></div>
  <div class="body">
    <input id="u" class="inp" placeholder="github.com/…/runs/123  ·  or  ·  123456789" autofocus>
    <div class="seg">
      <label><input type="radio" name="m" value="e2e" checked> E2E jobs</label>
      <label><input type="radio" name="m" value="deploy"> Deploy job</label>
      <label><input type="radio" name="m" value="all"> Whole run</label>
    </div>
  </div>
  <div class="actions">
    <a class="btn secondary" href="dwcard://close">Cancel</a>
    <a class="btn primary" href="#" onclick="go();return false">Watch</a>
  </div>
</div>
<script>
  function go(){
    var u=document.getElementById('u').value.trim(); if(!u) return;
    var m=document.querySelector('input[name=m]:checked').value;
    location.href='dwcard://input/'+encodeURIComponent(m+'\t'+u);
  }
  var el=document.getElementById('u');
  el.focus();
  el.addEventListener('keydown',function(e){if(e.key==='Enter'){go();}});
</script></body></html>
HTML
}

# Menu bar:  prompt (URL + mode) in one card, then watch.
dw-url-interactive() {
  _dw_ensure || return
  local card="$HOME/.config/deploywatcher/dwcard" payload input mode id

  if [[ -x "$card" ]]; then
    local outdir="$HOME/.config/deploywatcher/results" pf
    mkdir -p "$outdir"; pf="$outdir/prompt-$$.html"
    _dw_prompt_html > "$pf"
    payload=$("$card" "$pf" "DeployWatcher — watch any run" 480 320)   # returns mode<TAB>value
    rm -f "$pf"
    [[ -z "$payload" ]] && return 0
    mode=${payload%%$'\t'*}
    input=${payload#*$'\t'}
  else
    # Fallback: native prompts.
    input=$(osascript \
      -e 'on run' -e 'try' -e 'activate' -e 'end try' \
      -e 'set r to display dialog "Paste a GitHub Actions run URL or run ID:" default answer "" with title "DeployWatcher — watch any run" buttons {"Cancel", "Watch"} default button "Watch"' \
      -e 'return text returned of r' -e 'end run' 2>/dev/null)
    [[ -z "$input" ]] && return 0
    mode=$(osascript \
      -e 'on run' -e 'try' -e 'activate' -e 'end try' \
      -e 'set c to choose from list {"e2e", "deploy", "all"} with prompt "Watch which jobs?" with title "DeployWatcher" default items {"e2e"} OK button name "Watch" cancel button name "Cancel"' \
      -e 'if c is false then return ""' -e 'return item 1 of c' -e 'end run' 2>/dev/null)
  fi

  id=$(print -r -- "$input" | grep -oE '[0-9]{6,}' | head -1)
  if [[ -z "$id" ]]; then
    _dw_alert "⚠️ Couldn't find a run ID in what you pasted."
    return 1
  fi
  case "$mode" in
    deploy) _dw_watch_jobs "$id" eq "$DW_DEPLOY_JOB"  "Deploy (by URL)" ;;
    all)    _dw_watch_jobs "$id" re "."               "Run (by URL)" ;;
    *)      _dw_watch_jobs "$id" re "$DW_E2E_PATTERN" "E2E (by URL)" ;;
  esac
}

# Pops a sample card so you can see what a real notification looks like.
dw-test() { _dw_show_result ok "Finished successfully" "Staging deploy" "584" "staging" "Jul 30, 14:00" "Jul 30, 14:23" "23m 0s" "Deploy job" '<div class="job ok"><span class="dot">✅</span><span class="name">deploy</span></div>' "https://github.com/${DW_REPO:-owner/repo}/actions" "✅ Staging deploy: DONE" "sample"; }

# --- is anything watching right now? ----------------------------------------
DW_STATEDIR="$HOME/.config/deploywatcher/watchers"

# Remove state files whose process is no longer alive.
_dw_clean_state() {
  local sf pid
  for sf in "$DW_STATEDIR"/*.state(N); do
    pid=${sf:t:r}
    kill -0 "$pid" 2>/dev/null || rm -f "$sf"
  done
}

# Alive worker PIDs, one per line.
_dw_alive_pids() {
  ps -Ao pid=,args= | grep -E "[d]eploywatcher/(worker|run)\.zsh .*dw-" | awk '{print $1}'
}

_dw_status_text() {
  _dw_clean_state
  local pids; pids=$(_dw_alive_pids)
  if [[ -z "$pids" ]]; then
    print "🔴 No watcher running."
    return
  fi
  print "🟢 Watcher(s) running:"
  local pid sf label br id url
  print -r -- "$pids" | while read -r pid; do
    sf="$DW_STATEDIR/$pid.state"
    if [[ -f "$sf" ]]; then
      IFS=$'\t' read -r label br num started url < "$sf"
      print "• ${label}"
      print "    branch:   ${br}"
      print "    run:      #${num}"
      print "    started:  ${started}"
      print "    ${url}"
    else
      # Alive but hasn't latched onto a run yet (still searching).
      print "• (pid ${pid}) — searching for your run…"
    fi
  done
}

# URLs of runs currently being watched, one per line.
_dw_status_urls() {
  local pid sf
  print -r -- "$(_dw_alive_pids)" | while read -r pid; do
    sf="$DW_STATEDIR/$pid.state"
    [[ -f "$sf" ]] && cut -f5 "$sf"
  done
}

# Terminal:  print the status line(s).
dw-status()       { _dw_status_text; }

# HTML body for the status card — one row per running watcher, with Open-run.
_dw_status_html_body() {
  _dw_clean_state
  local pids; pids=$(_dw_alive_pids)
  [[ -z "$pids" ]] && { print '<p>No watcher running.</p>'; return; }
  local pid sf label br num started url out=""
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    sf="$DW_STATEDIR/$pid.state"
    local kill_btn="<a class=\"kill\" href=\"dwcard://kill/${pid}\" title=\"Stop this watcher\">✕</a>"
    if [[ -f "$sf" ]]; then
      IFS=$'\t' read -r label br num started url < "$sf"
      out+="<div class=\"job\" data-pid=\"${pid}\"><div style=\"flex:1\"><strong>$(_dw_html_escape "$label")</strong><br><span class=\"mono\">$(_dw_html_escape "$br")</span> · #${num} · $(_dw_html_escape "$started")</div><a class=\"btn secondary mini\" href=\"$url\">Open ↗</a>${kill_btn}</div>"
    else
      out+="<div class=\"job\" data-pid=\"${pid}\"><div style=\"flex:1\">(pid ${pid}) — searching for your run…</div>${kill_btn}</div>"
    fi
  done <<< "$pids"
  print -r -- "$out"
}

# Menu bar:  pop the status card (Open-run links per watcher).
dw-status-popup() {
  local pids hl
  pids=$(_dw_alive_pids)
  [[ -n "$pids" ]] && hl="Watchers running" || hl="No watcher running"
  _dw_show_card info "$hl" "DeployWatcher — status" "$(_dw_status_html_body)" "" 0 "$(_dw_status_text)" 480
}
