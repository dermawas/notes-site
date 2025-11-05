# Run Python front-matter validator
Write-Host "Running front-matter check..." -ForegroundColor Cyan

python tools\validate_frontmatter.py
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "Front-matter check FAILED" -ForegroundColor Red
    exit 1
}

Write-Host "Front-matter OK" -ForegroundColor Green
exit 0
