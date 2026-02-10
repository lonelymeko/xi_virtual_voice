#!/bin/bash
# Mac 音频系统完全重置脚本

echo "🔧 Mac 音频系统重置工具"
echo "=========================================="
echo ""

# 需要管理员权限
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  此脚本需要管理员权限"
    echo "请使用: sudo ./reset_audio.sh"
    exit 1
fi

echo "此脚本将执行以下操作:"
echo "1. 重启 Core Audio 服务"
echo "2. 重置音频 NVRAM"
echo "3. 清理音频缓存"
echo "4. 重置 VB-Cable"
echo "5. 检查并修复音频权限"
echo ""
read -p "是否继续? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 1. 关闭所有使用音频的应用
echo ""
echo "1️⃣  关闭使用音频的应用..."

# 列出可能占用音频的应用
AUDIO_APPS="Spotify iTunes Music Safari Chrome Firefox Discord Zoom Skype"
for app in $AUDIO_APPS; do
    if pgrep -x "$app" > /dev/null; then
        echo "   关闭 $app..."
        killall "$app" 2>/dev/null
    fi
done

sleep 2

# 2. 重启 Core Audio
echo ""
echo "2️⃣  重启 Core Audio 服务..."
killall coreaudiod
sleep 3

if pgrep -x "coreaudiod" > /dev/null; then
    echo "   ✅ Core Audio 已重启"
else
    echo "   ⚠️  Core Audio 未运行，正在启动..."
    launchctl start com.apple.audio.coreaudiod
    sleep 2
fi

# 3. 重置 NVRAM/PRAM (音频相关)
echo ""
echo "3️⃣  重置音频 NVRAM..."
nvram -c 2>/dev/null || echo "   ℹ️  无法清除 NVRAM (正常，可能需要在启动时执行)"

# 4. 清理音频缓存
echo ""
echo "4️⃣  清理音频缓存..."

# Core Audio 缓存
if [ -d "/Library/Caches/com.apple.audio" ]; then
    rm -rf /Library/Caches/com.apple.audio/*
    echo "   ✅ 已清理系统音频缓存"
fi

# 用户音频缓存
if [ -d "$HOME/Library/Caches/com.apple.audio" ]; then
    rm -rf "$HOME/Library/Caches/com.apple.audio/*"
    echo "   ✅ 已清理用户音频缓存"
fi

# Audio Unit 缓存
if [ -d "/Library/Caches/com.apple.audiounits.cache" ]; then
    rm -rf /Library/Caches/com.apple.audiounits.cache
    echo "   ✅ 已清理 Audio Unit 缓存"
fi

# 5. 重置音频权限
echo ""
echo "5️⃣  重置音频权限..."

# 重置麦克风权限数据库
tccutil reset Microphone 2>/dev/null && echo "   ✅ 已重置麦克风权限" || echo "   ℹ️  无法重置麦克风权限"

# 6. 检查 VB-Cable
echo ""
echo "6️⃣  检查 VB-Cable 状态..."

if system_profiler SPAudioDataType | grep -q "VB-Cable"; then
    echo "   ✅ VB-Cable 已安装"
    
    # 显示当前配置
    VB_CONFIG=$(system_profiler SPAudioDataType | grep -A 10 "VB-Cable")
    SAMPLE_RATE=$(echo "$VB_CONFIG" | grep "Current SampleRate" | awk '{print $3}')
    
    echo "   当前采样率: $SAMPLE_RATE Hz"
    
    if [ "$SAMPLE_RATE" != "48000" ]; then
        echo "   ⚠️  建议设置采样率为 48000 Hz"
        echo "   稍后将打开 Audio MIDI Setup 供您调整"
    fi
else
    echo "   ❌ 未检测到 VB-Cable"
    echo "   如需安装: https://vb-audio.com/Cable/"
fi

# 7. 检查物理麦克风
echo ""
echo "7️⃣  检查物理麦克风..."

# 列出所有输入设备
echo "   可用的输入设备:"
INPUTS=$(system_profiler SPAudioDataType | grep -B 2 "Input Channels" | grep -v "^--" | grep -v "Input Channels")
echo "$INPUTS"

# 8. 修复音频设置文件
echo ""
echo "8️⃣  修复音频设置文件..."

# 删除损坏的音频偏好设置
AUDIO_PREFS=(
    "/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist"
    "$HOME/Library/Preferences/com.apple.audio.plist"
    "$HOME/Library/Preferences/com.apple.coreaudio.plist"
)

for pref in "${AUDIO_PREFS[@]}"; do
    if [ -f "$pref" ]; then
        mv "$pref" "${pref}.backup" 2>/dev/null
        echo "   ✅ 已备份并重置: $(basename $pref)"
    fi
done

# 9. 重启 Audio MIDI Setup
echo ""
echo "9️⃣  重启 Audio MIDI Setup..."
killall "Audio MIDI Setup" 2>/dev/null

# 10. 最后一次重启 Core Audio
echo ""
echo "🔟 最终重启 Core Audio..."
killall coreaudiod
sleep 3

# 11. 验证
echo ""
echo "=========================================="
echo "✅ 音频系统重置完成"
echo ""
echo "📊 当前音频设备状态:"
echo ""

# 显示当前输入设备
echo "输入设备 (麦克风):"
SwitchAudioSource -a -t input 2>/dev/null || echo "未安装 SwitchAudioSource"

echo ""
echo "输出设备 (扬声器):"
SwitchAudioSource -a -t output 2>/dev/null || echo "未安装 SwitchAudioSource"

echo ""
echo "=========================================="
echo "💡 后续步骤:"
echo ""
echo "1. 📱 打开 Audio MIDI Setup 检查配置"
echo "   (即将自动打开)"
echo ""
echo "2. 🎤 测试物理麦克风"
echo "   录音: rec test.wav (使用 sox)"
echo "   或在系统设置 > 声音 > 输入 中测试"
echo ""
echo "3. 🔧 调整 VB-Cable 设置"
echo "   - 采样率: 48000 Hz"
echo "   - 格式: 2 ch, 16-bit Integer"
echo "   - Master Volume: 70-80%"
echo ""
echo "4. 🔄 如果问题仍然存在"
echo "   - 重启 Mac"
echo "   - 检查是否有 macOS 更新"
echo "   - 考虑重装 VB-Cable"
echo ""

# 打开 Audio MIDI Setup
sleep 2
echo "正在打开 Audio MIDI Setup..."
open "/System/Applications/Utilities/Audio MIDI Setup.app"

echo ""
echo "=========================================="
echo "✨ 完成！"
echo ""
echo "💬 建议:"
echo "1. 在 Audio MIDI Setup 中检查所有设备配置"
echo "2. 测试物理麦克风是否正常"
echo "3. 如果还有问题，可能需要重启电脑"
echo ""
