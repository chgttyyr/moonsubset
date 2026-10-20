# One-click demo script for MoonSubset
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  MoonSubset: End-to-End Demonstration Script     " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Ensure building latest
Write-Host "[1/3] Building MoonSubset toolchain..." -ForegroundColor Yellow
moon check
moon build

# 2. Run Latin Subset on OFL test font
Write-Host "`n[2/3] Subsetting OFL Latin Font (fixtures/test-font.ttf)..." -ForegroundColor Yellow
moon run cmd/main -- subset -f fixtures/test-font.ttf -c "Hello MoonBit 2026!" -o fixtures/demo-latin.ttf --css "DemoLatin"

# 3. Run Chinese Subset on System SimHei if available
if (Test-Path "C:\Windows\Fonts\simhei.ttf") {
    Write-Host "`n[3/3] Subsetting 9.7MB Chinese Font (simhei.ttf)..." -ForegroundColor Yellow
    moon run cmd/main -- subset -f C:\Windows\Fonts\simhei.ttf -c "你好世界欢迎来到2026开源黑客松" -o fixtures/demo-chinese.ttf --css "DemoChinese"
} else {
    Write-Host "`n[3/3] System font simhei.ttf not found, subsetting preset on test font..." -ForegroundColor Yellow
    moon run cmd/main -- subset -f fixtures/test-font.ttf --preset ascii -o fixtures/demo-ascii.ttf
}

Write-Host "`n[Done] Demonstration completed! Open 'examples/demo.html' in your browser to verify rendering." -ForegroundColor Green
