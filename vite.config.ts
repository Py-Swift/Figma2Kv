import { defineConfig } from "vite";
import swiftWasm from "@elementary-swift/vite-plugin-swift-wasm";
import os from "node:os";

// Use LLVM clang so C targets (swift-numerics etc) compile for wasm32
process.env.CC ??= "/usr/local/opt/llvm/bin/clang";
process.env.AR ??= "/usr/local/opt/llvm/bin/llvm-ar";
// Prepend swiftly's bin so the plugin uses swiftly's swift (reads .swift-version → 6.2.1)
process.env.PATH = `${os.homedir()}/.swiftly/bin:${process.env.PATH}`;

export default defineConfig({
  base: "./",
  plugins: [
    swiftWasm({
      useEmbeddedSDK: false,
    }),
  ],
  build: {
    outDir: "dist",
    rollupOptions: {
      input: {
        ui: "index.html",
      },
    },
  },
});
