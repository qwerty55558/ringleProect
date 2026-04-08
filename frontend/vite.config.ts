/// <reference types="vitest/config" />
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { copyFileSync, createReadStream, existsSync, mkdirSync, statSync } from 'node:fs'
import { dirname, extname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

// vad-web depends on Silero ONNX models + an AudioWorklet + the ORT WASM
// runtime. CDN delivery of these is flaky (jsdelivr occasionally 404s the
// .onnx files), so we copy them out of node_modules into public/vad/ at
// dev / build start. The conversation page references them via /vad/.
//
// Two complications worth knowing about:
//   1. ORT ships .mjs files; vite's dev server tries to transform anything
//      it considers an ES module, including files inside public/, and 500s
//      on these. We bypass that with a tiny static middleware below.
//   2. Both are also needed at production build time, so we copy on
//      `buildStart` as well.
const VAD_ASSETS: Array<[string, string]> = [
  ['node_modules/@ricky0123/vad-web/dist/silero_vad_legacy.onnx', 'silero_vad_legacy.onnx'],
  ['node_modules/@ricky0123/vad-web/dist/silero_vad_v5.onnx',     'silero_vad_v5.onnx'],
  ['node_modules/@ricky0123/vad-web/dist/vad.worklet.bundle.min.js', 'vad.worklet.bundle.min.js'],
  ['node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.wasm',      'ort-wasm-simd-threaded.wasm'],
  ['node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.mjs',       'ort-wasm-simd-threaded.mjs'],
  ['node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.jsep.wasm', 'ort-wasm-simd-threaded.jsep.wasm'],
  ['node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.jsep.mjs',  'ort-wasm-simd-threaded.jsep.mjs'],
]

const MIME_BY_EXT: Record<string, string> = {
  '.wasm': 'application/wasm',
  '.mjs':  'text/javascript; charset=utf-8',
  '.js':   'text/javascript; charset=utf-8',
  '.onnx': 'application/octet-stream',
}

function copyVadAssets(): void {
  const out = resolve(__dirname, 'public/vad')
  if (!existsSync(out)) mkdirSync(out, { recursive: true })
  for (const [src, dest] of VAD_ASSETS) {
    const abs = resolve(__dirname, src)
    if (existsSync(abs)) copyFileSync(abs, resolve(out, dest))
  }
}

function vadAssetsPlugin() {
  return {
    name: 'vad-assets',
    buildStart() { copyVadAssets() },
    configureServer(server: import('vite').ViteDevServer) {
      copyVadAssets()
      // Custom static handler for /vad/* that bypasses vite's module
      // transform pipeline (which can't deal with bare .mjs ES modules
      // referenced from inside public/).
      server.middlewares.use((req, res, next) => {
        if (!req.url || !req.url.startsWith('/vad/')) return next()
        const cleanPath = req.url.split('?')[0]
        const file = resolve(__dirname, 'public', cleanPath.replace(/^\//, ''))
        if (!file.startsWith(resolve(__dirname, 'public/vad'))) return next()
        if (!existsSync(file) || !statSync(file).isFile()) return next()
        const ext = extname(file).toLowerCase()
        res.setHeader('Content-Type', MIME_BY_EXT[ext] ?? 'application/octet-stream')
        res.setHeader('Cache-Control', 'public, max-age=31536000')
        createReadStream(file).pipe(res)
      })
    },
  }
}

export default defineConfig({
  plugins: [react(), vadAssetsPlugin()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    css: false,
  },
})
