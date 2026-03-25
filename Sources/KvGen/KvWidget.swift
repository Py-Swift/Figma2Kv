/// Widget instance in KV language
///
/// Represents a widget instance, either as a root widget or child widget.
/// Contains properties, child widgets, canvas instructions, and event handlers.
///
/// Example from style.kv:
/// ```
/// Image:
///     id: my_image
///     source: 'image.png'
///     size: 100, 100
/// ```
///
/// Similar to YAML mappings but with widget-specific semantics
public struct KvWidget: KvNode, Sendable {
    /// Widget class name (e.g., "Button", "Label")
    public let name: String
    
    /// Optional identifier for referencing this widget
    public let id: String?
    
    /// Properties assigned to this widget
    public let properties: [KvProperty]
    
    /// Child widgets nested under this widget
    public let children: [KvWidget]
    
    /// Canvas instructions rendered before widget
    public let canvasBefore: KvCanvas?
    
    /// Main canvas instructions
    public let canvas: KvCanvas?
    
    /// Canvas instructions rendered after widget
    public let canvasAfter: KvCanvas?
    
    /// Event handlers (properties starting with on_)
    public let handlers: [KvProperty]
    
    /// Indentation level in source (0 = root)
    public let level: Int
    
    // Position tracking
    public let line: Int
    public let column: Int
    public let endLine: Int?
    public let endColumn: Int?
    
    public init(
        name: String,
        id: String? = nil,
        properties: [KvProperty] = [],
        children: [KvWidget] = [],
        canvasBefore: KvCanvas? = nil,
        canvas: KvCanvas? = nil,
        canvasAfter: KvCanvas? = nil,
        handlers: [KvProperty] = [],
        level: Int = 0,
        line: Int,
        column: Int = 0,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.name = name
        self.id = id
        self.properties = properties
        self.children = children
        self.canvasBefore = canvasBefore
        self.canvas = canvas
        self.canvasAfter = canvasAfter
        self.handlers = handlers
        self.level = level
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

extension KvWidget: TreeDisplayable {
    public func treeDescription(indent: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var result = "\(prefix)\(name):"
        if let id = id {
            result += " (id: \(id))"
        }
        result += " [line \(line), level \(level)]\n"
        
        if !properties.isEmpty {
            for prop in properties {
                result += prop.treeDescription(indent: indent + 1)
            }
        }
        
        if !handlers.isEmpty {
            for handler in handlers {
                result += handler.treeDescription(indent: indent + 1)
            }
        }
        
        if let canvas = canvasBefore {
            result += "\(prefix)  canvas.before:\n"
            result += canvas.treeDescription(indent: indent + 2)
        }
        
        if let canvas = canvas {
            result += "\(prefix)  canvas:\n"
            result += canvas.treeDescription(indent: indent + 2)
        }
        
        if let canvas = canvasAfter {
            result += "\(prefix)  canvas.after:\n"
            result += canvas.treeDescription(indent: indent + 2)
        }
        
        if !children.isEmpty {
            for child in children {
                result += child.treeDescription(indent: indent + 1)
            }
        }
        
        return result
    }
    
    /// Detailed tree content for deep traversal
    internal func detailedContent(depth: Int, parentBranches: [Bool]) -> String {
        var result = ""
        var childIndex = 0
        let totalItems = properties.count + handlers.count + (canvasBefore != nil ? 1 : 0) + (canvas != nil ? 1 : 0) + (canvasAfter != nil ? 1 : 0) + children.count
        
        // Properties
        for prop in properties {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            result += "\(prefix)\(prop.name): \(prop.value) [property, line \(prop.line)]\n"
            childIndex += 1
        }
        
        // Event handlers
        for handler in handlers {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            result += "\(prefix)\(handler.name): \(handler.value) [handler, line \(handler.line)]\n"
            
            childIndex += 1
        }
        
        // Canvas.before
        if let canvasBefore = canvasBefore {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            result += "\(prefix)canvas.before [canvas, line \(canvasBefore.line)]\n"
            result += canvasBefore.detailedContent(depth: depth + 1, parentBranches: parentBranches + [!isLast])
            childIndex += 1
        }
        
        // Canvas
        if let canvas = canvas {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            result += "\(prefix)canvas [canvas, line \(canvas.line)]\n"
            result += canvas.detailedContent(depth: depth + 1, parentBranches: parentBranches + [!isLast])
            childIndex += 1
        }
        
        // Canvas.after
        if let canvasAfter = canvasAfter {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            result += "\(prefix)canvas.after [canvas, line \(canvasAfter.line)]\n"
            result += canvasAfter.detailedContent(depth: depth + 1, parentBranches: parentBranches + [!isLast])
            childIndex += 1
        }
        
        // Child widgets
        for child in children {
            let isLast = childIndex == totalItems - 1
            let prefix = TreeFormatter.prefix(depth: depth, isLast: isLast, parentBranches: parentBranches)
            let idInfo = child.id != nil ? ", id: \(child.id!)" : ""
            result += "\(prefix)\(child.name) [widget, line \(child.line)\(idInfo)]\n"
            result += child.detailedContent(depth: depth + 1, parentBranches: parentBranches + [!isLast])
            childIndex += 1
        }
        
        return result
    }
    
}

/// Property assignment in KV language
///
/// Represents a property-value pair, similar to YAML key-value mappings
/// but with Python expressions as values and reactive binding support.
///
/// Example: `size: self.width, self.height`
///
/// Reference: parser.py lines 136-302 (ParserRuleProperty class)
public struct KvProperty: KvNode, Sendable {
    /// Property name (e.g., "size", "color", "on_press")
    public let name: String
    
    /// Raw value string as written in source
    public let value: String
    
    /// Compiled representation of the value
    public let compiledValue: KvCompiledValue
    
    /// Watched keys for reactive binding (e.g., [["self", "width"], ["root", "x"]])
    /// Extracted from property value expressions
    public let watchedKeys: [[String]]?
    
    /// If true, clear previous rules targeting this property
    /// Used for property overrides
    public let ignorePrevious: Bool
    
    /// Python AST for event handlers (when name starts with "on_")
    public let pythonAST: [Any]?
    
    // Position tracking
    public let line: Int
    public let column: Int
    public let endLine: Int?
    public let endColumn: Int?
    
    public init(
        name: String,
        value: String,
        compiledValue: KvCompiledValue = .expression(""),
        watchedKeys: [[String]]? = nil,
        ignorePrevious: Bool = false,
        pythonAST: [Any]? = nil,
        line: Int,
        column: Int = 0,
        endLine: Int? = nil,
        endColumn: Int? = nil
    ) {
        self.name = name
        self.value = value
        self.compiledValue = compiledValue
        self.watchedKeys = watchedKeys
        self.ignorePrevious = ignorePrevious
        self.pythonAST = pythonAST
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

extension KvProperty: TreeDisplayable {
    public func treeDescription(indent: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var result = "\(prefix)\(name): \(value)"
        
        if let watched = watchedKeys, !watched.isEmpty {
            let keys = watched.map { $0.joined(separator: ".") }.joined(separator: ", ")
            result += " [watches: \(keys)]"
        }
        
        result += " [line \(line)]\n"
        return result
    }
}

/// Compiled representation of a property value
///
/// Property values can be:
/// - Literal constants (pre-evaluated at parse time)
/// - Python expressions (evaluated reactively)
/// - Python code blocks (executed for event handlers)
///
/// Reference: parser.py lines 158-226 (precompile method)
public enum KvCompiledValue: Sendable {
    /// Pre-evaluated constant value
    case literal(String)
    
    /// Python expression to evaluate (eval mode)
    case expression(String)
    
    /// Python code to execute (exec mode, for on_* handlers)
    case code(String)
}
