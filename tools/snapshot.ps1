<# snapshot.ps1  — FlowformLab
   Writer-only snapshot (no GitHub calls). It just writes tools\progress_snapshot.txt
#>

[CmdletBinding()]
param(
  [string]$RepoPath        = "D:\seno\GitHub\flowformlab\Repo\notes-site",
  [string]$ManualNotesPath = "$PSScriptRoot\progress_manual.txt"
)

$ErrorActionPreference = "Stop"
Write-Host "snapshot.ps1 :: writer-only v2025-11-06-01" -ForegroundColor Cyan

function New-Section([string]$Name) { "## $Name`r`n" }

if (-not (Test-Path -LiteralPath $RepoPath)) { throw "RepoPath not found: $RepoPath" }
$toolsDir      = Join-Path $RepoPath "tools"
if (-not (Test-Path -LiteralPath $toolsDir)) { New-Item -ItemType Directory -Path $toolsDir | Out-Null }
$snapshotPath  = Join-Path $toolsDir "progress_snapshot.txt"
$validatorJson = Join-Path $toolsDir "validate_frontmatter.last.json"

# Gather basic env
$nowLocal = Get-Date
$tz       = (Get-TimeZone).Id

# Optional validator summary
$validatorSummary = "(No validator run found at tools\validate_frontmatter.last.json)"
if (Test-Path -LiteralPath $validatorJson) {
  try {
    $vf = Get-Content -LiteralPath $validatorJson -Raw | ConvertFrom-Json
    $checked = $vf.checkedCount
    $errors  = $vf.errorCount
    $warns   = $vf.warningCount
    if ($checked -ne $null -or $errors -ne $null -or $warns -ne $null) {
      $validatorSummary = @"
Checked : $checked
Errors  : $errors
Warnings: $warns
"@
    }
  } catch {
    $validatorSummary = "(Could not parse validate_frontmatter.last.json: $($_.Exception.Message))"
  }
}

# Optional manual notes
$manualNotes = if (Test-Path -LiteralPath $ManualNotesPath) {
  (Get-Content -LiteralPath $ManualNotesPath -Raw)
} else {
  "(Add optional notes at: $ManualNotesPath)"
}

# Build body (Markdown)
$lines = @()
$lines += "# FlowformLab Project Snapshot"
$lines += ""
$lines += ("**Timestamp:** {0} ({1})" -f $nowLocal.ToString("yyyy-MM-dd HH:mm:ss"), $tz)
$lines += ("**Repo:** {0}" -f $RepoPath)
$lines += ""
$lines += (New-Section 'Environment')
$lines += "- Shell: PowerShell"
$lines += "- n8n & Ollama in Docker (Windows Desktop)"
$lines += "- Model: llama3.2:1b"
$lines += "- Ollama API: http://host.docker.internal:11434/api/generate"
$lines += ""
$lines += (New-Section 'Git')
$lines += "(git details omitted in writer-only snapshot)"
$lines += ""
$lines += (New-Section 'Front-Matter Validator (last run)')
$lines += '```'
$lines += ($validatorSummary.TrimEnd())
$lines += '```'
$lines += ""
$lines += (New-Section 'Notes')
$lines += $manualNotes
$lines += ""
$lines += (New-Section 'Next Suggested Steps')
$lines += "- Finalize Node B: AI heading picker in n8n (fix JSON parse → Pick Normalizer → integration test)."
$lines += "- Use project_note.ps1 to post/update the single board card (no posting from snapshot.ps1)."

$body = ($lines -join "`r`n")
$body | Out-File -LiteralPath $snapshotPath -Encoding UTF8
Write-Host "✅ Wrote snapshot: $snapshotPath"
