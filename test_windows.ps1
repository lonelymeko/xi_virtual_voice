# Windows 音频系统测试脚本

Write-Host "================================" -ForegroundColor Cyan
Write-Host "  Windows TTS 虚拟麦克风测试" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# 检查是否以管理员身份运行
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️  建议以管理员身份运行此脚本" -ForegroundColor Yellow
    Write-Host ""
}

# 1. 检查必要工具
Write-Host "1️⃣  检查必要工具" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

$allTools = $true

# 检查 FFmpeg
Write-Host "检查 FFmpeg..." -NoNewline
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-String "ffmpeg version" | Select-Object -First 1
    Write-Host " ✅" -ForegroundColor Green
    Write-Host "   版本: $ffmpegVersion" -ForegroundColor Gray
} catch {
    Write-Host " ❌ 未安装" -ForegroundColor Red
    Write-Host "   安装: choco install ffmpeg" -ForegroundColor Yellow
    $allTools = $false
}

# 检查 NirCmd
Write-Host "检查 NirCmd..." -NoNewline
try {
    $nircmdCheck = Get-Command nircmd -ErrorAction Stop
    Write-Host " ✅" -ForegroundColor Green
} catch {
    Write-Host " ❌ 未安装" -ForegroundColor Red
    Write-Host "   下载: https://www.nirsoft.net/utils/nircmd.html" -ForegroundColor Yellow
    $allTools = $false
}

# 检查 AudioDeviceCmdlets
Write-Host "检查 AudioDeviceCmdlets..." -NoNewline
if (Get-Module -ListAvailable -Name AudioDeviceCmdlets) {
    Write-Host " ✅" -ForegroundColor Green
    Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue
} else {
    Write-Host " ⚠️  未安装（可选）" -ForegroundColor Yellow
    Write-Host "   安装: Install-Module -Name AudioDeviceCmdlets" -ForegroundColor Gray
}

Write-Host ""

# 2. 检查虚拟音频设备
Write-Host "2️⃣  检查虚拟音频设备" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

$hasVirtualDevice = $false

try {
    if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
        $devices = Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback"}
        
        foreach ($device in $devices) {
            if ($device.Name -like "*CABLE*" -or $device.Name -like "*VoiceMeeter*" -or $device.Name -like "*Virtual*") {
                Write-Host "✅ 找到虚拟设备: $($device.Name)" -ForegroundColor Green
                $hasVirtualDevice = $true
            }
        }
    } else {
        # 使用 NirCmd 检查（备用方法）
        Write-Host "使用备用方法检测设备..." -ForegroundColor Gray
    }
} catch {
    Write-Host "⚠️  无法检测虚拟设备" -ForegroundColor Yellow
}

if (-not $hasVirtualDevice) {
    Write-Host "❌ 未找到虚拟音频设备" -ForegroundColor Red
    Write-Host "   请安装 VB-CABLE: https://vb-audio.com/Cable/" -ForegroundColor Yellow
    Write-Host "   或安装 VoiceMeeter: https://vb-audio.com/Voicemeeter/" -ForegroundColor Yellow
}

Write-Host ""

# 3. 列出所有音频设备
Write-Host "3️⃣  所有可用的播放设备" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

try {
    if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
        $playbackDevices = Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback"}
        
        foreach ($device in $playbackDevices) {
            $marker = if ($device.Default) { "🔊" } else { "  " }
            $color = if ($device.Name -like "*CABLE*" -or $device.Name -like "*Virtual*") { "Cyan" } else { "White" }
            Write-Host "$marker $($device.Name)" -ForegroundColor $color
            
            if ($device.Default) {
                Write-Host "   (当前默认设备)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "⚠️  需要 AudioDeviceCmdlets 模块来列出设备" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ 无法列出设备: $_" -ForegroundColor Red
}

Write-Host ""

# 4. 测试音频生成和播放
Write-Host "4️⃣  测试音频生成" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

if ($allTools) {
    Write-Host "生成测试音频..." -NoNewline
    $testFile = "$env:TEMP\test_tone.wav"
    
    try {
        & ffmpeg -f lavfi -i "sine=frequency=1000:duration=2" -y $testFile 2>$null
        Write-Host " ✅" -ForegroundColor Green
        Write-Host "   文件: $testFile" -ForegroundColor Gray
        
        # 测试播放
        Write-Host "播放测试音频（2秒）..." -NoNewline
        Start-Process -FilePath "ffplay" -ArgumentList "-nodisp","-autoexit","-loglevel","quiet",$testFile -Wait -NoNewWindow
        Write-Host " ✅" -ForegroundColor Green
        
        # 清理
        Remove-Item $testFile -ErrorAction SilentlyContinue
    } catch {
        Write-Host " ❌ 失败: $_" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  跳过测试（缺少必要工具）" -ForegroundColor Yellow
}

Write-Host ""

# 5. 测试设备切换
Write-Host "5️⃣  测试设备切换" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
    try {
        # 保存当前设备
        $currentDevice = (Get-AudioDevice -Playback).Name
        Write-Host "当前设备: $currentDevice" -ForegroundColor Cyan
        
        # 查找虚拟设备
        $virtualDevice = Get-AudioDevice -List | Where-Object {
            $_.Type -eq "Playback" -and ($_.Name -like "*CABLE*" -or $_.Name -like "*Virtual*")
        } | Select-Object -First 1
        
        if ($virtualDevice) {
            Write-Host "尝试切换到: $($virtualDevice.Name)" -ForegroundColor Cyan
            Set-AudioDevice -Name $virtualDevice.Name
            Start-Sleep -Seconds 1
            
            $newDevice = (Get-AudioDevice -Playback).Name
            if ($newDevice -eq $virtualDevice.Name) {
                Write-Host "✅ 切换成功" -ForegroundColor Green
            } else {
                Write-Host "❌ 切换失败" -ForegroundColor Red
            }
            
            # 恢复原设备
            Write-Host "恢复原设备: $currentDevice" -ForegroundColor Cyan
            Set-AudioDevice -Name $currentDevice
            Start-Sleep -Seconds 1
            Write-Host "✅ 已恢复" -ForegroundColor Green
        } else {
            Write-Host "⚠️  未找到虚拟设备，跳过切换测试" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ 设备切换测试失败: $_" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  需要 AudioDeviceCmdlets 模块" -ForegroundColor Yellow
}

Write-Host ""

# 6. 检查项目配置
Write-Host "6️⃣  检查项目配置" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Gray

# 检查 .env 文件
if (Test-Path ".env") {
    Write-Host "✅ 找到 .env 文件" -ForegroundColor Green
    
    $envContent = Get-Content ".env"
    $hasApiKey = $envContent | Select-String "DASHSCOPE_API_KEY" | Select-Object -First 1
    
    if ($hasApiKey) {
        Write-Host "✅ API Key 已配置" -ForegroundColor Green
    } else {
        Write-Host "⚠️  API Key 未配置" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ 未找到 .env 文件" -ForegroundColor Red
    Write-Host "   请创建 .env 文件并配置 API Key" -ForegroundColor Yellow
}

# 检查 Go 模块
if (Test-Path "go.mod") {
    Write-Host "✅ 找到 go.mod" -ForegroundColor Green
} else {
    Write-Host "⚠️  未找到 go.mod" -ForegroundColor Yellow
}

# 检查前端
if (Test-Path "frontend\package.json") {
    Write-Host "✅ 找到前端配置" -ForegroundColor Green
} else {
    Write-Host "⚠️  未找到前端配置" -ForegroundColor Yellow
}

Write-Host ""

# 7. 总结
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  测试总结" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$readyToUse = $allTools -and $hasVirtualDevice

if ($readyToUse) {
    Write-Host "✅ 系统已就绪！" -ForegroundColor Green
    Write-Host ""
    Write-Host "🚀 下一步:" -ForegroundColor Cyan
    Write-Host "   1. 确保 .env 文件已配置" -ForegroundColor White
    Write-Host "   2. 运行: wails dev" -ForegroundColor White
    Write-Host "   3. 在游戏中将麦克风设置为虚拟设备" -ForegroundColor White
} else {
    Write-Host "⚠️  系统尚未完全配置" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📋 待办事项:" -ForegroundColor Cyan
    
    if (-not $allTools) {
        Write-Host "   ❌ 安装缺少的工具（见上方）" -ForegroundColor Red
    }
    
    if (-not $hasVirtualDevice) {
        Write-Host "   ❌ 安装虚拟音频设备（VB-CABLE 或 VoiceMeeter）" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "📖 详细文档: WINDOWS_SETUP.md" -ForegroundColor Gray
Write-Host ""
