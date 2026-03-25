// Figma plugin sandbox — runs in Figma's main thread.
// Serialises the current selection and sends it to the UI iframe.

figma.showUI(__html__, { width: 420, height: 540 });

// Helper: recursively serialise a SceneNode to a plain object
function serialise(node: SceneNode): object {
  const base: Record<string, unknown> = {
    type: node.type,
    name: node.name,
  };

  if ("absoluteBoundingBox" in node && node.absoluteBoundingBox) {
    base.absoluteBoundingBox = node.absoluteBoundingBox;
  }

  if ("fills" in node && Array.isArray(node.fills)) {
    base.fills = (node.fills as readonly Paint[]).map((f) => {
      if (f.type === "SOLID") {
        return { type: f.type, color: f.color, opacity: f.opacity ?? 1 };
      }
      return { type: f.type };
    });
  }

  if ("characters" in node) base.characters = node.characters;
  if ("fontSize" in node) base.fontSize = node.fontSize;

  if ("children" in node) {
    base.children = (node as ChildrenMixin).children.map(serialise);
  }

  return base;
}

function sendSelection() {
  const selection = figma.currentPage.selection;
  const nodes =
    selection.length > 0
      ? selection
      : (figma.currentPage.children as SceneNode[]);

  if (nodes.length === 0) {
    figma.ui.postMessage({ type: "error", message: "Nothing selected." });
    return;
  }

  const serialised = nodes.map(serialise);
  figma.ui.postMessage({
    type: "figmaNodes",
    data: JSON.stringify(serialised),
  });
}

let liveHandler: (() => void) | null = null;

figma.ui.onmessage = (msg) => {
  if (msg.type === "convert") {
    sendSelection();
    return;
  }

  if (msg.type === "setLive") {
    if (msg.enabled) {
      if (!liveHandler) {
        liveHandler = () => sendSelection();
        figma.on("selectionchange", liveHandler);
      }
      // Send current selection immediately when live mode is turned on
      sendSelection();
    } else {
      if (liveHandler) {
        figma.off("selectionchange", liveHandler);
        liveHandler = null;
      }
    }
  }
};
