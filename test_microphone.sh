#!/bin/bash
# 快速测试麦克风音质

echo "🎤 麦克风音质测试"
echo "=========================================="
echo ""

# 显示当前输入设备
echo "📊 当前可用的输入设备:"
SwitchAudioSource -a -t input
echo ""

# 获取当前输入设备
CURRENT_INPUT=$(SwitchAudioSource -c -t input)
echo "当前输入设备: $CURRENT_INPUT"
echo ""

# 测试每个物理麦克风
TEST_DIR="/tmp/mic_test"
mkdir -p "$TEST_DIR"

echo "=========================================="
echo "将测试以下麦克风:"
echo "1. MacBook Air麦克风 (内置麦克风)"
echo "2. THS326 (如果是外接设备)"
echo ""

# 测试内置麦克风
echo "1️⃣  测试 MacBook Air 内置麦克风..."
echo "   切换到内置麦克风..."
SwitchAudioSource -s "MacBook Air麦克风" -t input
sleep 1

echo "   录音 5 秒（请说话测试）..."
echo "   开始录音 - 请说: '测试一二三，我是 xixiu'"
rec -r 48000 -c 2 -b 16 "$TEST_DIR/builtin_mic.wav" trim 0 5 2>/dev/null

if [ $? -eq 0 ]; then
    echo "   ✅ 录音完成: $TEST_DIR/builtin_mic.wav"
    echo "   正在播放..."
    afplay "$TEST_DIR/builtin_mic.wav"
    sleep 1
    
    # 分析音频
    echo "   分析音频质量..."
    sox "$TEST_DIR/builtin_mic.wav" -n stats 2>&1 | grep -E "(Maximum amplitude|RMS|Noise floor)"
else
    echo "   ❌ 录音失败（可能未安装 sox）"
    echo "   安装命令: brew install sox"
fi

echo ""

# 测试 THS326
if SwitchAudioSource -a -t input | grep -q "THS326"; then
    echo "2️⃣  测试 THS326 外接设备..."
    echo "   切换到 THS326..."
    SwitchAudioSource -s "THS326" -t input
    sleep 1
    
    echo "   录音 5 秒（请说话测试）..."
    echo "   开始录音 - 请说: '测试一二三，我是 xixiu'"
    rec -r 48000 -c 2 -b 16 "$TEST_DIR/ths326_mic.wav" trim 0 5 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "   ✅ 录音完成: $TEST_DIR/ths326_mic.wav"
        echo "   正在播放..."
        afplay "$TEST_DIR/ths326_mic.wav"
        sleep 1
        
        # 分析音频
        echo "   分析音频质量..."
        sox "$TEST_DIR/ths326_mic.wav" -n stats 2>&1 | grep -E "(Maximum amplitude|RMS|Noise floor)"
    else
        echo "   ❌ 录音失败"
    fi
    
    echo ""
fi

# 恢复原始输入设备
echo "恢复原始输入设备: $CURRENT_INPUT"
SwitchAudioSource -s "$CURRENT_INPUT" -t input

echo ""
echo "=========================================="
echo "✅ 测试完成"
echo ""
echo "📁 录音文件位置: $TEST_DIR"
echo ""
echo "💡 判断标准:"
echo "   ✅ 正常: 音量稳定，背景安静，声音清晰"
echo "   ⚠️  有电流音: 背景有嗡嗡声、嘶嘶声、杂音"
echo ""
echo "🔧 如果有电流音:"
echo "   1. 检查是否插入外接设备导致底噪"
echo "   2. 尝试拔掉所有 USB 设备"
echo "   3. 检查充电器是否导致干扰"
echo "   4. 重启 Mac"
echo "   5. 在 Audio MIDI Setup 中调整增益"
echo ""
echo "📊 重新播放录音:"
echo "   afplay $TEST_DIR/builtin_mic.wav"
echo "   afplay $TEST_DIR/ths326_mic.wav"
echo ""
