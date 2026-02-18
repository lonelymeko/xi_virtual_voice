@echo off
REM ============================================================
REM FFmpeg 自动下载和安装脚本 (Windows)
REM ============================================================

setlocal EnableDelayedExpansion

echo.
echo ========================================
echo   FFmpeg 自动安装工具
echo ========================================
echo.

REM 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [提示] 建议以管理员身份运行以安装到系统目录
    echo [提示] 将安装到当前用户目录
    set "INSTALL_DIR=%USERPROFILE%\ffmpeg"
) else (
    set "INSTALL_DIR=C:\ffmpeg"
)

REM FFmpeg 下载链接 (使用 GitHub releases)
set "FFMPEG_VERSION=7.0.2"
set "FFMPEG_URL=https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
set "DOWNLOAD_FILE=%TEMP%\ffmpeg.zip"

echo [1/5] 检查 FFmpeg 是否已安装...
where ffmpeg >nul 2>&1
if %errorLevel% equ 0 (
    echo [✓] FFmpeg 已安装
    ffmpeg -version | findstr "ffmpeg version"
    echo.
    choice /C YN /M "是否重新安装"
    if errorlevel 2 goto :end
)

echo [2/5] 创建安装目录: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
)

echo [3/5] 下载 FFmpeg...
echo [提示] 下载地址: %FFMPEG_URL%
echo [提示] 这可能需要几分钟，请耐心等待...

REM 使用 PowerShell 下载
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%FFMPEG_URL%' -OutFile '%DOWNLOAD_FILE%' -UserAgent 'Mozilla/5.0'}"

if not exist "%DOWNLOAD_FILE%" (
    echo [✗] 下载失败！
    echo.
    echo [方案A] 手动下载:
    echo    1. 访问: https://github.com/BtbN/FFmpeg-Builds/releases
    echo    2. 下载: ffmpeg-master-latest-win64-gpl.zip
    echo    3. 解压到: %INSTALL_DIR%
    echo.
    echo [方案B] 使用 Chocolatey:
    echo    choco install ffmpeg
    echo.
    echo [方案C] 使用 Scoop:
    echo    scoop install ffmpeg
    pause
    goto :end
)

echo [4/5] 解压 FFmpeg...
powershell -Command "Expand-Archive -Path '%DOWNLOAD_FILE%' -DestinationPath '%INSTALL_DIR%\temp' -Force"

REM 移动文件到正确位置
for /d %%i in ("%INSTALL_DIR%\temp\ffmpeg-*") do (
    xcopy "%%i\bin\*" "%INSTALL_DIR%\bin\" /E /I /Y >nul
    xcopy "%%i\doc\*" "%INSTALL_DIR%\doc\" /E /I /Y >nul
)

REM 清理临时文件
rd /s /q "%INSTALL_DIR%\temp" 2>nul
del /f /q "%DOWNLOAD_FILE%" 2>nul

echo [5/5] 配置环境变量...

REM 检查 PATH 中是否已包含 FFmpeg
echo %PATH% | findstr /C:"%INSTALL_DIR%\bin" >nul
if %errorLevel% neq 0 (
    echo [提示] 添加到系统 PATH...
    
    REM 使用 PowerShell 添加到用户环境变量
    powershell -Command "& {$path = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($path -notlike '*%INSTALL_DIR%\bin*') { [Environment]::SetEnvironmentVariable('Path', $path + ';%INSTALL_DIR%\bin', 'User'); echo '[✓] 已添加到用户 PATH' } else { echo '[✓] 已在 PATH 中' }}"
) else (
    echo [✓] 已在 PATH 中
)

echo.
echo ========================================
echo   安装完成！
echo ========================================
echo.
echo [安装位置] %INSTALL_DIR%
echo [可执行文件] %INSTALL_DIR%\bin\ffmpeg.exe
echo.
echo [重要] 请重启终端或命令提示符以使 PATH 生效
echo.

REM 验证安装
echo [验证安装]
if exist "%INSTALL_DIR%\bin\ffmpeg.exe" (
    echo [✓] ffmpeg.exe 找到
    "%INSTALL_DIR%\bin\ffmpeg.exe" -version 2>nul | findstr "ffmpeg version"
) else (
    echo [✗] ffmpeg.exe 未找到
)

if exist "%INSTALL_DIR%\bin\ffprobe.exe" (
    echo [✓] ffprobe.exe 找到
) else (
    echo [✗] ffprobe.exe 未找到
)

echo.
echo [快速测试]
echo 请在新的命令提示符窗口中运行:
echo   ffmpeg -version
echo.

pause

:end
endlocal
