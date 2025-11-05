Write-Host "`n🔍 Running FlowformLab front-matter validator…" -ForegroundColor Cyan

python tools/validate_frontmatter.py
$code = $LASTEXITCODE

if ($code -ne 0) {
    Write-Host "❌ Validation failed. Fix front-matter before continuing." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Front-matter OK" -ForegroundColor Green
