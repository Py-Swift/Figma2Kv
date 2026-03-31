import Foundation

// MARK: - Smooth options

/// Controls which shape kinds use their anti-aliased Kivy variants.
public struct SmoothOptions: Sendable {
    /// `Rectangle` → `SmoothRectangle` when `true` (default: `false`).
    public var rectangle: Bool
    /// `RoundedRectangle` → `SmoothRoundedRectangle` when `true` (default: `true`).
    public var roundedRectangle: Bool
    /// `Ellipse` → `SmoothEllipse` when `true` (default: `true`).
    public var ellipse: Bool
    /// `Triangle` → `SmoothTriangle` when `true` (default: `true`).
    public var triangle: Bool
    /// `Line` → `SmoothLine` when `true` (default: `true`).
    public var line: Bool

    public init(rectangle: Bool = false, roundedRectangle: Bool = true, ellipse: Bool = true, triangle: Bool = true, line: Bool = true) {
        self.rectangle        = rectangle
        self.roundedRectangle = roundedRectangle
        self.ellipse          = ellipse
        self.triangle         = triangle
        self.line             = line
    }
}

// MARK: - Shape IR

public enum CanvasShapeKind {
    case rectangle
    case roundedRectangle
    case ellipse
    case triangle
}

public struct CanvasShapeIR {
    public let kind: CanvasShapeKind
    /// Position relative to the parent frame, y-flipped to Kivy's bottom-left origin.
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    // RGBA fill (0.0 – 1.0)
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double
    /// Per-corner radii [top-left, top-right, bottom-right, bottom-left] in pixels.
    /// Non-nil only when `kind == .roundedRectangle`.
    public let cornerRadii: [Double]?
}

// MARK: - Canvas target

/// Which Kivy canvas layer the shapes belong to.
public enum CanvasTarget {
    case before   // self.canvas.before  (default)
    case after    // self.canvas.after
    case main     // self.canvas
}

// MARK: - Item tree (shapes + nested groups)

/// A canvas renderable: either a leaf shape or a nested InstructionGroup.
public indirect enum CanvasItem {
    case shape(CanvasShapeIR)
    case group(CanvasGroupIR)
}

/// A named Kivy `InstructionGroup` emitted as its own Python class.
public struct CanvasGroupIR {
    public let className: String
    public let items: [CanvasItem]
    /// Dimensions of the top-level frame this group belongs to.
    /// Used in scalable mode to compute positional percentages.
    public let frameWidth: Int
    public let frameHeight: Int
}

/// One named canvas layer with its items.
public struct CanvasLayerIR {
    public let target: CanvasTarget
    public let items: [CanvasItem]
}

// MARK: - Frame IR

/// Intermediate representation of one Figma frame / component as a canvas-instruction widget.
public struct CanvasFrameIR {
    /// PascalCase Python class name (sanitised from the Figma layer name).
    public let className: String
    public let width: Int
    public let height: Int
    /// One entry per `<canvas.before>` / `<canvas.after>` / `<canvas>` layer found.
    public let layers: [CanvasLayerIR]
}
