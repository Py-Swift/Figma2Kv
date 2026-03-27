import FigmaApi

/// Plugin-facing Figma node model.
///
/// Represents the subset of the Figma scene tree that the plugin serialises
/// and sends to the server. Types that are already defined in `FigmaApi`
/// (FigmaBounds, FigmaPaint, FigmaLayoutGrid, FigmaColor) are used directly.
///
/// Note: `type` and `layoutMode` are kept as `String` rather than the REST-API
/// enums because the Plugin API serialises them identically as raw strings.

// MARK: - PluginNode

public struct PluginNode: Codable, Sendable {
    /// Figma node type: FRAME, GROUP, COMPONENT, INSTANCE, TEXT,
    /// RECTANGLE, ELLIPSE, VECTOR, etc.
    public let type: String

    /// Layer name as shown in the Figma layers panel
    public let name: String

    /// Absolute position + size on the canvas
    public let absoluteBoundingBox: FigmaBounds?

    /// Fill paints applied to this node
    public let fills: [FigmaPaint]?

    /// Text content (TEXT nodes only)
    public let characters: String?

    /// Font size in points (TEXT nodes only)
    public let fontSize: Double?

    /// Child nodes (FRAME, GROUP, COMPONENT, INSTANCE)
    public let children: [PluginNode]?

    /// Auto layout direction: "HORIZONTAL" | "VERTICAL" | "NONE" | "GRID"
    public let layoutMode: String?

    /// Auto layout wrap: "WRAP" | "NO_WRAP"
    public let layoutWrap: String?

    /// How this node sizes itself on each axis: "FIXED" | "FILL" | "HUG"
    public let layoutSizingHorizontal: String?
    public let layoutSizingVertical: String?

    /// Number of columns when layoutMode == "GRID"
    public let gridColumnCount: Int?
    /// Number of rows when layoutMode == "GRID"
    public let gridRowCount: Int?
    /// Horizontal gap between grid cells
    public let gridColumnGap: Double?
    /// Vertical gap between grid cells
    public let gridRowGap: Double?

    /// Gap between children in HORIZONTAL / VERTICAL auto-layout
    public let itemSpacing: Double?
    /// Padding (HORIZONTAL / VERTICAL auto-layout and GRID)
    public let paddingLeft: Double?
    public let paddingRight: Double?
    public let paddingTop: Double?
    public let paddingBottom: Double?

    /// Visual layout grids attached to this frame
    public let layoutGrids: [FigmaLayoutGrid]?
}
