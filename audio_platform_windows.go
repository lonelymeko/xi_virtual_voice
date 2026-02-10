//go:build windows
// +build windows

package main

import (
	"fmt"
	"os/exec"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

var (
	winmm                  = syscall.NewLazyDLL("winmm.dll")
	procWaveOutGetNumDevs  = winmm.NewProc("waveOutGetNumDevs")
	procWaveOutGetDevCapsW = winmm.NewProc("waveOutGetDevCapsW")
)

// WAVEOUTCAPS Windows 音频设备信息结构
type WAVEOUTCAPS struct {
	WMid           uint16
	WPid           uint16
	VDriverVersion uint32
	SzPname        [32]uint16
	DwFormats      uint32
	WChannels      uint16
	WReserved1     uint16
	DwSupport      uint32
}

// WindowsPlatform Windows 平台实现
type WindowsPlatform struct {
	originalDevice string
}

// NewWindowsPlatform 创建 Windows 平台实例
func NewWindowsPlatform() (*WindowsPlatform, error) {
	platform := &WindowsPlatform{}

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
	return NewWindowsPlatform()
} // GetPlatformName 获取平台名称
func (p *WindowsPlatform) GetPlatformName() string {
	return "Windows"
}

// CheckDependencies 检查必要的工具
func (p *WindowsPlatform) CheckDependencies() error {
	// 检查 ffmpeg
	cmd := exec.Command("where", "ffmpeg")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg 未安装\n下载地址: https://www.gyan.dev/ffmpeg/builds/\n或使用 Chocolatey: choco install ffmpeg")
	}

	// 检查 NirCmd（用于设备切换）
	cmd = exec.Command("where", "nircmd")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("NirCmd 未安装\n下载地址: https://www.nirsoft.net/utils/nircmd.html\n请将 nircmd.exe 添加到 PATH")
	}

	return nil
}

// GetAudioDevices 获取所有音频输出设备（使用 Windows API）
func (p *WindowsPlatform) GetAudioDevices() ([]AudioDevice, error) {
	devices := make([]AudioDevice, 0)

	// 方法1: 使用 NirCmd 获取设备列表
	cmd := exec.Command("nircmd", "win", "dlg", "", "~Audio Devices")
	output, err := cmd.CombinedOutput()

	if err != nil {
		// 方法2: 使用 PowerShell 获取设备
		psCmd := `Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback"} | Select-Object -ExpandProperty Name`
		cmd = exec.Command("powershell", "-Command", psCmd)
		output, err = cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("获取音频设备失败: %v", err)
		}
	}

	// 获取当前默认设备
	currentDevice, _ := p.GetCurrentDevice()

	// 解析设备列表
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" && !strings.HasPrefix(line, "#") {
			devices = append(devices, AudioDevice{
				Name:      line,
				IsDefault: line == currentDevice,
			})
		}
	}

	// 如果上述方法失败，使用 Windows API
	if len(devices) == 0 {
		devices, err = p.getDevicesViaAPI()
		if err != nil {
			return nil, err
		}
	}

	return devices, nil
}

// getDevicesViaAPI 使用 Windows API 获取设备
func (p *WindowsPlatform) getDevicesViaAPI() ([]AudioDevice, error) {
	devices := make([]AudioDevice, 0)

	// 获取设备数量
	numDevs, _, _ := procWaveOutGetNumDevs.Call()

	for i := uintptr(0); i < numDevs; i++ {
		var caps WAVEOUTCAPS
		ret, _, _ := procWaveOutGetDevCapsW.Call(
			i,
			uintptr(unsafe.Pointer(&caps)),
			unsafe.Sizeof(caps),
		)

		if ret == 0 { // MMSYSERR_NOERROR
			deviceName := syscall.UTF16ToString(caps.SzPname[:])
			devices = append(devices, AudioDevice{
				Name:      deviceName,
				IsDefault: i == 0, // 第一个通常是默认设备
			})
		}
	}

	return devices, nil
}

// GetCurrentDevice 获取当前默认输出设备
func (p *WindowsPlatform) GetCurrentDevice() (string, error) {
	// 使用 PowerShell 获取当前设备
	psCmd := `(Get-AudioDevice -Playback).Name`
	cmd := exec.Command("powershell", "-Command", psCmd)
	output, err := cmd.Output()
	if err != nil {
		// 尝试使用 NirCmd
		cmd = exec.Command("nircmd", "getdefaultsounddevice", "output")
		output, err = cmd.Output()
		if err != nil {
			return "", fmt.Errorf("获取当前设备失败: %v", err)
		}
	}

	return strings.TrimSpace(string(output)), nil
}

// SwitchDevice 切换到指定设备
func (p *WindowsPlatform) SwitchDevice(device string) error {
	// 方法1: 使用 NirCmd（推荐）
	cmd := exec.Command("nircmd", "setdefaultsounddevice", device)
	err := cmd.Run()

	if err != nil {
		// 方法2: 使用 PowerShell 和 AudioDeviceCmdlets
		psCmd := fmt.Sprintf(`Set-AudioDevice -Name "%s"`, device)
		cmd = exec.Command("powershell", "-Command", psCmd)
		err = cmd.Run()

		if err != nil {
			return fmt.Errorf("切换设备失败: %v\n提示: 请安装 AudioDeviceCmdlets 模块\nInstall-Module -Name AudioDeviceCmdlets", err)
		}
	}

	// 等待设备切换完成
	time.Sleep(800 * time.Millisecond)
	return nil
}

// RestoreDevice 恢复到原始设备
func (p *WindowsPlatform) RestoreDevice(originalDevice string) error {
	if originalDevice == "" {
		originalDevice = p.originalDevice
	}

	if originalDevice == "" {
		return nil
	}

	cmd := exec.Command("nircmd", "setdefaultsounddevice", originalDevice)
	err := cmd.Run()

	if err != nil {
		psCmd := fmt.Sprintf(`Set-AudioDevice -Name "%s"`, originalDevice)
		cmd = exec.Command("powershell", "-Command", psCmd)
		err = cmd.Run()
	}

	time.Sleep(500 * time.Millisecond)
	return err
}

// PlayToDevice 播放音频到指定设备
func (p *WindowsPlatform) PlayToDevice(audioFile, device string) error {
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

		// 确保在函数结束时恢复原设备
		defer p.RestoreDevice(originalDevice)
	}

	// 使用 ffplay 播放（安静模式）
	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
	if err := cmd.Run(); err != nil {
		// 如果 ffplay 不可用，尝试使用 NirCmd
		cmd = exec.Command("nircmd", "mediaplay", "3000", audioFile)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("播放音频失败: %v", err)
		}
	}

	// 等待播放完成
	time.Sleep(500 * time.Millisecond)

	return nil
}

// PlayToSpeaker 播放音频到系统默认扬声器（不切换设备）
func (p *WindowsPlatform) PlayToSpeaker(audioFile string) error {
	fmt.Printf("🔊 使用 ffplay 直接播放到默认扬声器\n")

	// 使用 ffplay 播放（安静模式）
	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
	if err := cmd.Run(); err != nil {
		// 如果 ffplay 不可用，尝试使用 NirCmd
		cmd = exec.Command("nircmd", "mediaplay", "3000", audioFile)
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("播放音频失败: %v", err)
		}
	}

	return nil
}
