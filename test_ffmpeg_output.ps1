# 测试 ffmpeg 输出到特定音频设备的方法

Write-Host "`n=== 测试 1: 检查 ffmpeg 支持的输出格式 ===" -ForegroundColor Cyan
ffmpeg -formats 2>&1 | Select-String -Pattern "wasapi|dsound|sdl"

Write-Host "`n=== 测试 2: 列出 DirectSound 设备 ===" -ForegroundColor Cyan
ffmpeg -list_devices true -f dsound -i dummy 2>&1 | Select-String -Pattern "DirectSound"

Write-Host "`n=== 测试 3: 列出 WASAPI 设备 ===" -ForegroundColor Cyan  
# WASAPI 是 Windows 推荐的音频 API
Write-Host "检查是否支持 WASAPI..." -ForegroundColor Yellow
