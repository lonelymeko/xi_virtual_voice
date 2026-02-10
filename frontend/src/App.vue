<script lang="ts" setup>
import TTSPanelCompact from './components/TTSPanelCompact.vue'
</script>

<template>
  <div class="app">
    <TTSPanelCompact />
  </div>
</template>

<style>
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  background: #f5f5f5;
  min-height: 100vh;
  overflow: hidden;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
}

.app {
  min-height: 100vh;
  display: flex;
}

</style>
