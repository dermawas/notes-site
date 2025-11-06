# tools/snapshot.ps1
# Creates a progress snapshot and updates a GitHub Project v2 Draft Issue by title.
# Requirements: gh CLI logged in, Python (for validator), git available (optional).

param(
  [string]$CardTitle = "Ghostwriter: connect n8n → Decap CMS (draft push)",  # which card/body to update
  [switch]$Append                                                                      # append instead of replace
)

# ---- CONSTANTS ----
$OWNER    = "dermawas"
$PROJ_NO  = 2
$REPO     = (Resolve-Path ".").Path
$OUTFILE  = Join-Path $REPO "tools\progress_snapshot.md"

# ---- Helper: run a command safely and capture text ----
function Run-Cmd([string]$Cmd, [switch]$Quiet) {
  try {
    $out = Invoke-Expression $Cmd 2>&1 | Out-String
    if (-not $Quiet) { $out.Trim() }
    else { return $out.Trim() }
  } catch {
    return ""
  }
}

# ---- Section: front-matter validation (optional) ----
$fmReport = ""
$validator = Join-Path $REPO "tools\validate_frontmatter.py"
if (Test-Path $validator) {
  $fmReport = Run-Cmd "python `"$validator`""
}

# ---- Section: git status (optional) ----
$gitStatus = Run-Cmd "git status --porcelain=v1" -Quiet
$gitLog    = Run-Cmd "git log -n 5 --pretty=format:'%h %ad %s' --date=short" -Quiet

# ---- Known constants we want to keep in one place ----
$constants = @"
- Repo path: `$REPO = $REPO
- Owner / Project#: `$OWNER = $OWNER, `$PROJ_NO = $PROJ_NO
- n8n model (local Ollama): **llama3.2:1b**
- Validator entry point: tools/validate_frontmatter.py
- Fixer entry point     : tools/fix_frontmatter.py
"@

# ---- Build snapshot markdown ----
$ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss K")
$md = @"
# FlowformLab Snapshot — $ts

## Constants
$constants

## Front-matter validator (latest run)
