package test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"testing"

	"github.com/joho/godotenv"
)

// QwenTTSRequest 对应你 Curl 中的 JSON 结构
// 注意：Voice 在 Input 里面，而不是外面
type QwenTTSRequest struct {
	Model string `json:"model"`
	Input struct {
		Text         string `json:"text"`
		Voice        string `json:"voice"`         // 这里是关键：Voice 在 Input 内部
		LanguageType string `json:"language_type"` // 这里是关键：LanguageType 也在 Input 内部
	} `json:"input"`
}

// QwenTTSResponse 对应 API 返回的 JSON 结构
type QwenTTSResponse struct {
	Output struct {
		Audio struct {
			Data      string `json:"data"`
			ExpiresAt int64  `json:"expires_at"`
			ID        string `json:"id"`
			URL       string `json:"url"` // 音频文件的 URL
		} `json:"audio"`
		FinishReason string `json:"finish_reason"`
	} `json:"output"`
	Usage struct {
		Characters int `json:"characters"`
	} `json:"usage"`
	RequestID string `json:"request_id"`
}

func TestAliyunTTS(t *testing.T) {
	err := godotenv.Load("../.env")
	if err != nil {
		panic(err)
	}
	// 替换你的 API KEY
	apiKey := os.Getenv("DASHSCOPE_API_KEY")
	model := os.Getenv("QWEN_VOICE_MODEL")
	// 1. 构造符合 Qwen3 要求的请求体
	reqBody := QwenTTSRequest{
		Model: model,
		Input: struct {
			Text         string `json:"text"`
			Voice        string `json:"voice"`
			LanguageType string `json:"language_type"`
		}{
			Text:         "那我来给大家推荐一款T恤，这款呢真的是超级好看...",
			Voice:        "Cherry", // 设置音色
			LanguageType: "Chinese",
		},
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		panic(err)
	}

	// 2. 创建请求
	// 注意：Endpoint 是多模态生成的地址，不是普通的 audio 生成地址
	url := os.Getenv("DASHSCOPE_ENDPOINT")
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		panic(err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	// 某些阿里云接口可能需要 X-DashScope-WorkSpace，如果有报错需加上
	// req.Header.Set("X-DashScope-WorkSpace", "your-workspace-id")

	// 3. 发送
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()

	// 4. 处理响应
	// Qwen3 返回的是 JSON，包含音频文件的 URL
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		fmt.Printf("Error: %s\n", body)
		return
	}

	// 解析 JSON 响应
	var ttsResp QwenTTSResponse
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}

	err = json.Unmarshal(body, &ttsResp)
	if err != nil {
		fmt.Printf("JSON 解析失败: %v\n响应内容: %s\n", err, string(body))
		panic(err)
	}

	// 获取音频 URL
	audioURL := ttsResp.Output.Audio.URL
	if audioURL == "" {
		fmt.Println("未获取到音频 URL")
		return
	}
	fmt.Printf("音频 URL: %s\n", audioURL)

	// 5. 下载音频文件
	audioResp, err := http.Get(audioURL)
	if err != nil {
		panic(err)
	}
	defer audioResp.Body.Close()

	outFile, err := os.Create("qwen_output.wav")
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	written, err := io.Copy(outFile, audioResp.Body)
	if err != nil {
		panic(err)
	}

	fmt.Printf("音频下载完成，大小: %d 字节\n", written)

	// 6. 自动播放音频（macOS 使用 afplay 命令）
	fmt.Println("正在播放音频...")
	if err := runCommand("afplay qwen_output.wav"); err != nil {
		fmt.Printf("播放失败: %v\n", err)
	} else {
		fmt.Println("播放完成!")
	}
}

// runCommand 执行 shell 命令
func runCommand(cmdStr string) error {
	cmd := exec.Command("sh", "-c", cmdStr)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
