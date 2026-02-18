# DirectShow 测试脚本
Write-Host "DirectShow Audio Test" -ForegroundColor Cyan
Write-Host "================================" 
Write-Host ""

# 检查 ffmpeg
Write-Host "1. Checking ffmpeg..." -ForegroundColor Yellow
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    Write-Host "   ERROR: ffmpeg not found" -ForegroundColor Red
    exit 1
}
Write-Host "   OK: ffmpeg found" -ForegroundColor Green
Write-Host ""

# 列出设备
Write-Host "2. Listing DirectShow audio devices..." -ForegroundColor Yellow
$output = & ffmpeg -list_devices true -f dshow -i dummy 2>&1
$devices = @()
$inAudio = $false

foreach ($line in $output) {
    $str = $line.ToString()
    if ($str -match "DirectShow audio devices") {
        $inAudio = $true
        continue
    }
    if ($str -match "DirectShow video devices") {
        $inAudio = $false
    }
    if ($inAudio -and $str -match '"([^"]+)"') {
        $devices += $matches[1]
        Write-Host "   Device: $($matches[1])" -ForegroundColor Cyan
    }
}

if ($devices.Count -eq 0) {
    Write-Host "   WARNING: No DirectShow devices found" -ForegroundColor Yellow
}
else {
    Write-Host "   Found $($devices.Count) devices" -ForegroundColor Green
}
Write-Host ""

# 查找虚拟设备
Write-Host "3. Looking for virtual audio devices..." -ForegroundColor Yellow
$virtualDevs = @()
foreach ($dev in $devices) {
    if ($dev -like "*CABLE*" -or $dev -like "*Virtual*") {
        $virtualDevs += $dev
        Write-Host "   Virtual: $dev" -ForegroundColor Green
    }
}

if ($virtualDevs.Count -eq 0) {
    Write-Host "   WARNING: No virtual devices found" -ForegroundColor Yellow
}
Write-Host ""

# 生成测试音频
Write-Host "4. Creating test audio..." -ForegroundColor Yellow
$testFile = "test.wav"
if (-not (Test-Path $testFile)) {
    $null = & ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -y $testFile 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   OK: Test file created" -ForegroundColor Green
    }
    else {
        Write-Host "   ERROR: Failed to create test file" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "   OK: Test file exists" -ForegroundColor Gray
}
Write-Host ""

# 测试播放
if ($virtualDevs.Count -gt 0) {
    Write-Host "5. Testing DirectShow playback..." -ForegroundColor Yellow
    
    foreach ($dev in $virtualDevs) {
        Write-Host "   Testing: $dev" -ForegroundColor Cyan
        $start = Get-Date
        $null = & ffmpeg -re -i $testFile -f dshow "audio=$dev" 2>&1
        $elapsed = ((Get-Date) - $start).TotalSeconds
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   OK: Playback succeeded (${elapsed}s)" -ForegroundColor Green
        }
        else {
            Write-Host "   ERROR: Playback failed" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "5. Skipping playback test (no virtual devices)" -ForegroundColor Yellow
}
Write-Host ""

# 总结
Write-Host "================================" 
Write-Host "Summary:" -ForegroundColor Cyan
if ($devices.Count -gt 0) {
    Write-Host "  DirectShow is available" -ForegroundColor Green
    Write-Host "  App can use DirectShow for faster audio playback" -ForegroundColor White
}
else {
    Write-Host "  DirectShow is NOT available" -ForegroundColor Red
    Write-Host "  App will use device switching method" -ForegroundColor Yellow
}
Write-Host ""

# 清理
if (Test-Path $testFile) {
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
}
