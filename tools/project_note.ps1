# project_note.ps1 (ASCII-only, v2025-11-06-E)
# Update or create ONE "FlowformLab Project Snapshot" card without duplicates.
# Logic order:
# 1) Use stored DI_ to edit
# 2) Use stored PVTI_ -> resolve DI_ with retries -> edit
# 3) List by title -> resolve DI_ with retries -> edit
# 4) Create -> capture PVTI_ -> resolve DI_ with retries -> edit (else save PVTI_ for next run)

[CmdletBinding()]
param(
  [string]$Owner         = "dermawas",
  [int]   $ProjectNumber = 2,
  [string]$Title         = "FlowformLab Project Snapshot",
  [string]$RepoPath      = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$SnapshotPath  = "$PSScriptRoot\progress_snapshot.txt",
  [string]$LastItemId    = "$PSScriptRoot\last_note_item_id.txt",   # PVTI_...
  [string]$LastDraftId   = "$PSScriptRoot\last_note_draft_id.txt"   # DI_...
)

$ErrorActionPreference = "Stop"
$ProjectId = "PVT_kwHOAOgW284BHRNH"

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

function Gh-Items {
  try { & $ghExe project item-list $ProjectNumber --owner "$Owner" --format json 2>$null } catch { return $null }
}
function Parse-Json($j){
  if(-not $j){ return @() }
  try { $j | ConvertFrom-Json } catch { @() }
}
function FindNewestByTitle($items,$title){
  $items | Where-Object { $_.title -eq $title } |
    Sort-Object @{Expression={$_.updatedAt}}, @{Expression={$_.createdAt}} -Descending |
    Select-Object -First 1
}
function Resolve-DI-Once($pvti){
  if(-not $pvti){ return $null }
  $q = @"
query Q(\$id:ID!){
  node(id:\$id){
    __typename
    ... on ProjectV2Item {
      id
      content { __typename ... on DraftIssue { id } }
    }
  }
}
"@
  try {
    $raw = & $ghExe api graphql -f query="$q" -f id="$pvti" 2>$null
    if(-not $raw){ return $null }
    $obj = $raw | ConvertFrom-Json
    if($obj -and $obj.data -and $obj.data.node -and $obj.data.node.content -and $obj.data.node.content.id){
      return $obj.data.node.content.id
    }
    return $null
  } catch { return $null }
}
function Resolve-DI-With-Retry($pvti,$tries=10,$delaySec=1){
  for($i=1; $i -le $tries; $i++){
    $di = Resolve-DI-Once $pvti
    if($di){ return $di }
    Start-Sleep -Seconds $delaySec
  }
  return $null
}
function SaveIds($pvti,$di){
  if($pvti){ $pvti | Out-File -LiteralPath $LastItemId  -Encoding ASCII }
  if($di){   $di   | Out-File -LiteralPath $LastDraftId -Encoding ASCII }
}
function Edit-Draft($di,$title,$body){
  Write-Host "Editing draft (DI) id=$di ..."
  & $ghExe project item-edit --project-id "$ProjectId" --id "$di" --title "$title" --body @"
$body
"@
}
function Create-Item-Capture($title,$body){
  Write-Host "Creating new note (attempt capture via JSON)..."
  $raw = & $ghExe project item-create $ProjectNumber --owner "$Owner" --title "$title" --body @"
$body
"@ --format json 2>$null

  $pvti = $null
  $di   = $null
  if($raw){
    try {
      $obj = $raw | ConvertFrom-Json
      if($obj.id){ $pvti = $obj.id }
      if($obj.content -and $obj.content.id){ $di = $obj.content.id }
      if(-not $pvti -and $obj.items -and $obj.items.Count -gt 0){
        $pvti = $obj.items[0].id
        if($obj.items[0].content -and $obj.items[0].content.id){ $di = $obj.items[0].content.id }
      }
    } catch { }
  }

  if(-not $pvti){
    # As a fallback, try to find newest by title once
    $latest = Parse-Json (Gh-Items) | FindNewestByTitle $title
    if($latest -and $latest.id){ $pvti = $latest.id }
  }
  if($pvti -and -not $di){
    # Poll DI as it often lags by a second or two
    $di = Resolve-DI-With-Retry $pvti 10 1
  }
  SaveIds $pvti $di
  return @{ pvti=$pvti; di=$di }
}

# MAIN
$body = Get-Content -LiteralPath $SnapshotPath -Raw
Write-Host "project_note.ps1 :: resolve-safe mode"

# 1) Try stored DI first
$storedDI = if(Test-Path -LiteralPath $LastDraftId){ (Get-Content -LiteralPath $LastDraftId -Raw).Trim() } else { $null }
if($storedDI -and $storedDI -like 'DI_*'){
  try{
    Edit-Draft $storedDI $Title $body
    Write-Host "Updated existing card (stored DI)."
    exit 0
  } catch {
    Write-Warning "Stored DI edit failed: $($_.Exception.Message)"
  }
}

# 2) Try stored PVTI -> resolve DI with retry
$storedPVTI = if(Test-Path -LiteralPath $LastItemId){ (Get-Content -LiteralPath $LastItemId -Raw).Trim() } else { $null }
if($storedPVTI -and $storedPVTI -like 'PVTI_*'){
  $diFromStored = Resolve-DI-With-Retry $storedPVTI 10 1
  if($diFromStored){
    try{
      Edit-Draft $diFromStored $Title $body
      SaveIds $storedPVTI $diFromStored
      Write-Host "Updated existing card (resolved DI from stored PVTI)."
      exit 0
    } catch {
      Write-Warning "Edit via stored PVTI/DI failed: $($_.Exception.Message)"
    }
  }
}

# 3) Try list by title -> resolve DI with retry
$items = Parse-Json (Gh-Items)
$found = FindNewestByTitle $items $Title
if($found -and $found.id){
  $pvti = $found.id
  $di = Resolve-DI-With-Retry $pvti 10 1
  if($di){
    try{
      Edit-Draft $di $Title $body
      SaveIds $pvti $di
      Write-Host "Updated card via title match."
      exit 0
    } catch {
      Write-Warning "Edit via title match failed: $($_.Exception.Message)"
    }
  }
}

# 4) Create and capture IDs directly (with retries on DI)
$cap = Create-Item-Capture $Title $body
$pvtiNew = $cap.pvti
$diNew   = $cap.di
if($diNew){
  try{
    Edit-Draft $diNew $Title $body
    Write-Host "Updated immediately after creation."
    exit 0
  } catch { }
}
if($pvtiNew){
  Write-Host "Saved PVTI=$pvtiNew. Could not resolve DI yet; next run should update."
  exit 0
}

Write-Host "Could not create or resolve item; no changes made."
