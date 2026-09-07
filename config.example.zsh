# DeployWatcher config — copy to config.zsh (gitignored) and edit for your setup.
DW_ACTOR="your-github-login"     # or leave empty to auto-detect via `gh api user`
DW_REPO="owner/repo"             # e.g. acme/webapp ; or leave empty to detect from git remote

# Workflow file names + job identifiers for YOUR project's CI:
DW_WF_FEATURE="deploy.yml"
DW_WF_STAGING="staging.yml"
DW_WF_E2E="e2e.yml"
DW_DEPLOY_JOB="deploy"           # the deploy job's exact name
DW_E2E_PATTERN="Playwright e2e"  # regex matched against E2E job names
