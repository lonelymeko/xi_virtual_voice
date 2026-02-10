package main

// AudioPlatform 跨平台音频接口
type AudioPlatform interface {
	// 获取所有音频输出设备
	GetAudioDevices() ([]AudioDevice, error)

	// 播放音频到指定设备
	PlayToDevice(audioFile, device string) error

	// 播放音频到系统默认扬声器（不切换设备）
	PlayToSpeaker(audioFile string) error

	// 获取当前默认设备
	GetCurrentDevice() (string, error)

	// 切换音频设备
	SwitchDevice(device string) error

	// 恢复原始设备
	RestoreDevice(originalDevice string) error

	// 检查必要的工具是否已安装
	CheckDependencies() error

	// 获取平台名称
	GetPlatformName() string
}

// NewAudioPlatform 根据操作系统创建对应的平台实现
func NewAudioPlatform() (AudioPlatform, error) {
	// 平台特定的实现在各自的 _darwin.go, _windows.go, _linux.go 文件中
	// 这个函数会在编译时根据目标平台自动选择正确的实现
	return newPlatformImpl()
}

// GetAudioConverterCommand 获取音频转换命令（跨平台）
func GetAudioConverterCommand(inputFile, outputFile string) (string, []string, error) {
	// FFmpeg 在所有平台都可用
	args := []string{
		"-i", inputFile,
		"-af", "highpass=f=200,lowpass=f=3400,anlmdn=s=0.002:p=0.004:m=15,dynaudnorm=f=150:g=15,volume=0.85",
		"-ar", "48000",
		"-ac", "2",
		"-acodec", "pcm_s16le",
		"-loglevel", "error",
		"-y",
		outputFile,
	}

	return "ffmpeg", args, nil
}
