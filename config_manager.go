package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// TTSConfig TTS 配置结构
type TTSConfig struct {
	Voice         string `json:"voice"`           // 当前选择的音色
	Language      string `json:"language"`        // 当前选择的语言
	MicDevice     string `json:"mic_device"`      // 虚拟麦克风设备
	SpeakerDevice string `json:"speaker_device"`  // 扬声器设备
	PlayToSpeaker bool   `json:"play_to_speaker"` // 是否播放到扬声器
}

// ConfigManager 配置管理器
type ConfigManager struct {
	configPath string
	config     *TTSConfig
	mu         sync.RWMutex
}

// NewConfigManager 创建配置管理器
func NewConfigManager() (*ConfigManager, error) {
	// 获取配置文件路径（在应用数据目录）
	configDir, err := os.UserConfigDir()
	if err != nil {
		configDir = "."
	}

	appConfigDir := filepath.Join(configDir, "xi_virtual_voice")
	if err := os.MkdirAll(appConfigDir, 0755); err != nil {
		return nil, fmt.Errorf("创建配置目录失败: %v", err)
	}

	configPath := filepath.Join(appConfigDir, "tts_config.json")

	cm := &ConfigManager{
		configPath: configPath,
		config:     &TTSConfig{},
	}

	// 尝试加载现有配置
	if err := cm.Load(); err != nil {
		// 如果加载失败，使用默认配置
		cm.config = &TTSConfig{
			Voice:         "Cherry",
			Language:      "Auto",
			MicDevice:     "",
			SpeakerDevice: "",
			PlayToSpeaker: false,
		}
		fmt.Printf("📝 使用默认配置\n")
	} else {
		fmt.Printf("✅ 已加载配置: %s\n", configPath)
	}

	return cm, nil
}

// Load 从文件加载配置
func (cm *ConfigManager) Load() error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	data, err := os.ReadFile(cm.configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("配置文件不存在")
		}
		return fmt.Errorf("读取配置文件失败: %v", err)
	}

	if err := json.Unmarshal(data, cm.config); err != nil {
		return fmt.Errorf("解析配置文件失败: %v", err)
	}

	return nil
}

// Save 保存配置到文件
func (cm *ConfigManager) Save() error {
	cm.mu.RLock()
	defer cm.mu.RUnlock()

	data, err := json.MarshalIndent(cm.config, "", "  ")
	if err != nil {
		return fmt.Errorf("序列化配置失败: %v", err)
	}

	if err := os.WriteFile(cm.configPath, data, 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}

	fmt.Printf("💾 配置已保存: %s\n", cm.configPath)
	return nil
}

// GetConfig 获取当前配置（副本）
func (cm *ConfigManager) GetConfig() TTSConfig {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return *cm.config
}

// UpdateConfig 更新配置并保存
func (cm *ConfigManager) UpdateConfig(config TTSConfig) error {
	cm.mu.Lock()
	cm.config = &config
	cm.mu.Unlock()

	return cm.Save()
}

// UpdateField 更新单个字段
func (cm *ConfigManager) UpdateField(field string, value interface{}) error {
	cm.mu.Lock()
	defer cm.mu.Unlock()

	switch field {
	case "voice":
		if v, ok := value.(string); ok {
			cm.config.Voice = v
		}
	case "language":
		if v, ok := value.(string); ok {
			cm.config.Language = v
		}
	case "mic_device":
		if v, ok := value.(string); ok {
			cm.config.MicDevice = v
		}
	case "speaker_device":
		if v, ok := value.(string); ok {
			cm.config.SpeakerDevice = v
		}
	case "play_to_speaker":
		if v, ok := value.(bool); ok {
			cm.config.PlayToSpeaker = v
		}
	default:
		return fmt.Errorf("未知的配置字段: %s", field)
	}

	return cm.Save()
}
