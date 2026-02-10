package main

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
	"sync"
	"time"

	"github.com/joho/godotenv"
)

// TTSService TTS 服务
type TTSService struct {
	apiKey        string
	model         string
	endpoint      string
	currentDevice string
	mu            sync.Mutex
}

// NewTTSService 创建 TTS 服务
func NewTTSService() (*TTSService, error) {
	err := godotenv.Load(".env")
	if err != nil {
		// 尝试从上级目录加载
		err = godotenv.Load("../.env")
		if err != nil {
			return nil, fmt.Errorf("加载环境变量失败: %v", err)
		}
	}

	return &TTSService{
		apiKey:   os.Getenv("DASHSCOPE_API_KEY"),
		model:    os.Getenv("QWEN_VOICE_MODEL"),
		endpoint: os.Getenv("DASHSCOPE_ENDPOINT"),
	}, nil
}

// AudioDevice 音频设备信息
type AudioDevice struct {
	Name      string `json:"name"`
	IsDefault bool   `json:"isDefault"`
}

// TTSRequest TTS 请求
type TTSRequest struct {
	Text   string `json:"text"`
	Voice  string `json:"voice"`
	Device string `json:"device"`
}

// TTSResponse TTS 响应
type TTSResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Error   string `json:"error,omitempty"`
}

// GetAudioDevices 获取所有音频输出设备
func (s *TTSService) GetAudioDevices() ([]AudioDevice, error) {
	// 检查是否安装了 SwitchAudioSource
	cmd := exec.Command("which", "SwitchAudioSource")
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("SwitchAudioSource 未安装，请运行: brew install switchaudio-osx")
	}

	// 获取所有输出设备
	cmd = exec.Command("SwitchAudioSource", "-a", "-t", "output")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("获取音频设备失败: %v", err)
	}

	// 获取当前设备
	currentCmd := exec.Command("SwitchAudioSource", "-c")
	currentOutput, _ := currentCmd.Output()
	currentDevice := strings.TrimSpace(string(currentOutput))

	// 解析设备列表
	lines := strings.Split(string(output), "\n")
	devices := make([]AudioDevice, 0)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			devices = append(devices, AudioDevice{
				Name:      line,
				IsDefault: line == currentDevice,
			})
		}
	}

	return devices, nil
}

// GenerateAndPlaySpeech 生成语音并播放到指定设备
func (s *TTSService) GenerateAndPlaySpeech(text, voice, device string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// 1. 生成语音
	audioFile, err := s.generateSpeech(text, voice)
	if err != nil {
		return err
	}
	defer os.Remove(audioFile)

	// 2. 转换音频格式以提高音质（可选，如果转换失败会使用原文件）
	convertedFile, err := s.convertAudioFormat(audioFile)
	if err == nil && convertedFile != audioFile {
		defer os.Remove(convertedFile)
		audioFile = convertedFile
	}

	// 3. 播放到指定设备
	return s.playToDevice(audioFile, device)
}

// generateSpeech 调用 TTS API 生成语音
func (s *TTSService) generateSpeech(text, voice string) (string, error) {
	// 构造请求
	reqBody := map[string]interface{}{
		"model": s.model,
		"input": map[string]interface{}{
			"text":          text,
			"voice":         voice,
			"language_type": "Chinese",
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("JSON 编码失败: %v", err)
	}

	// 发送请求
	req, err := http.NewRequest("POST", s.endpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("创建请求失败: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.apiKey)

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

	// 下载音频文件
	audioResp, err := http.Get(audioURL)
	if err != nil {
		return "", fmt.Errorf("下载音频失败: %v", err)
	}
	defer audioResp.Body.Close()

	// 保存到临时文件
	tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("tts_output_%d.wav", os.Getpid()))
	outFile, err := os.Create(tmpFile)
	if err != nil {
		return "", fmt.Errorf("创建临时文件失败: %v", err)
	}
	defer outFile.Close()

	_, err = io.Copy(outFile, audioResp.Body)
	if err != nil {
		return "", fmt.Errorf("保存音频失败: %v", err)
	}

	return tmpFile, nil
}

// convertAudioFormat 转换音频格式并清理音频（降噪、去电流声）
func (s *TTSService) convertAudioFormat(inputFile string) (string, error) {
	outputFile := strings.TrimSuffix(inputFile, ".wav") + "_clean.wav"

	// 使用 ffmpeg 高级音频处理滤镜链：
	// 1. highpass=f=200: 去除200Hz以下的低频噪音（电流声、嗡嗡声）
	// 2. lowpass=f=3400: 去除3400Hz以上的高频噪音（人声主要在200-3400Hz）
	// 3. anlmdn: 自适应降噪滤镜
	//    - s=0.002: 降噪强度
	//    - p=0.004: 降噪参数
	//    - m=15: 中值滤波窗口大小
	// 4. dynaudnorm: 动态音量标准化
	//    - f=150: 滤波器大小
	//    - g=15: 增益因子
	// 5. volume=0.85: 降低音量避免爆音和失真
	cmd := exec.Command("ffmpeg",
		"-i", inputFile, // 输入文件
		"-af", "highpass=f=200,lowpass=f=3400,anlmdn=s=0.002:p=0.004:m=15,dynaudnorm=f=150:g=15,volume=0.85", // 音频清理滤镜链
		"-ar", "48000", // 采样率 48kHz
		"-ac", "2", // 立体声
		"-acodec", "pcm_s16le", // PCM 编码
		"-loglevel", "error", // 只显示错误
		"-y", // 覆盖输出文件
		outputFile,
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		// 如果转换失败，返回原文件（不影响播放）
		fmt.Printf("音频处理失败: %v, 输出: %s\n", err, stderr.String())
		return inputFile, nil
	}

	return outputFile, nil
}

// playToDevice 播放音频到指定设备
func (s *TTSService) playToDevice(audioFile, device string) error {
	// 保存当前设备
	getCurrentCmd := exec.Command("SwitchAudioSource", "-c")
	currentDeviceBytes, err := getCurrentCmd.Output()
	if err == nil {
		s.currentDevice = strings.TrimSpace(string(currentDeviceBytes))
	}

	// 切换到目标设备
	switchCmd := exec.Command("SwitchAudioSource", "-s", device)
	if err := switchCmd.Run(); err != nil {
		return fmt.Errorf("切换到设备 %s 失败: %v", device, err)
	}

	// 等待设备切换完成并稳定（增加到 500ms）
	time.Sleep(500 * time.Millisecond)

	// 使用 afplay 播放音频（-q 1 提高质量）
	playCmd := exec.Command("afplay",
		"-q", "1", // 设置播放质量为最高
		audioFile,
	)

	// 捕获错误输出
	var stderr bytes.Buffer
	playCmd.Stderr = &stderr

	// 同步等待播放完成（不要提前切换设备）
	playErr := playCmd.Run()

	if playErr != nil {
		fmt.Printf("播放错误输出: %s\n", stderr.String())
	}

	// 播放完成后等待缓冲区清空（增加到 300ms）
	time.Sleep(300 * time.Millisecond)

	// 恢复原设备
	if s.currentDevice != "" {
		restoreCmd := exec.Command("SwitchAudioSource", "-s", s.currentDevice)
		restoreCmd.Run()
		time.Sleep(300 * time.Millisecond)
	}

	if playErr != nil {
		return fmt.Errorf("播放失败: %v", playErr)
	}

	return nil
}

// GetAvailableVoices 获取可用的音色列表
func (s *TTSService) GetAvailableVoices() []map[string]string {
	return []map[string]string{
		{"value": "Cherry", "label": "辛悦 - 阳光积极、亲切自然小姐姐 (女性)"},
		{"value": "Serena", "label": "苏瑶 - 温柔小姐姐 (女性)"},
		{"value": "Ethan", "label": "晨熙 - 标准普通话，阳光温暖活力朝气 (男性)"},
		{"value": "Chelsie", "label": "千雪 - 二次元虚拟女友 (女性)"},
		{"value": "Momo", "label": "茉兔 - 撒娇搞怪逗你开心 (女性)"},
		{"value": "Vivian", "label": "十三 - 捧场的、可爱的小暴躁 (女性)"},
		{"value": "Bella", "label": "萌宝 - 喝酒不打醉拳的小萝莉 (女性)"},
	}
}
