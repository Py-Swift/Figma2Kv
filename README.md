# Figma2Kv

A Figma plugin that converts your Figma node tree into [Kivy](https://kivy.org) `.kv` language, powered by a Swift parser compiled to WebAssembly.

---

## Installation

### Option A — Download the pre-built release (recommended)

1. Go to the [Releases](https://github.com/Py-Swift/Figma2Kv/releases) page and download the latest `Figma2Kv-X.X.X.zip`
2. Unzip it anywhere on your machine
3. Open the **Figma desktop app** and open any file
4. Press `Cmd+/` (Mac) or `Ctrl+/` (Windows) to open Quick Actions
5. Search for **"Import plugin from manifest"** and select it
6. Navigate to the unzipped folder and select `manifest.json`
7. The plugin now appears under **Plugins → Figma2Kv**

### Option B — Build from source

Requirements:
- macOS with [swiftly](https://github.com/swiftlang/swiftly) installed
- Node.js 22+
- LLVM (`brew install llvm`)

```bash
# Clone
git clone https://github.com/Py-Swift/Figma2Kv.git
cd Figma2Kv

# Install npm deps
npm install

# Install Swift 6.2.1 and the WASM SDK
swiftly install 6.2.1 --use
swift sdk install \
  https://github.com/swiftwasm/swift/releases/download/swift-6.2.1-RELEASE/swift-6.2.1-RELEASE_wasm32-unknown-wasi.artifactbundle.zip

# Build
npm run build
```

Then follow steps 3–7 from Option A, pointing at the `manifest.json` in this folder.

---

## Usage

1. Select one or more nodes on the Figma canvas
2. Open the plugin (**Plugins → Figma2Kv**)
3. Click **Convert selection** — the `.kv` output appears in the panel
4. Click **Copy KV** to copy it to your clipboard

### Live mode

Click **⦿ Live** to enable live mode. The output will automatically update every time you click a different node on the canvas — no need to press Convert each time.

### Resizing the panel

- Drag the **bottom-right** corner to resize width and height
- Drag the **bottom-left** corner to resize height only

---

## Development

```bash
npm run build        # full build (Swift WASM + Vite + tsc + inline)
npm run build:code   # recompile code.ts only (no WASM rebuild)
```

To release a new version, push a plain semver tag:

```bash
git tag 0.1.0 && git push origin 0.1.0
```

GitHub Actions will build on `macos-15`, produce `Figma2Kv-0.1.0.zip`, and attach it to the release automatically.

