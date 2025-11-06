<#  snapshot.ps1
    FlowformLab Project Board Snapshot (PS5-safe + resilient)
    - Generates tools\progress_snapshot.txt with environment + (optional) git + validator summary
    - (Optional) Posts as a Draft item (note) to GitHub Project v2 via GraphQL
    - Handles missing git/gh gracefully; resolves project id via `gh project list` by number OR title.

    Usage:
      .\snapshot.ps1
      .\snapshot.ps1 -PostToProject
#>

[CmdletBinding()]
param(
  [string]$Owner            = "dermawas",                   # your GitHub username (personal account)
  [int]   $ProjectNumber    = 2,                            # fallback: try by this number
  [string]$ProjectTitle     = "flowformlab.com backlog",    # fallback: try by this title
  [string]$RepoPath         = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$Title            = "FlowformLab Project Snapshot",
  [string]$ManualNotesPath  = "$PSScriptRoot\progress_manual.txt",
  [switch]$PostToProject
)

$ErrorActionPreference = "Stop"
function New-Section([string]$Name) { "## $Name`r`n" }

# --- Resolve tools dir & output paths ---
if (-not (Test-Path -LiteralPath $RepoPath)) { throw "RepoPath not found: $RepoPath" }
$toolsDir       = Join-Path $RepoPath "tools"
if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }

$snapshotPath   = Join-Path $toolsDir "progress_snapshot.txt"
$lastItemPath   = Join-Path $toolsDir "last_project_item_id.txt"
$lastDraftPath  = Join-Path $toolsDir "last_draft_issue_id.txt"
$validatorJson  = Join-Path $toolsDir "validate_frontmatter.last.json"

# --- Locate git.exe and gh.exe (gracefully) ---
function Resolve-Exe([string]$name, [string[]]$fallbacks) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($path in $fallbacks) {
    if (Test-Path -LiteralPath $path) { return $path }
  }
  return $null
}

$gitExe = Resolve-Exe -name "git" -fallbacks @(
  "$Env:ProgramFiles\Git\cmd\git.exe",
  "$Env:ProgramFiles\Git\bin\git.exe",
  "$Env:ProgramFiles(x86)\Git\cmd\git.exe",
  "$Env:ProgramFiles(x86)\Git\bin\git.exe"
)

$ghExe = Resolve-Exe -name "gh" -fallbacks @(
  "$Env:ProgramFiles\GitHub CLI\gh.exe",
  "$Env:LocalAppData\Programs\GitHub CLI\gh.exe"
)

# Helper to invoke git if available (PS5-safe)
function Invoke-Git([string]$ArgsString) {
  if (-not $gitExe) { return $null }
  try {
    & $gitExe @($ArgsString -split ' ') 2>$null
  } catch {
    return $null
  }
}

# --- Helper: resolve ProjectV2 ID using `gh project list` first (user scope), then GraphQL ---
function Get-UserProjectV2Id {
  param(
    [Parameter(Mandatory=$true)][string]$OwnerLogin,
    [Parameter(Mandatory=$true)][int]$Number,
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$GhExe
  )

  # Try the CLI list (most reliable for user projects)
  $listJson = $null
  try {
    $listJson = & $GhExe project list --owner "$OwnerLogin" --format json 2>$null
  } catch { }

  $matchedNumber = $null
  if ($listJson) {
    try {
      $projects = $listJson | ConvertFrom-Json
      # projects fields usually: number, title, url
      # 1) exact number
      $pByNum = $projects | Where-Object { $_.number -eq $Number } | Select-Object -First 1
      # 2) exact title
      $pByTitle = $projects | Where-Object { $_.title -eq $Title } | Select-Object -First 1
      # 3) contains match
      if (-not $pByTitle) {
        $pByTitle = $projects | Where-Object { $_.title -like "*$Title*" } | Select-Object -First 1
      }

      if ($pByNum) { $matchedNumber = $pByNum.number }
      elseif ($pByTitle) { $matchedNumber = $pByTitle.number }

      if (-not $matchedNumber -and $projects) {
        Write-Host "Diagnostics: Projects visible for user '$OwnerLogin':"
        $projects | ForEach-Object { Write-Host (" - #{0}: {1}" -f $_.number, $_.title) }
      }
    } catch {
      Write-Host "Warning: could not parse 'gh project list' JSON: $($_.Exception.Message)"
    }
  } else {
    Write-Host "Warning: 'gh project list --owner $OwnerLogin' returned no output (older gh? not authenticated?)."
  }

  # If we still don't know the number, try GraphQL enumerate user projects
  if (-not $matchedNumber) {
    $qUserList = @'
query ListProjects($owner:String!) {
  user(login: $owner) {
    projectsV2(first: 50) {
      nodes { id title number }
    }
  }
}
'@
    try {
      $resp = & $GhExe api graphql -f query="$qUserList" -f owner="$OwnerLogin" | ConvertFrom-Json
      if ($resp -and $resp.user -and $resp.user.projectsV2 -and $resp.user.projectsV2.nodes) {
        $uNodes = $resp.user.projectsV2.nodes
        $byNum = $uNodes | Where-Object { $_.number -eq $Number } | Select-Object -First 1
        $byTitle = $uNodes | Where-Object { $_.title -eq $Title } | Select-Object -First 1
        if (-not $byTitle) { $byTitle = $uNodes | Where-Object { $_.title -like "*$Title*" } | Select-Object -First 1 }
        if ($byNum) { $matchedNumber = $byNum.number }
        elseif ($byTitle) { $matchedNumber = $byTitle.number }

        if (-not $matchedNumber) {
          Write-Host "Diagnostics (GraphQL user projects for '$OwnerLogin'):"
          $uNodes | ForEach-Object { Write-Host (" - #{0}: {1}" -f $_.number, $_.title) }
        }
      }
    } catch {
      Write-Host "Warning: GraphQL user project listing error: $($_.Exception.Message)"
    }
  }

  if (-not $matchedNumber) { return $null }

  # Once we have the number, get the node id via GraphQL
  $qUserByNumber = @'
query GetProjectId($owner:String!, $number:Int!) {
  user(login: $owner) {
    projectV2(number: $number) { id title number }
  }
}
'@
  try {
    $resp = & $GhExe api graphql -f query="$qUserByNumber" -f owner="$OwnerLogin" -F number=$matchedNumber | ConvertFrom-Json
    if ($resp -and $resp.user -and $resp.user.projectV2 -and $resp.user.projectV2.id) {
      return $resp.user.projectV2.id
    }
  } catch {
    Write-Host "Warning: GraphQL fetch by number failed: $($_.Exception.Message)"
  }

  return $null
}

Push-Location $RepoPath
try {
  # --- Environment ---
  $nowLocal     = Get-Date
  $tz           = (Get-TimeZone).Id

  # --- Git info (optional if git missing) ---
  $gitAvailable = $false
  $branch = $latestCommit = $statusPorc = $null
  $staged = $unstaged = $null

  if ($gitExe) {
    $gitAvailable = $true
    $branch       = (Invoke-Git "rev-parse --abbrev-ref HEAD")
    $latestCommit = (Invoke-Git "log -1 --pretty=format:`"%h %ad %s`" --date=iso")
    $statusPorc   = (Invoke-Git "status --porcelain=v1")
    $staged       = (Invoke-Git "diff --cached --name-status")
    $unstaged     = (Invoke-Git "diff --name-status")
  }

  # --- Validator summary (optional) ---
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

  # --- Optional manual notes ---
  $manualNotes = if (Test-Path -LiteralPath $ManualNotesPath) {
    (Get-Content -LiteralPath $ManualNotesPath -Raw)
  } else {
    "(Add optional notes at: $ManualNotesPath)"
  }

  # --- Build snapshot body (Markdown) ---
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
  if ($gitAvailable) {
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
  } else {
    $lines += "- Git: NOT AVAILABLE in current PowerShell session"
    $lines += ""
    $lines += "### Staged changes"
    $lines += '```'
    $lines += '(git not found)'
    $lines += '```'
    $lines += "### Unstaged changes"
    $lines += '```'
    $lines += '(git not found)'
    $lines += '```'
    $lines += "### Status (porcelain)"
    $lines += '```'
    $lines += '(git not found)'
    $lines += '```'
  }
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

  # --- Write snapshot file ---
  $body | Out-File -LiteralPath $snapshotPath -Encoding UTF8
  Write-Host "Wrote snapshot: $snapshotPath"

  if ($PostToProject.IsPresent) {
    if (-not $ghExe) {
      Write-Warning "GitHub CLI (gh) not found; skipping Project post. Install gh or add it to PATH."
      return
    }

    # Resolve project id via CLI list and/or GraphQL user listing
    $projectId = Get-UserProjectV2Id -OwnerLogin $Owner -Number $ProjectNumber -Title $ProjectTitle -GhExe $ghExe
    if (-not $projectId) {
      throw "Could not resolve ProjectV2 id for owner '$Owner' (number=$ProjectNumber, title='$ProjectTitle')."
    }

    # --- Create Draft Issue (Project note card) ---
    $createMutation = @'
mutation CreateDraft($projectId:ID!, $title:String!, $body:String!) {
  createProjectV2DraftIssue(input:{projectId:$projectId, title:$title, body:$body}) {
    projectItem { id }
    draftIssue { id }
  }
}
'@

    $tmpBody = New-TemporaryFile
    try {
      $body | Out-File -LiteralPath $tmpBody -Encoding UTF8
      $createRaw = & $ghExe api graphql `
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

    Write-Host "Posted snapshot as Draft item to Project (Owner=$Owner)"
    Write-Host "  Project Item ID -> $lastItemPath"
    Write-Host "  Draft Issue ID  -> $lastDraftPath"
  }

} finally {
  Pop-Location
}
