import json
import os
import wave
import pyaudio
import sherpa_onnx
import numpy as np
import soundfile as sf
import re
import time
import threading
from websocket import create_connection, WebSocketException

# ==================== 模型路径配置 ====================
asr_model_path = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
vp_model_path = "data/model/SpeakerID/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx"

# ==================== 全局变量 ====================
vp_config, extractor, audio1, sample_rate1, embedding1 = None, None, None, None, None

# ==================== 读取配置 ====================
with open('db/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)
asr_sensitivity = config["asr_sensitivity"]
voiceprint_enabled = config["voiceprint_enabled"]

with open('set/more_set.json', 'r', encoding='utf-8') as f:
    more_set = json.load(f)
mic_num = more_set["mic_index"]
voiceprint_threshold = more_set["voiceprint_threshold"]
ws_url = more_set.get("websocket_url", "ws://localhost:7878/ws")
heartbeat_interval = more_set.get("heartbeat_interval", 30)
reconnect_interval = more_set.get("reconnect_interval", 5)

# ==================== 静音检测参数 ====================
SILENCE_DURATION_MAP = {"high": 1, "medium": 2, "low": 3}
SILENCE_DURATION = SILENCE_DURATION_MAP.get(asr_sensitivity, 3)

FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000
CHUNK = 1024
SILENCE_CHUNKS = SILENCE_DURATION * RATE / CHUNK  # 静音持续的帧数

p, stream, recognizer = None, None, None
cache_path = "cache/voiceprint/myvoice.wav"
model = f"{asr_model_path}/model.int8.onnx"
tokens = f"{asr_model_path}/tokens.txt"

# ==================== WebSocket 连接管理 ====================
class WebSocketManager:
    """WebSocket 连接管理器（支持心跳、自动重连和异步接收）"""
    
    def __init__(self, url, heartbeat_interval=30, reconnect_interval=5):
        self.url = url
        self.ws = None
        self.connected = False
        self.heartbeat_interval = heartbeat_interval  # 心跳间隔（秒）
        self.reconnect_interval = reconnect_interval  # 重连间隔（秒）
        self.lock = threading.Lock()
        self.heartbeat_thread = None
        self.receive_thread = None
        self.should_stop = False
        self.last_response = None
        self.response_event = threading.Event()
        
    def connect(self):
        """连接到 WebSocket 服务器"""
        try:
            with self.lock:
                if self.connected and self.ws:
                    return True
                    
                # 创建连接，较长的超时时间
                self.ws = create_connection(self.url, timeout=10)
                # 连接后禁用超时（使用接收线程的短超时）
                self.ws.settimeout(None)
                self.connected = True
                print(f"✅ WebSocket 已连接: {self.url}")
                
                # 启动心跳线程
                if not self.heartbeat_thread or not self.heartbeat_thread.is_alive():
                    self.should_stop = False
                    self.heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
                    self.heartbeat_thread.start()
                
                # 启动接收线程
                if not self.receive_thread or not self.receive_thread.is_alive():
                    self.receive_thread = threading.Thread(target=self._receive_loop, daemon=True)
                    self.receive_thread.start()
                
                return True
        except Exception as e:
            self.connected = False
            print(f"⚠️ WebSocket 连接失败: {e}")
            return False
    
    def _receive_loop(self):
        """异步接收消息的线程"""
        from websocket import ABNF, WebSocketTimeoutException
        
        while not self.should_stop:
            try:
                if not self.connected or not self.ws:
                    time.sleep(1)
                    continue
                
                # 设置短超时，允许检查 should_stop
                self.ws.settimeout(1.0)
                opcode, data = self.ws.recv_data()
                
                if opcode == ABNF.OPCODE_TEXT:
                    message = data.decode('utf-8')
                    try:
                        msg_data = json.loads(message)
                        msg_type = msg_data.get("type", "unknown")
                        
                        if msg_type == "response":
                            # TTS 响应
                            if msg_data.get("success"):
                                print(f"✅ TTS 已播放: {msg_data.get('message', '')}")
                            else:
                                print(f"⚠️ TTS 失败: {msg_data.get('message', '')}")
                            
                            # 保存响应并触发事件
                            self.last_response = msg_data
                            self.response_event.set()
                            
                        elif msg_type == "pong":
                            # 服务器响应的 pong
                            pass  # 静默处理
                        else:
                            print(f"📥 收到消息: {message}")
                    except json.JSONDecodeError:
                        print(f"📥 收到文本: {message}")
                        
                elif opcode == ABNF.OPCODE_PING:
                    # 服务器发送的 ping，websocket-client 会自动回复 pong
                    pass  # 静默处理
                    
            except WebSocketTimeoutException:
                # 超时是正常的，继续循环
                continue
            except Exception as e:
                if not self.should_stop:
                    print(f"⚠️ 接收消息出错: {e}")
                    self.connected = False
                break
    
    def _heartbeat_loop(self):
        """心跳循环（后台线程）"""
        while not self.should_stop:
            time.sleep(self.heartbeat_interval)
            
            if not self.connected:
                # 尝试重连
                print("🔄 WebSocket 断开，尝试重连...")
                self.connect()
            else:
                # 发送心跳 ping
                try:
                    with self.lock:
                        if self.ws:
                            # 发送 JSON 格式的 ping（服务器支持）
                            ping_msg = json.dumps({"type": "ping"})
                            self.ws.send(ping_msg)
                            # 也发送 WebSocket 协议层的 ping
                            self.ws.ping()
                except Exception as e:
                    print(f"⚠️ 心跳失败，标记为断开: {e}")
                    self.connected = False
    
    def send(self, message, wait_response=False, timeout=15):
        """
        发送消息（自动重连）
        
        Args:
            message: 要发送的消息（字符串）
            wait_response: 是否等待响应（默认 False）
            timeout: 等待响应的超时时间（秒）
        
        Returns:
            bool: 是否发送成功
        """
        max_retries = 3
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                # 确保已连接
                if not self.connected:
                    if not self.connect():
                        retry_count += 1
                        time.sleep(1)
                        continue
                
                # 清除之前的响应
                if wait_response:
                    self.response_event.clear()
                    self.last_response = None
                
                # 发送消息
                with self.lock:
                    if self.ws:
                        self.ws.send(message)
                        
                        # 如果需要等待响应
                        if wait_response:
                            # 释放锁，等待响应
                            pass
                        else:
                            print(f"📤 TTS 请求已发送: {message[:50]}...")
                        
                        # 等待响应（如果需要）
                        if wait_response:
                            if self.response_event.wait(timeout=timeout):
                                return True
                            else:
                                print(f"⚠️ 等待响应超时（{timeout}秒）")
                                return False
                        
                        return True
                        
            except WebSocketException as e:
                print(f"⚠️ 发送失败 (尝试 {retry_count + 1}/{max_retries}): {e}")
                self.connected = False
                retry_count += 1
                if retry_count < max_retries:
                    time.sleep(1)
            except Exception as e:
                print(f"❌ WebSocket 发送错误: {e}")
                return False
        
        print(f"❌ WebSocket 发送失败，已重试 {max_retries} 次")
        return False
    
    def close(self):
        """关闭连接"""
        self.should_stop = True
        with self.lock:
            if self.ws:
                try:
                    self.ws.close()
                    print("🔌 WebSocket 连接已关闭")
                except:
                    pass
                self.ws = None
            self.connected = False

# 全局 WebSocket 管理器实例（使用配置文件中的参数）
ws_manager = WebSocketManager(ws_url, heartbeat_interval=heartbeat_interval, reconnect_interval=reconnect_interval)


def has_valid_content(text):
    """检查文本是否包含有效内容（排除只有标点符号的情况）"""
    if not text:
        return False
    # 移除所有空白字符、标点符号和表情标记
    clean_text = re.sub(r'[\s\[\].,!?;:，。！？；：、\-—_\(\)（）【】《》""''\u3000]+', '', text)
    return len(clean_text) > 0


def send_to_websocket(message):
    """
    向 WebSocket 服务器发送消息（使用连接池，非阻塞）
    
    优化说明：
    - 使用异步接收线程，不阻塞等待响应
    - 自动重连机制
    - 心跳保活
    """
    return ws_manager.send(message, wait_response=False)



def rms(data):
    """计算音频数据的均方根"""
    audio_data = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    if len(audio_data) == 0:
        return 0.0
    return np.sqrt(np.mean(audio_data ** 2))


def dbfs(rms_value):
    """将均方根转换为分贝满量程（dBFS）"""
    if rms_value <= 0:
        return -float('inf')
    return 20 * np.log10(rms_value / (2 ** 15))


def record_audio():
    """从麦克风录音，自动检测静音停止"""
    global p, stream
    frames = []
    recording = True
    silence_counter = 0

    if p is None:
        p = pyaudio.PyAudio()
        stream = p.open(
            format=FORMAT,
            channels=CHANNELS,
            rate=RATE,
            input=True,
            frames_per_buffer=CHUNK,
            input_device_index=mic_num
        )

    print("🎤 开始录音，请说话...")

    while recording:
        data = stream.read(CHUNK, exception_on_overflow=False)  # macOS 上建议加此参数防溢出
        frames.append(data)
        current_rms = rms(data)
        current_dbfs = dbfs(current_rms)

        if current_dbfs > -50:  # 有声音（阈值可调整）
            silence_counter = 0
        else:
            silence_counter += 1
            if silence_counter > SILENCE_CHUNKS:
                recording = False

    print("🔇 检测到静音，录音结束")
    return b''.join(frames)


def verify_speakers():
    """声纹识别：对比当前录音与注册声纹"""
    global vp_config, extractor, audio1, sample_rate1, embedding1
    audio_file1 = "cache/voiceprint/myvoice.wav"
    audio_file2 = cache_path

    def load_audio(filename):
        audio, sample_rate = sf.read(filename, dtype="float32", always_2d=True)
        audio = audio[:, 0]  # 取第一声道
        return audio, sample_rate

    def extract_speaker_embedding(audio, sample_rate):
        vp_stream = extractor.create_stream()
        vp_stream.accept_waveform(sample_rate=sample_rate, waveform=audio)
        vp_stream.input_finished()
        embedding = extractor.compute(vp_stream)
        return np.array(embedding)

    def cosine_similarity():
        dot_product = np.dot(embedding1, embedding2)
        norm1 = np.linalg.norm(embedding1)
        norm2 = np.linalg.norm(embedding2)
        return dot_product / (norm1 * norm2) if (norm1 * norm2) != 0 else 0.0

    print("正在加载说话人嵌入模型...")
    try:
        if vp_config is None:
            # macOS M 架构使用 "cpu" provider，num_threads 建议设置为性能核心数
            num_threads = max(1, os.cpu_count() - 2)  # 留一些余量给系统
            vp_config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
                model=vp_model_path,
                debug=False,
                provider="cpu",        # macOS M 架构只支持 cpu
                num_threads=num_threads
            )
            extractor = sherpa_onnx.SpeakerEmbeddingExtractor(vp_config)
            audio1, sample_rate1 = load_audio(audio_file1)
            embedding1 = extract_speaker_embedding(audio1, sample_rate1)

        audio2, sample_rate2 = load_audio(audio_file2)
        embedding2 = extract_speaker_embedding(audio2, sample_rate2)
        similarity = cosine_similarity()

        if similarity >= voiceprint_threshold:
            print(f"✓ 结果: 是同一个说话人 (相似度 {similarity:.4f} >= 阈值 {voiceprint_threshold})")
            return True
        else:
            print(f"✗ 结果: 不是同一个说话人 (相似度 {similarity:.4f} < 阈值 {voiceprint_threshold})")
            return False
    except Exception as e:
        print(f"声纹识别出错，详情：{e}")
        return True


def recognize_audio(audiodata):
    """语音识别：使用 SenseVoice 模型进行离线识别"""
    global recognizer

    if recognizer is None:
        num_threads = max(1, os.cpu_count() - 2)
        recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=model,
            tokens=tokens,
            use_itn=True,              # 启用逆文本规范化（数字、日期等）
            num_threads=num_threads     # macOS M 芯片多核优化
        )

    # 保存录音到缓存文件
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with wave.open(cache_path, 'wb') as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(p.get_sample_size(FORMAT))
        wf.setframerate(RATE)
        wf.writeframes(audiodata)

    # 检查录音时长是否太短
    with wave.open(cache_path, 'rb') as wf:
        n_frames = wf.getnframes()
        duration = n_frames / RATE
    if duration < SILENCE_DURATION + 0.5:
        return ""

    # 声纹验证（如果开启）
    if voiceprint_enabled:
        if not verify_speakers():
            return ""

    # SenseVoice 识别
    audio, sample_rate = sf.read(cache_path, dtype="float32", always_2d=True)
    asr_stream = recognizer.create_stream()
    asr_stream.accept_waveform(sample_rate, audio[:, 0])
    recognizer.decode_stream(asr_stream)

    # 解析结果（SenseVoice 返回 JSON，包含 text + emotion + event）
    res = json.loads(str(asr_stream.result))
    emotion_key = res.get('emotion', '').strip('<|>')
    event_key = res.get('event', '').strip('<|>')
    text = res.get('text', '')

    emotion_dict = {
        "HAPPY": "[开心]", "SAD": "[伤心]", "ANGRY": "[愤怒]",
        "DISGUSTED": "[厌恶]", "SURPRISED": "[惊讶]",
        "NEUTRAL": "", "EMO_UNKNOWN": ""
    }
    event_dict = {
        "BGM": "", "Applause": "[鼓掌]", "Laughter": "[大笑]",
        "Cry": "[哭]", "Sneeze": "[打喷嚏]", "Cough": "[咳嗽]",
        "Breath": "[深呼吸]", "Speech": "", "Event_UNK": ""
    }

    emotion = emotion_dict.get(emotion_key, "")
    event = event_dict.get(event_key, "")
    result = event + text + emotion

    if result == "The.":  # SenseVoice 的常见误识别
        return ""
    
    # 如果识别到有效内容（排除只有标点符号），发送到 WebSocket
    if has_valid_content(text):
        send_to_websocket(result)
    
    return result