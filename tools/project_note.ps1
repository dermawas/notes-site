# project_note.ps1 — FlowformLab v4.5b
# No-duplicate guarantee:
# 1) List items by Title -> use content.id (DI_) to update
# 2) If none listed but we have cached PVTI -> poll GraphQL node(PVTI) for DI_ -> update (no create)
# 3) Only create when Title not listed AND no cached PVTI
# Stores:
#   - last_note_item_id.txt  (PVTI_ guard)
#   - last_note_draft_id.txt (DI_   cache)

[CmdletBinding()]
param(
  [string]$Owner         = "dermawas",
  [int]   $ProjectNumber = 2,
  [string]$Title         = "FlowformLab Project Snapshot",
  [string]$SnapshotPath  = "$PSScriptRoot\progress_snapshot.txt",
  [string]$LastItemId    = "$PSScriptRoot\last_note_item_id.txt",   # PVTI_ cache / create-guard
  [string]$LastDraftId   = "$PSScriptRoot\last_note_draft_id.txt",  # DI_ cache
  [string]$ProjectNodeId = "PVT_kwHOAOgW284BHRNH",
  [int]$PollTries        = 10,
  [int]$PollDelaySec     = 4
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

Write-Host "=== project_note.ps1 v4.5b ==="
Write-Host "Owner:          $Owner"
Write-Host "Project number: $ProjectNumber"
Write-Host "Project node id:$ProjectNodeId"
Write-Host "Title:          $Title"
Write-Host "Snapshot:       $SnapshotPath"

# ---------- utils ----------
function Read-AllText([string]$path){
  try { return [IO.File]::ReadAllText($path) } catch { throw "Failed to read: $path" }
}
function SaveText([string]$path,[string]$val){
  if($val){ $val | Out-File -LiteralPath $path -Encoding ASCII }
}
function LoadText([string]$path){
  if(Test-Path -LiteralPath $path){
    $v = (Get-Content -LiteralPath $path -Raw).Trim()
    if($v){ return $v }
  }
  return $null
}

# ---------- CLI helpers ----------
function Gh-ItemsJson {
  try { & $ghExe project item-list $ProjectNumber --owner "$Owner" --format json 2>$null } catch { return $null }
}
function Parse-Json($j){
  if(-not $j){ return @() }
  try { return $j | ConvertFrom-Json } catch { return @() }
}
function FindByTitleNewest($items,$title){
  $items | Where-Object { $_.title -eq $title } |
    Sort-Object @{Expression={$_.updatedAt}}, @{Expression={$_.createdAt}} -Descending |
    Select-Object -First 1
}

function Edit-By-DI([string]$di,[string]$title,[string]$bodyText){
  if(-not $di){ throw "Edit-By-DI: missing DI id" }
  Write-Host "Editing DraftIssue via DI=$di ..."
  & $ghExe project item-edit --project-id "$ProjectNodeId" --id "$di" --title "$title" --body @"
$bodyText
"@ | Out-Null
}

function Create-One([int]$projectNumber,[string]$owner,[string]$title,[string]$bodyText){
  Write-Host "Creating ONE DraftIssue card (no existing + no cached PVTI)..."
  $raw = & $ghExe project item-create $projectNumber --owner "$owner" --title "$title" --body @"
$bodyText
"@ --format json 2>$null
  $pvti = $null
  if($raw){
    try{
      $obj = $raw | ConvertFrom-Json
      if($obj.id){ $pvti = $obj.id }
      elseif($obj.items -and $obj.items.Count -gt 0){ $pvti = $obj.items[0].id }
    } catch { }
  }
  if($pvti){ Write-Host "Created PVTI=$pvti" } else { Write-Host "Warning: gh did not return PVTI id." }
  return $pvti
}

# ---------- GraphQL (only to resolve DI for cached PVTI) ----------
function GraphQL-DI-From-PVTI([string]$pvti){
  if(-not $pvti){ return $null }
  $q = @"
query GetDraftFromItem(\$id:ID!) {
  node(id:\$id) {
    __typename
    ... on ProjectV2Item {
      id
      content { __typename ... on DraftIssue { id title updatedAt } }
    }
  }
}
"@
  try{
    $raw = & $ghExe api graphql -f query="$q" -f id="$pvti" 2>$null
    if(-not $raw){ return $null }
    $obj = $raw | ConvertFrom-Json
    return $obj.data.node.content.id
  } catch { return $null }
}
function Poll-DI-From-PVTI([string]$pvti,[int]$tries,[int]$delaySec){
  for($i=1; $i -le $tries; $i++){
    $di = GraphQL-DI-From-PVTI $pvti
    if($di -and $di -like 'DI_*'){
      Write-Host ("Resolved DI from PVTI on attempt {0}: {1}" -f $i, $di)
      return $di
    }
    Write-Host "DI not yet attached; waiting $delaySec s (attempt $i/$tries)..."
    Start-Sleep -Seconds $delaySec
  }
  return $null
}

# ---------------- MAIN ----------------
$bodyText = Read-AllText $SnapshotPath
$cachedPVTI = LoadText $LastItemId
$cachedDI   = LoadText $LastDraftId

# A) Try NEWEST card by Title from CLI (happy path)
$items  = Parse-Json (Gh-ItemsJson)
$newest = FindByTitleNewest $items $Title

if($newest){
  $di = $null
  if($newest.content -and $newest.content.id -and $newest.content.id -like 'DI_*'){ $di = $newest.content.id }
  if($di){
    Edit-By-DI -di $di -title $Title -bodyText $bodyText
    SaveText $LastDraftId $di
    if($newest.id){ SaveText $LastItemId $newest.id }  # refresh PVTI guard
    Write-Host "Done (updated via item-list DI)."
    exit 0
  } else {
    Write-Host "Existing card(s) found but DI missing in CLI output; using PVTI guard only."
    if(-not $cachedPVTI -and $newest.id){ SaveText $LastItemId $newest.id }
    Write-Host "No edit performed to avoid duplicates."
    exit 0
  }
}

# B) No card listed by Title
if($cachedPVTI){
  Write-Host "No card listed, but cached PVTI exists: $cachedPVTI"
  $diFromPvti = Poll-DI-From-PVTI -pvti $cachedPVTI -tries $PollTries -delaySec $PollDelaySec
  if($diFromPvti){
    Edit-By-DI -di $diFromPvti -title $Title -bodyText $bodyText
    SaveText $LastDraftId $diFromPvti
    Write-Host "Done (updated via cached PVTI -> DI)."
    exit 0
  } else {
    Write-Host "Still waiting for DI to attach to cached PVTI; not creating a new card."
    exit 0
  }
}

# C) Truly no card and no PVTI -> create once
$pvtiNew = Create-One -projectNumber $ProjectNumber -owner $Owner -title $Title -bodyText $bodyText
if($pvtiNew){
  SaveText $LastItemId $pvtiNew
  $diNew = Poll-DI-From-PVTI -pvti $pvtiNew -tries $PollTries -delaySec $PollDelaySec
  if($diNew){
    Edit-By-DI -di $diNew -title $Title -bodyText $bodyText
    SaveText $LastDraftId $diNew
    Write-Host "Done (created and updated via DI)."
    exit 0
  } else {
    Write-Host "Created; DI not visible yet. Guard saved, will not create again."
    exit 0
  }
}

Write-Host "No action taken."
exit 0
