import Foundation
import KvParser
import KivyWidgetRegistry

/// Maps a Figma node tree to a KvModule, then generates a .kv string.
///
/// ## Mapping rules
/// | Figma type              | Kivy output                        |
/// |-------------------------|------------------------------------|
/// | COMPONENT               | `<Name@FloatLayout>:` rule         |
/// | FRAME / GROUP / INSTANCE| `FloatLayout:` widget              |
/// | TEXT                    | `Label:` widget                    |
/// | RECTANGLE / VECTOR      | `Widget:` + canvas Rectangle       |
/// | ELLIPSE                 | `Widget:` + canvas Ellipse         |
///
/// ## Coordinate system
/// Figma uses absolute canvas coordinates (top-left origin).
/// Kivy uses relative-to-parent coordinates (bottom-left origin).
/// Conversion for child inside a parent frame:
///   kv_x = child.x - parent.x
///   kv_y = parent.height - (child.y - parent.y) - child.height
public enum FigmaMapper {

    // MARK: - Public entry

    /// Decode a JSON array of FigmaNode (the plugin's serialised selection)
    /// and return a complete .kv source string.
    public static func convert(json: String) throws -> String {
        let data = Data(json.utf8)
        let nodes = try JSONDecoder().decode([FigmaNode].self, from: data)
        let module = buildModule(from: nodes)
        return KvCodeGen.generate(from: module)
    }

    // MARK: - Module assembly

    private static func buildModule(from nodes: [FigmaNode]) -> KvModule {
        var line = 1
        var rules: [KvRule] = []
        var rootWidgets: [KvWidget] = []

        for node in nodes {
            if node.type == "COMPONENT" {
                rules.append(nodeToRule(node, line: &line))
            } else {
                rootWidgets.append(nodeToWidget(node, parentBounds: nil, line: &line))
            }
        }

        // Single root widget or wrap multiples in a FloatLayout
        let root: KvWidget?
        switch rootWidgets.count {
        case 0:
            root = nil
        case 1:
            root = rootWidgets[0]
        default:
            root = KvWidget(name: "FloatLayout", children: rootWidgets, line: line)
        }

        return KvModule(rules: rules, root: root)
    }

    // MARK: - Rule (COMPONENT)

    private static func nodeToRule(_ node: FigmaNode, line: inout Int) -> KvRule {
        let children = (node.children ?? []).map { child in
            nodeToWidget(child, parentBounds: node.absoluteBoundingBox, line: &line)
        }
        line += 1
        return KvRule(
            selector: .dynamicClass(name: sanitiseName(node.name), bases: ["FloatLayout"]),
            properties: sizeProps(for: node.absoluteBoundingBox, relativeTo: nil, line: &line),
            children: children,
            line: line
        )
    }

    // MARK: - Widget

    private static func nodeToWidget(
        _ node: FigmaNode,
        parentBounds: FigmaBounds?,
        line: inout Int
    ) -> KvWidget {
        line += 1
        let currentLine = line
        let posProps = sizeProps(for: node.absoluteBoundingBox,
                                 relativeTo: parentBounds,
                                 line: &line)

        switch node.type {

        case "TEXT":
            let textProps = textProperties(node: node, line: &line)
            return KvWidget(
                name: "Label",
                properties: posProps + textProps,
                line: currentLine
            )

        case "RECTANGLE", "VECTOR":
            return KvWidget(
                name: "Widget",
                properties: posProps,
                canvas: fillCanvas(node: node, line: &line, shape: "Rectangle"),
                line: currentLine
            )

        case "ELLIPSE":
            return KvWidget(
                name: "Widget",
                properties: posProps,
                canvas: fillCanvas(node: node, line: &line, shape: "Ellipse"),
                line: currentLine
            )

        default:
            // FRAME, GROUP, INSTANCE and anything unknown → FloatLayout
            let children = (node.children ?? []).map { child in
                nodeToWidget(child, parentBounds: node.absoluteBoundingBox, line: &line)
            }
            return KvWidget(
                name: "FloatLayout",
                properties: posProps,
                children: children,
                line: currentLine
            )
        }
    }

    // MARK: - Property helpers

    /// size_hint + size + pos properties from Figma bounds
    private static func sizeProps(
        for bounds: FigmaBounds?,
        relativeTo parent: FigmaBounds?,
        line: inout Int
    ) -> [KvProperty] {
        guard let b = bounds else { return [] }
        var props: [KvProperty] = []
        line += 1

        // Disable stretching so Kivy respects explicit size
        props.append(prop("size_hint", "None, None", line: line))

        let w = Int(b.width.rounded())
        let h = Int(b.height.rounded())
        line += 1
        props.append(prop("size", "\(w), \(h)", line: line))

        if let p = parent {
            let relX = Int((b.x - p.x).rounded())
            // Flip y: Figma top-left → Kivy bottom-left
            let relY = Int((p.height - (b.y - p.y) - b.height).rounded())
            line += 1
            props.append(prop("pos", "\(relX), \(relY)", line: line))
        }

        return props
    }

    /// Label-specific: text, font_size, color
    private static func textProperties(node: FigmaNode, line: inout Int) -> [KvProperty] {
        var props: [KvProperty] = []
        let text = (node.characters ?? "").replacingOccurrences(of: "'", with: "\\'")
        line += 1
        props.append(prop("text", "'\(text)'", line: line))

        if let fs = node.fontSize {
            line += 1
            props.append(prop("font_size", "\(Int(fs.rounded()))sp", line: line))
        }

        if let color = solidColor(from: node.fills) {
            line += 1
            props.append(prop("color", rgbaString(color), line: line))
        }

        return props
    }

    /// Canvas with Color + Rectangle or Ellipse for filled shapes
    private static func fillCanvas(
        node: FigmaNode,
        line: inout Int,
        shape: String
    ) -> KvCanvas? {
        guard let color = solidColor(from: node.fills) else { return nil }
        line += 1
        let colorInstr = KvCanvasInstruction(
            instructionType: "Color",
            properties: [prop("rgba", rgbaString(color), line: line)],
            line: line
        )
        line += 1
        let shapeInstr = KvCanvasInstruction(
            instructionType: shape,
            properties: [
                prop("pos", "self.pos", line: line),
                prop("size", "self.size", line: line + 1),
            ],
            line: line
        )
        line += 1
        return KvCanvas(instructions: [colorInstr, shapeInstr], line: line)
    }

    // MARK: - Utilities

    private static func prop(_ name: String, _ value: String, line: Int) -> KvProperty {
        KvProperty(name: name, value: value, line: line)
    }

    private static func solidColor(from fills: [FigmaFill]?) -> FigmaColor? {
        fills?.first(where: { $0.type == "SOLID" })?.color
    }

    private static func rgbaString(_ c: FigmaColor) -> String {
        String(format: "%.3f, %.3f, %.3f, %.3f", c.r, c.g, c.b, c.a ?? 1.0)
    }

    /// Sanitise a Figma layer name into a valid Kivy class identifier:
    /// strip spaces and special chars, capitalise words.
    private static func sanitiseName(_ name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let camel = words
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        return camel.isEmpty ? "FigmaWidget" : camel
    }
}
