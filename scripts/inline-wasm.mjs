#!/usr/bin/env node
// Post-build script for Figma plugin:
//
// Step 1 — Inline WASM as base64 data URI into the JS bundle.
//   Figma's sandboxed iframe blocks fetch(), so we can't load the .wasm file
//   via URL. Vite's ?init helper already handles data: URIs by decoding base64
//   and calling WebAssembly.instantiate(bytes) directly.
//
// Step 2 — Inline the entire JS bundle into index.html as a <script> block.
//   Figma loads plugin UI HTML via document.write() into a data:text/html iframe,
//   which has no base URL. This means <script src="./assets/ui-*.js"> can never
//   resolve — the script silently never loads. We must make index.html fully
//   self-contained.

import { readFileSync, writeFileSync, readdirSync } from 'fs'
import { join } from 'path'

const distDir   = new URL('../dist', import.meta.url).pathname
const assetsDir = join(distDir, 'assets')
const files     = readdirSync(assetsDir)

const wasmFile = files.find(f => f.endsWith('.wasm'))
const jsFile   = files.find(f => f.endsWith('.js'))

if (!wasmFile || !jsFile) {
  console.error('[inline] ERROR: could not find .wasm or .js in dist/assets/')
  process.exit(1)
}

const wasmPath = join(assetsDir, wasmFile)
const jsPath   = join(assetsDir, jsFile)

// ── Step 1: inline WASM ──────────────────────────────────────────────────────
console.log(`[inline] Reading ${wasmFile} …`)
const wasmBytes  = readFileSync(wasmPath)
const wasmBase64 = wasmBytes.toString('base64')
const dataUri    = `data:application/wasm;base64,${wasmBase64}`
console.log(`[inline] WASM size: ${(wasmBytes.length / 1024 / 1024).toFixed(1)} MB`)

let js = readFileSync(jsPath, 'utf8')

// Pattern Vite emits: ``+new URL(`Figma2Kv-<hash>.wasm`,import.meta.url).href
js = js.replace(
  /``\s*\+\s*new URL\(`[^`]*\.wasm`\s*,\s*import\.meta\.url\)\.href/g,
  `"${dataUri}"`
)
// Fallback without leading template literal
js = js.replace(
  /new URL\(`[^`]*\.wasm`\s*,\s*import\.meta\.url\)\.href/g,
  `"${dataUri}"`
)

if (!js.includes(dataUri)) {
  console.error('[inline] ERROR: could not find WASM URL pattern in JS bundle')
  process.exit(1)
}

writeFileSync(jsPath, js)
console.log(`[inline] WASM inlined into ${jsFile}`)

// ── Step 2: inline JS into index.html ────────────────────────────────────────
const htmlPath = join(distDir, 'index.html')
let html = readFileSync(htmlPath, 'utf8')

// Vite emits something like:
//   <script type="module" crossorigin src="./assets/ui-<hash>.js"></script>
// and sometimes a modulepreload link for it. Remove both and replace with inline script.
html = html.replace(
  /<link[^>]+modulepreload[^>]*>/gi,
  ''
)
html = html.replace(
  /<script\s[^>]*\bsrc=["'][^"']*assets\/[^"']*\.js["'][^>]*><\/script>/gi,
  `<script type="module">\n${js}\n</script>`
)

writeFileSync(htmlPath, html)
console.log(`[inline] JS inlined into index.html — done.`)
console.log(`[inline] Final index.html size: ${(readFileSync(htmlPath).length / 1024 / 1024).toFixed(1)} MB`)
