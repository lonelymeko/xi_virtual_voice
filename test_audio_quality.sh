#!/bin/bash
# 音频质量测试脚本

echo "🎵 音频质量测试"
echo "===================="

# 1. 检查 VB-Cable 配置
echo -e "\n1️⃣  检查 VB-Cable 配置"
system_profiler SPAudioDataType | grep -A 5 "VB-Cable" | grep -E "VB-Cable|SampleRate|Channels"

# 2. 测试生成音频
echo -e "\n2️⃣  测试生成音频文件"
cd test
go test -v -run TestSpeakToVirtualMic -timeout 30s

# 3. 检查生成的音频文件
echo -e "\n3️⃣  检查音频文件质量"
AUDIO_FILE=$(ls -t /tmp/tts_output_*.wav 2>/dev/null | head -1)

if [ -f "$AUDIO_FILE" ]; then
    echo "找到音频文件: $AUDIO_FILE"
    
    echo -e "\n📊 音频文件信息:"
    ffprobe -hide_banner "$AUDIO_FILE" 2>&1 | grep -E "Stream|Duration"
    
    echo -e "\n🔊 音量检测:"
    ffmpeg -i "$AUDIO_FILE" -af "volumedetect" -f null /dev/null 2>&1 | grep -E "mean_volume|max_volume"
    
    echo -e "\n📈 音频统计:"
    ffmpeg -i "$AUDIO_FILE" -af "astats" -f null /dev/null 2>&1 | grep -E "DC offset|Min level|Max level|RMS"
    
else
    echo "❌ 未找到音频文件"
fi

# 4. 检查转换后的音频
CONVERTED_FILE=$(ls -t /tmp/tts_output_*_converted.wav 2>/dev/null | head -1)

if [ -f "$CONVERTED_FILE" ]; then
    echo -e "\n4️⃣  检查转换后的音频"
    echo "找到转换文件: $CONVERTED_FILE"
    
    echo -e "\n📊 转换后音频信息:"
    ffprobe -hide_banner "$CONVERTED_FILE" 2>&1 | grep -E "Stream|Duration"
    
    echo -e "\n🔊 转换后音量:"
    ffmpeg -i "$CONVERTED_FILE" -af "volumedetect" -f null /dev/null 2>&1 | grep -E "mean_volume|max_volume"
fi

# 5. 对比原始和转换后的音频
if [ -f "$AUDIO_FILE" ] && [ -f "$CONVERTED_FILE" ]; then
    echo -e "\n5️⃣  音频对比"
    echo "原始文件大小: $(ls -lh "$AUDIO_FILE" | awk '{print $5}')"
    echo "转换文件大小: $(ls -lh "$CONVERTED_FILE" | awk '{print $5}')"
fi

echo -e "\n===================="
echo "✅ 测试完成"

# 6. 建议
echo -e "\n💡 优化建议:"
if system_profiler SPAudioDataType | grep -A 5 "VB-Cable" | grep "48000"; then
    echo "✅ VB-Cable 采样率已设置为 48000 Hz (推荐)"
else
    echo "⚠️  建议将 VB-Cable 采样率设置为 48000 Hz"
    echo "   打开 Audio MIDI Setup > VB-Cable > Format > 48000.0 Hz"
fi

echo -e "\n🎯 使用说明:"
echo "1. 在应用中输入文本并发送"
echo "2. 观察是否有噪音或杂音"
echo "3. 如果有问题，参考 AUDIO_TROUBLESHOOTING.md"
