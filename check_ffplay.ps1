Write-Host "Checking for ffplay..." -ForegroundColor Cyan

# 1. Check global PATH
$ffplayPath = Get-Command ffplay -ErrorAction SilentlyContinue

if ($ffplayPath) {
    Write-Host "[OK] Found ffplay in PATH: $($ffplayPath.Source)" -ForegroundColor Green
    try {
        $version = ffplay -version 2>&1 | Select-Object -First 1
        Write-Host "     Version: $version" -ForegroundColor Gray
    } catch {
        Write-Host "     (Version check failed)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[WARN] ffplay not found in global PATH" -ForegroundColor Yellow
    
    # 2. Check next to ffmpeg
    $ffmpegPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpegPath) {
        $ffmpegDir = Split-Path $ffmpegPath.Source -Parent
        $possiblePath = Join-Path $ffmpegDir "ffplay.exe"
        if (Test-Path $possiblePath) {
            Write-Host "[OK] Found ffplay next to ffmpeg: $possiblePath" -ForegroundColor Green
            Write-Host "     (Can be used via absolute path)" -ForegroundColor Gray
        } else {
             Write-Host "[FAIL] ffplay.exe not found in $ffmpegDir" -ForegroundColor Red
             Write-Host "       Your ffmpeg installation may be incomplete." -ForegroundColor Red
        }
    } else {
        Write-Host "[FAIL] ffmpeg not found either." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
if ($ffplayPath -or ($ffmpegPath -and (Test-Path (Join-Path (Split-Path $ffmpegPath.Source -Parent) "ffplay.exe")))) {
    Write-Host "[SUCCESS] ffplay is available! We can use the optimized solution." -ForegroundColor Green
} else {
    Write-Host "[FAILURE] ffplay not found. Please download full ffmpeg package." -ForegroundColor Red
    Write-Host "          Download: https://www.gyan.dev/ffmpeg/builds/" -ForegroundColor Gray
}
