@echo off
chcp 65001 >nul
echo ====================================
echo    TTS 虚拟麦克风 - 首次配置
echo ====================================
echo.

REM 检查是否已存在 .env 文件
if exist ".env" (
    echo [提示] 已存在 .env 文件
    choice /C YN /M "是否要重新配置"
    if errorlevel 2 goto :EOF
    echo.
)

echo 请输入您的阿里云 DashScope API 密钥:
echo （从 https://dashscope.console.aliyun.com/apiKey 获取）
echo.
set /p API_KEY="API Key: "

if "%API_KEY%"=="" (
    echo [错误] API Key 不能为空
    pause
    exit /b 1
)

echo.
echo 正在创建配置文件...

(
    echo # 阿里云 DashScope API 配置
    echo DASHSCOPE_API_KEY=%API_KEY%
    echo.
    echo # 语音模型（可选，默认: qwen-audio-turbo）
    echo QWEN_VOICE_MODEL=qwen-audio-turbo
    echo.
    echo # API 端点（可选）
    echo DASHSCOPE_ENDPOINT=https://dashscope.aliyuncs.com/api/v1/services/aigc/text2speech/speech-synthesis
) > .env

echo.
echo [成功] 配置文件已创建: .env
echo.
echo 接下来的步骤:
echo 1. 安装 VB-Audio Virtual Cable（虚拟音频驱动）
echo    下载: https://vb-audio.com/Cable/
echo.
echo 2. 运行 xi_virtual_voice.exe
echo.
pause
