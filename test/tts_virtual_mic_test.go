package test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/joho/godotenv"
)

// TTSVirtualMic TTS 虚拟麦克风服务
type TTSVirtualMic struct {
	apiKey         string
	model          string
	endpoint       string
	voice          string
	vbCableDevice  string
	originalDevice string
}

// NewTTSVirtualMic 创建 TTS 虚拟麦克风服务
func NewTTSVirtualMic() (*TTSVirtualMic, error) {
	err := godotenv.Load("../.env")
	if err != nil {
		return nil, fmt.Errorf("加载环境变量失败: %v", err)
	}

	return &TTSVirtualMic{
		apiKey:        os.Getenv("DASHSCOPE_API_KEY"),
		model:         os.Getenv("QWEN_VOICE_MODEL"),
		endpoint:      os.Getenv("DASHSCOPE_ENDPOINT"),
		voice:         "Cherry",
		vbCableDevice: "VB-Cable",
	}, nil
}

// Speak 说话：生成语音并播放到虚拟麦克风
func (t *TTSVirtualMic) Speak(text string) error {
	fmt.Printf("\n🎙️  准备播放: %s\n", text)
	fmt.Println(strings.Repeat("=", 60))

	// 1. 生成语音
	audioFile, err := t.generateSpeech(text)
	if err != nil {
		return err
	}
	defer os.Remove(audioFile)

	// 2. 播放到虚拟麦克风
	return t.playToVirtualMic(audioFile)
}

// generateSpeech 生成语音并返回音频文件路径
func (t *TTSVirtualMic) generateSpeech(text string) (string, error) {
	fmt.Println("📝 步骤 1/3: 正在调用 TTS API...")

	// 构造请求
	reqBody := map[string]interface{}{
		"model": t.model,
		"input": map[string]interface{}{
			"text":          text,
			"voice":         t.voice,
			"language_type": "Chinese",
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("JSON 编码失败: %v", err)
	}

	// 发送请求
	req, err := http.NewRequest("POST", t.endpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("创建请求失败: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+t.apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("发送请求失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("API 错误 (状态码 %d): %s", resp.StatusCode, body)
	}

	// 解析响应
	var ttsResp struct {
		Output struct {
			Audio struct {
				URL string `json:"url"`
			} `json:"audio"`
		} `json:"output"`
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("读取响应失败: %v", err)
	}

	err = json.Unmarshal(body, &ttsResp)
	if err != nil {
		return "", fmt.Errorf("JSON 解析失败: %v", err)
	}

	audioURL := ttsResp.Output.Audio.URL
	if audioURL == "" {
		return "", fmt.Errorf("未获取到音频 URL")
	}
	fmt.Println("   ✓ TTS API 调用成功")

	// 下载音频
	fmt.Println("📥 步骤 2/3: 正在下载音频文件...")
	audioResp, err := http.Get(audioURL)
	if err != nil {
		return "", fmt.Errorf("下载音频失败: %v", err)
	}
	defer audioResp.Body.Close()

	// 保存到临时文件
	tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("tts_%d.wav", os.Getpid()))
	outFile, err := os.Create(tmpFile)
	if err != nil {
		return "", fmt.Errorf("创建临时文件失败: %v", err)
	}
	defer outFile.Close()

	written, err := io.Copy(outFile, audioResp.Body)
	if err != nil {
		return "", fmt.Errorf("保存音频失败: %v", err)
	}

	fmt.Printf("   ✓ 音频已下载: %d 字节\n", written)
	return tmpFile, nil
}

// playToVirtualMic 播放音频到虚拟麦克风
func (t *TTSVirtualMic) playToVirtualMic(audioFile string) error {
	fmt.Println("🎤 步骤 3/3: 正在播放到虚拟麦克风...")

	// 检查是否安装了 SwitchAudioSource
	if t.hasSwitchAudioSource() {
		return t.playWithAutoSwitch(audioFile)
	}

	// 否则使用手动方式
	return t.playManual(audioFile)
}

// hasSwitchAudioSource 检查是否安装了 SwitchAudioSource 工具
func (t *TTSVirtualMic) hasSwitchAudioSource() bool {
	cmd := exec.Command("which", "SwitchAudioSource")
	err := cmd.Run()
	return err == nil
}

// playWithAutoSwitch 自动切换音频设备并播放（需要 SwitchAudioSource）
func (t *TTSVirtualMic) playWithAutoSwitch(audioFile string) error {
	// 1. 保存当前音频设备
	getCurrentCmd := exec.Command("SwitchAudioSource", "-c")
	currentDeviceBytes, err := getCurrentCmd.Output()
	if err == nil {
		t.originalDevice = strings.TrimSpace(string(currentDeviceBytes))
		fmt.Printf("   ℹ️  当前音频设备: %s\n", t.originalDevice)
	}

	// 2. 切换到 VB-Cable
	fmt.Printf("   🔄 切换音频输出到: %s\n", t.vbCableDevice)
	switchCmd := exec.Command("SwitchAudioSource", "-s", t.vbCableDevice)
	if err := switchCmd.Run(); err != nil {
		return fmt.Errorf("切换到 VB-Cable 失败: %v\n提示: 请确保 VB-Cable 已安装", err)
	}

	// 3. 播放音频
	fmt.Println("   ▶️  正在播放...")
	playCmd := exec.Command("afplay", audioFile)
	playErr := playCmd.Run()

	// 4. 恢复原音频设备
	if t.originalDevice != "" {
		fmt.Printf("   🔄 恢复音频输出到: %s\n", t.originalDevice)
		restoreCmd := exec.Command("SwitchAudioSource", "-s", t.originalDevice)
		restoreCmd.Run()
	}

	if playErr != nil {
		return fmt.Errorf("播放失败: %v", playErr)
	}

	fmt.Println("   ✅ 播放完成!")
	return nil
}

// playManual 手动播放（需要用户手动设置系统输出到 VB-Cable）
func (t *TTSVirtualMic) playManual(audioFile string) error {
	fmt.Println("\n⚠️  未检测到 SwitchAudioSource 工具")
	fmt.Println("📌 请手动设置系统音频输出:")
	fmt.Println("   1. 打开 系统设置 > 声音 > 输出")
	fmt.Println("   2. 选择 VB-Cable 作为输出设备")
	fmt.Println("   3. 按回车继续...")
	fmt.Print("\n按 Enter 继续: ")
	fmt.Scanln()

	fmt.Println("\n   ▶️  正在播放...")
	playCmd := exec.Command("afplay", audioFile)
	if err := playCmd.Run(); err != nil {
		return fmt.Errorf("播放失败: %v", err)
	}

	fmt.Println("   ✅ 播放完成!")
	fmt.Println("\n💡 提示: 可以安装 SwitchAudioSource 实现自动切换:")
	fmt.Println("   brew install switchaudio-osx")
	return nil
}

// SetVoice 设置音色
func (t *TTSVirtualMic) SetVoice(voice string) {
	t.voice = voice
}

// =========== 辅助函数 ===========

// InstallSwitchAudioSource 安装 SwitchAudioSource 工具
func InstallSwitchAudioSource() error {
	fmt.Println("正在安装 SwitchAudioSource...")
	cmd := exec.Command("brew", "install", "switchaudio-osx")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// ShowAudioDevices 显示所有音频设备
func ShowAudioDevices() {
	fmt.Println("\n=== 可用的音频设备 ===")

	// 方法1: 使用 SwitchAudioSource
	cmd := exec.Command("SwitchAudioSource", "-a", "-t", "output")
	output, err := cmd.Output()
	if err == nil {
		fmt.Println("输出设备:")
		fmt.Println(string(output))
	}

	// 方法2: 使用 system_profiler
	fmt.Println("\n详细信息:")
	cmd2 := exec.Command("system_profiler", "SPAudioDataType")
	output2, _ := cmd2.Output()
	lines := strings.Split(string(output2), "\n")
	for _, line := range lines {
		if strings.Contains(line, "VB-Cable") ||
			strings.Contains(line, "Output Channels") ||
			strings.Contains(line, "Input Channels") {
			fmt.Println(line)
		}
	}
}

// =========== 测试函数 ===========

// TestSpeakToVirtualMic 完整测试：TTS + 虚拟麦克风
func TestSpeakToVirtualMic(t *testing.T) {
	tts, err := NewTTSVirtualMic()
	if err != nil {
		t.Fatalf("创建服务失败: %v", err)
	}

	text := "你好，我是虚拟语音助手。现在正在通过VB-Cable虚拟麦克风播放这段语音，游戏中的队友应该能听到我说话。"
	err = tts.Speak(text)
	if err != nil {
		t.Fatalf("播放失败: %v", err)
	}
}

// TestMultipleSentences 测试连续说多句话
func TestMultipleSentences(t *testing.T) {
	tts, err := NewTTSVirtualMic()
	if err != nil {
		t.Fatalf("创建服务失败: %v", err)
	}

	sentences := []string{
		"大家好，我是一号玩家。",
		"我正在测试虚拟麦克风功能。",
		"如果你们能听到我的声音，请在公屏打1。",
	}

	for i, sentence := range sentences {
		fmt.Printf("\n=== 句子 %d/%d ===\n", i+1, len(sentences))
		err := tts.Speak(sentence)
		if err != nil {
			t.Fatalf("播放失败: %v", err)
		}
	}
}

// TestDifferentVoices 测试不同音色
func TestDifferentVoices(t *testing.T) {
	tts, err := NewTTSVirtualMic()
	if err != nil {
		t.Fatalf("创建服务失败: %v", err)
	}

	voices := []string{"Cherry", "Stella", "Stanley"}
	for _, voice := range voices {
		tts.SetVoice(voice)
		err := tts.Speak(fmt.Sprintf("这是%s音色的测试", voice))
		if err != nil {
			t.Logf("音色 %s 测试失败: %v", voice, err)
		}
	}
}

// TestShowDevices 列出所有音频设备
func TestShowDevices(t *testing.T) {
	ShowAudioDevices()
}

// TestCheckTools 检查必要工具
func TestCheckTools(t *testing.T) {
	fmt.Println("\n=== 工具检查 ===")

	tools := []string{"afplay", "ffmpeg", "SwitchAudioSource"}
	for _, tool := range tools {
		cmd := exec.Command("which", tool)
		err := cmd.Run()
		if err == nil {
			fmt.Printf("✅ %s: 已安装\n", tool)
		} else {
			fmt.Printf("❌ %s: 未安装\n", tool)
			if tool == "SwitchAudioSource" {
				fmt.Println("   安装命令: brew install switchaudio-osx")
			}
		}
	}
}
