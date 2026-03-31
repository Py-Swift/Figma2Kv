// swift-tools-version: 6.0
import PackageDescription

let local = true

let figmaApi: Package.Dependency = local
    ? .package(path: "../FigmaApi")
    : .package(url: "https://github.com/Py-Swift/FigmaApi.git", branch: "master")

let pySwiftAST: Package.Dependency = .package(url: "https://github.com/Py-Swift/PySwiftAST.git", branch: "master")

let package = Package(
    name: "Figma2Kv",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Figma2Kv", targets: ["Figma2Kv"]),
        .library(name: "KivyCanvasDesigner", targets: ["KivyCanvasDesigner"]),
    ],
    dependencies: [
        figmaApi,
        pySwiftAST,
        .package(url: "https://github.com/Py-Swift/SwiftyKvLang", branch: "master"),
    ],
    targets: [
        .target(
            name: "Figma2Kv",
            dependencies: [
                .product(name: "FigmaApi", package: "FigmaApi"),
                .product(name: "KvParser", package: "SwiftyKvLang"),
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "KivyCanvasDesigner",
            dependencies: [
                .product(name: "FigmaApi", package: "FigmaApi"),
                .product(name: "PySwiftCodeGen", package: "PySwiftAST"),
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
