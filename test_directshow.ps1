# DirectShow 音频设备测试脚本
Write-Host "🔍 测试 Windows DirectShow 音频支持" -ForegroundColor Cyan
Write-Host ("=" * 60)
Write-Host ""

# 1. 检查 ffmpeg
Write-Host "1️⃣  检查 ffmpeg..." -ForegroundColor Yellow
$ffmpegCheck = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpegCheck) {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-String "ffmpeg version" | Select-Object -First 1
    Write-Host "   ✅ FFmpeg 已安装" -ForegroundColor Green
    Write-Host "   $ffmpegVersion" -ForegroundColor Gray
} else {
    Write-Host "   ❌ FFmpeg 未安装" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 2. 列出 DirectShow 音频设备
Write-Host "2️⃣  列出 DirectShow 音频设备" -ForegroundColor Yellow
Write-Host "   执行: ffmpeg -list_devices true -f dshow -i dummy" -ForegroundColor Gray
Write-Host ""

$dshowOutput = & ffmpeg -list_devices true -f dshow -i dummy 2>&1

# 解析音频设备
$audioDevices = @()
$inAudioSection = $false

foreach ($line in $dshowOutput) {
    if ($line -match "DirectShow audio devices") {
        $inAudioSection = $true
        continue
    }
    if ($line -match "DirectShow video devices") {
        $inAudioSection = $false
    }
    
    if ($inAudioSection -and $line -match '"([^"]+)"') {
        $deviceName = $matches[1]
        $audioDevices += $deviceName
        Write-Host "   📢 $deviceName" -ForegroundColor Cyan
    }
}

if ($audioDevices.Count -eq 0) {
    Write-Host "   ⚠️  未找到 DirectShow 音频设备" -ForegroundColor Yellow
    Write-Host "   这可能意味着您的 ffmpeg 版本不支持 DirectShow" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "   ✅ 找到 $($audioDevices.Count) 个 DirectShow 音频设备" -ForegroundColor Green
}
Write-Host ""

# 3. 查找虚拟音频设备
Write-Host "3️⃣  检查虚拟音频设备" -ForegroundColor Yellow
$virtualDevices = $audioDevices | Where-Object { $_ -like "*CABLE*" -or $_ -like "*Virtual*" -or $_ -like "*VoiceMeeter*" }

if ($virtualDevices) {
    Write-Host "   ✅ 找到虚拟音频设备:" -ForegroundColor Green
    foreach ($device in $virtualDevices) {
        Write-Host "      🎤 $device" -ForegroundColor Cyan
    }
} else {
    Write-Host "   ⚠️  未找到虚拟音频设备" -ForegroundColor Yellow
    Write-Host "   请安装 VB-CABLE: https://vb-audio.com/Cable/" -ForegroundColor Yellow
}
Write-Host ""

# 4. 生成测试音频
Write-Host "4️⃣  生成测试音频文件" -ForegroundColor Yellow
$testFile = "dshow_test_tone.wav"

if (Test-Path $testFile) {
    Write-Host "   测试文件已存在，跳过生成" -ForegroundColor Gray
} else {
    Write-Host "   生成 1秒 1000Hz 测试音..." -NoNewline
    & ffmpeg -f lavfi -i "sine=frequency=1000:duration=1" -y $testFile 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " ✅" -ForegroundColor Green
    } else {
        Write-Host " ❌" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# 5. 测试 DirectShow 播放
if ($virtualDevices) {
    Write-Host "5️⃣  测试 DirectShow 播放" -ForegroundColor Yellow
    
    foreach ($device in $virtualDevices) {
        Write-Host "   测试播放到: $device" -ForegroundColor Cyan
        Write-Host "   命令: ffmpeg -re -i $testFile -f dshow audio=`"$device`"" -ForegroundColor Gray
        
        $startTime = Get-Date
        $output = & ffmpeg -re -i $testFile -f dshow "audio=$device" 2>&1
        $duration = (Get-Date) - $startTime
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ 播放成功！耗时: $([math]::Round($duration.TotalSeconds, 2))秒" -ForegroundColor Green
        } else {
            Write-Host "   ❌ 播放失败" -ForegroundColor Red
            Write-Host "   错误输出:" -ForegroundColor Gray
            $output | Select-Object -Last 5 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        }
        Write-Host ""
    }
} else {
    Write-Host "5️⃣  跳过播放测试（没有虚拟音频设备）" -ForegroundColor Yellow
}

# 6. 性能对比测试
Write-Host "6️⃣  性能对比测试" -ForegroundColor Yellow

if ($virtualDevices -and (Get-Module -ListAvailable AudioDeviceCmdlets)) {
    Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue
    
    $targetDevice = $virtualDevices[0]
    $originalDevice = (Get-AudioDevice -Playback).Name
    
    Write-Host "   原始设备: $originalDevice" -ForegroundColor Gray
    Write-Host "   目标设备: $targetDevice" -ForegroundColor Gray
    Write-Host ""
    
    # 测试 1: DirectShow 方式
    Write-Host "   方式 1: DirectShow (不切换设备)" -ForegroundColor Cyan
    $start = Get-Date
    & ffmpeg -re -i $testFile -f dshow "audio=$targetDevice" 2>&1 | Out-Null
    $dshowTime = (Get-Date) - $start
    $dshowSuccess = ($LASTEXITCODE -eq 0)
    if ($dshowSuccess) {
        Write-Host "      耗时: $([math]::Round($dshowTime.TotalSeconds, 2))秒" -ForegroundColor Green
    } else {
        Write-Host "      耗时: $([math]::Round($dshowTime.TotalSeconds, 2))秒" -ForegroundColor Red
    }
    Write-Host ""
    
    # 测试 2: 切换设备方式
    Write-Host "   方式 2: 切换设备 + 播放 + 恢复" -ForegroundColor Cyan
    $start = Get-Date
    
    Get-AudioDevice -List | Where-Object {$_.Name -eq $targetDevice} | Set-AudioDevice
    Start-Sleep -Milliseconds 800
    & ffplay -nodisp -autoexit -loglevel quiet $testFile 2>&1 | Out-Null
    Get-AudioDevice -List | Where-Object {$_.Name -eq $originalDevice} | Set-AudioDevice
    Start-Sleep -Milliseconds 500
    
    $switchTime = (Get-Date) - $start
    Write-Host "      耗时: $([math]::Round($switchTime.TotalSeconds, 2))秒" -ForegroundColor Yellow
    Write-Host ""
    
    # 对比
    Write-Host "   📊 性能对比:" -ForegroundColor Yellow
    Write-Host "      DirectShow: $([math]::Round($dshowTime.TotalSeconds, 2))秒" -ForegroundColor Green
    Write-Host "      切换方式:   $([math]::Round($switchTime.TotalSeconds, 2))秒" -ForegroundColor Yellow
    $speedup = $switchTime.TotalSeconds / $dshowTime.TotalSeconds
    Write-Host "      性能提升:   $([math]::Round($speedup, 1))x" -ForegroundColor Cyan
} else {
    Write-Host "   ⚠️  跳过性能测试（缺少必要组件）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("=" * 60)
Write-Host "📊 测试总结" -ForegroundColor Cyan
Write-Host ""

if ($audioDevices.Count -gt 0) {
    Write-Host "✅ DirectShow 可用" -ForegroundColor Green
    Write-Host "   应用可以使用 DirectShow 直接播放到指定设备" -ForegroundColor White
    Write-Host "   无需切换系统默认音频设备" -ForegroundColor White
} else {
    Write-Host "❌ DirectShow 不可用" -ForegroundColor Red
    Write-Host "   应用将使用设备切换方式（速度较慢）" -ForegroundColor Yellow
}

Write-Host ""

# 清理
if (Test-Path $testFile) {
    Remove-Item $testFile -Force
}
