<#  snapshot.ps1
    FlowformLab Project Board Snapshot (PS5-safe + resilient)
    - Generates tools\progress_snapshot.txt with environment + (optional) git + validator summary
    - Posts as a Draft item (note) to GitHub Project v2 via gh CLI
    - Confirmed working with personal projects (dermawas / flowformlab.com backlog)
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

# --- Resolve paths ---
if (-not (Test-Path -LiteralPath $RepoPath)) { throw "RepoPath not found: $RepoPath" }
$toolsDir = Join-Path $RepoPath "tools"
if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }

$snapshotPath  = Join-Path $toolsDir "progress_snapshot.txt"
$validatorJson = Join-Path $toolsDir "validate_frontmatter.last.json"

# --- Locate executables ---
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
  "$Env:ProgramFiles\Git\bin\git.exe"
)

$ghExe = Resolve-Exe -name "gh" -fallbacks @(
  "$Env:ProgramFiles\GitHub CLI\gh.exe",
  "$Env:LocalAppData\Programs\GitHub CLI\gh.exe"
)

function Invoke-Git([string]$ArgsString) {
  if (-not $gitExe) { return $null }
  try { & $gitExe @($ArgsString -split ' ') 2>$null } catch { return $null }
}

Push-Location $RepoPath
try {
  # --- Environment ---
  $nowLocal = Get-Date
  $tz = (Get-TimeZone).Id

  # --- Git Info ---
  $gitAvailable = $false
  $branch = $latestCommit = $statusPorc = $null
  if ($gitExe) {
    $gitAvailable = $true
    $branch       = (Invoke-Git "rev-parse --abbrev-ref HEAD")
    $latestCommit = (Invoke-Git "log -1 --pretty=format:`"%h %ad %s`" --date=iso")
    $statusPorc   = (Invoke-Git "status --porcelain=v1")
  }

  # --- Validator ---
  $validatorSummary = ""
  if (Test-Path -LiteralPath $validatorJson) {
    try {
      $vf = Get-Content -LiteralPath $validatorJson -Raw | ConvertFrom-Json
      $validatorSummary = "Checked: $($vf.checkedCount)`nErrors: $($vf.errorCount)`nWarnings: $($vf.warningCount)"
    } catch {
      $validatorSummary = "(Could not parse validator JSON)"
    }
  } else {
    $validatorSummary = "(No validator run found)"
  }

  # --- Manual notes ---
  $manualNotes = if (Test-Path -LiteralPath $ManualNotesPath) {
    (Get-Content -LiteralPath $ManualNotesPath -Raw)
  } else {
    "(Add optional notes at: $ManualNotesPath)"
  }

  # --- Compose body ---
  $lines = @()
  $lines += "# FlowformLab Project Snapshot"
  $lines += ""
  $lines += "**Timestamp:** $($nowLocal.ToString('yyyy-MM-dd HH:mm:ss')) ($tz)"
  $lines += "**Repo:** $RepoPath"
  $lines += "**Owner / Project #:** $Owner / $ProjectNumber"
  $lines += ""
  $lines += (New-Section 'Environment')
  $lines += "- Shell: PowerShell"
  $lines += "- n8n & Ollama in Docker (Windows Desktop)"
  $lines += "- Model: llama3.2:1b"
  $lines += "- Ollama API: http://host.docker.internal:11434/api/generate"
  $lines += ""
  $lines += (New-Section 'Git')
  if ($gitAvailable) {
    $lines += "- Branch: $branch"
    $lines += "- Latest commit: $latestCommit"
    $lines += '```'
    $lines += ($statusPorc | Out-String).TrimEnd()
    $lines += '```'
  } else {
    $lines += "(git not found in session)"
  }
  $lines += ""
  $lines += (New-Section 'Front-Matter Validator (last run)')
  $lines += '```'
  $lines += $validatorSummary
  $lines += '```'
  $lines += ""
  $lines += (New-Section 'Notes')
  $lines += $manualNotes
  $lines += ""
  $lines += (New-Section 'Next Suggested Steps')
  $lines += "- Finalize Node B: AI heading picker in n8n (fix JSON parse → Pick Normalizer → integration test)."
  $lines += "- Extend snapshot automation to update an existing Project card (future project_note.ps1)."

  $body = ($lines -join "`r`n")
  $body | Out-File -LiteralPath $snapshotPath -Encoding UTF8
  Write-Host "✅ Wrote snapshot: $snapshotPath"

  if ($PostToProject) {
    if (-not $ghExe) {
      Write-Warning "GitHub CLI not found. Install gh.exe."
      return
    }

    Write-Host "Resolved project node id (hardcoded): PVT_kwHOAOgW284BHRNH"
    Write-Host "Creating project note via gh CLI..."
    & $ghExe project item-create $ProjectNumber --owner "$Owner" --title "$Title" --body @"
$body
"@
    Write-Host "✅ Posted snapshot via gh CLI (owner=$Owner, project=$ProjectNumber)"
  }

} finally {
  Pop-Location
}
