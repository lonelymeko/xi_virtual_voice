# DirectShow 支持检测脚本
Write-Host "DirectShow Support Check" -ForegroundColor Cyan
Write-Host "================================" 
Write-Host ""

# 1. 检查 ffmpeg
Write-Host "1. Checking ffmpeg..." -ForegroundColor Yellow
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($null -eq $ffmpeg) {
    Write-Host "   ERROR: ffmpeg not found" -ForegroundColor Red
    exit 1
}
Write-Host "   OK: ffmpeg found" -ForegroundColor Green
Write-Host ""

# 2. 检查 DirectShow 支持
Write-Host "2. Checking DirectShow support..." -ForegroundColor Yellow
$formats = & ffmpeg -formats 2>&1 | Out-String
if ($formats -match "dshow") {
    Write-Host "   OK: DirectShow is supported!" -ForegroundColor Green
    Write-Host "   Your ffmpeg includes DirectShow support" -ForegroundColor Cyan
}
else {
    Write-Host "   WARNING: DirectShow not found in formats" -ForegroundColor Yellow
}
Write-Host ""

# 3. 列出实际的音频设备
Write-Host "3. Listing actual audio devices..." -ForegroundColor Yellow
Write-Host "   Running: ffmpeg -list_devices true -f dshow -i dummy" -ForegroundColor Gray
Write-Host ""

$output = & ffmpeg -list_devices true -f dshow -i dummy 2>&1
$devices = @()
$captureNext = $false

foreach ($line in $output) {
    $str = $line.ToString()
    
    # 打印原始输出（用于调试）
    if ($str -match "DirectShow" -or $str -match "Alternative name" -or $str -match '"') {
        Write-Host "   $str" -ForegroundColor DarkGray
    }
    
    # 解析设备名称
    if ($str -match '"([^"]+)"') {
        $deviceName = $matches[1]
        if ($deviceName -notlike "*@device*") {
            $devices += $deviceName
        }
    }
}

Write-Host ""
if ($devices.Count -gt 0) {
    Write-Host "   Found $($devices.Count) devices:" -ForegroundColor Green
    foreach ($dev in $devices) {
        $isVirtual = $dev -like "*CABLE*" -or $dev -like "*Virtual*" -or $dev -like "*VoiceMeeter*"
        if ($isVirtual) {
            Write-Host "   [VIRTUAL] $dev" -ForegroundColor Cyan
        }
        else {
            Write-Host "   [DEVICE]  $dev" -ForegroundColor White
        }
    }
}
else {
    Write-Host "   WARNING: No devices found" -ForegroundColor Yellow
    Write-Host "   This might be a parsing issue" -ForegroundColor Gray
}
Write-Host ""

# 4. 创建测试音频
Write-Host "4. Creating test audio..." -ForegroundColor Yellow
$testFile = "dshow_test.wav"
if (-not (Test-Path $testFile)) {
    $null = & ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -y $testFile 2>&1
    if (Test-Path $testFile) {
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

# 5. 测试播放（如果找到虚拟设备）
$virtualDevs = $devices | Where-Object { $_ -like "*CABLE*" -or $_ -like "*Virtual*" -or $_ -like "*VoiceMeeter*" }

if ($virtualDevs.Count -gt 0) {
    Write-Host "5. Testing DirectShow playback..." -ForegroundColor Yellow
    
    $testDev = $virtualDevs[0]
    Write-Host "   Testing device: $testDev" -ForegroundColor Cyan
    Write-Host "   Command: ffmpeg -re -i $testFile -f dshow `"audio=$testDev`"" -ForegroundColor Gray
    
    $start = Get-Date
    $playOutput = & ffmpeg -re -i $testFile -f dshow "audio=$testDev" 2>&1
    $elapsed = ((Get-Date) - $start).TotalSeconds
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   SUCCESS: Playback worked! (${elapsed}s)" -ForegroundColor Green
    }
    else {
        Write-Host "   ERROR: Playback failed" -ForegroundColor Red
        Write-Host "   Last few lines of output:" -ForegroundColor Gray
        $playOutput | Select-Object -Last 3 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    }
}
else {
    Write-Host "5. Skipping playback test" -ForegroundColor Yellow
    Write-Host "   No virtual audio devices found" -ForegroundColor Gray
    Write-Host "   Install VB-CABLE: https://vb-audio.com/Cable/" -ForegroundColor Gray
}
Write-Host ""

# 总结
Write-Host "================================" 
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host ""

if ($formats -match "dshow") {
    Write-Host "✓ DirectShow IS supported in your ffmpeg" -ForegroundColor Green
    Write-Host "✓ Your app CAN use DirectShow for fast playback" -ForegroundColor Green
    Write-Host ""
    if ($devices.Count -gt 0) {
        Write-Host "✓ Found $($devices.Count) audio devices" -ForegroundColor Green
    }
    else {
        Write-Host "! Device list might be empty (check Windows audio settings)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "✗ DirectShow NOT supported" -ForegroundColor Red
    Write-Host "  App will use device switching method" -ForegroundColor Yellow
}

Write-Host ""

# 清理
if (Test-Path $testFile) {
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
}
