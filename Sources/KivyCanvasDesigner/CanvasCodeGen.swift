import PySwiftAST
import PySwiftCodeGen

// MARK: - Code Generator

enum CanvasCodeGen {

    private struct GeneratedRef {
        enum Kind {
            case shape(CanvasShapeIR)
            case group(CanvasGroupIR)
        }
        let attrName: String
        let kind: Kind
    }

    // MARK: - Public entry

    /// Generates a Python source string for all frames in a single module.
    static func generate(frames: [CanvasFrameIR], scalable: Bool = false, smooth: SmoothOptions = .init()) -> String {
        guard !frames.isEmpty else { return "" }

        // Determine which graphics classes are needed (recurse into groups).
        var needsRectangle        = false
        var needsRoundedRectangle = false
        var needsEllipse          = false
        var needsTriangle         = false
        var needsGroups           = false
        func scanItems(_ items: [CanvasItem]) {
            for item in items {
                switch item {
                case .shape(let s):
                    switch s.kind {
                    case .rectangle:        needsRectangle        = true
                    case .roundedRectangle: needsRoundedRectangle = true
                    case .ellipse:          needsEllipse          = true
                    case .triangle:         needsTriangle         = true
                    }
                case .group(let g):
                    needsGroups = true
                    scanItems(g.items)
                }
            }
        }
        for frame in frames {
            for layer in frame.layers { scanItems(layer.items) }
        }

        var graphicsNames = ["Color"]
        if needsRectangle        { graphicsNames.append(smooth.rectangle        ? "SmoothRectangle"        : "Rectangle") }
        if needsRoundedRectangle { graphicsNames.append(smooth.roundedRectangle ? "SmoothRoundedRectangle" : "RoundedRectangle") }
        if needsEllipse          { graphicsNames.append(smooth.ellipse          ? "SmoothEllipse"          : "Ellipse") }
        if needsTriangle         { graphicsNames.append(smooth.triangle         ? "SmoothTriangle"         : "Triangle") }
        if needsGroups           { graphicsNames.append("InstructionGroup") }

        // Imports
        let importWidget = Statement.importFrom(ImportFrom(
            module: "kivy.uix.widget",
            names: [Alias(name: "Widget", asName: nil)],
            level: 0
        ))
        let importGraphics = Statement.importFrom(ImportFrom(
            module: "kivy.graphics",
            names: graphicsNames.map { Alias(name: $0, asName: nil) },
            level: 0
        ))

        // Collect all InstructionGroup subclasses in post-order (leafs emitted first).
        let groups = allGroupsPostOrder(frames: frames)

        // Assemble module body: imports → group classes → frame Widget classes.
        var body: [Statement] = [importWidget, importGraphics]
        for group in groups {
            body.append(.blank())
            body.append(.blank())
            body.append(groupClassDef(group, scalable: scalable, smooth: smooth))
        }
        for frame in frames {
            body.append(.blank())
            body.append(.blank())
            body.append(classDefFor(frame, scalable: scalable, smooth: smooth))
        }

        if let lastName = frames.last?.className {
            body.append(.blank())
            body.append(.assign(Assign(
                targets: [.name(Name(id: "preview", ctx: .store))],
                value: callExpr(fun: nameExpr(lastName), args: [], keywords: []),
                typeComment: nil
            )))
        }

        return generatePythonCode(from: .module(body))
    }

    // MARK: - Class definition

    private static func classDefFor(_ frame: CanvasFrameIR, scalable: Bool, smooth: SmoothOptions) -> Statement {
        var refs: [GeneratedRef] = []
        let initFunc = initFuncFor(frame, scalable: scalable, smooth: smooth, refs: &refs)
        var body: [Statement] = [initFunc]
        if scalable && !refs.isEmpty {
            body.append(.blank())
            body.append(updateCanvasFuncFor(frame: frame, refs: refs))
        }
        return .classDef(ClassDef(
            name: frame.className,
            bases: [nameExpr("Widget")],
            body: body
        ))
    }

    private static func initFuncFor(_ frame: CanvasFrameIR, scalable: Bool, smooth: SmoothOptions, refs: inout [GeneratedRef]) -> Statement {
        .functionDef(FunctionDef(
            name: "__init__",
            args: Arguments(
                args: [Arg(arg: "self")],
                kwarg: Arg(arg: "kwargs")
            ),
            body: initBodyFor(frame, scalable: scalable, smooth: smooth, refs: &refs)
        ))
    }

    // MARK: - __init__ body (Widget)

    private static func initBodyFor(_ frame: CanvasFrameIR, scalable: Bool, smooth: SmoothOptions, refs: inout [GeneratedRef]) -> [Statement] {
        // super().__init__(**kwargs)
        let superCall = exprStmt(
            callExpr(
                fun: attrExpr(
                    callExpr(fun: nameExpr("super"), args: [], keywords: []),
                    "__init__"
                ),
                args: [],
                keywords: [Keyword(arg: nil, value: nameExpr("kwargs"))]
            )
        )

        let activeLayers = frame.layers.filter { !$0.items.isEmpty }
        guard !activeLayers.isEmpty else { return [superCall] }

        var stmts: [Statement] = [superCall]

        // In scalable mode: unpack x,y,w,h once from self, then use those locals.
        let xExpr:      Expression?
        let yExpr:      Expression?
        let widthExpr:  Expression?
        let heightExpr: Expression?
        if scalable {
            let localsAssign = Statement.assign(Assign(
                targets: [.tuple(Tuple(elts: [
                    .name(Name(id: "x", ctx: .store)),
                    .name(Name(id: "y", ctx: .store)),
                    .name(Name(id: "w", ctx: .store)),
                    .name(Name(id: "h", ctx: .store)),
                ]))],
                value: .tuple(Tuple(elts: [
                    attrExpr(nameExpr("self"), "x"),
                    attrExpr(nameExpr("self"), "y"),
                    attrExpr(nameExpr("self"), "width"),
                    attrExpr(nameExpr("self"), "height"),
                ])),
                typeComment: nil
            ))
            stmts.append(localsAssign)
            xExpr      = nameExpr("x")
            yExpr      = nameExpr("y")
            widthExpr  = nameExpr("w")
            heightExpr = nameExpr("h")
        } else {
            xExpr      = nil
            yExpr      = nil
            widthExpr  = nil
            heightExpr = nil
        }

        var counter = 0

        for (i, layer) in activeLayers.enumerated() {
            if i > 0 { stmts.append(.blank()) }

            // cb = self.canvas.before / after / (main)
            let cbExpr: Expression
            switch layer.target {
            case .before: cbExpr = attrExpr(attrExpr(nameExpr("self"), "canvas"), "before")
            case .after:  cbExpr = attrExpr(attrExpr(nameExpr("self"), "canvas"), "after")
            case .main:   cbExpr = attrExpr(nameExpr("self"), "canvas")
            }
            stmts.append(.assign(Assign(
                targets: [.name(Name(id: "cb", ctx: .store))],
                value: cbExpr,
                typeComment: nil
            )))

            stmts.append(contentsOf: cbAddItemStmts(
                layer.items,
                scalable: scalable,
                smooth: smooth,
                frameWidth: frame.width,
                frameHeight: frame.height,
                xExpr: xExpr,
                yExpr: yExpr,
                widthExpr: widthExpr,
                heightExpr: heightExpr,
                refs: &refs,
                counter: &counter
            ))
        }

        if scalable && !refs.isEmpty {
            stmts.append(.blank())
            stmts.append(exprStmt(callExpr(
                fun: attrExpr(nameExpr("self"), "bind"),
                args: [],
                keywords: [
                    Keyword(arg: "pos",  value: attrExpr(nameExpr("self"), "_update_canvas")),
                    Keyword(arg: "size", value: attrExpr(nameExpr("self"), "_update_canvas"))
                ]
            )))
            stmts.append(exprStmt(callExpr(
                fun: attrExpr(nameExpr("self"), "_update_canvas"),
                args: [],
                keywords: []
            )))
        }

        return stmts
    }

    // MARK: - InstructionGroup class definition

    private static func groupClassDef(_ group: CanvasGroupIR, scalable: Bool, smooth: SmoothOptions) -> Statement {
        let superCall = exprStmt(
            callExpr(
                fun: attrExpr(
                    callExpr(fun: nameExpr("super"), args: [], keywords: []),
                    "__init__"
                ),
                args: [],
                keywords: []
            )
        )

        let initArgs: Arguments
        let xExpr:      Expression?
        let yExpr:      Expression?
        let widthExpr:  Expression?
        let heightExpr: Expression?
        if scalable {
            initArgs   = Arguments(args: [Arg(arg: "self"), Arg(arg: "x"), Arg(arg: "y"), Arg(arg: "w"), Arg(arg: "h")], kwarg: nil)
            xExpr      = nameExpr("x")
            yExpr      = nameExpr("y")
            widthExpr  = nameExpr("w")
            heightExpr = nameExpr("h")
        } else {
            initArgs   = Arguments(args: [Arg(arg: "self")], kwarg: nil)
            xExpr      = nil
            yExpr      = nil
            widthExpr  = nil
            heightExpr = nil
        }

        var counter = 0
        var refs: [GeneratedRef] = []
        var body: [Statement] = [superCall]
        body.append(contentsOf: addItemStmts(
            group.items,
            scalable: scalable,
            smooth: smooth,
            frameWidth:  group.frameWidth,
            frameHeight: group.frameHeight,
            xExpr:      xExpr,
            yExpr:      yExpr,
            widthExpr:  widthExpr,
            heightExpr: heightExpr,
            refs: &refs,
            counter: &counter
        ))
        let initFunc = Statement.functionDef(FunctionDef(
            name: "__init__",
            args: initArgs,
            body: body
        ))
        var classBody: [Statement] = [initFunc]
        if scalable && !refs.isEmpty {
            classBody.append(.blank())
            classBody.append(updateFuncForGroup(group: group, refs: refs))
        }
        return .classDef(ClassDef(
            name: group.className,
            bases: [nameExpr("InstructionGroup")],
            body: classBody
        ))
    }

    // MARK: - Post-order group collection

    private static func allGroupsPostOrder(frames: [CanvasFrameIR]) -> [CanvasGroupIR] {
        var result: [CanvasGroupIR] = []
        var seen: Swift.Set<String> = []
        func walk(_ items: [CanvasItem]) {
            for item in items {
                if case .group(let g) = item {
                    walk(g.items)
                    if seen.insert(g.className).inserted {
                        result.append(g)
                    }
                }
            }
        }
        for frame in frames {
            for layer in frame.layers { walk(layer.items) }
        }
        return result
    }

    // MARK: - Item statements

    /// For Widget canvas layers: assign `self.xxx_N = Instruction(...)` then `cb.add(self.xxx_N)`.
    private static func cbAddItemStmts(
        _ items: [CanvasItem],
        scalable: Bool,
        smooth: SmoothOptions,
        frameWidth: Int,
        frameHeight: Int,
        xExpr: Expression?,
        yExpr: Expression?,
        widthExpr: Expression?,
        heightExpr: Expression?,
        refs: inout [GeneratedRef],
        counter: inout Int
    ) -> [Statement] {
        var stmts: [Statement] = []
        var lastR = Double.nan, lastG = Double.nan, lastB = Double.nan, lastA = Double.nan

        for item in items {
            switch item {
            case .shape(let shape):
                if shape.r != lastR || shape.g != lastG || shape.b != lastB || shape.a != lastA {
                    let rgba = Expression.tuple(Tuple(elts: [
                        floatConst(shape.r), floatConst(shape.g),
                        floatConst(shape.b), floatConst(shape.a)
                    ]))
                    let attrName = "color_\(counter)"
                    counter += 1
                    let ref = attrExpr(nameExpr("self"), attrName)
                    stmts.append(.assign(Assign(
                        targets: [ref],
                        value: callExpr(fun: nameExpr("Color"), args: [], keywords: [Keyword(arg: "rgba", value: rgba)]),
                        typeComment: nil
                    )))
                    stmts.append(cbAdd(ref))
                    lastR = shape.r; lastG = shape.g; lastB = shape.b; lastA = shape.a
                }
                let shapeName: String
                switch shape.kind {
                case .rectangle:        shapeName = smooth.rectangle        ? "SmoothRectangle"        : "Rectangle"
                case .roundedRectangle: shapeName = smooth.roundedRectangle ? "SmoothRoundedRectangle" : "RoundedRectangle"
                case .ellipse:          shapeName = smooth.ellipse          ? "SmoothEllipse"          : "Ellipse"
                case .triangle:         shapeName = smooth.triangle         ? "SmoothTriangle"         : "Triangle"
                }
                let attrPrefix: String
                switch shape.kind {
                case .rectangle, .roundedRectangle: attrPrefix = "rect_"
                case .ellipse:                      attrPrefix = "ellipse_"
                case .triangle:                     attrPrefix = "tri_"
                }
                let attrName = attrPrefix + "\(counter)"
                counter += 1
                let ref = attrExpr(nameExpr("self"), attrName)
                let shapeKws: [Keyword]
                if shape.kind == .triangle {
                    let pts = triPoints(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "points", value: pts)]
                } else if shape.kind == .roundedRectangle, let radii = shape.cornerRadii {
                    let (pos, size) = posSize(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "pos", value: pos), Keyword(arg: "size", value: size), Keyword(arg: "radius", value: radiusExpr(radii))]
                } else {
                    let (pos, size) = posSize(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "pos", value: pos), Keyword(arg: "size", value: size)]
                }
                stmts.append(.assign(Assign(
                    targets: [ref],
                    value: callExpr(fun: nameExpr(shapeName), args: [], keywords: shapeKws),
                    typeComment: nil
                )))
                stmts.append(cbAdd(ref))
                refs.append(GeneratedRef(attrName: attrName, kind: .shape(shape)))
            case .group(let group):
                lastR = Double.nan
                var groupArgs: [Expression] = []
                if scalable, let xe = xExpr, let ye = yExpr, let we = widthExpr, let he = heightExpr {
                    groupArgs = [xe, ye, we, he]
                }
                let attrName = "\(group.className.prefix(1).lowercased())\(group.className.dropFirst())_\(counter)"
                counter += 1
                let ref = attrExpr(nameExpr("self"), attrName)
                stmts.append(.assign(Assign(
                    targets: [ref],
                    value: callExpr(fun: nameExpr(group.className), args: groupArgs, keywords: []),
                    typeComment: nil
                )))
                stmts.append(cbAdd(ref))
                refs.append(GeneratedRef(attrName: attrName, kind: .group(group)))
            }
        }
        return stmts
    }

    /// For InstructionGroup: assign `self.xxx_N = Instruction(...)` then `self.add(self.xxx_N)`.
    private static func addItemStmts(
        _ items: [CanvasItem],
        scalable: Bool = false,
        smooth: SmoothOptions = .init(),
        frameWidth: Int = 0,
        frameHeight: Int = 0,
        xExpr: Expression? = nil,
        yExpr: Expression? = nil,
        widthExpr: Expression? = nil,
        heightExpr: Expression? = nil,
        refs: inout [GeneratedRef],
        counter: inout Int
    ) -> [Statement] {
        var stmts: [Statement] = []
        var lastR = Double.nan, lastG = Double.nan, lastB = Double.nan, lastA = Double.nan

        for item in items {
            switch item {
            case .shape(let shape):
                if shape.r != lastR || shape.g != lastG || shape.b != lastB || shape.a != lastA {
                    let rgba = Expression.tuple(Tuple(elts: [
                        floatConst(shape.r), floatConst(shape.g),
                        floatConst(shape.b), floatConst(shape.a)
                    ]))
                    let attrName = "color_\(counter)"
                    counter += 1
                    let ref = attrExpr(nameExpr("self"), attrName)
                    stmts.append(.assign(Assign(
                        targets: [ref],
                        value: callExpr(fun: nameExpr("Color"), args: [], keywords: [Keyword(arg: "rgba", value: rgba)]),
                        typeComment: nil
                    )))
                    stmts.append(selfAdd(ref))
                    lastR = shape.r; lastG = shape.g; lastB = shape.b; lastA = shape.a
                }
                let shapeName: String
                switch shape.kind {
                case .rectangle:        shapeName = smooth.rectangle        ? "SmoothRectangle"        : "Rectangle"
                case .roundedRectangle: shapeName = smooth.roundedRectangle ? "SmoothRoundedRectangle" : "RoundedRectangle"
                case .ellipse:          shapeName = smooth.ellipse          ? "SmoothEllipse"          : "Ellipse"
                case .triangle:         shapeName = smooth.triangle         ? "SmoothTriangle"         : "Triangle"
                }
                let attrPrefix: String
                switch shape.kind {
                case .rectangle, .roundedRectangle: attrPrefix = "rect_"
                case .ellipse:                      attrPrefix = "ellipse_"
                case .triangle:                     attrPrefix = "tri_"
                }
                let attrName = attrPrefix + "\(counter)"
                counter += 1
                let ref = attrExpr(nameExpr("self"), attrName)
                let shapeKws: [Keyword]
                if shape.kind == .triangle {
                    let pts = triPoints(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "points", value: pts)]
                } else if shape.kind == .roundedRectangle, let radii = shape.cornerRadii {
                    let (pos, size) = posSize(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "pos", value: pos), Keyword(arg: "size", value: size), Keyword(arg: "radius", value: radiusExpr(radii))]
                } else {
                    let (pos, size) = posSize(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    shapeKws = [Keyword(arg: "pos", value: pos), Keyword(arg: "size", value: size)]
                }
                stmts.append(.assign(Assign(
                    targets: [ref],
                    value: callExpr(fun: nameExpr(shapeName), args: [], keywords: shapeKws),
                    typeComment: nil
                )))
                stmts.append(selfAdd(ref))
                refs.append(GeneratedRef(attrName: attrName, kind: .shape(shape)))
            case .group(let group):
                lastR = Double.nan
                var groupArgs: [Expression] = []
                if scalable, let xe = xExpr, let ye = yExpr, let we = widthExpr, let he = heightExpr {
                    groupArgs = [xe, ye, we, he]
                }
                let attrName = "\(group.className.prefix(1).lowercased())\(group.className.dropFirst())_\(counter)"
                counter += 1
                let ref = attrExpr(nameExpr("self"), attrName)
                stmts.append(.assign(Assign(
                    targets: [ref],
                    value: callExpr(fun: nameExpr(group.className), args: groupArgs, keywords: []),
                    typeComment: nil
                )))
                stmts.append(selfAdd(ref))
                refs.append(GeneratedRef(attrName: attrName, kind: .group(group)))
            }
        }
        return stmts
    }

    private static func selfAdd(_ ref: Expression) -> Statement {
        exprStmt(callExpr(
            fun: attrExpr(nameExpr("self"), "add"),
            args: [ref],
            keywords: []
        ))
    }

    private static func cbAdd(_ ref: Expression) -> Statement {
        exprStmt(callExpr(
            fun: attrExpr(nameExpr("cb"), "add"),
            args: [ref],
            keywords: []
        ))
    }

    private static func posSize(
        _ shape: CanvasShapeIR,
        scalable: Bool, frameWidth: Int, frameHeight: Int,
        xe: Expression?, ye: Expression?, we: Expression?, he: Expression?
    ) -> (Expression, Expression) {
        if scalable, let xe, let ye, let we, let he, frameWidth > 0, frameHeight > 0 {
            // pos = (x + w * pct_x,  y + h * pct_y)
            // size = (w * pct_w,  h * pct_h)
            let px = Expression.binOp(BinOp(left: xe, op: .add, right: scaledCoord(shape.x,      frameWidth,  we)))
            let py = Expression.binOp(BinOp(left: ye, op: .add, right: scaledCoord(shape.y,      frameHeight, he)))
            let sw = scaledCoord(shape.width,  frameWidth,  we)
            let sh = scaledCoord(shape.height, frameHeight, he)
            return (.tuple(Tuple(elts: [px, py])), .tuple(Tuple(elts: [sw, sh])))
        } else {
            return (
                .tuple(Tuple(elts: [intConst(shape.x), intConst(shape.y)])),
                .tuple(Tuple(elts: [intConst(shape.width), intConst(shape.height)]))
            )
        }
    }

    /// Returns a `points` list expression for a flat-bottom isoceles triangle derived from
    /// the shape's bounding box: bottom-left, bottom-right, top-center.
    private static func triPoints(
        _ shape: CanvasShapeIR,
        scalable: Bool, frameWidth: Int, frameHeight: Int,
        xe: Expression?, ye: Expression?, we: Expression?, he: Expression?
    ) -> Expression {
        if scalable, let xe, let ye, let we, let he, frameWidth > 0, frameHeight > 0 {
            let x0 = Expression.binOp(BinOp(left: xe, op: .add, right: scaledCoord(shape.x,                        frameWidth,  we)))
            let x1 = Expression.binOp(BinOp(left: xe, op: .add, right: scaledCoord(shape.x + shape.width,          frameWidth,  we)))
            let x2 = Expression.binOp(BinOp(left: xe, op: .add, right: scaledCoord(shape.x + shape.width / 2,      frameWidth,  we)))
            let y0 = Expression.binOp(BinOp(left: ye, op: .add, right: scaledCoord(shape.y,                        frameHeight, he)))
            let y1 = Expression.binOp(BinOp(left: ye, op: .add, right: scaledCoord(shape.y + shape.height,         frameHeight, he)))
            return .list(List(elts: [x0, y0, x1, y0, x2, y1]))
        } else {
            let x0 = shape.x
            let x1 = shape.x + shape.width
            let x2 = shape.x + shape.width / 2
            let y0 = shape.y
            let y1 = shape.y + shape.height
            return .list(List(elts: [
                intConst(x0), intConst(y0),
                intConst(x1), intConst(y0),
                intConst(x2), intConst(y1)
            ]))
        }
    }


    private static func nameExpr(_ id: String) -> Expression {
        .name(Name(id: id))
    }

    private static func attrExpr(_ value: Expression, _ attr: String) -> Expression {
        .attribute(Attribute(value: value, attr: attr, ctx: .load))
    }

    private static func callExpr(
        fun: Expression, args: [Expression], keywords: [Keyword]
    ) -> Expression {
        .call(Call(fun: fun, args: args, keywords: keywords))
    }

    private static func exprStmt(_ expr: Expression) -> Statement {
        .expr(Expr(value: expr))
    }

    private static func intConst(_ v: Int) -> Expression {
        .constant(Constant(value: .int(v)))
    }

    private static func floatConst(_ v: Double) -> Expression {
        .constant(Constant(value: .float(v)))
    }

    /// Returns `dimExpr * pct` where pct = value/frameDim, up to 8 significant decimal places
    /// but trailing zeros are stripped automatically by Swift's String(Double) formatting.
    private static func scaledCoord(_ value: Int, _ frameDim: Int, _ dimExpr: Expression) -> Expression {
        let pct = (Double(value) / Double(max(frameDim, 1)) * 1e8).rounded() / 1e8
        return .binOp(BinOp(left: dimExpr, op: .mult, right: floatConst(pct)))
    }

    private static func radiusExpr(_ radii: [Double]) -> Expression {
        let allSame = radii.dropFirst().allSatisfy { $0 == radii[0] }
        if allSame {
            return .list(List(elts: [floatConst(radii[0])]))
        } else {
            return .list(List(elts: radii.map { floatConst($0) }))
        }
    }

    // MARK: - Update helpers

    private static func updateStmts(
        refs: [GeneratedRef],
        scalable: Bool,
        frameWidth: Int,
        frameHeight: Int,
        xExpr: Expression?,
        yExpr: Expression?,
        widthExpr: Expression?,
        heightExpr: Expression?
    ) -> [Statement] {
        var stmts: [Statement] = []
        for ref in refs {
            switch ref.kind {
            case .shape(let shape):
                if shape.kind == .triangle {
                    let pts = triPoints(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    stmts.append(.assign(Assign(
                        targets: [attrExpr(attrExpr(nameExpr("self"), ref.attrName), "points")],
                        value: pts,
                        typeComment: nil
                    )))
                } else {
                    let (pos, size) = posSize(shape, scalable: scalable, frameWidth: frameWidth, frameHeight: frameHeight, xe: xExpr, ye: yExpr, we: widthExpr, he: heightExpr)
                    stmts.append(.assign(Assign(
                        targets: [attrExpr(attrExpr(nameExpr("self"), ref.attrName), "pos")],
                        value: pos,
                        typeComment: nil
                    )))
                    stmts.append(.assign(Assign(
                        targets: [attrExpr(attrExpr(nameExpr("self"), ref.attrName), "size")],
                        value: size,
                        typeComment: nil
                    )))
                }
            case .group:
                if scalable, let xe = xExpr, let ye = yExpr, let we = widthExpr, let he = heightExpr {
                    stmts.append(exprStmt(callExpr(
                        fun: attrExpr(attrExpr(nameExpr("self"), ref.attrName), "update"),
                        args: [xe, ye, we, he],
                        keywords: []
                    )))
                }
            }
        }
        return stmts
    }

    private static func updateCanvasFuncFor(frame: CanvasFrameIR, refs: [GeneratedRef]) -> Statement {
        let xE = nameExpr("x"); let yE = nameExpr("y")
        let wE = nameExpr("w"); let hE = nameExpr("h")
        var body: [Statement] = []
        body.append(.assign(Assign(
            targets: [.tuple(Tuple(elts: [
                .name(Name(id: "x", ctx: .store)), .name(Name(id: "y", ctx: .store)),
                .name(Name(id: "w", ctx: .store)), .name(Name(id: "h", ctx: .store))
            ]))],
            value: .tuple(Tuple(elts: [
                attrExpr(nameExpr("self"), "x"), attrExpr(nameExpr("self"), "y"),
                attrExpr(nameExpr("self"), "width"), attrExpr(nameExpr("self"), "height")
            ])),
            typeComment: nil
        )))
        body.append(contentsOf: updateStmts(
            refs: refs, scalable: true,
            frameWidth: frame.width, frameHeight: frame.height,
            xExpr: xE, yExpr: yE, widthExpr: wE, heightExpr: hE
        ))
        return .functionDef(FunctionDef(
            name: "_update_canvas",
            args: Arguments(args: [Arg(arg: "self")], vararg: Arg(arg: "args")),
            body: body
        ))
    }

    private static func updateFuncForGroup(group: CanvasGroupIR, refs: [GeneratedRef]) -> Statement {
        let xE = nameExpr("x"); let yE = nameExpr("y")
        let wE = nameExpr("w"); let hE = nameExpr("h")
        let body = updateStmts(
            refs: refs, scalable: true,
            frameWidth: group.frameWidth, frameHeight: group.frameHeight,
            xExpr: xE, yExpr: yE, widthExpr: wE, heightExpr: hE
        )
        return .functionDef(FunctionDef(
            name: "update",
            args: Arguments(args: [Arg(arg: "self"), Arg(arg: "x"), Arg(arg: "y"), Arg(arg: "w"), Arg(arg: "h")]),
            body: body
        ))
    }
}
