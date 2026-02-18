//go:build windows
// +build windows

package main

import (
	"fmt"
	"os"
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

	fmt.Println("✅ ffmpeg 已安装")
	return nil
}

// GetAudioDevices 获取所有音频输出设备
func (p *WindowsPlatform) GetAudioDevices() ([]AudioDevice, error) {
	devices := make([]AudioDevice, 0)

	// 使用 PowerShell 获取设备列表,先导入模块
	psCmd := `Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue; Get-AudioDevice -List | Where-Object {$_.Type -eq "Playback"} | ForEach-Object { $_.Name }`
	cmd := exec.Command("powershell", "-Command", psCmd)
	output, err := cmd.Output()

	if err != nil {
		// 如果 AudioDeviceCmdlets 未安装,使用 Windows API
		fmt.Printf("⚠️  PowerShell AudioDeviceCmdlets 未安装或加载失败,使用 Windows API\n")
		fmt.Printf("   错误信息: %v\n", err)
		return p.getDevicesViaAPI()
	}

	// 获取当前默认设备
	currentDevice, _ := p.GetCurrentDevice()

	// 解析设备列表
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			devices = append(devices, AudioDevice{
				Name:      line,
				IsDefault: line == currentDevice,
			})
		}
	}

	// 如果没有找到设备,使用 Windows API
	if len(devices) == 0 {
		return p.getDevicesViaAPI()
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
	// 使用 PowerShell 获取当前设备,先导入模块
	psCmd := `Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue; (Get-AudioDevice -Playback).Name`
	cmd := exec.Command("powershell", "-Command", psCmd)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("获取当前设备失败: %v\n输出: %s\n提示: 请确认 AudioDeviceCmdlets 模块已正确安装", err, string(output))
	}

	return strings.TrimSpace(string(output)), nil
}

// SwitchDevice 切换到指定设备
func (p *WindowsPlatform) SwitchDevice(device string) error {
	// AudioDeviceCmdlets 的正确用法是通过管道传递设备对象
	// Get-AudioDevice -List | Where-Object {$_.Name -eq "设备名"} | Set-AudioDevice
	psCmd := fmt.Sprintf(`Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue; Get-AudioDevice -List | Where-Object {$_.Name -eq "%s"} | Set-AudioDevice`, device)
	cmd := exec.Command("powershell", "-Command", psCmd)
	output, err := cmd.CombinedOutput()

	if err != nil {
		return fmt.Errorf("切换设备失败: %v\n输出: %s\n提示: 请确认设备名称正确,可用设备列表请查看应用日志", err, string(output))
	}

	// 缩短等待时间，从 800ms 减少到 200ms
	time.Sleep(200 * time.Millisecond)
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

	// 使用正确的 AudioDeviceCmdlets 语法
	psCmd := fmt.Sprintf(`Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue; Get-AudioDevice -List | Where-Object {$_.Name -eq "%s"} | Set-AudioDevice`, originalDevice)
	cmd := exec.Command("powershell", "-Command", psCmd)
	err := cmd.Run()

	// 缩短恢复等待时间，从 500ms 减少到 100ms（因为是异步的）
	time.Sleep(100 * time.Millisecond)
	return err
}

// PlayToDevice 播放音频到指定设备(支持虚拟麦克风)
//
// 优化方案: 使用 SDL_AUDIO_DEVICE_NAME 环境变量指定设备 (需要 ffplay)
// 优势: 无需切换系统默认设备，且无副作用
// 备选: 系统设备切换 (当 ffplay 方案失败时)
func (p *WindowsPlatform) PlayToDevice(audioFile, device string) error {
	fmt.Printf("🎵 播放音频到设备: %s (尝试 ffplay 环境变量)\n", device)

	// 1. 优先尝试使用 ffplay 环境变量方案 (最快，无痕)
	if err := playViaFFplayEnv(audioFile, device); err == nil {
		fmt.Printf("✅ ffplay 播放成功\n")
		return nil
	} else {
		fmt.Printf("⚠️ ffplay 方案失败: %v\n", err)
	}

	// 2. 如果失败，回退到切换系统默认设备 (最可靠)
	fmt.Printf("⚠️ 回退到设备切换方案...\n")
	return p.playWithTempSwitch(audioFile, device)
}

// playViaFFplayEnv 使用环境变量指定设备进行播放
// 原理: ffplay 使用 SDL 库，可通过 SDL_AUDIO_DEVICE_NAME 环境变量指定音频设备
func playViaFFplayEnv(audioFile, device string) error {
	// 1. 设置环境变量 SDL_AUDIO_DEVICE_NAME
	// 注意: 设备名称需要精确匹配，且可能涉及编码问题
	// 在 Windows 上，通常直接使用设备全名即可

	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)

	// 为此命令设置特定环境变量
	cmd.Env = append(os.Environ(), fmt.Sprintf("SDL_AUDIO_DEVICE_NAME=%s", device))

	// 隐藏窗口
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	output, err := cmd.CombinedOutput()
	if err != nil {
		// ffplay 在找不到设备时通常会打印错误并退出
		// 我们可以捕获这个错误
		return fmt.Errorf("ffplay 错误: %v, 输出: %s", err, string(output))
	}

	return nil
}

// playViaDShow 保留此函数以备将来可能的改进
// 目前 Windows ffmpeg 不支持直接输出到指定设备
func (p *WindowsPlatform) playViaDShow(audioFile, device string) error {
	// 经过测试发现: Windows 下 ffmpeg 的 DirectShow (-f dshow)
	// 主要用于音频/视频捕获(输入)，而不是播放(输出)
	//
	// ffmpeg 在 Windows 上的音频输出选项:
	// 1. SDL: 只能输出到默认设备
	// 2. DirectSound (dsound): 理论支持但实际很难指定设备
	// 3. WASAPI: 不直接支持设备选择
	//
	// 结论: 最可靠的方案仍然是临时切换系统默认设备
	// 我们已经将切换时间优化到最低 (200ms + 100ms = 300ms 开销)

	return fmt.Errorf("Windows 下 ffmpeg 不支持直接输出到指定设备，使用设备切换方案")
}

// playWithTempSwitch 临时切换设备播放（优化版：异步恢复）
func (p *WindowsPlatform) playWithTempSwitch(audioFile, device string) error {
	// 获取当前设备
	originalDevice, err := p.GetCurrentDevice()
	if err != nil {
		fmt.Printf("⚠️  无法获取当前设备: %v\n", err)
		// 如果获取失败，直接播放
		cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		return cmd.Run()
	}

	// 检查是否需要切换
	if device == originalDevice {
		fmt.Printf("   目标设备与当前相同，无需切换\n")
		cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		return cmd.Run()
	}

	// 切换到目标设备
	fmt.Printf("🔄 切换设备: %s -> %s\n", originalDevice, device)
	if err := p.SwitchDevice(device); err != nil {
		return fmt.Errorf("切换设备失败: %v", err)
	}

	// 使用 defer 确保播放后恢复设备（无论成功失败）
	defer func() {
		fmt.Printf("🔄 恢复设备: %s\n", originalDevice)
		if err := p.RestoreDevice(originalDevice); err != nil {
			fmt.Printf("⚠️  恢复设备失败: %v\n", err)
		}
	}()

	// 播放音频
	fmt.Printf("▶️  开始播放...\n")
	cmd := exec.Command("ffplay",
		"-nodisp",
		"-autoexit",
		"-loglevel", "quiet",
		audioFile,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("播放失败: %v", err)
	}

	fmt.Printf("✅ 播放完成\n")
	return nil
}

// PlayToSpeaker 播放音频到系统默认扬声器（不切换设备）
func (p *WindowsPlatform) PlayToSpeaker(audioFile string) error {
	fmt.Printf("🔊 播放到默认扬声器\n")

	// 使用 ffplay 播放（安静模式）
	cmd := exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", audioFile)

	// 隐藏控制台窗口
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow: true,
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("播放音频失败: %v", err)
	}

	return nil
}
