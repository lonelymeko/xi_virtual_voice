#!/bin/bash
# VB-Cable 电流音诊断和修复脚本

echo "🔧 VB-Cable 电流音诊断"
echo "======================================"

# 1. 检查 VB-Cable 当前配置
echo -e "\n1️⃣  检查 VB-Cable 配置"
VB_CONFIG=$(system_profiler SPAudioDataType | grep -A 10 "VB-Cable")
echo "$VB_CONFIG"

SAMPLE_RATE=$(echo "$VB_CONFIG" | grep "Current SampleRate" | awk '{print $3}')
echo -e "\n当前采样率: $SAMPLE_RATE Hz"

if [ "$SAMPLE_RATE" != "48000" ]; then
    echo "⚠️  警告: 采样率不是 48000 Hz"
    echo "   建议操作: 打开 Audio MIDI Setup，设置为 48000 Hz"
fi

# 2. 测试音频文件
echo -e "\n2️⃣  生成测试音频"
cd test
go test -v -run TestSpeakToVirtualMic -timeout 30s > /tmp/tts_test.log 2>&1 &
TEST_PID=$!

echo "等待音频生成..."
sleep 5

# 检查是否有音频文件
AUDIO_FILE=$(ls -t /tmp/tts_output_*.wav 2>/dev/null | head -1)
CONVERTED_FILE=$(ls -t /tmp/tts_output_*_converted.wav 2>/dev/null | head -1)

if [ -f "$AUDIO_FILE" ]; then
    echo -e "\n3️⃣  分析原始音频文件"
    echo "文件: $AUDIO_FILE"
    
    # 检查音频信息
    echo -e "\n📊 音频信息:"
    ffprobe -hide_banner "$AUDIO_FILE" 2>&1 | grep -E "Stream|Duration|Audio"
    
    # 检查音量
    echo -e "\n🔊 音量分析:"
    VOLUME_INFO=$(ffmpeg -i "$AUDIO_FILE" -af "volumedetect" -f null /dev/null 2>&1 | grep -E "mean_volume|max_volume")
    echo "$VOLUME_INFO"
    
    MAX_VOLUME=$(echo "$VOLUME_INFO" | grep "max_volume" | awk '{print $5}')
    if (( $(echo "$MAX_VOLUME > -1.0" | bc -l) )); then
        echo "⚠️  警告: 音量过高，可能导致爆音/失真"
        echo "   最大音量: $MAX_VOLUME dB (建议 < -1.0 dB)"
    fi
    
    # 检查噪音/静音
    echo -e "\n📈 噪音分析:"
    ffmpeg -i "$AUDIO_FILE" -af "astats=metadata=1:reset=1" -f null /dev/null 2>&1 | grep -E "DC offset|Noise floor" | head -2
fi

if [ -f "$CONVERTED_FILE" ]; then
    echo -e "\n4️⃣  分析转换后的音频"
    echo "文件: $CONVERTED_FILE"
    
    echo -e "\n📊 音频信息:"
    ffprobe -hide_banner "$CONVERTED_FILE" 2>&1 | grep -E "Stream|Duration|Audio"
    
    echo -e "\n🔊 音量分析:"
    CONVERTED_VOLUME=$(ffmpeg -i "$CONVERTED_FILE" -af "volumedetect" -f null /dev/null 2>&1 | grep -E "mean_volume|max_volume")
    echo "$CONVERTED_VOLUME"
fi

# 5. 对比测试
if [ -f "$AUDIO_FILE" ] && [ -f "$CONVERTED_FILE" ]; then
    echo -e "\n5️⃣  对比测试"
    
    echo "原始文件大小: $(ls -lh "$AUDIO_FILE" | awk '{print $5}')"
    echo "转换文件大小: $(ls -lh "$CONVERTED_FILE" | awk '{print $5}')"
    
    echo -e "\n📝 播放测试建议:"
    echo "1. 直接播放原始文件: afplay '$AUDIO_FILE'"
    echo "2. 直接播放转换文件: afplay '$CONVERTED_FILE'"
    echo "3. 对比哪个音质更好"
fi

# 6. 检查 Core Audio 状态
echo -e "\n6️⃣  检查 Core Audio 状态"
if pgrep -x "coreaudiod" > /dev/null; then
    echo "✅ Core Audio 服务运行正常"
else
    echo "❌ Core Audio 服务未运行"
    echo "   尝试重启: sudo killall coreaudiod"
fi

# 7. 建议
echo -e "\n======================================"
echo "💡 修复建议:"
echo ""

if [ "$SAMPLE_RATE" != "48000" ]; then
    echo "🔧 1. 设置 VB-Cable 采样率为 48000 Hz"
    echo "   open '/System/Applications/Utilities/Audio MIDI Setup.app'"
    echo "   选择 VB-Cable > Format > 48000.0 Hz, 2 ch, 16-bit Integer"
    echo ""
fi

echo "🔧 2. 重启 Core Audio (如果问题严重)"
echo "   sudo killall coreaudiod"
echo ""

echo "🔧 3. 测试不同的播放方法"
if [ -f "$CONVERTED_FILE" ]; then
    echo "   # 方法 A: 直接播放转换后的文件"
    echo "   afplay '$CONVERTED_FILE'"
    echo ""
    echo "   # 方法 B: 使用 ffplay"
    echo "   ffplay -nodisp -autoexit '$CONVERTED_FILE'"
fi
echo ""

echo "🔧 4. 调整 VB-Cable 音量"
echo "   在 Audio MIDI Setup 中降低 VB-Cable 的 Master Volume 到 75%"
echo ""

echo "🔧 5. 使用替代方案"
echo "   考虑尝试 BlackHole (https://github.com/ExistentialAudio/BlackHole)"
echo ""

# 8. 快速修复
echo "======================================"
echo "🚀 快速修复 (自动化)"
read -p "是否尝试自动修复 VB-Cable 配置? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "正在重启 Core Audio..."
    sudo killall coreaudiod
    sleep 2
    echo "✅ Core Audio 已重启"
    
    echo -e "\n请在 Audio MIDI Setup 中手动设置:"
    echo "1. VB-Cable 采样率: 48000 Hz"
    echo "2. 格式: 2 ch, 16-bit Integer"
    echo "3. Master Volume: 75%"
    
    open "/System/Applications/Utilities/Audio MIDI Setup.app"
fi

# 清理
wait $TEST_PID 2>/dev/null

echo -e "\n======================================"
echo "✅ 诊断完成"
echo ""
echo "如果问题仍然存在，请查看:"
echo "- AUDIO_TROUBLESHOOTING.md (详细排查)"
echo "- 或运行: ./test_audio_quality.sh"
