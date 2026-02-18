package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HTTPServer HTTP API 服务器
type HTTPServer struct {
	ttsService *TTSServiceV2
	config     *WSConfig
}

// HTTPTTSRequest HTTP TTS 请求结构
type HTTPTTSRequest struct {
	Text     string `json:"text"`
	Voice    string `json:"voice,omitempty"`
	Language string `json:"language,omitempty"`
}

// HTTPTTSResponse HTTP TTS 响应结构
type HTTPTTSResponse struct {
	Success   bool      `json:"success"`
	Message   string    `json:"message"`
	Duration  float64   `json:"duration,omitempty"`
	ErrorCode string    `json:"error_code,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

// NewHTTPServer 创建 HTTP 服务器
func NewHTTPServer(ttsService *TTSServiceV2, config *WSConfig) *HTTPServer {
	return &HTTPServer{
		ttsService: ttsService,
		config:     config,
	}
}

// HandleTTS 处理 TTS 请求
func (s *HTTPServer) HandleTTS(w http.ResponseWriter, r *http.Request) {
	// 设置 CORS 头（允许跨域）
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	// 处理 OPTIONS 预检请求
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// 只接受 POST 方法
	if r.Method != http.MethodPost {
		s.respondError(w, "Method not allowed. Use POST", "METHOD_NOT_ALLOWED", http.StatusMethodNotAllowed)
		return
	}

	// 读取请求体
	body, err := io.ReadAll(r.Body)
	if err != nil {
		s.respondError(w, "Failed to read request body", "INVALID_REQUEST", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// 解析 JSON
	var req HTTPTTSRequest
	if err := json.Unmarshal(body, &req); err != nil {
		s.respondError(w, "Invalid JSON format: "+err.Error(), "INVALID_JSON", http.StatusBadRequest)
		return
	}

	// 验证必填字段
	if req.Text == "" {
		s.respondError(w, "Text field is required", "INVALID_REQUEST", http.StatusBadRequest)
		return
	}

	fmt.Printf("📨 收到 HTTP TTS 请求\n")
	fmt.Printf("   文本: %s\n", req.Text)
	fmt.Printf("   来源: %s\n", r.RemoteAddr)

	// 使用请求中的参数或默认配置
	voice := req.Voice
	if voice == "" {
		voice = s.config.Voice
	}
	language := req.Language
	if language == "" {
		language = s.config.Language
	}

	// 处理 TTS - 调用 GenerateAndPlaySpeech
	startTime := time.Now()
	err = s.ttsService.GenerateAndPlaySpeech(req.Text, voice, s.config.MicDevice, language)
	duration := time.Since(startTime).Seconds()

	// 返回响应
	if err != nil {
		fmt.Printf("❌ TTS 处理失败: %v\n", err)

		// 判断错误类型
		errorCode := "TTS_FAILED"
		statusCode := http.StatusInternalServerError

		errMsg := err.Error()
		if errMsg == "文本内容为空" {
			errorCode = "INVALID_REQUEST"
			statusCode = http.StatusBadRequest
		} else if stringIndexOf(errMsg, "设备") >= 0 || stringIndexOf(errMsg, "Device") >= 0 {
			errorCode = "DEVICE_NOT_FOUND"
			statusCode = http.StatusServiceUnavailable
		}

		s.respondError(w, err.Error(), errorCode, statusCode)
		return
	}

	fmt.Printf("✅ TTS 处理成功 (耗时: %.2fs)\n", duration)
	s.respondSuccess(w, "TTS 播放成功", duration)
}

// respondSuccess 返回成功响应
func (s *HTTPServer) respondSuccess(w http.ResponseWriter, message string, duration float64) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	response := HTTPTTSResponse{
		Success:   true,
		Message:   message,
		Duration:  duration,
		Timestamp: time.Now(),
	}

	json.NewEncoder(w).Encode(response)
}

// respondError 返回错误响应
func (s *HTTPServer) respondError(w http.ResponseWriter, message, errorCode string, statusCode int) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)

	response := HTTPTTSResponse{
		Success:   false,
		Message:   message,
		ErrorCode: errorCode,
		Timestamp: time.Now(),
	}

	json.NewEncoder(w).Encode(response)
}

// UpdateConfig 更新配置
func (s *HTTPServer) UpdateConfig(config *WSConfig) {
	s.config = config
	fmt.Printf("✅ HTTP API 配置已更新: voice=%s, language=%s, micDevice=%s\n",
		config.Voice, config.Language, config.MicDevice)
}

// GetConfig 获取当前配置
func (s *HTTPServer) GetConfig() *WSConfig {
	return s.config
}

// contains 检查字符串是否包含子串
func stringContainsSubstr(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr ||
			stringIndexOf(s, substr) >= 0))
}

func stringIndexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
