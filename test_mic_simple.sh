#!/bin/bash
# 使用 macOS 原生工具测试麦克风

echo "🎤 麦克风音质快速测试（使用系统工具）"
echo "=========================================="
echo ""

TEST_DIR="/tmp/mic_test"
mkdir -p "$TEST_DIR"

# 获取当前输入设备
CURRENT_INPUT=$(SwitchAudioSource -c -t input)
echo "当前输入设备: $CURRENT_INPUT"
echo ""

# 测试内置麦克风
echo "1️⃣  测试 MacBook Air 内置麦克风"
echo "   切换到内置麦克风..."
SwitchAudioSource -s "MacBook Air麦克风" -t input
sleep 1

echo "   录音 5 秒（请对着电脑说话）..."
echo "   ⏺️  开始录音！请说: '测试一二三，这是内置麦克风测试'"
echo ""

# 使用 ffmpeg 录音（更可靠）
if command -v ffmpeg &> /dev/null; then
    timeout 5 ffmpeg -f avfoundation -i ":MacBook Air麦克风" -t 5 -ar 48000 -ac 2 "$TEST_DIR/builtin_mic.wav" -y 2>/dev/null
    
    if [ -f "$TEST_DIR/builtin_mic.wav" ]; then
        echo "   ✅ 录音完成"
        echo "   正在播放..."
        afplay "$TEST_DIR/builtin_mic.wav"
        
        # 显示文件信息
        FILE_SIZE=$(ls -lh "$TEST_DIR/builtin_mic.wav" | awk '{print $5}')
        echo "   文件大小: $FILE_SIZE"
    else
        echo "   ❌ 录音失败"
    fi
else
    echo "   ℹ️  ffmpeg 未安装，使用简单方法..."
    echo "   请在系统设置中手动测试麦克风"
fi

echo ""

# 测试 THS326
if SwitchAudioSource -a -t input | grep -q "THS326"; then
    echo "2️⃣  测试 THS326"
    echo "   切换到 THS326..."
    SwitchAudioSource -s "THS326" -t input
    sleep 1
    
    echo "   录音 5 秒（请说话）..."
    echo "   ⏺️  开始录音！请说: '测试一二三，这是 THS326 测试'"
    echo ""
    
    if command -v ffmpeg &> /dev/null; then
        timeout 5 ffmpeg -f avfoundation -i ":THS326" -t 5 -ar 48000 -ac 2 "$TEST_DIR/ths326_mic.wav" -y 2>/dev/null
        
        if [ -f "$TEST_DIR/ths326_mic.wav" ]; then
            echo "   ✅ 录音完成"
            echo "   正在播放..."
            afplay "$TEST_DIR/ths326_mic.wav"
            
            FILE_SIZE=$(ls -lh "$TEST_DIR/ths326_mic.wav" | awk '{print $5}')
            echo "   文件大小: $FILE_SIZE"
        else
            echo "   ❌ 录音失败"
        fi
    fi
    
    echo ""
fi

# 恢复原始设备
echo "恢复原始输入设备: $CURRENT_INPUT"
SwitchAudioSource -s "$CURRENT_INPUT" -t input

echo ""
echo "=========================================="
echo "✅ 测试完成"
echo ""
echo "📁 录音文件: $TEST_DIR"
ls -lh "$TEST_DIR"/*.wav 2>/dev/null
echo ""
echo "💡 如何判断音质:"
echo "   1. 重新播放录音仔细听"
echo "   2. 注意是否有背景嗡嗡声"
echo "   3. 注意是否有嘶嘶的白噪音"
echo "   4. 声音是否清晰无失真"
echo ""
echo "🔧 常见电流音原因:"
echo "   • USB 设备干扰（特别是充电设备）"
echo "   • 充电器导致的地线回路"
echo "   • 增益设置过高"
echo "   • 音频接口质量问题"
echo "   • 软件或驱动问题"
echo ""
echo "📊 重新播放测试:"
echo "   afplay $TEST_DIR/builtin_mic.wav"
echo "   afplay $TEST_DIR/ths326_mic.wav"
echo ""
