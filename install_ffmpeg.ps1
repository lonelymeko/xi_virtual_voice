# FFmpeg 自动安装脚本 (PowerShell)
# 支持 Windows 10/11

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "$env:USERPROFILE\ffmpeg",
    
    [Parameter()]
    [switch]$SystemWide,
    
    [Parameter()]
    [switch]$Force
)

# 设置错误处理
$ErrorActionPreference = "Stop"

# 颜色输出函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# 标题
Write-Host ""
Write-ColorOutput "========================================" "Cyan"
Write-ColorOutput "   FFmpeg 自动安装工具 (PowerShell)" "Cyan"
Write-ColorOutput "========================================" "Cyan"
Write-Host ""

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($SystemWide -and -not $isAdmin) {
    Write-ColorOutput "[错误] 系统级安装需要管理员权限" "Red"
    Write-ColorOutput "[提示] 请以管理员身份运行 PowerShell" "Yellow"
    exit 1
}

if ($SystemWide) {
    $InstallPath = "C:\ffmpeg"
}

# 检查是否已安装
Write-ColorOutput "[1/6] 检查 FFmpeg 是否已安装..." "Cyan"
$existingFFmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue

if ($existingFFmpeg) {
    Write-ColorOutput "[✓] FFmpeg 已安装: $($existingFFmpeg.Source)" "Green"
    & ffmpeg -version 2>&1 | Select-Object -First 1
    
    if (-not $Force) {
        $response = Read-Host "`n是否重新安装? (y/n)"
        if ($response -ne 'y') {
            Write-ColorOutput "`n安装已取消" "Yellow"
            exit 0
        }
    }
}

# 创建安装目录
Write-ColorOutput "`n[2/6] 创建安装目录: $InstallPath" "Cyan"
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-ColorOutput "[✓] 目录已创建" "Green"
} else {
    Write-ColorOutput "[✓] 目录已存在" "Green"
}

# 下载 FFmpeg
Write-ColorOutput "`n[3/6] 下载 FFmpeg..." "Cyan"
$downloadUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$zipFile = "$env:TEMP\ffmpeg.zip"

Write-ColorOutput "[提示] 下载地址: $downloadUrl" "Gray"
Write-ColorOutput "[提示] 这可能需要几分钟，请耐心等待..." "Gray"

try {
    # 设置 TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # 下载文件
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
    $webClient.DownloadFile($downloadUrl, $zipFile)
    
    Write-ColorOutput "[✓] 下载完成: $([math]::Round((Get-Item $zipFile).Length / 1MB, 2)) MB" "Green"
} catch {
    Write-ColorOutput "[✗] 下载失败: $($_.Exception.Message)" "Red"
    Write-Host ""
    Write-ColorOutput "请尝试手动下载:" "Yellow"
    Write-ColorOutput "  1. 访问: https://github.com/BtbN/FFmpeg-Builds/releases" "Yellow"
    Write-ColorOutput "  2. 下载: ffmpeg-master-latest-win64-gpl.zip" "Yellow"
    Write-ColorOutput "  3. 解压到: $InstallPath" "Yellow"
    exit 1
}

# 解压文件
Write-ColorOutput "`n[4/6] 解压 FFmpeg..." "Cyan"
$tempExtractPath = "$InstallPath\temp"

try {
    # 清理旧的临时目录
    if (Test-Path $tempExtractPath) {
        Remove-Item $tempExtractPath -Recurse -Force
    }
    
    # 解压
    Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
    
    # 查找并移动文件
    $ffmpegFolder = Get-ChildItem -Path $tempExtractPath -Directory | Where-Object { $_.Name -like "ffmpeg-*" } | Select-Object -First 1
    
    if ($ffmpegFolder) {
        # 复制 bin 目录
        $binSource = Join-Path $ffmpegFolder.FullName "bin"
        $binDest = Join-Path $InstallPath "bin"
        
        if (Test-Path $binDest) {
            Remove-Item $binDest -Recurse -Force
        }
        Copy-Item $binSource -Destination $binDest -Recurse -Force
        
        # 复制 doc 目录（可选）
        $docSource = Join-Path $ffmpegFolder.FullName "doc"
        $docDest = Join-Path $InstallPath "doc"
        
        if (Test-Path $docSource) {
            if (Test-Path $docDest) {
                Remove-Item $docDest -Recurse -Force
            }
            Copy-Item $docSource -Destination $docDest -Recurse -Force
        }
        
        Write-ColorOutput "[✓] 解压完成" "Green"
    } else {
        throw "找不到 FFmpeg 目录"
    }
} catch {
    Write-ColorOutput "[✗] 解压失败: $($_.Exception.Message)" "Red"
    exit 1
} finally {
    # 清理临时文件
    if (Test-Path $tempExtractPath) {
        Remove-Item $tempExtractPath -Recurse -Force
    }
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }
}

# 配置环境变量
Write-ColorOutput "`n[5/6] 配置环境变量..." "Cyan"
$binPath = Join-Path $InstallPath "bin"

if ($SystemWide) {
    $scope = "Machine"
} else {
    $scope = "User"
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", $scope)

if ($currentPath -notlike "*$binPath*") {
    $newPath = $currentPath.TrimEnd(';') + ";" + $binPath
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
    
    # Update current session PATH
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = $machinePath + ";" + $userPath
    
    Write-ColorOutput "[OK] Added to $scope PATH" "Green"
} else {
    Write-ColorOutput "[OK] Already in PATH" "Green"
}

# 验证安装
Write-ColorOutput "`n[6/6] 验证安装..." "Cyan"
$ffmpegExe = Join-Path $binPath "ffmpeg.exe"
$ffprobeExe = Join-Path $binPath "ffprobe.exe"

if (Test-Path $ffmpegExe) {
    Write-ColorOutput "[✓] ffmpeg.exe 找到" "Green"
    
    # 尝试运行 ffmpeg
    try {
        $version = & $ffmpegExe -version 2>&1 | Select-Object -First 1
        Write-ColorOutput "    $version" "Gray"
    } catch {
        Write-ColorOutput "[⚠] 无法运行 ffmpeg" "Yellow"
    }
} else {
    Write-ColorOutput "[✗] ffmpeg.exe 未找到" "Red"
}

if (Test-Path $ffprobeExe) {
    Write-ColorOutput "[✓] ffprobe.exe 找到" "Green"
} else {
    Write-ColorOutput "[✗] ffprobe.exe 未找到" "Red"
}

# 完成
Write-Host ""
Write-ColorOutput "========================================" "Cyan"
Write-ColorOutput "   安装完成！" "Green"
Write-ColorOutput "========================================" "Cyan"
Write-Host ""
Write-ColorOutput "[安装位置] $InstallPath" "White"
Write-ColorOutput "[可执行文件] $binPath\ffmpeg.exe" "White"
Write-ColorOutput "[环境变量] $scope PATH" "White"
Write-Host ""
Write-ColorOutput "[重要] 请重启 PowerShell/终端以使 PATH 生效" "Yellow"
Write-Host ""
Write-ColorOutput "[快速测试] 在新的终端中运行:" "Cyan"
Write-ColorOutput "  ffmpeg -version" "Gray"
Write-Host ""

# 询问是否立即测试
$testNow = Read-Host "是否在新窗口中测试? (y/n)"
if ($testNow -eq 'y') {
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "ffmpeg -version"
}

Write-ColorOutput "`n安装脚本执行完毕！" "Green"
