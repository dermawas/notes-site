# project_note.ps1 — FlowformLab v4.2a (param-compatible, DI resolver with poll + GraphQL fallback)
# Goal: Update or create ONE "FlowformLab Project Snapshot" DraftIssue card without duplicates.
# Order:
# 1) Use stored DI_ to edit
# 2) Use stored PVTI_ -> poll DI_ -> edit
# 3) GraphQL list by title -> DI_ -> edit
# 4) Create -> capture PVTI_ -> poll DI_ -> edit (else save PVTI_ for next run)
# Notes: ASCII-only logging, requires gh CLI authenticated.

[CmdletBinding()]
param(
  [string]$Owner         = "dermawas",
  [int]   $ProjectNumber = 2,
  [string]$Title         = "FlowformLab Project Snapshot",
  [string]$RepoPath      = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$SnapshotPath  = "$PSScriptRoot\progress_snapshot.txt",
  [string]$LastItemId    = "$PSScriptRoot\last_note_item_id.txt",   # PVTI_...
  [string]$LastDraftId   = "$PSScriptRoot\last_note_draft_id.txt",  # DI_...
  # Known ProjectV2 node id; leave empty to auto-resolve via GraphQL
  [string]$ProjectNodeId = "PVT_kwHOAOgW284BHRNH",
  # Polling params (tuned for GitHub eventual consistency)
  [int]$MaxPollTries = 7,
  [int]$PollDelaySec = 12
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

Write-Host "=== project_note.ps1 v4.2a ==="
Write-Host "Owner:          $Owner"
Write-Host "Project number: $ProjectNumber"
Write-Host "Title:          $Title"
Write-Host "Snapshot:       $SnapshotPath"

# ---------- Utilities ----------
function Read-AllText([string]$path){
  try { return [IO.File]::ReadAllText($path) } catch { throw "Failed to read: $path" }
}
function Save-Ids([string]$pvti,[string]$di){
  if($pvti){ $pvti | Out-File -LiteralPath $LastItemId  -Encoding ASCII }
  if($di){   $di   | Out-File -LiteralPath $LastDraftId -Encoding ASCII }
}
function Load-Id([string]$path){
  if(Test-Path -LiteralPath $path){
    $v = (Get-Content -LiteralPath $path -Raw).Trim()
    if($v){ return $v }
  }
  return $null
}

function Resolve-Project-NodeId {
  if ($ProjectNodeId) { return $ProjectNodeId }
  Write-Host "Resolving Project node id via GraphQL..."
  $q = @"
query GetProject(\$owner:String!, \$number:Int!) {
  user(login:\$owner) {
    projectV2(number:\$number) { id title }
  }
}
"@
  $raw = & $ghExe api graphql -f query="$q" -f owner="$Owner" -F number=$ProjectNumber
  $obj = $raw | ConvertFrom-Json
  $id  = $obj.data.user.projectV2.id
  if (-not $id) { throw "Could not resolve ProjectV2 node id for $Owner #$ProjectNumber" }
  return $id
}

# ---------- Create / Edit ----------
function Edit-Draft([string]$draftId,[string]$title,[string]$bodyText){
  # IMPORTANT: Edit by DraftIssue id (DI_) via GraphQL mutation (not project item-edit)
  $m = @"
mutation UpdateDraft(\$draftId:ID!, \$title:String!, \$body:String!) {
  updateProjectV2DraftIssue(input:{ draftIssueId:\$draftId, title:\$title, body:\$body }) {
    projectItem { id }
  }
}
"@
  & $ghExe api graphql -f query="$m" -f draftId="$draftId" -f title="$title" -f body="$bodyText" | Out-Null
  Write-Host "Edited DraftIssue DI=$draftId"
}

function Create-Item-Capture([string]$title,[string]$bodyPath){
  # Create a DraftIssue card and capture PVTI_ (and DI_ if immediately available)
  Write-Host "Creating new DraftIssue card..."
  $raw = & $ghExe project item-create --owner "$Owner" --number $ProjectNumber --title "$title" --body-file "$bodyPath" --format json 2>$null
  $pvti = $null; $di = $null
  if($raw){
    try{
      $obj = $raw | ConvertFrom-Json
      if($obj.id){ $pvti = $obj.id }
      if($obj.content -and $obj.content.id){ $di = $obj.content.id }
      if(-not $pvti -and $obj.items -and $obj.items.Count -gt 0){
        $pvti = $obj.items[0].id
        if($obj.items[0].content -and $obj.items[0].content.id){ $di = $obj.items[0].content.id }
      }
    } catch { }
  }
  if($pvti){
    Write-Host "Created Project Item PVTI=$pvti"
  } else {
    Write-Host "Warning: gh did not return PVTI id."
  }
  return @{ pvti = $pvti; di = $di }
}

# ---------- DI Resolution ----------
function Resolve-DI-From-PVTI-Once([string]$pvti){
  if(-not $pvti){ return $null }
  $q = @"
query GetDraftFromItem(\$id:ID!) {
  node(id:\$id) {
    __typename
    ... on ProjectV2Item {
      id
      content {
        __typename
        ... on DraftIssue { id title createdAt updatedAt }
      }
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

function Resolve-DI-With-Poll([string]$pvti,[int]$maxTries,[int]$delaySec){
  for($i=1; $i -le $maxTries; $i++){
    $di = Resolve-DI-From-PVTI-Once $pvti
    if($di){
      # Avoid "$i:" parsing issue by using -f formatting
      Write-Host ("Resolved DI from PVTI on attempt {0}: {1}" -f $i, $di)
      return $di
    }
    Write-Host "DI not yet attached; waiting $delaySec s (attempt $i/$maxTries)..."
    Start-Sleep -Seconds $delaySec
  }
  return $null
}

function Find-DI-By-Title([string]$projectId,[string]$title,[int]$pageSize=50){
  if(-not $projectId){ return $null }
  $q = @"
query ListDraftIssues(\$projectId:ID!, \$first:Int!, \$after:String) {
  node(id:\$projectId) {
    ... on ProjectV2 {
      id
      items(first:\$first, after:\$after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          content {
            __typename
            ... on DraftIssue { id title createdAt updatedAt }
          }
        }
      }
    }
  }
}
"@
  $after = $null
  while($true){
    $args = @('-f', "query=$q", '-f', "projectId=$projectId", '-F', "first=$pageSize")
    if($after){ $args += @('-f', "after=$after") }
    try{
      $raw = & $ghExe api graphql @args 2>$null
      if(-not $raw){ return $null }
      $obj = $raw | ConvertFrom-Json
      $nodes = $obj.data.node.items.nodes
      foreach($n in $nodes){
        if($n.content.__typename -eq 'DraftIssue' -and $n.content.title -eq $title){
          $found = $n.content.id
          if($found){
            Write-Host "Found DraftIssue by title: DI=$found"
            return $found
          }
        }
      }
      $hasNext = $obj.data.node.items.pageInfo.hasNextPage
      if(-not $hasNext){ break }
      $after = $obj.data.node.items.pageInfo.endCursor
    } catch { break }
  }
  return $null
}

# ---------- MAIN ----------
$bodyText  = Read-AllText $SnapshotPath
$storedDI  = Load-Id $LastDraftId
$storedPI  = Load-Id $LastItemId

# 1) Prefer stored DI_ for immediate update
if($storedDI -and $storedDI -like 'DI_*'){
  Write-Host "Using stored DI to update: $storedDI"
  Edit-Draft -draftId $storedDI -title $Title -bodyText $bodyText
  Save-Ids $storedPI $storedDI
  Write-Host "Done (updated via stored DI)."
  exit 0
}

# 2) Try stored PVTI_ -> poll DI_ -> update
if($storedPI -and $storedPI -like 'PVTI_*'){
  Write-Host "Attempting to resolve DI from stored PVTI: $storedPI"
  $di = Resolve-DI-With-Poll -pvti $storedPI -maxTries $MaxPollTries -delaySec $PollDelaySec
  if($di){
    Edit-Draft -draftId $di -title $Title -bodyText $bodyText
    Save-Ids $storedPI $di
    Write-Host "Done (updated via PVTI->DI)."
    exit 0
  } else {
    Write-Host "Could not resolve DI from PVTI after polling."
  }
}

# 3) Fallback: search entire project by title and update
$projId = Resolve-Project-NodeId
Write-Host "Project node id: $projId"
Write-Host "Scanning project items to find DraftIssue by title..."
$existingDI = Find-DI-By-Title -projectId $projId -title $Title
if($existingDI){
  Edit-Draft -draftId $existingDI -title $Title -bodyText $bodyText
  Save-Ids $storedPI $existingDI
  Write-Host "Done (updated via title search)."
  exit 0
}

# 4) Create -> try to resolve DI immediately -> update or save PVTI
$cap = Create-Item-Capture -title $Title -bodyPath $SnapshotPath
$pvtiNew = $cap.pvti
$diNew   = $cap.di
if(-not $diNew -and $pvtiNew){
  $diNew = Resolve-DI-With-Poll -pvti $pvtiNew -maxTries $MaxPollTries -delaySec $PollDelaySec
}

if($diNew){
  Edit-Draft -draftId $diNew -title $Title -bodyText $bodyText
  Save-Ids $pvtiNew $diNew
  Write-Host "Done (created and updated)."
  exit 0
}

if($pvtiNew){
  Save-Ids $pvtiNew $null
  Write-Host "Saved PVTI=$pvtiNew. Could not resolve DI yet; next run should update."
  exit 0
}

Write-Host "Could not create or resolve DraftIssue; no changes made."
exit 1
