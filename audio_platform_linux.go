//go:build linux
// +build linux

package main

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// LinuxPlatform Linux 平台实现（使用 PulseAudio/PipeWire）
type LinuxPlatform struct {
	originalDevice string
	usePipeWire    bool
}

// NewLinuxPlatform 创建 Linux 平台实例
func NewLinuxPlatform() (*LinuxPlatform, error) {
	platform := &LinuxPlatform{}

	// 检测使用 PulseAudio 还是 PipeWire
	cmd := exec.Command("which", "pw-cli")
	platform.usePipeWire = cmd.Run() == nil

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
	return NewLinuxPlatform()
} // GetPlatformName 获取平台名称
func (p *LinuxPlatform) GetPlatformName() string {
	if p.usePipeWire {
		return "Linux (PipeWire)"
	}
	return "Linux (PulseAudio)"
}

// CheckDependencies 检查必要的工具
func (p *LinuxPlatform) CheckDependencies() error {
	// 检查 ffmpeg
	cmd := exec.Command("which", "ffmpeg")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg 未安装\n安装命令: sudo apt install ffmpeg")
	}

	if p.usePipeWire {
		// 检查 PipeWire 工具
		cmd = exec.Command("which", "pw-cli")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("PipeWire 工具未安装\n安装命令: sudo apt install pipewire pipewire-pulse")
		}
	} else {
		// 检查 PulseAudio 工具
		cmd = exec.Command("which", "pactl")
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("PulseAudio 未安装\n安装命令: sudo apt install pulseaudio pulseaudio-utils")
		}
	}

	return nil
}

// GetAudioDevices 获取所有音频输出设备
func (p *LinuxPlatform) GetAudioDevices() ([]AudioDevice, error) {
	devices := make([]AudioDevice, 0)

	var cmd *exec.Cmd
	if p.usePipeWire {
		cmd = exec.Command("pw-cli", "list-objects", "Node")
	} else {
		cmd = exec.Command("pactl", "list", "short", "sinks")
	}

	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("获取音频设备失败: %v", err)
	}

	// 获取当前设备
	currentDevice, _ := p.GetCurrentDevice()

	// 解析设备列表
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		var deviceName string
		if p.usePipeWire {
			// 解析 PipeWire 输出
			if strings.Contains(line, "node.name") {
				parts := strings.Split(line, "\"")
				if len(parts) >= 2 {
					deviceName = parts[1]
				}
			}
		} else {
			// 解析 PulseAudio 输出
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				deviceName = parts[1]
			}
		}

		if deviceName != "" {
			devices = append(devices, AudioDevice{
				Name:      deviceName,
				IsDefault: deviceName == currentDevice,
			})
		}
	}

	return devices, nil
}

// GetCurrentDevice 获取当前默认输出设备
func (p *LinuxPlatform) GetCurrentDevice() (string, error) {
	var cmd *exec.Cmd

	if p.usePipeWire {
		cmd = exec.Command("pw-cli", "get-default-sink")
	} else {
		cmd = exec.Command("pactl", "get-default-sink")
	}

	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("获取当前设备失败: %v", err)
	}

	return strings.TrimSpace(string(output)), nil
}

// SwitchDevice 切换到指定设备
func (p *LinuxPlatform) SwitchDevice(device string) error {
	var cmd *exec.Cmd

	if p.usePipeWire {
		cmd = exec.Command("pw-cli", "set-default-sink", device)
	} else {
		cmd = exec.Command("pactl", "set-default-sink", device)
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("切换设备失败: %v", err)
	}

	time.Sleep(500 * time.Millisecond)
	return nil
}

// RestoreDevice 恢复到原始设备
func (p *LinuxPlatform) RestoreDevice(originalDevice string) error {
	if originalDevice == "" {
		originalDevice = p.originalDevice
	}

	if originalDevice == "" {
		return nil
	}

	var cmd *exec.Cmd

	if p.usePipeWire {
		cmd = exec.Command("pw-cli", "set-default-sink", originalDevice)
	} else {
		cmd = exec.Command("pactl", "set-default-sink", originalDevice)
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("恢复设备失败: %v", err)
	}

	time.Sleep(300 * time.Millisecond)
	return nil
}

// PlayToDevice 播放音频到指定设备
func (p *LinuxPlatform) PlayToDevice(audioFile, device string) error {
	// 保存当前设备
	originalDevice, err := p.GetCurrentDevice()
	if err != nil {
		return fmt.Errorf("获取当前设备失败: %v", err)
	}

	// 切换到目标设备
	if device != "" && device != originalDevice {
		if err := p.SwitchDevice(device); err != nil {
			return err
		}

		defer p.RestoreDevice(originalDevice)
	}

	// 使用 ffplay 播放
	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
	if err := cmd.Run(); err != nil {
		// 尝试使用 paplay（PulseAudio）
		cmd = exec.Command("paplay", audioFile)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("播放音频失败: %v", err)
		}
	}

	time.Sleep(300 * time.Millisecond)
	return nil
}

// PlayToSpeaker 播放音频到系统默认扬声器（不切换设备）
func (p *LinuxPlatform) PlayToSpeaker(audioFile string) error {
	fmt.Printf("🔊 使用 ffplay 直接播放到默认扬声器\n")

	// 使用 ffplay 播放
	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
	if err := cmd.Run(); err != nil {
		// 尝试使用 paplay（PulseAudio）
		cmd = exec.Command("paplay", audioFile)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("播放音频失败: %v", err)
		}
	}

	return nil
}
