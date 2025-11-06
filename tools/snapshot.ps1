<#  project_note.ps1
    Update (or create) a single Project note card by Title on a personal GitHub Projects v2 board.

    Behavior:
      - Reads the note body from tools\progress_snapshot.txt (or a custom file).
      - Looks for an existing Draft item with the same Title.
      - If found, tries to update via `gh project item-edit`.
        - If edit isn't supported in your gh version, it deletes the old card and creates a fresh one.
      - If not found, creates a new Draft note card.

    Usage:
      .\project_note.ps1
      .\project_note.ps1 -Title "FlowformLab Project Snapshot"
      .\project_note.ps1 -BodyPath "D:\path\to\custom_body.md"
#>

[CmdletBinding()]
param(
  [string]$Owner         = "dermawas",
  [int]   $ProjectNumber = 2,
  [string]$Title         = "FlowformLab Project Snapshot",
  [string]$RepoPath      = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$BodyPath      = "$PSScriptRoot\progress_snapshot.txt"
)

$ErrorActionPreference = "Stop"

# --- Sanity checks ---
if (-not (Test-Path -LiteralPath $RepoPath)) { throw "RepoPath not found: $RepoPath" }
$toolsDir = Join-Path $RepoPath "tools"
if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }
if (-not (Test-Path -LiteralPath $BodyPath)) { throw "Body file not found: $BodyPath" }

function Resolve-Exe([string]$name, [string[]]$fallbacks) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in $fallbacks) { if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}

$ghExe = Resolve-Exe -name "gh" -fallbacks @(
  "$Env:ProgramFiles\GitHub CLI\gh.exe",
  "$Env:LocalAppData\Programs\GitHub CLI\gh.exe"
)
if (-not $ghExe) { throw "GitHub CLI (gh) not found on PATH." }

# --- Load body text (as-is; keep multiline) ---
$body = Get-Content -LiteralPath $BodyPath -Raw

Write-Host "🔎 Searching existing items on project #$ProjectNumber (owner=$Owner)..."
# item-list JSON typically includes: id, title, type, content, etc.
# We only need id + title.
$itemListJson = & $ghExe project item-list $ProjectNumber --owner "$Owner" --format json 2>$null
$existing = $null
if ($itemListJson) {
  try {
    $items = $itemListJson | ConvertFrom-Json
    # Match exact title on Draft items first
    $existing = $items | Where-Object { $_.title -eq $Title -and ($_.type -eq "DRAFT_ISSUE" -or -not $_.type) } | Select-Object -First 1
    # If not found, match exact title regardless of type
    if (-not $existing) { $existing = $items | Where-Object { $_.title -eq $Title } | Select-Object -First 1 }
  } catch {
    Write-Warning "Could not parse gh JSON: $($_.Exception.Message)"
  }
} else {
  Write-Warning "No output from 'gh project item-list'. (Older gh? Not authenticated?)"
}

function TryEdit {
  param([string]$ItemId, [string]$TitleToSet, [string]$BodyToSet)
  Write-Host "✏️  Trying in-place edit (gh project item-edit)..."
  try {
    & $ghExe project item-edit $ProjectNumber --owner "$Owner" --id "$ItemId" --title "$TitleToSet" --body @"
$BodyToSet
"@
    return $true
  } catch {
    Write-Warning "item-edit failed: $($_.Exception.Message)"
    return $false
  }
}

function CreateNew {
  param([string]$TitleToSet, [string]$BodyToSet)
  Write-Host "➕ Creating new note..."
  & $ghExe project item-create $ProjectNumber --owner "$Owner" --title "$TitleToSet" --body @"
$BodyToSet
"@
}

function DeleteItem {
  param([string]$ItemId)
  Write-Host "🗑️  Deleting old item id=$ItemId..."
  try {
    & $ghExe project item-delete $ProjectNumber --owner "$Owner" --id "$ItemId"
  } catch {
    Write-Warning "Delete failed: $($_.Exception.Message)"
  }
}

if ($existing -and $existing.id) {
  Write-Host "✅ Found existing item: id=$($existing.id)  title='$($existing.title)'"
  # Try an in-place edit first; if not supported, delete + create new.
  if (-not (TryEdit -ItemId $existing.id -TitleToSet $Title -BodyToSet $body)) {
    DeleteItem -ItemId $existing.id
    CreateNew -TitleToSet $Title -BodyToSet $body
  } else {
    Write-Host "✅ Updated existing card."
  }
} else {
  Write-Host "ℹ️  No existing item with title '$Title' — will create a new one."
  CreateNew -TitleToSet $Title -BodyToSet $body
}

Write-Host "🎯 Done."
