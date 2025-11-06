<# project_note.ps1
   FlowformLab — Update or Create ONE "FlowformLab Project Snapshot" card without duplicates
   - Works with GitHub Projects v2 (personal project)
   - Uses gh CLI
   - IMPORTANT: gh project item-edit wants the Draft Issue *content* id (prefix DI_), not the PVTI_ item id.
     We resolve DI_ via GraphQL given a PVTI_ item id.
#>

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

# Personal project node id (confirmed)
$ProjectId = "PVT_kwHOAOgW284BHRNH"

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
if (-not $ghExe) { throw "GitHub CLI (gh) not found in PATH." }

if (-not (Test-Path -LiteralPath $RepoPath))     { throw "RepoPath not found: $RepoPath" }
if (-not (Test-Path -LiteralPath $SnapshotPath)) { throw "Snapshot file not found: $SnapshotPath" }

# ---- Helpers ----
function Gh-Project-Items-Json {
  try { & $ghExe project item-list $ProjectNumber --owner "$Owner" --format json 2>$null } catch { return $null }
}

function Parse-Items($json) {
  if (-not $json) { return @() }
  try {
    $obj = $json | ConvertFrom-Json
    if ($obj -is [System.Array])            { return $obj }
    elseif ($obj.items)                     { return $obj.items }
    elseif ($obj.data -and $obj.data.items) { return $obj.data.items }
    elseif ($obj.id -and $obj.title)        { return @($obj) }
    else                                    { return @() }
  } catch { return @() }
}

function FindNewestByTitle($items, $title) {
  $matches = $items | Where-Object { $_.title -eq $title }
  if (-not $matches) { return $null }
  $matches | Sort-Object @{Expression={$_.updatedAt}}, @{Expression={$_.createdAt}} -Descending | Select-Object -First 1
}

# Resolve DI_ draft content id from a PVTI_ item id using GraphQL
function Resolve-DraftId-From-Item([string]$ItemId) {
  if (-not $ItemId) { return $null }
  $q = @"
query GetDraft(\$id:ID!) {
  node(id:\$id) {
    __typename
    ... on ProjectV2Item {
      id
      content {
        __typename
        ... on DraftIssue { id }
      }
    }
  }
}
"@
  try {
    $raw = & $ghExe api graphql -f query="$q" -f id="$ItemId" 2>$null
    if (-not $raw) { return $null }
    $obj = $raw | ConvertFrom-Json
    if ($obj -and $obj.data -and $obj.data.node -and $obj.data.node.content -and $obj.data.node.content.id) {
      return $obj.data.node.content.id
    }
  } catch { }
  return $null
}

function SaveIds($ItemId, $DraftId) {
  if ($ItemId) { $ItemId | Out-File -LiteralPath $LastItemId -Encoding ASCII }
  if ($DraftId) { $DraftId | Out-File -LiteralPath $LastDraftId -Encoding ASCII }
}

function Edit-By-DraftId([string]$DraftId, [string]$TitleToSet, [string]$BodyToSet) {
  Write-Host "Editing draft (DI) id=$DraftId ..."
  & $ghExe project item-edit --project-id "$ProjectId" --id "$DraftId" --title "$TitleToSet" --body @"
$BodyToSet
"@
}

function Create-Item([string]$TitleToSet, [string]$BodyToSet) {
  Write-Host "Creating new note..."
  & $ghExe project item-create $ProjectNumber --owner "$Owner" --title "$TitleToSet" --body @"
$BodyToSet
"@
  # Re-list and capture newest
  $items = Parse-Items (Gh-Project-Items-Json)
  $newest = FindNewestByTitle $items $TitleToSet
  if ($newest -and $newest.id) {
    $pvti = $newest.id
    $di = Resolve-DraftId-From-Item $pvti
    SaveIds $pvti $di
    if ($di) {
      Write-Host "Created item id=$pvti  (draft content id=$di saved)."
    } else {
      Write-Host "Created item id=$pvti  (draft content id not visible yet; will resolve next run)."
    }
  } else {
    Write-Host "Created item (couldn't capture ids from CLI)."
  }
}

# -------- Main --------
$body = Get-Content -LiteralPath $SnapshotPath -Raw
Write-Host "Scanning project #$ProjectNumber (owner=$Owner) ..."

# 1) Try stored DI_ first
$storedDI = $null
if (Test-Path -LiteralPath $LastDraftId) {
  $storedDI = (Get-Content -LiteralPath $LastDraftId -Raw).Trim()
}
if ($storedDI -and $storedDI -like 'DI_*') {
  try {
    Edit-By-DraftId -DraftId $storedDI -TitleToSet $Title -BodyToSet $body
    Write-Host "Updated using stored draft id."
    exit 0
  } catch {
    Write-Warning "Edit with stored draft id failed: $($_.Exception.Message)"
  }
}

# 2) Fall back: find latest item by title, then resolve its DI_ and edit
$items = Parse-Items (Gh-Project-Items-Json)
$match = FindNewestByTitle $items $Title
if ($match -and $match.id) {
  $pvti = $match.id
  $di = Resolve-DraftId-From-Item $pvti
  if ($di) {
    try {
      Edit-By-DraftId -DraftId $di -TitleToSet $Title -BodyToSet $body
      SaveIds $pvti $di
      Write-Host "Updated existing card (matched by title; DI captured)."
      exit 0
    } catch {
      Write-Warning "Edit by title/DI failed: $($_.Exception.Message)"
    }
  } else {
    Write-Warning "Could not resolve DI_ from PVTI_ item id=$pvti; will create a new note once."
  }
}

# 3) Create (first run or if DI couldn’t be resolved)
Create-Item -TitleToSet $Title -BodyToSet $body
Write-Host "Done."
