import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// FiveM loads the UI from nui://pls_mechanic/web/dist/index.html -> relative asset paths
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    emptyOutDir: true,
    target: 'chrome87',
    cssTarget: 'chrome87',
    chunkSizeWarningLimit: 1500,
  },
  server: {
    port: 5173,
    // dev switcher reads ../locales/_src/ui.json
    fs: { allow: ['..'] },
  },
})
