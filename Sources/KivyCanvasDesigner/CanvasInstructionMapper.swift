import Foundation
import FigmaApi

// MARK: - Mapper

enum CanvasInstructionMapper {

    // MARK: - Public entry

    /// Maps a flat list of Figma nodes to canvas-instruction frame IRs.
    /// Each top-level FRAME, COMPONENT, or INSTANCE becomes one `CanvasFrameIR`.
    /// A top-level CANVAS/PAGE node is unwrapped one level so its children are processed.
    static func map(nodes: [FigmaNode]) -> [CanvasFrameIR] {
        var result: [CanvasFrameIR] = []
        for node in nodes {
            switch node.type {
            case .canvas, .page:
                for child in node.children ?? [] {
                    if let ir = frameToIR(child) { result.append(ir) }
                }
            default:
                if let ir = frameToIR(node) { result.append(ir) }
            }
        }
        return result
    }

    // MARK: - Frame → IR

    private static func frameToIR(_ node: FigmaNode) -> CanvasFrameIR? {
        // Accept frames/components/instances as normal containers.
        // Also accept groups if they are themselves named as a canvas layer
        // (i.e. the user locked/sent <canvas> directly).
        let selfIsCanvasLayer = canvasTarget(for: node.name) != nil
        switch node.type {
        case .frame, .component, .instance:
            break
        case .group where selfIsCanvasLayer:
            break
        default:
            return nil
        }

        let className = sanitiseName(node.name)
        let b = node.absoluteBoundingBox
        let w = Int((b?.width ?? 0).rounded())
        let h = Int((b?.height ?? 0).rounded())
        let layers = canvasLayersFor(node, parentBounds: b)
        return CanvasFrameIR(className: className, width: w, height: h, layers: layers)
    }

    // MARK: - Canvas layer detection

    /// Parses a Figma layer name into a `CanvasTarget` if it is a canvas sentinel name.
    /// Recognised names (case-insensitive):
    ///   `<canvas>`          → .before  (default)
    ///   `<canvas.before>`   → .before
    ///   `<canvas.after>`    → .after
    ///   `</canvas>`         → .after
    ///   `<canvas.main>`     → .main
    private static func canvasTarget(for name: String) -> CanvasTarget? {
        switch name.lowercased() {
        case "<canvas>", "<canvas.before>":
            return .before
        case "<canvas.after>", "</canvas>":
            return .after
        case "<canvas.main>":
            return .main
        default:
            return nil
        }
    }

    /// Derives the canvas layers for a frame node.
    ///
    /// - If the node itself is a canvas-layer sentinel (`<canvas>` etc.) → single layer
    ///   using the node's own children.
    /// - If any direct children are canvas-layer sentinels → one layer per named child.
    /// - Fallback → all shapes collected recursively → single `.before` layer.
    private static func canvasLayersFor(
        _ node: FigmaNode,
        parentBounds: FigmaBounds?
    ) -> [CanvasLayerIR] {
        // Case 1: the node itself is a canvas sentinel (user locked/sent it directly).
        if let target = canvasTarget(for: node.name) {
            let items = collectItems(node.children ?? [], parentBounds: parentBounds)
            return [CanvasLayerIR(target: target, items: items)]
        }

        // Case 2: look for named canvas children.
        let namedLayers: [CanvasLayerIR] = (node.children ?? []).compactMap { child in
            guard let target = canvasTarget(for: child.name) else { return nil }
            let items = collectItems(child.children ?? [], parentBounds: parentBounds)
            return CanvasLayerIR(target: target, items: items)
        }
        if !namedLayers.isEmpty { return namedLayers }

        // Case 3: fallback — collect all items and put them in canvas.before.
        let items = collectItems(node.children ?? [], parentBounds: parentBounds)
        return [CanvasLayerIR(target: .before, items: items)]
    }

    // MARK: - Item collection (recursive)

    private static func collectItems(
        _ children: [FigmaNode],
        parentBounds: FigmaBounds?
    ) -> [CanvasItem] {
        var items: [CanvasItem] = []
        for child in children {
            guard child.isVisible else { continue }
            switch child.type {
            case .rectangle, .vector:
                let radii = cornerRadii(for: child)
                let kind: CanvasShapeKind = radii != nil ? .roundedRectangle : .rectangle
                if let ir = shapeToIR(child, kind: kind, cornerRadii: radii, parentBounds: parentBounds) {
                    items.append(.shape(ir))
                }
            case .ellipse:
                if let ir = shapeToIR(child, kind: .ellipse, cornerRadii: nil, parentBounds: parentBounds) {
                    items.append(.shape(ir))
                }
            case .polygon, .regularPolygon:
                if let ir = shapeToIR(child, kind: .triangle, cornerRadii: nil, parentBounds: parentBounds) {
                    items.append(.shape(ir))
                }
            case .group:
                if canvasTarget(for: child.name) != nil {
                    // Canvas sentinel: inline its children rather than creating a group.
                    items.append(contentsOf: collectItems(child.children ?? [], parentBounds: parentBounds))
                } else {
                    // Named Figma GROUP → InstructionGroup subclass.
                    let groupItems = collectItems(child.children ?? [], parentBounds: parentBounds)
                    if !groupItems.isEmpty {
                        items.append(.group(CanvasGroupIR(
                            className: sanitiseName(child.name),
                            items: groupItems,
                            frameWidth:  Int((parentBounds?.width  ?? 0).rounded()),
                            frameHeight: Int((parentBounds?.height ?? 0).rounded())
                        )))
                    }
                }
            case .frame, .instance, .component:
                // Frames are Figma arrangement containers — flatten their children inline.
                items.append(contentsOf: collectItems(child.children ?? [], parentBounds: parentBounds))
            default:
                break
            }
        }
        return items
    }

    // MARK: - Single shape → IR

    private static func shapeToIR(
        _ node: FigmaNode,
        kind: CanvasShapeKind,
        cornerRadii: [Double]?,
        parentBounds: FigmaBounds?
    ) -> CanvasShapeIR? {
        guard let (color, paintOpacity) = solidColorAndOpacity(from: node.fills),
              let b = node.absoluteBoundingBox else { return nil }
        let nodeOpacity = node.effectiveOpacity

        let x: Int
        let y: Int
        if let p = parentBounds {
            x = Int((b.x - p.x).rounded())
            // y-flip: Figma top-left origin → Kivy bottom-left origin
            y = Int((p.height - (b.y - p.y) - b.height).rounded())
        } else {
            x = Int(b.x.rounded())
            y = Int(b.y.rounded())
        }
        let w = Int(b.width.rounded())
        let h = Int(b.height.rounded())

        let finalAlpha = color.alpha * paintOpacity * nodeOpacity
        return CanvasShapeIR(
            kind: kind,
            x: x, y: y, width: w, height: h,
            r: color.r, g: color.g, b: color.b, a: finalAlpha,
            cornerRadii: cornerRadii
        )
    }

    /// Returns per-corner radii [tl, tr, br, bl] if the node has any non-zero corner,
    /// otherwise `nil`.
    private static func cornerRadii(for node: FigmaNode) -> [Double]? {
        let radii: [Double]
        if let perCorner = node.rectangleCornerRadii, perCorner.count == 4 {
            radii = perCorner
        } else if let uniform = node.cornerRadius, uniform > 0 {
            radii = [uniform, uniform, uniform, uniform]
        } else {
            return nil
        }
        return radii.contains(where: { $0 > 0 }) ? radii : nil
    }

    // MARK: - Helpers

    private static func solidColorAndOpacity(from fills: [FigmaPaint]?) -> (FigmaColor, Double)? {
        guard let paint = fills?.first(where: { $0.type == .solid && $0.visible != false }),
              let color = paint.color else { return nil }
        return (color, paint.effectiveOpacity)
    }

    static func sanitiseName(_ name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let camel = words
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        return camel.isEmpty ? "FigmaWidget" : camel
    }
}

