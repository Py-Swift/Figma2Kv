/// Figma node types the plugin serialises and sends to WASM
///
/// Only the subset of Figma's API shape we need for KV mapping.
/// The plugin walks the scene tree and produces JSON matching these types.

// MARK: - Root payload

/// Top-level array sent from the plugin: one entry per selected node
typealias FigmaSelection = [FigmaNode]

// MARK: - Node

public struct FigmaNode: Codable, Sendable {
    /// Figma node type: FRAME, GROUP, COMPONENT, INSTANCE, TEXT,
    /// RECTANGLE, ELLIPSE, VECTOR, etc.
    public let type: String

    /// Layer name as shown in the Figma layers panel
    public let name: String

    /// Absolute position + size on the canvas
    public let absoluteBoundingBox: FigmaBounds?

    /// Fill paints applied to this node
    public let fills: [FigmaFill]?

    /// Text content (TEXT nodes only)
    public let characters: String?

    /// Font size in points (TEXT nodes only)
    public let fontSize: Double?

    /// Child nodes (FRAME, GROUP, COMPONENT, INSTANCE)
    public let children: [FigmaNode]?
}

// MARK: - Bounds

public struct FigmaBounds: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

// MARK: - Fill

public struct FigmaFill: Codable, Sendable {
    /// Paint type: SOLID, GRADIENT_LINEAR, IMAGE, etc.
    public let type: String

    /// RGBA colour (present for SOLID fills)
    public let color: FigmaColor?

    /// Overall opacity of the fill layer (0-1, defaults to 1)
    public let opacity: Double?
}

// MARK: - Color

/// Figma colour components – each in 0…1 range, same as Kivy
public struct FigmaColor: Codable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double?
}
