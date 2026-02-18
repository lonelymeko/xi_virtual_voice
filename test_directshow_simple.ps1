# 简化的 DirectShow 测试脚本
Write-Host "测试 Windows DirectShow 音频支持" -ForegroundColor Cyan
Write-Host "=====================================" 
Write-Host ""

# 1. 检查 ffmpeg
Write-Host "1. 检查 ffmpeg..." -ForegroundColor Yellow
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg) {
    Write-Host "   OK - FFmpeg 已安装" -ForegroundColor Green
} else {
    Write-Host "   ERROR - FFmpeg 未安装" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 2. 列出 DirectShow 音频设备
Write-Host "2. 列出 DirectShow 音频设备..." -ForegroundColor Yellow
$output = & ffmpeg -list_devices true -f dshow -i dummy 2>&1
$audioDevices = @()

$inAudio = $false
foreach ($line in $output) {
    $lineStr = $line.ToString()
    if ($lineStr -match "DirectShow audio devices") {
        $inAudio = $true
        continue
    }
    if ($lineStr -match "DirectShow video devices") {
        $inAudio = $false
    }
    
    if ($inAudio -and $lineStr -match '"([^"]+)"') {
        $deviceName = $matches[1]
        $audioDevices += $deviceName
        Write-Host "   [设备] $deviceName" -ForegroundColor Cyan
    }
}

if ($audioDevices.Count -eq 0) {
    Write-Host "   WARNING - 未找到 DirectShow 音频设备" -ForegroundColor Yellow
} else {
    Write-Host "   OK - 找到 $($audioDevices.Count) 个设备" -ForegroundColor Green
}
Write-Host ""

# 3. 查找虚拟音频设备
Write-Host "3. 检查虚拟音频设备..." -ForegroundColor Yellow
$virtualDevices = @()
foreach ($device in $audioDevices) {
    if ($device -like "*CABLE*" -or $device -like "*Virtual*" -or $device -like "*VoiceMeeter*") {
        $virtualDevices += $device
        Write-Host "   [虚拟] $device" -ForegroundColor Green
    }
}

if ($virtualDevices.Count -eq 0) {
    Write-Host "   WARNING - 未找到虚拟音频设备" -ForegroundColor Yellow
    Write-Host "   请安装 VB-CABLE: https://vb-audio.com/Cable/" -ForegroundColor Yellow
}
Write-Host ""

# 4. 生成测试音频
Write-Host "4. 生成测试音频文件..." -ForegroundColor Yellow
$testFile = "test_tone.wav"

if (Test-Path $testFile) {
    Write-Host "   OK - 测试文件已存在" -ForegroundColor Gray
} else {
    Write-Host "   生成 1秒测试音..." -NoNewline
    $result = & ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -y $testFile 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " ERROR" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# 5. 测试 DirectShow 播放
if ($virtualDevices.Count -gt 0) {
    Write-Host "5. 测试 DirectShow 播放..." -ForegroundColor Yellow
    
    foreach ($device in $virtualDevices) {
        Write-Host "   测试设备: $device" -ForegroundColor Cyan
        
        $startTime = Get-Date
        $result = & ffmpeg -re -i $testFile -f dshow "audio=$device" 2>&1
        $duration = (Get-Date) - $startTime
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   OK - 播放成功! 耗时: $([math]::Round($duration.TotalSeconds, 2))秒" -ForegroundColor Green
        } else {
            Write-Host "   ERROR - 播放失败" -ForegroundColor Red
        }
        Write-Host ""
    }
} else {
    Write-Host "5. 跳过播放测试 (没有虚拟音频设备)" -ForegroundColor Yellow
    Write-Host ""
}

# 总结
Write-Host "=====================================" 
Write-Host "测试总结:" -ForegroundColor Cyan
Write-Host ""

if ($audioDevices.Count -gt 0) {
    Write-Host "✓ DirectShow 可用" -ForegroundColor Green
    Write-Host "  应用可以使用 DirectShow 直接播放到指定设备" -ForegroundColor White
    Write-Host "  无需切换系统默认音频设备,速度更快!" -ForegroundColor White
} else {
    Write-Host "✗ DirectShow 不可用" -ForegroundColor Red
    Write-Host "  应用将使用设备切换方式 (速度较慢)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "提示: 如需性能对比测试,请先安装 AudioDeviceCmdlets 模块" -ForegroundColor Gray
Write-Host "      Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force" -ForegroundColor Gray
Write-Host ""

# 清理
if (Test-Path $testFile) {
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
}
