# Windows 音频模块测试脚本
Write-Host "🔍 Windows 音频系统诊断" -ForegroundColor Cyan
Write-Host "=" * 60
Write-Host ""

# 1. 检查执行策略
Write-Host "1️⃣  检查 PowerShell 执行策略" -ForegroundColor Yellow
$policy = Get-ExecutionPolicy -Scope CurrentUser
Write-Host "   当前策略: $policy"
if ($policy -eq "Restricted") {
    Write-Host "   ⚠️  执行策略过于严格,建议运行:" -ForegroundColor Red
    Write-Host "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor White
} else {
    Write-Host "   ✅ 执行策略正常" -ForegroundColor Green
}
Write-Host ""

# 2. 检查 AudioDeviceCmdlets 模块
Write-Host "2️⃣  检查 AudioDeviceCmdlets 模块" -ForegroundColor Yellow
$module = Get-Module -ListAvailable -Name AudioDeviceCmdlets
if ($module) {
    Write-Host "   ✅ 模块已安装" -ForegroundColor Green
    Write-Host "   版本: $($module.Version)" -ForegroundColor Gray
    Write-Host "   路径: $($module.Path)" -ForegroundColor Gray
    
    # 尝试导入模块
    Write-Host "   尝试导入模块..." -NoNewline
    try {
        Import-Module AudioDeviceCmdlets -ErrorAction Stop
        Write-Host " ✅" -ForegroundColor Green
        
        # 测试命令
        Write-Host "   测试 Get-AudioDevice 命令..." -NoNewline
        $currentDevice = Get-AudioDevice -Playback -ErrorAction Stop
        Write-Host " ✅" -ForegroundColor Green
        Write-Host "   当前播放设备: $($currentDevice.Name)" -ForegroundColor Cyan
        
    } catch {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "   错误: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "   ❌ 模块未安装" -ForegroundColor Red
    Write-Host "   请运行: Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force" -ForegroundColor Yellow
}
Write-Host ""

# 3. 检查 FFmpeg
Write-Host "3️⃣  检查 FFmpeg" -ForegroundColor Yellow
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-String "ffmpeg version" | Select-Object -First 1
    Write-Host "   ✅ FFmpeg 已安装" -ForegroundColor Green
    Write-Host "   $ffmpegVersion" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ FFmpeg 未安装或不在 PATH 中" -ForegroundColor Red
    Write-Host "   下载: https://www.gyan.dev/ffmpeg/builds/" -ForegroundColor Yellow
}
Write-Host ""

# 4. 列出音频设备
Write-Host "4️⃣  音频设备列表" -ForegroundColor Yellow
try {
    Import-Module AudioDeviceCmdlets -ErrorAction Stop
    $devices = Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback"}
    
    if ($devices) {
        Write-Host "   找到 $($devices.Count) 个播放设备:" -ForegroundColor Green
        Write-Host ""
        $devices | ForEach-Object {
            $indicator = if ($_.Default) { "🔊 [默认]" } else { "   " }
            Write-Host "   $indicator $($_.Name)" -ForegroundColor $(if ($_.Default) { "Cyan" } else { "White" })
        }
        
        # 检查是否有虚拟音频设备
        $virtualDevices = $devices | Where-Object { $_.Name -like "*CABLE*" -or $_.Name -like "*VoiceMeeter*" -or $_.Name -like "*Virtual*" }
        Write-Host ""
        if ($virtualDevices) {
            Write-Host "   ✅ 找到虚拟音频设备:" -ForegroundColor Green
            $virtualDevices | ForEach-Object {
                Write-Host "      - $($_.Name)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "   ⚠️  未找到虚拟音频设备 (CABLE/VoiceMeeter)" -ForegroundColor Yellow
            Write-Host "   请安装 VB-CABLE: https://vb-audio.com/Cable/" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ⚠️  未找到音频设备" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ 无法列出音频设备" -ForegroundColor Red
    Write-Host "   错误: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 5. 测试设备切换（如果有虚拟设备）
Write-Host "5️⃣  测试设备切换功能" -ForegroundColor Yellow
try {
    Import-Module AudioDeviceCmdlets -ErrorAction Stop
    $currentDevice = Get-AudioDevice -Playback
    Write-Host "   当前设备: $($currentDevice.Name)" -ForegroundColor Cyan
    
    $cableDevice = Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback" -and $_.Name -like "*CABLE Input*"}
    if ($cableDevice) {
        Write-Host "   测试切换到 CABLE Input..." -NoNewline
        $cableDevice | Set-AudioDevice
        Start-Sleep -Milliseconds 500
        
        $newDevice = Get-AudioDevice -Playback
        if ($newDevice.Name -eq $cableDevice.Name) {
            Write-Host " ✅" -ForegroundColor Green
            
            # 恢复原设备
            Write-Host "   恢复原设备..." -NoNewline
            Get-AudioDevice -List | Where-Object {$_.Name -eq $currentDevice.Name} | Set-AudioDevice
            Start-Sleep -Milliseconds 500
            Write-Host " ✅" -ForegroundColor Green
        } else {
            Write-Host " ❌ 切换失败" -ForegroundColor Red
        }
    } else {
        Write-Host "   ⚠️  未找到 CABLE Input 设备,跳过测试" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ 测试失败" -ForegroundColor Red
    Write-Host "   错误: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# 总结
Write-Host "=" * 60
Write-Host "📊 诊断完成" -ForegroundColor Cyan
Write-Host ""
Write-Host "如果所有检查都通过,请:" -ForegroundColor Yellow
Write-Host "1. 确保已重启应用程序" -ForegroundColor White
Write-Host "2. 在应用中选择 'CABLE Input' 作为输出设备" -ForegroundColor White
Write-Host "3. 在游戏/Discord 中选择 'CABLE Output' 作为麦克风" -ForegroundColor White
Write-Host ""
