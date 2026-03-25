import { runApplication } from "elementary-ui-browser-runtime";
import appInit from "virtual:swift-wasm?init";

const convertBtn = document.getElementById("convertBtn") as HTMLButtonElement;
const copyBtn = document.getElementById("copyBtn") as HTMLButtonElement;
const output = document.getElementById("output") as HTMLDivElement;
const status = document.getElementById("status") as HTMLDivElement;

// Initialise the WASM reactor — runs Swift main.swift which exposes globalThis.figma2kv
try {
  console.log("[figma2kv] Starting WASM init...");
  await runApplication(appInit);
  console.log("[figma2kv] WASM ready, figma2kv =", (globalThis as any).figma2kv);
  status.textContent = "Ready.";
} catch (e) {
  console.error("[figma2kv] WASM init failed:", e);
  status.textContent = "⚠ WASM init failed: " + e;
}

convertBtn.addEventListener("click", () => {
  status.textContent = "Converting…";
  copyBtn.style.display = "none";
  parent.postMessage({ pluginMessage: { type: "convert" } }, "*");
});

copyBtn.addEventListener("click", () => {
  navigator.clipboard.writeText(output.textContent ?? "");
  copyBtn.textContent = "Copied!";
  setTimeout(() => (copyBtn.textContent = "Copy KV"), 1500);
});

window.onmessage = (event: MessageEvent) => {
  const msg = event.data?.pluginMessage;
  if (!msg) return;

  if (msg.type === "error") {
    output.textContent = "";
    status.textContent = "⚠ " + msg.message;
    return;
  }

  if (msg.type === "figmaNodes") {
    const api = (globalThis as any).figma2kv;
    if (!api) {
      status.textContent = "⚠ WASM not ready";
      return;
    }
    const result = api.convert(msg.data as string);
    if (result.kv) {
      output.textContent = result.kv as string;
      copyBtn.style.display = "inline-block";
      status.textContent = "Done.";
    } else {
      output.textContent = "";
      status.textContent = "Error: " + ((result.error as string) ?? "unknown");
    }
  }
};
