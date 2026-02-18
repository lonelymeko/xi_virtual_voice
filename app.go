package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"strings"
)

// App struct
type App struct {
	ctx           context.Context
	ttsService    *TTSService    // 旧版服务（macOS only）
	ttsServiceV2  *TTSServiceV2  // 新版跨平台服务
	wsServer      *WSServer      // WebSocket 服务器
	httpServer    *HTTPServer    // HTTP API 服务器
	configManager *ConfigManager // 配置管理器
	useLegacy     bool           // 是否使用旧版服务
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{
		useLegacy: false, // 默认使用新版跨平台服务
	}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	fmt.Printf("🚀 启动应用...\n")
	fmt.Printf("   操作系统: %s\n", runtime.GOOS)
	fmt.Printf("   架构: %s\n", runtime.GOARCH)

	// 初始化配置管理器
	configManager, err := NewConfigManager()
	if err != nil {
		fmt.Printf("⚠️  配置管理器初始化失败: %v\n", err)
	} else {
		a.configManager = configManager
		fmt.Printf("✅ 配置管理器已初始化\n")
	}

	// 尝试初始化新版跨平台服务
	ttsServiceV2, err := NewTTSServiceV2()
	if err != nil {
		fmt.Printf("⚠️  新版服务初始化失败: %v\n", err)

		// 回退到旧版服务（仅限 macOS）
		if runtime.GOOS == "darwin" {
			fmt.Printf("   尝试使用旧版服务（仅 macOS）...\n")
			ttsService, legacyErr := NewTTSService()
			if legacyErr != nil {
				fmt.Printf("❌ 旧版服务也初始化失败: %v\n", legacyErr)
			} else {
				a.ttsService = ttsService
				a.useLegacy = true
				fmt.Printf("✅ 使用旧版服务\n")
			}
		}
	} else {
		a.ttsServiceV2 = ttsServiceV2
		a.useLegacy = false
		fmt.Printf("✅ 使用新版跨平台服务\n")

		// 从配置文件加载默认配置
		var defaultConfig *WSConfig
		if a.configManager != nil {
			savedConfig := a.configManager.GetConfig()
			defaultConfig = &WSConfig{
				Voice:         savedConfig.Voice,
				Language:      savedConfig.Language,
				MicDevice:     savedConfig.MicDevice,
				SpeakerDevice: savedConfig.SpeakerDevice,
				PlayToSpeaker: savedConfig.PlayToSpeaker,
			}
			fmt.Printf("📋 从配置文件加载设置\n")
			fmt.Printf("   音色: %s\n", defaultConfig.Voice)
			fmt.Printf("   语言: %s\n", defaultConfig.Language)
			fmt.Printf("   虚拟麦克风: %s\n", defaultConfig.MicDevice)
			fmt.Printf("   扬声器: %s\n", defaultConfig.SpeakerDevice)
			fmt.Printf("   播放到扬声器: %v\n", defaultConfig.PlayToSpeaker)
		} else {
			// 使用默认配置
			defaultConfig = &WSConfig{
				Voice:         "Cherry",
				Language:      "Auto",
				MicDevice:     "VB-Cable",
				SpeakerDevice: "",
				PlayToSpeaker: false,
			}
		}

		// 初始化 WebSocket 服务器
		a.wsServer = NewWSServer(ttsServiceV2, defaultConfig)

		// 从环境变量读取 WebSocket 配置
		wsHost := os.Getenv("WS_HOST")
		if wsHost == "" {
			wsHost = "localhost"
		}
		wsPort := os.Getenv("WS_PORT")
		if wsPort == "" {
			wsPort = "7878"
		}
		wsPath := os.Getenv("WS_PATH")
		if wsPath == "" {
			wsPath = "/ws"
		}

		// 从环境变量读取 HTTP 配置
		httpPort := os.Getenv("HTTP_PORT")
		if httpPort == "" {
			httpPort = "9091"
		}
		httpPath := os.Getenv("HTTP_PATH")
		if httpPath == "" {
			httpPath = "/api/tts"
		}

		fmt.Printf("✅ 服务器已初始化\n")
		fmt.Printf("   WebSocket - ws://%s:%s%s\n", wsHost, wsPort, wsPath)
		fmt.Printf("   HTTP API  - http://%s:%s%s\n", wsHost, httpPort, httpPath)

		// 启动 WebSocket 服务器
		wsAddr := ":" + wsPort
		go func() {
			fmt.Printf("🌐 正在启动 WebSocket 服务器...\n")
			wsMux := http.NewServeMux()
			wsMux.HandleFunc(wsPath, a.wsServer.HandleWebSocket)
			if err := http.ListenAndServe(wsAddr, wsMux); err != nil {
				fmt.Printf("❌ WebSocket 服务器启动失败: %v\n", err)
			}
		}()
		fmt.Printf("🚀 WebSocket 服务器已在后台启动 (ws://%s:%s%s)\n", wsHost, wsPort, wsPath)

		// 启动 HTTP API 服务器
		a.httpServer = NewHTTPServer(ttsServiceV2, defaultConfig)
		httpAddr := ":" + httpPort
		go func() {
			fmt.Printf("🌐 正在启动 HTTP API 服务器...\n")
			httpMux := http.NewServeMux()
			httpMux.HandleFunc(httpPath, a.httpServer.HandleTTS)
			if err := http.ListenAndServe(httpAddr, httpMux); err != nil {
				fmt.Printf("❌ HTTP API 服务器启动失败: %v\n", err)
			}
		}()
		fmt.Printf("🚀 HTTP API 服务器已在后台启动 (http://%s:%s%s)\n", wsHost, httpPort, httpPath)
	}

	if a.ttsService == nil && a.ttsServiceV2 == nil {
		fmt.Printf("❌ TTS 服务初始化失败！\n")
	}
}

// Greet returns a greeting for the given name
func (a *App) Greet(name string) string {
	platform := runtime.GOOS
	return fmt.Sprintf("Hello %s, It's show time on %s! 🎤", name, platform)
}

// GetPlatformInfo 获取平台信息
func (a *App) GetPlatformInfo() map[string]string {
	info := map[string]string{
		"os":      runtime.GOOS,
		"arch":    runtime.GOARCH,
		"service": "legacy",
	}

	if !a.useLegacy && a.ttsServiceV2 != nil {
		info["service"] = "v2"
		info["platform"] = a.ttsServiceV2.platform.GetPlatformName()
	}

	return info
}

// GetAudioDevices 获取所有音频设备
func (a *App) GetAudioDevices() ([]AudioDevice, error) {
	if a.useLegacy {
		if a.ttsService == nil {
			return nil, fmt.Errorf("TTS 服务未初始化")
		}
		return a.ttsService.GetAudioDevices()
	}

	if a.ttsServiceV2 == nil {
		return nil, fmt.Errorf("TTS 服务未初始化")
	}
	return a.ttsServiceV2.GetAudioDevices()
}

// GetAvailableVoices 获取可用的音色列表
func (a *App) GetAvailableVoices() []map[string]string {
	if a.useLegacy {
		if a.ttsService == nil {
			return []map[string]string{}
		}
		return a.ttsService.GetAvailableVoices()
	}

	if a.ttsServiceV2 == nil {
		return []map[string]string{}
	}
	return a.ttsServiceV2.GetAvailableVoices()
}

// GetAvailableLanguages 获取支持的语言列表
func (a *App) GetAvailableLanguages() []map[string]string {
	if a.ttsServiceV2 == nil {
		return []map[string]string{}
	}
	return a.ttsServiceV2.GetAvailableLanguages()
}

// SpeakToDevice 生成语音并播放到指定设备
func (a *App) SpeakToDevice(text, voice, device string) TTSResponse {
	// 输入验证
	if text == "" {
		return TTSResponse{
			Success: false,
			Error:   "请输入文本内容",
		}
	}

	if device == "" {
		return TTSResponse{
			Success: false,
			Error:   "请选择输出设备",
		}
	}

	// 使用旧版服务
	if a.useLegacy {
		if a.ttsService == nil {
			return TTSResponse{
				Success: false,
				Error:   "TTS 服务未初始化",
			}
		}

		err := a.ttsService.GenerateAndPlaySpeech(text, voice, device)
		if err != nil {
			return TTSResponse{
				Success: false,
				Error:   err.Error(),
			}
		}

		return TTSResponse{
			Success: true,
			Message: "语音生成并播放成功",
		}
	}

	// 使用新版跨平台服务
	if a.ttsServiceV2 == nil {
		return TTSResponse{
			Success: false,
			Error:   "TTS 服务未初始化",
		}
	}

	err := a.ttsServiceV2.GenerateAndPlaySpeech(text, voice, device, "Auto")
	if err != nil {
		return TTSResponse{
			Success: false,
			Error:   fmt.Sprintf("播放失败: %v", err),
		}
	}

	return TTSResponse{
		Success: true,
		Message: fmt.Sprintf("✅ 语音已成功播放到 %s", device),
	}
}

// SpeakWithPreview 生成语音，可选同时播放到扬声器和虚拟麦克风
func (a *App) SpeakWithPreview(text, voice, micDevice, speakerDevice, language string, playToSpeaker bool) TTSResponse {
	// 输入验证
	if text == "" {
		return TTSResponse{
			Success: false,
			Error:   "请输入文本内容",
		}
	}

	if micDevice == "" {
		return TTSResponse{
			Success: false,
			Error:   "请选择虚拟麦克风设备",
		}
	}

	// 使用新版服务（支持更多功能）
	if a.ttsServiceV2 == nil {
		return TTSResponse{
			Success: false,
			Error:   "TTS 服务未初始化",
		}
	}

	fmt.Printf("🎤 开始处理请求...\n")
	fmt.Printf("   语言: %s\n", language)
	fmt.Printf("   虚拟麦克风: %s\n", micDevice)
	fmt.Printf("   同时播放到扬声器: %v\n", playToSpeaker)
	if playToSpeaker && speakerDevice != "" {
		fmt.Printf("   扬声器设备: %s\n", speakerDevice)
	}

	// 1. 生成语音文件
	audioFile, err := a.ttsServiceV2.generateSpeech(text, voice, language)
	if err != nil {
		return TTSResponse{
			Success: false,
			Error:   fmt.Sprintf("生成语音失败: %v", err),
		}
	}
	// 注意：不要在这里删除文件，因为后面还要用
	defer func() {
		// 最后清理所有临时文件
		os.Remove(audioFile)
		os.Remove(strings.Replace(audioFile, ".wav", "_clean.wav", 1))
	}()

	fmt.Printf("✅ 语音生成完成: %s\n", audioFile)

	// 2. 音频清理
	cleanFile, err := a.ttsServiceV2.convertAudioFormat(audioFile)
	if err == nil && cleanFile != audioFile {
		audioFile = cleanFile
		fmt.Printf("✅ 音频清理完成: %s\n", audioFile)
	}

	// 3. 播放音频
	var speakerErr, micErr error

	if playToSpeaker {
		// 方案A: 先播放到扬声器预览，再发送到虚拟麦克风
		fmt.Printf("🔊 开始播放到扬声器（预览）\n")
		speakerErr = a.ttsServiceV2.platform.PlayToSpeaker(audioFile)
		if speakerErr != nil {
			fmt.Printf("⚠️  扬声器播放失败: %v\n", speakerErr)
		} else {
			fmt.Printf("✅ 扬声器播放完成\n")
		}
	}

	// 播放到虚拟麦克风
	fmt.Printf("🎙️ 开始播放到虚拟麦克风: %s\n", micDevice)
	micErr = a.ttsServiceV2.platform.PlayToDevice(audioFile, micDevice)
	if micErr != nil {
		fmt.Printf("⚠️  虚拟麦克风播放失败: %v\n", micErr)
	} else {
		fmt.Printf("✅ 虚拟麦克风播放完成\n")
	}

	// 检查错误
	if micErr != nil {
		return TTSResponse{
			Success: false,
			Error:   fmt.Sprintf("虚拟麦克风播放失败: %v", micErr),
		}
	}

	// 构造成功消息
	var message string
	if playToSpeaker {
		if speakerErr != nil {
			message = fmt.Sprintf("✅ 已播放到虚拟麦克风 %s（扬声器播放失败: %v）", micDevice, speakerErr)
		} else {
			message = fmt.Sprintf("✅ 已同时播放到扬声器和虚拟麦克风 %s", micDevice)
		}
	} else {
		message = fmt.Sprintf("✅ 已播放到虚拟麦克风 %s", micDevice)
	}

	return TTSResponse{
		Success: true,
		Message: message,
	}
}

// WindowSetAlwaysOnTop 设置窗口是否置顶
func (a *App) WindowSetAlwaysOnTop(alwaysOnTop bool) error {
	// Wails 运行时会自动处理窗口置顶
	// 这个方法主要是为了前端调用
	fmt.Printf("🪟 窗口置顶状态: %v\n", alwaysOnTop)
	return nil
}

// StartWebSocketServer 启动 WebSocket 服务器（已废弃，服务器会自动启动）
func (a *App) StartWebSocketServer(port string) TTSResponse {
	if a.wsServer == nil {
		return TTSResponse{
			Success: false,
			Error:   "WebSocket 服务器未初始化",
		}
	}

	return TTSResponse{
		Success: true,
		Message: "WebSocket 服务器已在启动时自动运行 (端口: 7878)",
	}
}

// UpdateWSConfig 更新 WebSocket 和 HTTP API 配置
func (a *App) UpdateWSConfig(voice, language, micDevice, speakerDevice string, playToSpeaker bool) TTSResponse {
	if a.wsServer == nil && a.httpServer == nil {
		return TTSResponse{
			Success: false,
			Error:   "服务器未初始化",
		}
	}

	config := &WSConfig{
		Voice:         voice,
		Language:      language,
		MicDevice:     micDevice,
		SpeakerDevice: speakerDevice,
		PlayToSpeaker: playToSpeaker,
	}

	// 更新 WebSocket 服务器配置
	if a.wsServer != nil {
		a.wsServer.UpdateConfig(config)
	}

	// 更新 HTTP API 服务器配置
	if a.httpServer != nil {
		a.httpServer.UpdateConfig(config)
	}

	// 同时保存到配置文件
	if a.configManager != nil {
		ttsConfig := TTSConfig{
			Voice:         voice,
			Language:      language,
			MicDevice:     micDevice,
			SpeakerDevice: speakerDevice,
			PlayToSpeaker: playToSpeaker,
		}
		if err := a.configManager.UpdateConfig(ttsConfig); err != nil {
			fmt.Printf("⚠️  保存配置失败: %v\n", err)
		}
	}

	return TTSResponse{
		Success: true,
		Message: "配置已更新并保存(WebSocket + HTTP API)",
	}
}

// GetWSConfig 获取 WebSocket 当前配置
func (a *App) GetWSConfig() *WSConfig {
	if a.wsServer == nil {
		return &WSConfig{}
	}
	return a.wsServer.GetConfig()
}

// SaveConfig 保存当前配置（供前端调用）
func (a *App) SaveConfig(voice, language, micDevice, speakerDevice string, playToSpeaker bool) TTSResponse {
	if a.configManager == nil {
		return TTSResponse{
			Success: false,
			Error:   "配置管理器未初始化",
		}
	}

	config := TTSConfig{
		Voice:         voice,
		Language:      language,
		MicDevice:     micDevice,
		SpeakerDevice: speakerDevice,
		PlayToSpeaker: playToSpeaker,
	}

	if err := a.configManager.UpdateConfig(config); err != nil {
		return TTSResponse{
			Success: false,
			Error:   fmt.Sprintf("保存配置失败: %v", err),
		}
	}

	// 同步更新 WebSocket 配置
	if a.wsServer != nil {
		wsConfig := &WSConfig{
			Voice:         voice,
			Language:      language,
			MicDevice:     micDevice,
			SpeakerDevice: speakerDevice,
			PlayToSpeaker: playToSpeaker,
		}
		a.wsServer.UpdateConfig(wsConfig)
	}

	return TTSResponse{
		Success: true,
		Message: "配置已保存",
	}
}

// LoadConfig 加载保存的配置（供前端调用）
func (a *App) LoadConfig() map[string]interface{} {
	if a.configManager == nil {
		return map[string]interface{}{
			"voice":           "Cherry",
			"language":        "Auto",
			"mic_device":      "",
			"speaker_device":  "",
			"play_to_speaker": false,
		}
	}

	config := a.configManager.GetConfig()
	return map[string]interface{}{
		"voice":           config.Voice,
		"language":        config.Language,
		"mic_device":      config.MicDevice,
		"speaker_device":  config.SpeakerDevice,
		"play_to_speaker": config.PlayToSpeaker,
	}
}
