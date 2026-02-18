package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// WSServer WebSocket 服务器
type WSServer struct {
	ttsService *TTSServiceV2
	upgrader   websocket.Upgrader
	mu         sync.Mutex
	config     *WSConfig
}

// WSConfig WebSocket 服务配置
type WSConfig struct {
	Voice         string `json:"voice"`           // 默认音色
	Language      string `json:"language"`        // 默认语言
	MicDevice     string `json:"mic_device"`      // 虚拟麦克风设备名称
	SpeakerDevice string `json:"speaker_device"`  // 扬声器设备名称
	PlayToSpeaker bool   `json:"play_to_speaker"` // 是否同时播放到扬声器
}

// WSMessage WebSocket 消息格式
type WSMessage struct {
	Type     string `json:"type,omitempty"`     // 消息类型：text(默认), ping, pong
	Text     string `json:"text"`               // 要转换的文本
	Voice    string `json:"voice,omitempty"`    // 可选：覆盖默认音色
	Language string `json:"language,omitempty"` // 可选：覆盖默认语言
}

const (
	// 心跳相关常量
	pongWait       = 60 * time.Second // 等待 pong 消息的超时时间
	pingInterval   = 50 * time.Second // 发送 ping 的间隔
	writeWait      = 10 * time.Second // 写消息的超时时间
	maxMessageSize = 8192             // 最大消息大小（8KB）
)

// NewWSServer 创建 WebSocket 服务器
func NewWSServer(ttsService *TTSServiceV2, config *WSConfig) *WSServer {
	return &WSServer{
		ttsService: ttsService,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // 允许所有来源（生产环境请限制）
			},
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
		config: config,
	}
}

// HandleWebSocket 处理 WebSocket 连接
func (s *WSServer) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("❌ WebSocket 升级失败: %v", err)
		return
	}
	defer conn.Close()

	log.Printf("✅ WebSocket 客户端已连接: %s", conn.RemoteAddr())

	// 配置连接参数
	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))

	// 设置 pong 处理器
	conn.SetPongHandler(func(string) error {
		log.Printf("💗 收到 pong 心跳: %s", conn.RemoteAddr())
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	// 启动心跳发送器
	done := make(chan struct{})
	go s.pingLoop(conn, done)
	defer close(done)

	// 消息处理循环
	for {
		// 读取消息
		_, message, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("⚠️ WebSocket 错误: %v", err)
			} else {
				log.Printf("🔌 客户端断开连接: %s", conn.RemoteAddr())
			}
			break
		}

		log.Printf("📨 收到消息: %s", string(message))

		// 解析消息
		var msg WSMessage
		text := string(message)

		// 尝试解析 JSON 格式
		if err := json.Unmarshal(message, &msg); err != nil {
			// 如果不是 JSON，当作纯文本处理
			msg.Text = text
			msg.Type = "text"
		}

		// 处理不同类型的消息
		switch msg.Type {
		case "ping":
			// 响应 ping 消息
			log.Printf("💓 收到 ping 消息，发送 pong")
			s.sendPong(conn)
			continue
		case "pong":
			// 客户端响应的 pong，已在 SetPongHandler 中处理
			log.Printf("💗 收到客户端 pong 消息")
			continue
		case "text", "":
			// 处理 TTS 文本消息
			if msg.Text == "" {
				log.Printf("⚠️ 收到空消息，跳过")
				continue
			}

			// 使用配置中的默认值（如果消息中未指定）
			voice := msg.Voice
			if voice == "" {
				voice = s.config.Voice
			}

			language := msg.Language
			if language == "" {
				language = s.config.Language
			}

			// 调用 TTS 生成并播放
			go s.handleTTS(msg.Text, voice, language, conn)
		default:
			log.Printf("⚠️ 未知的消息类型: %s", msg.Type)
		}
	}

	log.Printf("🔌 WebSocket 客户端已断开: %s", conn.RemoteAddr())
}

// pingLoop 心跳发送循环
func (s *WSServer) pingLoop(conn *websocket.Conn, done chan struct{}) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			// 发送 ping
			if err := s.sendPing(conn); err != nil {
				log.Printf("⚠️ 发送 ping 失败: %v", err)
				return
			}
			log.Printf("💓 发送 ping 心跳: %s", conn.RemoteAddr())
		case <-done:
			return
		}
	}
}

// sendPing 发送 ping 消息
func (s *WSServer) sendPing(conn *websocket.Conn) error {
	conn.SetWriteDeadline(time.Now().Add(writeWait))
	return conn.WriteMessage(websocket.PingMessage, nil)
}

// sendPong 发送 pong 消息（响应客户端的 ping）
func (s *WSServer) sendPong(conn *websocket.Conn) {
	response := map[string]interface{}{
		"type": "pong",
	}
	data, _ := json.Marshal(response)

	conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		log.Printf("⚠️ 发送 pong 失败: %v", err)
	}
}

// handleTTS 处理 TTS 请求（在 goroutine 中执行）
func (s *WSServer) handleTTS(text, voice, language string, conn *websocket.Conn) {
	s.mu.Lock()
	defer s.mu.Unlock()

	log.Printf("🎤 开始 TTS 处理...")
	log.Printf("   文本: %s", text)
	log.Printf("   音色: %s", voice)
	log.Printf("   语言: %s", language)

	// 1. 如果开启了扬声器预览，先播放到扬声器
	if s.config.PlayToSpeaker && s.config.SpeakerDevice != "" {
		log.Printf("🔊 播放到扬声器（预览）: %s", s.config.SpeakerDevice)
		err := s.ttsService.GenerateAndPlaySpeech(text, voice, s.config.SpeakerDevice, language)
		if err != nil {
			errMsg := fmt.Sprintf("❌ 扬声器播放失败: %v", err)
			log.Println(errMsg)
			s.sendResponse(conn, false, errMsg)
			return
		}
		log.Printf("✅ 扬声器播放完成")
	}

	// 2. 播放到虚拟麦克风
	log.Printf("🎙️ 播放到虚拟麦克风: %s", s.config.MicDevice)
	err := s.ttsService.GenerateAndPlaySpeech(text, voice, s.config.MicDevice, language)
	if err != nil {
		errMsg := fmt.Sprintf("❌ 虚拟麦克风播放失败: %v", err)
		log.Println(errMsg)
		s.sendResponse(conn, false, errMsg)
		return
	}

	log.Printf("✅ TTS 处理完成")
	s.sendResponse(conn, true, "TTS 播放成功")
}

// sendResponse 向客户端发送响应（带连接检查）
func (s *WSServer) sendResponse(conn *websocket.Conn, success bool, message string) {
	// 尝试发送前先 ping 一下，检查连接是否还活着
	conn.SetWriteDeadline(time.Now().Add(1 * time.Second))
	if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
		log.Printf("⚠️ 连接已断开，无法发送响应: %v", err)
		return
	}

	response := map[string]interface{}{
		"type":    "response",
		"success": success,
		"message": message,
	}

	data, err := json.Marshal(response)
	if err != nil {
		log.Printf("⚠️ 响应序列化失败: %v", err)
		return
	}

	conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		log.Printf("⚠️ 发送响应失败（连接可能已断开）: %v", err)
	} else {
		log.Printf("✅ 响应已发送: %s", message)
	}
}

// UpdateConfig 更新配置
func (s *WSServer) UpdateConfig(config *WSConfig) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.config = config
	log.Printf("✅ WebSocket 配置已更新: %+v", config)
}

// GetConfig 获取当前配置
func (s *WSServer) GetConfig() *WSConfig {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.config
}
