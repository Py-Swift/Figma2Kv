// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Figma2Kv",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Figma2Kv", targets: ["Figma2Kv"]),
    ],
    dependencies: [
        .package(path: "../FigmaApi"),
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
    ]
)
