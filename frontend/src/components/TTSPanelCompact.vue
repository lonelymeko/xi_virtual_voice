<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { GetAudioDevices, GetAvailableVoices, GetAvailableLanguages, SpeakWithPreview } from '../../wailsjs/go/main/App'
import { WindowSetAlwaysOnTop } from '../../wailsjs/runtime/runtime'

interface AudioDevice {
  name: string
  isDefault: boolean
}

interface Voice {
  value: string
  label: string
}

interface Language {
  value: string
  label: string
}

interface TTSResponse {
  success: boolean
  message: string
  error?: string
}

// 状态
const text = ref('')
const selectedVoice = ref('Cherry')
const selectedLanguage = ref('Auto')
const selectedMicDevice = ref('')
const selectedSpeakerDevice = ref('')
const playToSpeaker = ref(false)
const isAlwaysOnTop = ref(false)
const audioDevices = ref<AudioDevice[]>([])
const voices = ref<Voice[]>([])
const languages = ref<Language[]>([])
const isGenerating = ref(false)
const statusMessage = ref('')
const statusType = ref<'success' | 'error' | 'info'>('info')

// 切换置顶
const toggleAlwaysOnTop = async () => {
  isAlwaysOnTop.value = !isAlwaysOnTop.value
  await WindowSetAlwaysOnTop(isAlwaysOnTop.value)
  showStatus(isAlwaysOnTop.value ? '📌 已置顶' : '📌 取消置顶', 'info')
}

// 显示状态
const showStatus = (msg: string, type: 'success' | 'error' | 'info') => {
  statusMessage.value = msg
  statusType.value = type
  setTimeout(() => { statusMessage.value = '' }, 2000)
}

// 加载设备
const loadDevices = async () => {
  try {
    const devices = await GetAudioDevices()
    audioDevices.value = devices.map((d: any) => ({
      name: d.name,
      isDefault: d.isDefault
    }))
    
    const vbCable = audioDevices.value.find((d: AudioDevice) => 
      d.name.includes('VB-Cable') || d.name.includes('CABLE')
    )
    if (vbCable) {
      selectedMicDevice.value = vbCable.name
    }
    
    const defaultSpeaker = audioDevices.value.find((d: AudioDevice) => d.isDefault)
    if (defaultSpeaker) {
      selectedSpeakerDevice.value = defaultSpeaker.name
    }
  } catch (error: any) {
    showStatus(`❌ ${error}`, 'error')
  }
}

// 加载音色
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

// 加载语言
const loadLanguages = async () => {
  try {
    const languageList = await GetAvailableLanguages()
    languages.value = languageList.map((l: Record<string, string>) => ({
      value: l.value,
      label: l.label
    }))
  } catch (error: any) {
    console.error('加载语言失败:', error)
  }
}

// 发送语音
const handleSpeak = async () => {
  if (!text.value.trim()) {
    showStatus('❌ 请输入文本', 'error')
    return
  }

  if (!selectedMicDevice.value) {
    showStatus('❌ 请选择虚拟麦克风', 'error')
    return
  }

  isGenerating.value = true
  statusMessage.value = '🎤 生成中...'
  statusType.value = 'info'

  try {
    // SpeakWithPreview 参数: text, voice, micDevice, speakerDevice, language, playToSpeaker
    const response: TTSResponse = await SpeakWithPreview(
      text.value,
      selectedVoice.value,
      selectedMicDevice.value,
      selectedSpeakerDevice.value,  // 扬声器设备
      selectedLanguage.value,       // 语言
      playToSpeaker.value            // 是否播放到扬声器
    )

    if (response.success) {
      showStatus('✅ ' + response.message, 'success')
    } else {
      showStatus('❌ ' + (response.error || '失败'), 'error')
    }
  } catch (error: any) {
    showStatus(`❌ ${error}`, 'error')
  } finally {
    isGenerating.value = false
  }
}

onMounted(() => {
  loadDevices()
  loadVoices()
  loadLanguages()
})
</script>

<template>
  <div class="app">
    <!-- 标题栏 -->
    <div class="titlebar">
      <div class="title">🎙️ TTS 工具</div>
      <button 
        @click="toggleAlwaysOnTop" 
        class="pin-btn"
        :class="{ active: isAlwaysOnTop }"
        title="窗口置顶"
      >
        📌
      </button>
    </div>

    <!-- 主内容 -->
    <div class="content">
      <!-- 文本输入 -->
      <textarea
        v-model="text"
        class="textarea"
        placeholder="输入文本..."
        rows="3"
        :disabled="isGenerating"
      ></textarea>

      <!-- 设置行1 -->
      <div class="row">
        <div class="field">
          <label>音色</label>
          <select v-model="selectedVoice" :disabled="isGenerating">
            <option v-for="v in voices" :key="v.value" :value="v.value">
              {{ v.label.split('-')[0].trim() }}
            </option>
          </select>
        </div>

        <div class="field">
          <label>语言</label>
          <select v-model="selectedLanguage" :disabled="isGenerating">
            <option v-for="l in languages" :key="l.value" :value="l.value">
              {{ l.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- 设置行2 -->
      <div class="row">
        <div class="field full">
          <label>虚拟麦克风</label>
          <select v-model="selectedMicDevice" :disabled="isGenerating">
            <option v-for="d in audioDevices" :key="d.name" :value="d.name">
              {{ d.name.substring(0, 35) }}{{ d.name.length > 35 ? '...' : '' }}
            </option>
          </select>
        </div>
      </div>

      <!-- 设置行3 -->
      <div class="row">
        <label class="checkbox">
          <input type="checkbox" v-model="playToSpeaker" :disabled="isGenerating" />
          <span>先播放到扬声器（预览）</span>
        </label>
      </div>

      <!-- 扬声器选择 -->
      <div v-if="playToSpeaker" class="row">
        <div class="field full">
          <label>扬声器</label>
          <select v-model="selectedSpeakerDevice" :disabled="isGenerating">
            <option v-for="d in audioDevices" :key="d.name" :value="d.name">
              {{ d.name.substring(0, 30) }}{{ d.name.length > 30 ? '...' : '' }}
            </option>
          </select>
        </div>
      </div>

      <!-- 状态 -->
      <div v-if="statusMessage" class="status" :class="statusType">
        {{ statusMessage }}
      </div>

      <!-- 提示信息 -->
      <!-- <div class="hint">
        提示：请先手动创建混合虚拟麦克风+播放器<br/>
        否则在推流到麦克风会静音系统扬声器哦
      </div> -->

      <!-- 发送按钮 -->
      <button
        @click="handleSpeak"
        class="btn-send"
        :disabled="isGenerating"
      >
        <span v-if="isGenerating">⏳ 生成中...</span>
        <span v-else>🚀 发送</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.app {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #f5f5f5;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  font-size: 13px;
}

.titlebar {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 8px 12px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  user-select: none;
  cursor: move;
  --wails-draggable: drag;
  position: relative;
}

.title {
  flex: 1;
  text-align: center;
  font-size: 14px;
  font-weight: 600;
}

.pin-btn {
  position: absolute;
  right: 12px;
  -webkit-app-region: no-drag;
  background: rgba(255, 255, 255, 0.2);
  border: none;
  border-radius: 4px;
  padding: 4px 8px;
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s;
}

.pin-btn:hover {
  background: rgba(255, 255, 255, 0.3);
}

.pin-btn.active {
  background: rgba(255, 255, 255, 0.4);
  box-shadow: 0 0 8px rgba(255, 255, 255, 0.5);
}

.content {
  flex: 1;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  overflow-y: auto;
}

.textarea {
  width: 100%;
  padding: 8px;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 13px;
  font-family: inherit;
  resize: vertical;
  min-height: 60px;
}

.textarea:focus {
  outline: none;
  border-color: #667eea;
}

.row {
  display: flex;
  gap: 8px;
  align-items: flex-end;
}

.field {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.field.full {
  flex: 1;
}

.field label {
  font-size: 11px;
  color: #666;
  font-weight: 500;
}

select {
  padding: 6px 8px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 12px;
  background: white;
  cursor: pointer;
}

select:focus {
  outline: none;
  border-color: #667eea;
}

select:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.checkbox {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px;
  background: white;
  border-radius: 6px;
  cursor: pointer;
  user-select: none;
}

.checkbox input {
  width: 16px;
  height: 16px;
  cursor: pointer;
}

.checkbox span {
  font-size: 12px;
  color: #333;
}

.hint {
  padding: 8px;
  background: #fff3cd;
  border: 1px solid #ffc107;
  border-radius: 6px;
  font-size: 11px;
  line-height: 1.4;
  color: #856404;
  margin-top: 8px;
}

.status {
  padding: 8px;
  border-radius: 6px;
  font-size: 12px;
  text-align: center;
  animation: slideIn 0.3s;
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

.status.info {
  background: #e3f2fd;
  color: #1976d2;
}

.status.success {
  background: #e8f5e9;
  color: #388e3c;
}

.status.error {
  background: #ffebee;
  color: #c62828;
}

.btn-send {
  width: 100%;
  padding: 10px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-send:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.btn-send:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>
