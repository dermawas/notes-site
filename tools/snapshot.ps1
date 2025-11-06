<#  snapshot.ps1
    FlowformLab Project Board Snapshot
    - Generates tools\progress_snapshot.txt with environment + git + validator summary
    - (Optional) Posts as a Draft item (note) to GitHub Project v2 via GraphQL
    - PS5-safe: no ?? operator; no inline-backticks inside double-quoted strings
#>

[CmdletBinding()]
param(
  [string]$Owner            = "dermawas",
  [int]   $ProjectNumber    = 2,
  [string]$RepoPath         = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$Title            = "FlowformLab Project Snapshot",
  [string]$ManualNotesPath  = "$PSScriptRoot\progress_manual.txt",
  [switch]$PostToProject
)

$ErrorActionPreference = "Stop"
function New-Section([string]$Name) { "## $Name`r`n" }

# Verify prerequisites
if (-not (Test-Path -LiteralPath $RepoPath)) { throw "RepoPath not found: $RepoPath" }

# Ensure tools dir
$toolsDir       = Join-Path $RepoPath "tools"
if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }

# Paths
$snapshotPath   = Join-Path $toolsDir "progress_snapshot.txt"
$lastItemPath   = Join-Path $toolsDir "last_project_item_id.txt"
$lastDraftPath  = Join-Path $toolsDir "last_draft_issue_id.txt"
$validatorJson  = Join-Path $toolsDir "validate_frontmatter.last.json"

Push-Location $RepoPath
try {
  # Environment & git
  $nowLocal     = Get-Date
  $tz           = (Get-TimeZone).Id
  $branch       = (git rev-parse --abbrev-ref HEAD) 2>$null
  $latestCommit = (git log -1 --pretty=format:"%h %ad %s" --date=iso) 2>$null
  $statusPorc   = (git status --porcelain=v1) 2>$null
  $staged       = (git diff --cached --name-status) 2>$null
  $unstaged     = (git diff --name-status) 2>$null

  # Validator summary (optional)
  $validatorSummary = ""
  if (Test-Path -LiteralPath $validatorJson) {
    try {
      $vf = Get-Content -LiteralPath $validatorJson -Raw | ConvertFrom-Json
      $checked = $vf.checkedCount
      $errors  = $vf.errorCount
      $warns   = $vf.warningCount
      if ($null -eq $checked -and $null -eq $errors -and $null -eq $warns) {
        $validatorSummary = "(Validator JSON present but expected keys not found.)"
      } else {
        $validatorSummary = @"
Checked : $checked
Errors  : $errors
Warnings: $warns
"@
      }
    } catch {
      $validatorSummary = "(Could not parse validate_frontmatter.last.json: $($_.Exception.Message))"
    }
  } else {
    $validatorSummary = "(No validator run found at tools\validate_frontmatter.last.json)"
  }

  # Optional manual notes
  $manualNotes = if (Test-Path -LiteralPath $ManualNotesPath) {
    (Get-Content -LiteralPath $ManualNotesPath -Raw)
  } else {
    "(Add optional notes at: $ManualNotesPath)"
  }

  # Build snapshot body (Markdown) — avoid inline backticks in interpolated strings
  $lines = @()
  $lines += "# FlowformLab Project Snapshot"
  $lines += ""
  $lines += ("**Timestamp:** {0} ({1})" -f $nowLocal.ToString("yyyy-MM-dd HH:mm:ss"), $tz)
  $lines += ("**Repo:** {0}" -f $RepoPath)
  $lines += ("**Owner / Project #:** {0} / {1}" -f $Owner, $ProjectNumber)
  $lines += ""
  $lines += (New-Section 'Environment')
  $lines += "- Shell: PowerShell"
  $lines += "- Editor: PowerShell for scripts (.ps1)"
  $lines += "- n8n & Ollama in Docker (Windows Desktop)"
  $lines += "- Model: llama3.2:1b"
  $lines += "- Ollama API: http://host.docker.internal:11434/api/generate"
  $lines += ""
  $lines += (New-Section 'Git')
  $lines += ("- Branch: {0}" -f $branch)
  $lines += ("- Latest commit: {0}" -f $latestCommit)
  $lines += ""
  $lines += "### Staged changes"
  $lines += '```'
  $lines += (($staged | Out-String).TrimEnd())
  $lines += '```'
  $lines += "### Unstaged changes"
  $lines += '```'
  $lines += (($unstaged | Out-String).TrimEnd())
  $lines += '```'
  $lines += "### Status (porcelain)"
  $lines += '```'
  $lines += (($statusPorc | Out-String).TrimEnd())
  $lines += '```'
  $lines += ""
  $lines += (New-Section 'Front-Matter Validator (last run)')
  $lines += '````'
  $lines += ($validatorSummary.TrimEnd())
  $lines += '````'
  $lines += ""
  $lines += (New-Section 'Notes')
  $lines += $manualNotes
  $lines += ""
  $lines += (New-Section 'Next Suggested Steps')
  $lines += "- Finalize Node B: AI heading picker in n8n (fix JSON parse → Pick Normalizer → integration test)."
  $lines += "- Extend snapshot automation to update an existing Project card (future project_note.ps1)."

  $body = ($lines -join "`r`n")

  # Write snapshot file
  $body | Out-File -LiteralPath $snapshotPath -Encoding UTF8
  Write-Host "✅ Wrote snapshot: $snapshotPath"

  if ($PostToProject.IsPresent) {
    # Resolve Project node ID (supports user OR org owners)
    $projectQuery = @"
query GetProjectId(\$owner:String!, \$number:Int!) {
  user(login: \$owner) {
    projectV2(number: \$number) { id }
  }
  organization(login: \$owner) {
    projectV2(number: \$number) { id }
  }
}
"@

    $projRaw = gh api graphql -f query="$projectQuery" -f owner="$Owner" -F number=$ProjectNumber
    if (-not $projRaw) { throw "Failed to query projectV2 id via gh api." }
    $projResp = $projRaw | ConvertFrom-Json

    $projectId = $null
    if ($projResp.user -and $projResp.user.projectV2 -and $projResp.user.projectV2.id) {
      $projectId = $projResp.user.projectV2.id
    } elseif ($projResp.organization -and $projResp.organization.projectV2 -and $projResp.organization.projectV2.id) {
      $projectId = $projResp.organization.projectV2.id
    }
    if (-not $projectId) { throw "Could not resolve project id for $Owner / $ProjectNumber." }

    # Create Draft Issue (Project note card)
    $createMutation = @"
mutation CreateDraft(\$projectId:ID!, \$title:String!, \$body:String!) {
  createProjectV2DraftIssue(input:{projectId:\$projectId, title:\$title, body:\$body}) {
    projectItem { id }
    draftIssue { id }
  }
}
"@

    $tmpBody = New-TemporaryFile
    try {
      $body | Out-File -LiteralPath $tmpBody -Encoding UTF8
      $createRaw = gh api graphql `
        -f query="$createMutation" `
        -f projectId="$projectId" `
        -f title="$Title" `
        -F body=@$tmpBody
      if (-not $createRaw) { throw "Failed to create Draft item via gh api." }
      $createResp = $createRaw | ConvertFrom-Json
    } finally {
      if (Test-Path $tmpBody) { Remove-Item $tmpBody -Force }
    }

    $projectItemId = $createResp.createProjectV2DraftIssue.projectItem.id
    $draftIssueId  = $createResp.createProjectV2DraftIssue.draftIssue.id
    if ($projectItemId) { $projectItemId | Out-File -LiteralPath $lastItemPath -Encoding ASCII }
    if ($draftIssueId)  { $draftIssueId  | Out-File -LiteralPath $lastDraftPath -Encoding ASCII }

    Write-Host "✅ Posted snapshot as Draft item to Project #$ProjectNumber (Owner=$Owner)"
    Write-Host "   Project Item ID saved to: $lastItemPath"
    Write-Host "   Draft Issue ID  saved to: $lastDraftPath"
  }

} finally {
  Pop-Location
}
