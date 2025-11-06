# tools/snapshot.ps1
# ------------------------------------------
# FlowformLab Progress Snapshot
# Creates tools\progress_snapshot.txt for local + project sync later

$ErrorActionPreference = "Stop"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Determine repo root even when run manually
$root = Split-Path -Parent $PSCommandPath
if (-not $root) {
  $root = Get-Location
}
Set-Location $root

$path = Join-Path $root "tools\progress_snapshot.txt"

$data = @"
=== FlowformLab Progress Snapshot ===
Timestamp: $now

Repo: D:\seno\GitHub\flowformlab\Repo\notes-site

✅ Front-matter validator installed
✅ Fixer script working
✅ PowerShell validator wrapper works
✅ Draft + Post templates validated

⚙️ n8n Ghostwriter Status
- Headings generator ✅
- AI heading selector ⏳ (Node B JSON escape fix needed)
- Heading normalizer ⏳ (after Node B)

📌 Next Step
Fix JSON payload in Node B to Ollama (llama3.2:1b)

📝 Notes
- Keep step-by-step method
- Ask before modifying core templates or scripts

"@

# Write snapshot file
Set-Content -Path $path -Value $data -Encoding UTF8
Write-Host "Snapshot saved → $path ✅" -ForegroundColor Green
