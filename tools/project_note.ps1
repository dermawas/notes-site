# project_note.ps1 — FlowformLab v4.3 (PVTI-first, no DI)
# Idempotent updates using gh CLI only:
# 1) Use stored PVTI_ -> item-edit
# 2) Else list items by title -> pick newest PVTI_ -> item-edit
# 3) Else create -> capture PVTI_ -> item-edit (same run)
# No DI / GraphQL content lookups. ASCII-only logs.

[CmdletBinding()]
param(
  [string]$Owner         = "dermawas",
  [int]   $ProjectNumber = 2,
  [string]$Title         = "FlowformLab Project Snapshot",
  [string]$SnapshotPath  = "$PSScriptRoot\progress_snapshot.txt",
  [string]$LastItemId    = "$PSScriptRoot\last_note_item_id.txt",   # PVTI_ cache
  [string]$ProjectNodeId = "PVT_kwHOAOgW284BHRNH"                    # used by item-edit
)

$ErrorActionPreference = "Stop"

function Resolve-Exe([string]$name,[string[]]$fallbacks){
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if($cmd){ return $cmd.Source }
  foreach($p in $fallbacks){ if(Test-Path $p){ return $p } }
  throw "GitHub CLI not found"
}
$ghExe = Resolve-Exe -name "gh" -fallbacks @(
  "$Env:ProgramFiles\GitHub CLI\gh.exe",
  "$Env:LocalAppData\Programs\GitHub CLI\gh.exe"
)

if(-not (Test-Path -LiteralPath $SnapshotPath)){ throw "Snapshot file not found: $SnapshotPath" }

Write-Host "=== project_note.ps1 v4.3 (PVTI-first) ==="
Write-Host "Owner:          $Owner"
Write-Host "Project number: $ProjectNumber"
Write-Host "Project node id:$ProjectNodeId"
Write-Host "Title:          $Title"
Write-Host "Snapshot:       $SnapshotPath"

function Read-AllText([string]$path){
  try { return [IO.File]::ReadAllText($path) } catch { throw "Failed to read: $path" }
}
function Save-PVTI([string]$pvti){
  if($pvti){ $pvti | Out-File -LiteralPath $LastItemId -Encoding ASCII }
}
function Load-PVTI(){
  if(Test-Path -LiteralPath $LastItemId){
    $v = (Get-Content -LiteralPath $LastItemId -Raw).Trim()
    if($v){ return $v }
  }
  return $null
}

# --- gh helpers (CLI-only) ---
function Gh-ItemsJson {
  try { & $ghExe project item-list $ProjectNumber --owner "$Owner" --format json 2>$null } catch { return $null }
}
function Parse-Json($j){
  if(-not $j){ return @() }
  try { return $j | ConvertFrom-Json } catch { return @() }
}
function FindNewestByTitle($items,$title){
  $items | Where-Object { $_.title -eq $title } |
    Sort-Object @{Expression={$_.updatedAt}}, @{Expression={$_.createdAt}} -Descending |
    Select-Object -First 1
}

function Edit-By-PVTI([string]$pvti,[string]$title,[string]$bodyText){
  if(-not $pvti){ throw "Edit-By-PVTI: missing pvti" }
  # NOTE: item-edit expects the project item id (PVTI_) + project id
  Write-Host "Editing item via PVTI=$pvti ..."
  & $ghExe project item-edit --project-id "$ProjectNodeId" --id "$pvti" --title "$title" --body @"
$bodyText
"@ | Out-Null
}

function Create-Item([int]$projectNumber,[string]$owner,[string]$title,[string]$bodyText){
  Write-Host "Creating new DraftIssue card (CLI create)..."
  $raw = & $ghExe project item-create $projectNumber --owner "$owner" --title "$title" --body @"
$bodyText
"@ --format json 2>$null
  $pvti = $null
  if($raw){
    try{
      $obj = $raw | ConvertFrom-Json
      if($obj.id){ $pvti = $obj.id }
      if(-not $pvti -and $obj.items -and $obj.items.Count -gt 0){ $pvti = $obj.items[0].id }
    } catch { }
  }
  if($pvti){ Write-Host "Created PVTI=$pvti" } else { Write-Host "Warning: gh did not return PVTI id." }
  return $pvti
}

# ---------------- MAIN ----------------
$bodyText = Read-AllText $SnapshotPath

# 1) Try cached PVTI directly
$pvti = Load-PVTI
if($pvti){
  try{
    Edit-By-PVTI -pvti $pvti -title $Title -bodyText $bodyText
    Write-Host "Done (updated via cached PVTI)."
    exit 0
  } catch {
    Write-Warning "Cached PVTI edit failed: $($_.Exception.Message)"
    # proceed to re-discover by title
  }
}

# 2) Discover newest PVTI by title (no create if one exists)
$items = Parse-Json (Gh-ItemsJson)
$newest = FindNewestByTitle $items $Title
if($newest -and $newest.id){
  try{
    Edit-By-PVTI -pvti $newest.id -title $Title -bodyText $bodyText
    Save-PVTI $newest.id
    Write-Host "Done (updated via title discovery)."
    exit 0
  } catch {
    Write-Warning "Edit via title discovery failed: $($_.Exception.Message)"
    # fall through to create
  }
}

# 3) Create one card (only if none exists), then edit immediately
$pvtiNew = Create-Item -projectNumber $ProjectNumber -owner $Owner -title $Title -bodyText $bodyText
if($pvtiNew){
  try{
    Edit-By-PVTI -pvti $pvtiNew -title $Title -bodyText $bodyText
    Save-PVTI $pvtiNew
    Write-Host "Done (created and updated same run)."
    exit 0
  } catch {
    Save-PVTI $pvtiNew
    Write-Host "Created PVTI cached; update failed this run but will succeed next."
    exit 0
  }
}

Write-Host "Could not create or update the snapshot card."
exit 1
