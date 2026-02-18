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

	"github.com/joho/godotenv"
)

// TTSServiceV2 跨平台 TTS 服务（重构版）
type TTSServiceV2 struct {
	apiKey   string
	model    string
	endpoint string
	platform AudioPlatform
	mu       sync.Mutex
}

// NewTTSServiceV2 创建跨平台 TTS 服务
func NewTTSServiceV2() (*TTSServiceV2, error) {
	// 智能加载环境变量（多路径尝试）
	var err error
	envPaths := []string{
		".env",    // 当前目录
		"../.env", // 上级目录
		filepath.Join(os.Getenv("HOME"), ".xi_virtual_voice.env"),        // 用户主目录
		filepath.Join(os.Getenv("USERPROFILE"), ".xi_virtual_voice.env"), // Windows 用户目录
	}

	envLoaded := false
	for _, envPath := range envPaths {
		if envPath == "" {
			continue
		}
		if err = godotenv.Load(envPath); err == nil {
			fmt.Printf("✅ 已加载配置文件: %s\n", envPath)
			envLoaded = true
			break
		}
	}

	if !envLoaded {
		// 尝试从系统环境变量读取
		if os.Getenv("DASHSCOPE_API_KEY") == "" {
			return nil, fmt.Errorf("未找到配置文件且未设置环境变量 DASHSCOPE_API_KEY\n请创建 .env 文件或设置系统环境变量")
		}
		fmt.Printf("⚠️  未找到 .env 文件，使用系统环境变量\n")
	}

	// 验证必需的环境变量
	apiKey := os.Getenv("DASHSCOPE_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("缺少必需的环境变量: DASHSCOPE_API_KEY")
	}

	// 创建平台实例
	platform, err := NewAudioPlatform()
	if err != nil {
		return nil, fmt.Errorf("初始化音频平台失败: %v", err)
	}

	fmt.Printf("✅ 已初始化平台: %s\n", platform.GetPlatformName())

	// 设置默认值
	model := os.Getenv("QWEN_VOICE_MODEL")
	if model == "" {
		model = "qwen-audio-turbo"
	}

	endpoint := os.Getenv("DASHSCOPE_ENDPOINT")
	if endpoint == "" {
		endpoint = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2speech/speech-synthesis"
	}

	return &TTSServiceV2{
		apiKey:   apiKey,
		model:    model,
		endpoint: endpoint,
		platform: platform,
	}, nil
}

// GetAudioDevices 获取所有音频输出设备
func (s *TTSServiceV2) GetAudioDevices() ([]AudioDevice, error) {
	return s.platform.GetAudioDevices()
}

// GenerateAndPlaySpeech 生成语音并播放到指定设备
func (s *TTSServiceV2) GenerateAndPlaySpeech(text, voice, device, language string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	fmt.Printf("🎤 开始生成语音...\n")
	fmt.Printf("   文本: %s\n", text)
	fmt.Printf("   音色: %s\n", voice)
	fmt.Printf("   语言: %s\n", language)
	fmt.Printf("   设备: %s\n", device)
	fmt.Printf("   平台: %s\n", s.platform.GetPlatformName())

	// 1. 生成语音
	audioFile, err := s.generateSpeech(text, voice, language)
	if err != nil {
		return err
	}
	defer os.Remove(audioFile)
	fmt.Printf("✅ 语音生成完成: %s\n", audioFile)

	// 2. 转换音频格式并清理噪音
	convertedFile, err := s.convertAudioFormat(audioFile)
	if err == nil && convertedFile != audioFile {
		defer os.Remove(convertedFile)
		audioFile = convertedFile
		fmt.Printf("✅ 音频清理完成: %s\n", audioFile)
	} else if err != nil {
		fmt.Printf("⚠️  音频清理失败，使用原文件: %v\n", err)
	}

	// 3. 播放到指定设备
	fmt.Printf("🔊 播放到设备: %s\n", device)
	err = s.platform.PlayToDevice(audioFile, device)
	if err != nil {
		return fmt.Errorf("播放失败: %v", err)
	}

	fmt.Printf("✅ 播放完成\n")
	return nil
}

// TTSAPIResponse 阿里云 TTS API 响应结构
type TTSAPIResponse struct {
	Output struct {
		Audio struct {
			Data      string `json:"data"`
			ExpiresAt int64  `json:"expires_at"`
			ID        string `json:"id"`
			URL       string `json:"url"`
		} `json:"audio"`
		FinishReason string `json:"finish_reason"`
	} `json:"output"`
	Usage struct {
		Characters int `json:"characters"`
	} `json:"usage"`
	RequestID string `json:"request_id"`
}

// generateSpeech 调用 TTS API 生成语音
func (s *TTSServiceV2) generateSpeech(text, voice, language string) (string, error) {
	// 如果没有指定语言，使用自动检测
	if language == "" {
		language = "Auto"
	}

	// 构造请求
	reqBody := map[string]interface{}{
		"model": s.model,
		"input": map[string]interface{}{
			"text":          text,
			"voice":         voice,
			"language_type": language,
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
		return "", fmt.Errorf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("API 错误 (状态码 %d): %s", resp.StatusCode, string(body))
	}

	// 读取响应体
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("读取响应失败: %v", err)
	}

	// 解析 JSON 响应
	var apiResp TTSAPIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		// 如果不是 JSON，可能是直接的音频流（旧版API）
		return s.saveAudioFromBytes(body)
	}

	// 检查是否有错误
	if apiResp.Output.FinishReason != "stop" {
		return "", fmt.Errorf("API 返回异常: %s", apiResp.Output.FinishReason)
	}

	// 获取音频 URL
	audioURL := apiResp.Output.Audio.URL
	if audioURL == "" {
		return "", fmt.Errorf("API 响应中未包含音频 URL")
	}

	fmt.Printf("📥 从 URL 下载音频: %s\n", audioURL)

	// 下载音频文件
	return s.downloadAudio(audioURL)
}

// saveAudioFromBytes 从字节数据保存音频（用于旧版直接返回音频流的API）
func (s *TTSServiceV2) saveAudioFromBytes(data []byte) (string, error) {
	tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("tts_output_%d.wav", os.Getpid()))

	err := os.WriteFile(tmpFile, data, 0644)
	if err != nil {
		return "", fmt.Errorf("保存音频失败: %v", err)
	}

	return tmpFile, nil
}

// downloadAudio 从 URL 下载音频文件
func (s *TTSServiceV2) downloadAudio(url string) (string, error) {
	// 下载音频
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("下载音频失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("下载失败，状态码: %d", resp.StatusCode)
	}

	// 创建临时文件
	tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("tts_output_%d.wav", os.Getpid()))
	outFile, err := os.Create(tmpFile)
	if err != nil {
		return "", fmt.Errorf("创建临时文件失败: %v", err)
	}
	defer outFile.Close()

	// 保存音频
	_, err = io.Copy(outFile, resp.Body)
	if err != nil {
		return "", fmt.Errorf("保存音频失败: %v", err)
	}

	fmt.Printf("✅ 音频已下载到: %s\n", tmpFile)
	return tmpFile, nil
}

// convertAudioFormat 转换音频格式并清理音频（跨平台）
func (s *TTSServiceV2) convertAudioFormat(inputFile string) (string, error) {
	outputFile := strings.TrimSuffix(inputFile, ".wav") + "_clean.wav"

	// 使用跨平台的 ffmpeg 命令
	cmd, args, err := GetAudioConverterCommand(inputFile, outputFile)
	if err != nil {
		return inputFile, err
	}

	execCmd := exec.Command(cmd, args...)
	var stderr bytes.Buffer
	execCmd.Stderr = &stderr

	if err := execCmd.Run(); err != nil {
		fmt.Printf("⚠️  音频处理失败: %v, 输出: %s\n", err, stderr.String())
		return inputFile, nil
	}

	return outputFile, nil
}

// GetAvailableVoices 获取可用的音色列表
func (s *TTSServiceV2) GetAvailableVoices() []map[string]string {
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

// GetAvailableLanguages 获取支持的语言列表
func (s *TTSServiceV2) GetAvailableLanguages() []map[string]string {
	return []map[string]string{
		{"value": "Auto", "label": "自动检测"},
		{"value": "Chinese", "label": "中文"},
		{"value": "English", "label": "英语"},
		{"value": "Japanese", "label": "日语"},
		{"value": "Korean", "label": "韩语"},
		{"value": "French", "label": "法语"},
		{"value": "German", "label": "德语"},
		{"value": "Spanish", "label": "西班牙语"},
		{"value": "Italian", "label": "意大利语"},
		{"value": "Portuguese", "label": "葡萄牙语"},
		{"value": "Russian", "label": "俄语"},
	}
}
