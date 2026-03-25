// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Figma2Kv",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Py-Swift/SwiftyKvLang", branch: "main"),
        //.package(url: "https://github.com/elementary-swift/elementary-ui.git", from: "0.1.3"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.46.3"),
        .package(url: "https://github.com/Py-Swift/JavaScriptKitExtensions", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Figma2Kv",
            dependencies: [
                .product(name: "KvParser", package: "SwiftyKvLang"),
                .product(name: "KivyWidgetRegistry", package: "SwiftyKvLang"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptKitExtensions", package: "JavaScriptKitExtensions"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
            ]
        ),
    ]
)
