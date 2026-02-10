//go:build darwin
// +build darwin

package main

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// MacOSPlatform macOS 平台实现
type MacOSPlatform struct {
	originalDevice string
}

// NewMacOSPlatform 创建 macOS 平台实例
func NewMacOSPlatform() (*MacOSPlatform, error) {
	platform := &MacOSPlatform{}

	// 检查依赖
	if err := platform.CheckDependencies(); err != nil {
		return nil, err
	}

	// 保存当前设备
	currentDevice, err := platform.GetCurrentDevice()
	if err == nil {
		platform.originalDevice = currentDevice
	}

	return platform, nil
}

// newPlatformImpl 创建平台实例（供 audio_platform.go 调用）
func newPlatformImpl() (AudioPlatform, error) {
	return NewMacOSPlatform()
} // GetPlatformName 获取平台名称
func (p *MacOSPlatform) GetPlatformName() string {
	return "macOS"
}

// CheckDependencies 检查必要的工具
func (p *MacOSPlatform) CheckDependencies() error {
	// 检查 SwitchAudioSource
	cmd := exec.Command("which", "SwitchAudioSource")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("SwitchAudioSource 未安装\n安装命令: brew install switchaudio-osx")
	}

	// 检查 ffmpeg
	cmd = exec.Command("which", "ffmpeg")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg 未安装\n安装命令: brew install ffmpeg")
	}

	// 检查 afplay（系统自带）
	cmd = exec.Command("which", "afplay")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("afplay 未找到（应该是系统自带的）")
	}

	return nil
}

// GetAudioDevices 获取所有音频输出设备
func (p *MacOSPlatform) GetAudioDevices() ([]AudioDevice, error) {
	// 获取所有输出设备
	cmd := exec.Command("SwitchAudioSource", "-a", "-t", "output")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("获取音频设备失败: %v", err)
	}

	// 获取当前设备
	currentDevice, _ := p.GetCurrentDevice()

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

// GetCurrentDevice 获取当前默认输出设备
func (p *MacOSPlatform) GetCurrentDevice() (string, error) {
	cmd := exec.Command("SwitchAudioSource", "-c", "-t", "output")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("获取当前设备失败: %v", err)
	}
	return strings.TrimSpace(string(output)), nil
}

// SwitchDevice 切换到指定设备
func (p *MacOSPlatform) SwitchDevice(device string) error {
	cmd := exec.Command("SwitchAudioSource", "-s", device, "-t", "output")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("切换设备失败: %v", err)
	}

	// 等待设备切换完成（减少延迟）
	time.Sleep(200 * time.Millisecond)
	return nil
}

// RestoreDevice 恢复到原始设备
func (p *MacOSPlatform) RestoreDevice(originalDevice string) error {
	if originalDevice == "" {
		originalDevice = p.originalDevice
	}

	if originalDevice == "" {
		return nil // 没有保存的原始设备，跳过
	}

	cmd := exec.Command("SwitchAudioSource", "-s", originalDevice, "-t", "output")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("恢复设备失败: %v", err)
	}

	// 减少切换延迟，快速恢复
	time.Sleep(100 * time.Millisecond)
	return nil
}

// PlayToDevice 播放音频到指定设备
func (p *MacOSPlatform) PlayToDevice(audioFile, device string) error {
	if device == "" {
		// 如果未指定设备，使用 afplay 播放到当前默认设备
		cmd := exec.Command("afplay", "-q", "1", audioFile)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("播放音频失败: %v", err)
		}
		return nil
	}

	// 对于指定设备，快速切换播放再立即切回
	fmt.Printf("🎙️ 播放到设备: %s（将快速切换设备）\n", device)
	return p.playBySwitch(audioFile, device)
}

// playBySwitch 通过快速切换系统音频设备来播放
func (p *MacOSPlatform) playBySwitch(audioFile, device string) error {
	currentDevice, err := p.GetCurrentDevice()
	if err != nil {
		return fmt.Errorf("获取当前设备失败: %v", err)
	}

	if device != currentDevice {
		// 切换到目标设备
		if err := p.SwitchDevice(device); err != nil {
			return err
		}

		// 使用 afplay 播放（afplay 会阻塞直到播放完成）
		cmd := exec.Command("afplay", "-q", "1", audioFile)
		playErr := cmd.Run()

		// 立即切换回原设备（即使播放失败也要切回）
		restoreErr := p.RestoreDevice(currentDevice)

		if playErr != nil {
			return fmt.Errorf("播放音频失败: %v", playErr)
		}

		if restoreErr != nil {
			fmt.Printf("⚠️  恢复设备失败: %v（但音频已播放）\n", restoreErr)
		}

		return nil
	}

	// 如果是当前设备，直接播放
	cmd := exec.Command("afplay", "-q", "1", audioFile)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("播放音频失败: %v", err)
	}

	return nil
}

// PlayToSpeaker 播放音频到系统默认扬声器（不切换设备）
func (p *MacOSPlatform) PlayToSpeaker(audioFile string) error {
	fmt.Printf("🔊 使用 afplay 直接播放到默认扬声器\n")

	// 使用 afplay 播放（高质量模式）
	cmd := exec.Command("afplay", "-q", "1", audioFile)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("播放音频失败: %v", err)
	}

	return nil
}
