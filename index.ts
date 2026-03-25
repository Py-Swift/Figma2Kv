import { runApplication } from "elementary-ui-browser-runtime";
import appInit from "virtual:swift-wasm?init";

const convertBtn  = document.getElementById("convertBtn")  as HTMLButtonElement;
const liveBtn     = document.getElementById("liveBtn")      as HTMLButtonElement;
const copyBtn     = document.getElementById("copyBtn")      as HTMLButtonElement;
const connectBtn  = document.getElementById("connectBtn")   as HTMLButtonElement;
const serverUrl   = document.getElementById("serverUrl")    as HTMLInputElement;
const output      = document.getElementById("output")       as HTMLDivElement;
const status      = document.getElementById("status")       as HTMLDivElement;

let connected = false;

let liveMode = false;

// ── Resize handles ───────────────────────────────────────────────────────────
const MIN_W = 280, MIN_H = 320;

function attachResize(el: HTMLElement, resizeW: boolean) {
  let resizing = false, startX = 0, startY = 0, startW = 0, startH = 0;
  el.addEventListener("pointerdown", (e) => {
    resizing = true;
    startX = e.clientX; startY = e.clientY;
    startW = window.innerWidth; startH = window.innerHeight;
    el.setPointerCapture(e.pointerId);
    e.preventDefault();
  });
  el.addEventListener("pointermove", (e) => {
    if (!resizing) return;
    const w = resizeW ? Math.max(MIN_W, startW + (e.clientX - startX)) : startW;
    const h = Math.max(MIN_H, startH + (e.clientY - startY));
    parent.postMessage({ pluginMessage: { type: "resize", width: Math.round(w), height: Math.round(h) } }, "*");
  });
  el.addEventListener("pointerup", () => { resizing = false; });
}

attachResize(document.getElementById("resizeHandleRight") as HTMLElement, true);
attachResize(document.getElementById("resizeHandleLeft")  as HTMLElement, false);

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

liveBtn.addEventListener("click", () => {
  liveMode = !liveMode;
  liveBtn.classList.toggle("active", liveMode);
  liveBtn.textContent = liveMode ? "⦿ Live (on)" : "⦿ Live";
  status.textContent = liveMode ? "Live mode on — watching selection…" : "Live mode off.";
  parent.postMessage({ pluginMessage: { type: "setLive", enabled: liveMode } }, "*");
});

copyBtn.addEventListener("click", () => {
  navigator.clipboard.writeText(output.textContent ?? "");
  copyBtn.textContent = "Copied!";
  setTimeout(() => (copyBtn.textContent = "Copy KV"), 1500);
});

connectBtn.addEventListener("click", () => {
  connected = !connected;
  connectBtn.classList.toggle("active", connected);
  connectBtn.textContent = connected ? "Connected" : "Connect";
  status.textContent = connected
    ? "Connected — will auto-send in live mode."
    : "Disconnected.";
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
      const kv = result.kv as string;
      output.textContent = kv;
      copyBtn.style.display = "inline-block";
      status.textContent = liveMode ? "Live — updated." : "Done.";
      if (liveMode && connected) {
        fetch(serverUrl.value.trim(), {
          method: "POST",
          headers: { "Content-Type": "text/plain" },
          body: kv,
        }).catch((e) => { status.textContent = "⚠ Send failed: " + e.message; });
      }
    } else {
      output.textContent = "";
      status.textContent = "Error: " + ((result.error as string) ?? "unknown");
    }
  }
};
