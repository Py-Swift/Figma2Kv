import { runApplication } from "elementary-ui-browser-runtime";
import appInit from "virtual:swift-wasm?init";

const convertBtn = document.getElementById("convertBtn") as HTMLButtonElement;
const liveBtn   = document.getElementById("liveBtn")   as HTMLButtonElement;
const copyBtn   = document.getElementById("copyBtn")   as HTMLButtonElement;
const output    = document.getElementById("output")    as HTMLDivElement;
const status    = document.getElementById("status")    as HTMLDivElement;

let liveMode = false;

// ── Resize handles ───────────────────────────────────────────────────────────
const MIN_W = 280, MIN_H = 320;

function attachResize(el: HTMLElement, invertX: boolean) {
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
    const dx = invertX ? -(e.clientX - startX) : (e.clientX - startX);
    const w = Math.max(MIN_W, startW + dx);
    const h = Math.max(MIN_H, startH + (e.clientY - startY));
    parent.postMessage({ pluginMessage: { type: "resize", width: Math.round(w), height: Math.round(h) } }, "*");
  });
  el.addEventListener("pointerup", () => { resizing = false; });
}

attachResize(document.getElementById("resizeHandleRight") as HTMLElement, false);
attachResize(document.getElementById("resizeHandleLeft")  as HTMLElement, true);

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
      status.textContent = liveMode ? "Live — updated." : "Done.";
    } else {
      output.textContent = "";
      status.textContent = "Error: " + ((result.error as string) ?? "unknown");
    }
  }
};
