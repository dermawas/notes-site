<#  post_project_note.ps1
    Creates a Project v2 Draft Issue (note) in FlowformLab project and logs the result.

    Usage:
      .\post_project_note.ps1 -Title "Ghostwriter E2E draft ✅" -Body $reportText
#>

param(
  [Parameter(Mandatory=$true)][string]$Title,
  [Parameter(Mandatory=$true)][string]$Body,
  [string]$ProjectId = "PVT_kwHOAOgW284BHRNH",   # flowformlab.com backlog
  [string]$LogPath   = "D:\seno\GitHub\flowformlab\Repo\notes-site\tools\progress_snapshot.txt"
)

function Log($msg){
  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line  = "[project_note] $stamp  $msg"
  Write-Host $line
  Add-Content -Path $LogPath -Value $line
}

# Create Draft Issue (note) in Project v2
$mutation = @"
mutation CreateDraft(\$project:ID!, \$title:String!, \$body:String!) {
  createProjectV2DraftIssue(input:{ projectId:\$project, title:\$title, body:\$body }) {
    projectItem { id }
  }
}
"@

try {
  $resp = gh api graphql `
    -f query="$mutation" `
    -f project=$ProjectId `
    -f title=$Title `
    -f body=$Body | ConvertFrom-Json

  $itemId = $resp.data.createProjectV2DraftIssue.projectItem.id
  if (-not $itemId) { throw "No projectItem id returned." }

  Log "Created draft note: $itemId  :: $Title"
  Write-Output $itemId
}
catch {
  Log "ERROR creating draft note: $_"
  throw
}
