# Xi Virtual Voice - 跨平台 AI 语音合成助手

Xi Virtual Voice 是一个现代化的、跨平台的桌面应用程序，旨在通过先进的 AI 语音技术实现文本转语音（TTS）并无缝集成到虚拟麦克风中。无论是在直播、在线会议还是语音聊天中，它都能为您提供即时、高质量的 AI 语音输出。

## 🌟 核心特性

*   **跨平台支持**: 完美支持 **macOS** 和 **Windows**，并在 Linux 上有实验性支持。
*   **AI 语音合成**: 集成了 Azure TTS 和 Google TTS 等顶尖语音服务，提供自然逼真的语音体验。
*   **虚拟麦克风集成**:
    *   **Windows**: 支持 VB-CABLE 等虚拟音频设备。
    *   **macOS**: 支持 BlackHole 等虚拟音频驱动。
    *   能够将合成的语音直接注入到虚拟麦克风，让 Discord、Zoom、OBS 等软件直接通过麦克风听到 AI 的声音。
*   **Web 远程控制**: 内置 HTTP 和 WebSocket 服务器，支持通过局域网内的手机或网页远程发送即时语音消息。
*   **多音色支持**: 内置多种高质量音色（如 Cherry, Premwadee 等），支持多语言（中文、英文、日文等）自动识别与合成。

## 🛠️ 技术栈

本项目采用现代化的技术栈构建，确保了高性能和良好的开发体验：

*   **前端**: [Vue 3](https://vuejs.org/) + [Vite](https://vitejs.dev/) + [TypeScript](https://www.typescriptlang.org/) - 构建响应式、类型安全的用户界面。
*   **后端**: [Go (Golang)](https://go.dev/) - 提供高性能的系统级服务、并发处理和跨平台能力。
*   **框架**: [Wails v2](https://wails.io/) - 将 Go 后端与 Web 前端结合，构建原生桌面应用的轻量级框架。
*   **音频处理**:
    *   **FFmpeg / ffplay**: 统一的跨平台音频播放与处理引擎。
    *   **PowerShell**: Windows 下高级音频设备管理。
    *   **CoreAudio**: macOS 原生音频支持。

## 🚀 解决的技术挑战

在开发过程中，我们攻克了多个跨平台音频处理的技术难题：

### 1. Windows 音频路由难题
*   **问题**: Windows 系统默认不仅允许音频播放到"默认设备"，很难将音频定向输出到特定的虚拟麦克风（如 VB-CABLE），而且切换默认设备会导致全系统音频中断。
*   **解决方案**:
    *   创新性地使用了 `ffplay` 结合 `SDL_AUDIO_DEVICE_NAME` 环境变量的技术方案。
    *   实现了**无侵入式播放**：无需修改系统默认音频设备，即可将语音流精准发送到指定的虚拟音频线缆，延迟低至毫秒级。
    *   提供了自动降级策略：在极少数不支持的环境下，自动回退到安全的设备切换模式。

### 2. 跨平台架构统一
*   **问题**: macOS 和 Windows 的音频驱动模型完全不同（CoreAudio vs WASAPI/DirectSound）。
*   **解决方案**:
    *   设计了统一的 interface `AudioPlatform`，屏蔽了底层差异。
    *   macOS 端利用 `afplay` 和系统命令。
    *   Windows 端利用 PowerShell 脚本集成和 FFmpeg 生态。
    *   确保前端 UI 代码无需任何修改即可在不同系统上运行。

### 3. 多协议服务并发
*   **问题**: 需要同时支持桌面操作、HTTP API 调用和 WebSocket 实时控制。
*   **解决方案**:
    *   Go 协程（Goroutine）并发模型，同时运行 Wails 绑定服务、HTTP 服务器和 WebSocket 服务器。
    *   实现了配置热更新机制，任意一端的设置修改都能实时同步到所有连接的客户端。

## 📦 安装与使用

### 环境要求
*   **Go** 1.18+
*   **Node.js** 16+
*   **ffmpeg** (Windows 用户需安装并配置环境变量)
*   **虚拟音频驱动**:
    *   Windows: [VB-CABLE](https://vb-audio.com/Cable/)
    *   macOS: [BlackHole](https://github.com/ExistentialAudio/BlackHole)

### 构建运行

1.  克隆仓库
    ```bash
    git clone https://github.com/lonelymeko/xi_virtual_voice.git
    cd xi_virtual_voice
    ```

2.  开发模式运行
    ```bash
    wails dev
    ```

3.  编译生产版本
    ```bash
    wails build
    ```

## 📝 贡献
欢迎提交 Issue 或 Pull Request 来改进 Xi Virtual Voice！

## 📄 许可证
MIT License
