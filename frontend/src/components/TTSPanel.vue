<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { GetAudioDevices, GetAvailableVoices, GetAvailableLanguages, SpeakToDevice, SpeakWithPreview } from '../../wailsjs/go/main/App'

interface AudioDevice {
  name: string
  isDefault: boolean
}

interface Voice {
  value: string
  label: string
}

interface TTSResponse {
  success: boolean
  message: string
  error?: string
}

// 状态管理
const text = ref('')
const selectedVoice = ref('Cherry')
const selectedLanguage = ref('Auto') // 语言选择，默认自动检测
const selectedMicDevice = ref('') // 虚拟麦克风设备
const selectedSpeakerDevice = ref('') // 扬声器设备
const playToSpeaker = ref(false) // 是否同时播放到扬声器
const audioDevices = ref<AudioDevice[]>([])
const voices = ref<Voice[]>([])
const languages = ref<Voice[]>([]) // 重用 Voice 接口，因为结构一样
const isGenerating = ref(false)
const statusMessage = ref('')
const statusType = ref<'success' | 'error' | 'info'>('info')

// 加载音频设备
const loadDevices = async () => {
  try {
    const devices = await GetAudioDevices()
    audioDevices.value = devices.map((d: any) => ({
      name: d.name,
      isDefault: d.isDefault
    }))
    
    // 默认选择虚拟麦克风（VB-Cable）
    const vbCable = audioDevices.value.find((d: AudioDevice) => d.name.includes('VB-Cable'))
    if (vbCable) {
      selectedMicDevice.value = vbCable.name
    } else if (audioDevices.value.length > 0) {
      selectedMicDevice.value = audioDevices.value[0].name
    }
    
    // 默认选择当前扬声器（第一个非虚拟设备）
    const defaultSpeaker = audioDevices.value.find((d: AudioDevice) => 
      !d.name.includes('VB-Cable') && !d.name.includes('Virtual')
    )
    if (defaultSpeaker) {
      selectedSpeakerDevice.value = defaultSpeaker.name
    } else if (audioDevices.value.length > 1) {
      selectedSpeakerDevice.value = audioDevices.value[1].name
    }
  } catch (error: any) {
    statusMessage.value = `加载设备失败: ${error}`
    statusType.value = 'error'
  }
}

// 加载音色列表
const loadVoices = async () => {
  try {
    const voiceList = await GetAvailableVoices()
    voices.value = voiceList.map((v: Record<string, string>) => ({
      value: v.value,
      label: v.label
    }))
  } catch (error: any) {
    console.error('加载音色失败:', error)
  }
}

// 加载语言列表
const loadLanguages = async () => {
  try {
    const languageList = await GetAvailableLanguages()
    languages.value = languageList.map((l: Record<string, string>) => ({
      value: l.value,
      label: l.label
    }))
  } catch (error: any) {
    console.error('加载语言列表失败:', error)
  }
}

// 发送语音
const handleSpeak = async () => {
  if (!text.value.trim()) {
    statusMessage.value = '请输入文本内容'
    statusType.value = 'error'
    return
  }

  if (!selectedMicDevice.value) {
    statusMessage.value = '请选择虚拟麦克风设备'
    statusType.value = 'error'
    return
  }

  if (playToSpeaker.value && !selectedSpeakerDevice.value) {
    statusMessage.value = '请选择扬声器设备'
    statusType.value = 'error'
    return
  }

  isGenerating.value = true
  statusMessage.value = playToSpeaker.value ? '正在生成语音并同时播放...' : '正在生成语音...'
  statusType.value = 'info'

  try {
    // 使用新的同时播放功能的方法
    const response: TTSResponse = await SpeakWithPreview(
      text.value,
      selectedVoice.value,
      selectedMicDevice.value,
      selectedSpeakerDevice.value,
      selectedLanguage.value,  // 语言参数
      playToSpeaker.value  // 是否同时播放到扬声器
    )

    if (response.success) {
      statusMessage.value = '✅ ' + response.message
      statusType.value = 'success'
    } else {
      statusMessage.value = '❌ ' + (response.error || '生成失败')
      statusType.value = 'error'
    }
  } catch (error: any) {
    statusMessage.value = `❌ 错误: ${error}`
    statusType.value = 'error'
  } finally {
    isGenerating.value = false
  }
}

// 刷新设备列表
const refreshDevices = () => {
  loadDevices()
  statusMessage.value = '设备列表已刷新'
  statusType.value = 'info'
  setTimeout(() => {
    statusMessage.value = ''
  }, 2000)
}

// 页面加载时初始化
onMounted(() => {
  loadDevices()
  loadVoices()
  loadLanguages()
})
</script>

<template>
  <div class="container">
    <div class="header">
      <h1>🎙️ TTS 虚拟麦克风</h1>
      <p class="subtitle">文本转语音 · 输出到虚拟麦克风</p>
    </div>

    <div class="main-content">
      <!-- 文本输入区域 -->
      <div class="input-section">
        <label class="label">
          <span class="label-text">📝 输入文本</span>
          <span class="char-count">{{ text.length }} 字</span>
        </label>
        <textarea
          v-model="text"
          class="text-input"
          placeholder="输入要转换为语音的文本，例如：大家好，我是虚拟语音助手..."
          rows="6"
          :disabled="isGenerating"
        ></textarea>
      </div>

      <!-- 设置区域 -->
      <div class="settings-section">
        <div class="setting-row">
          <div class="setting-item">
            <label class="label">
              <span class="label-text">🎵 音色选择</span>
            </label>
            <select v-model="selectedVoice" class="select-input" :disabled="isGenerating">
              <option v-for="voice in voices" :key="voice.value" :value="voice.value">
                {{ voice.label }}
              </option>
            </select>
          </div>

          <div class="setting-item">
            <label class="label">
              <span class="label-text">� 语言选择</span>
            </label>
            <select v-model="selectedLanguage" class="select-input" :disabled="isGenerating">
              <option v-for="lang in languages" :key="lang.value" :value="lang.value">
                {{ lang.label }}
              </option>
            </select>
          </div>
        </div>

        <div class="setting-row">
          <div class="setting-item">
            <label class="label">
              <span class="label-text">�🎙️ 虚拟麦克风</span>
              <button @click="refreshDevices" class="refresh-btn" :disabled="isGenerating">
                🔄
              </button>
            </label>
            <select v-model="selectedMicDevice" class="select-input" :disabled="isGenerating">
              <option v-for="device in audioDevices" :key="device.name" :value="device.name">
                {{ device.name }}{{ device.isDefault ? ' (默认)' : '' }}
              </option>
            </select>
          </div>
        </div>

        <!-- 播放选项 -->
        <div class="setting-row">
          <div class="checkbox-item">
            <label class="checkbox-label">
              <input 
                type="checkbox" 
                v-model="playToSpeaker" 
                :disabled="isGenerating"
                class="checkbox-input"
              />
              <span class="checkbox-text">🔈 同时播放到扬声器</span>
            </label>
            <p class="checkbox-hint">勾选后会同时播放到扬声器和虚拟麦克风（并行播放）</p>
          </div>
        </div>
        
        <!-- 扬声器选择（只在勾选时显示） -->
        <div v-if="playToSpeaker" class="setting-row">
          <div class="setting-item">
            <label class="label">
              <span class="label-text">🔊 扬声器设备</span>
            </label>
            <select v-model="selectedSpeakerDevice" class="select-input" :disabled="isGenerating">
              <option v-for="device in audioDevices" :key="device.name" :value="device.name">
                {{ device.name }}{{ device.isDefault ? ' (默认)' : '' }}
              </option>
            </select>
          </div>
        </div>
      </div>

      <!-- 状态消息 -->
      <div v-if="statusMessage" class="status-message" :class="statusType">
        {{ statusMessage }}
      </div>

      <!-- 发送按钮 -->
      <button
        @click="handleSpeak"
        class="send-btn"
        :class="{ generating: isGenerating }"
        :disabled="isGenerating"
      >
        <span v-if="isGenerating" class="spinner"></span>
        <span v-if="isGenerating">生成中...</span>
        <span v-else>🚀 发送到虚拟麦克风</span>
      </button>

      <!-- 使用提示 -->
      <div class="tips">
        <div class="tip-title">💡 使用提示</div>
        <ul class="tip-list">
          <li>选择 VB-Cable 作为输出设备</li>
          <li>在游戏中将麦克风输入设置为 VB-Cable</li>
          <li>点击发送后，语音会自动播放到虚拟麦克风</li>
          <li>生成时间约 2-4 秒，请耐心等待</li>
        </ul>
      </div>
    </div>
  </div>
</template>

<style scoped>
.container {
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
}

.header {
  text-align: center;
  margin-bottom: 30px;
}

.header h1 {
  font-size: 32px;
  margin: 0 0 10px 0;
  color: #2c3e50;
}

.subtitle {
  color: #7f8c8d;
  font-size: 14px;
  margin: 0;
}

.main-content {
  background: white;
  border-radius: 12px;
  padding: 30px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.1);
}

.input-section {
  margin-bottom: 24px;
}

.label {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
  font-weight: 600;
  color: #2c3e50;
}

.label-text {
  font-size: 14px;
}

.char-count {
  font-size: 12px;
  color: #95a5a6;
  font-weight: normal;
}

.text-input {
  width: 100%;
  padding: 12px;
  border: 2px solid #e0e0e0;
  border-radius: 8px;
  font-size: 14px;
  font-family: inherit;
  resize: vertical;
  transition: border-color 0.3s;
}

.text-input:focus {
  outline: none;
  border-color: #3498db;
}

.text-input:disabled {
  background-color: #f5f5f5;
  cursor: not-allowed;
}

.settings-section {
  margin-bottom: 24px;
}

.setting-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.setting-item {
  display: flex;
  flex-direction: column;
}

.select-input {
  padding: 10px 12px;
  border: 2px solid #e0e0e0;
  border-radius: 8px;
  font-size: 14px;
  background-color: white;
  cursor: pointer;
  transition: border-color 0.3s;
}

.select-input:focus {
  outline: none;
  border-color: #3498db;
}

.select-input:disabled {
  background-color: #f5f5f5;
  cursor: not-allowed;
}

.refresh-btn {
  margin-left: 8px;
  padding: 2px 8px;
  border: none;
  background: none;
  cursor: pointer;
  font-size: 14px;
  transition: transform 0.2s;
}

.refresh-btn:hover:not(:disabled) {
  transform: rotate(180deg);
}

.refresh-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.checkbox-item {
  padding: 16px;
  background-color: #f8f9fa;
  border-radius: 8px;
  border: 2px dashed #dee2e6;
  transition: all 0.3s;
}

.checkbox-item:hover {
  border-color: #667eea;
  background-color: #f0f4ff;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
  user-select: none;
}

.checkbox-input {
  width: 20px;
  height: 20px;
  cursor: pointer;
  accent-color: #667eea;
}

.checkbox-text {
  font-weight: 500;
  color: #2c3e50;
  font-size: 14px;
}

.checkbox-hint {
  margin: 8px 0 0 32px;
  font-size: 12px;
  color: #7f8c8d;
  line-height: 1.5;
}

.status-message {
  padding: 12px 16px;
  border-radius: 8px;
  margin-bottom: 16px;
  font-size: 14px;
  animation: slideIn 0.3s ease-out;
}

@keyframes slideIn {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.status-message.info {
  background-color: #e3f2fd;
  color: #1976d2;
  border-left: 4px solid #2196f3;
}

.status-message.success {
  background-color: #e8f5e9;
  color: #388e3c;
  border-left: 4px solid #4caf50;
}

.status-message.error {
  background-color: #ffebee;
  color: #c62828;
  border-left: 4px solid #f44336;
}

.send-btn {
  width: 100%;
  padding: 16px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
}

.send-btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.send-btn:active:not(:disabled) {
  transform: translateY(0);
}

.send-btn:disabled {
  background: #95a5a6;
  cursor: not-allowed;
  transform: none;
}

.send-btn.generating {
  background: #95a5a6;
}

.spinner {
  width: 16px;
  height: 16px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.tips {
  margin-top: 24px;
  padding: 16px;
  background-color: #f8f9fa;
  border-radius: 8px;
  border-left: 4px solid #3498db;
}

.tip-title {
  font-weight: 600;
  color: #2c3e50;
  margin-bottom: 8px;
  font-size: 14px;
}

.tip-list {
  margin: 0;
  padding-left: 20px;
  color: #5a6c7d;
  font-size: 13px;
  line-height: 1.8;
}

.tip-list li {
  margin-bottom: 4px;
}

@media (max-width: 600px) {
  .setting-row {
    grid-template-columns: 1fr;
  }

  .container {
    padding: 10px;
  }

  .main-content {
    padding: 20px;
  }
}
</style>
