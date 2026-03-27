# Figma2Kv

A pure Swift library that converts a [FigmaApi](https://github.com/Py-Swift/FigmaApi) node tree into [Kivy](https://kivy.org) `.kv` language using [SwiftyKvLang](https://github.com/Py-Swift/SwiftyKvLang).

---

## Overview

```
[FigmaApi types] → FigmaMapper → KvParser/KvCodeGen → .kv string
```

- **Input** — `[PluginNode]`: a subset of the Figma scene tree, decoded from the JSON the plugin sends to the server. Uses `FigmaPaint`, `FigmaBounds`, and `FigmaLayoutGrid` from `FigmaApi` directly.
- **Output** — a `.kv` string ready to use in a Kivy application.

---

## Adding as a dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Py-Swift/Figma2Kv", branch: "master"),
],
targets: [
    .target(dependencies: [
        .product(name: "Figma2Kv", package: "Figma2Kv"),
    ]),
]
```

`import Figma2Kv` also re-exports `FigmaApi`, so all Figma types are available from a single import.

---

## Usage

```swift
import Figma2Kv

// From a JSON string (array of PluginNode)
let kv = try FigmaMapper.convert(json: jsonString)

// From already-decoded nodes
let nodes: [PluginNode] = try JSONDecoder().decode([PluginNode].self, from: data)
let kv = FigmaMapper.convert(nodes: nodes)
```

---

## Node → KV mapping

| Figma type | KV output |
|---|---|
| `CANVAS` / `PAGE` | `Screen:` |
| `COMPONENT` | `<Name@Base>:` rule |
| `FRAME` / `INSTANCE` | auto-detected layout widget |
| `GROUP` | canvas instructions bubbled to parent |
| `TEXT` | `Label:` |
| `RECTANGLE` / `VECTOR` | `Widget:` + canvas `Rectangle` |
| `ELLIPSE` | `Widget:` + canvas `Ellipse` |

### Auto-layout detection

| `layoutMode` | KV widget |
|---|---|
| `HORIZONTAL` | `BoxLayout` (orientation: horizontal) |
| `VERTICAL` | `BoxLayout` (orientation: vertical) |
| `GRID` | `GridLayout` (cols from `gridColumnCount`) |
| none | `FloatLayout` |

### Frame naming conventions

| Layer name | KV output |
|---|---|
| `BoxLayout` (registry hit) | `BoxLayout:` inline |
| `MyWidget:<BoxLayout>` | `<MyWidget@BoxLayout>:` rule |
| `MyWidget:BoxLayout` | `MyWidget:` (external Python class) |

---

## Dependencies

- [FigmaApi](https://github.com/Py-Swift/FigmaApi) — Figma type primitives
- [SwiftyKvLang](https://github.com/Py-Swift/SwiftyKvLang) — KvParser + KivyWidgetRegistry + KvCodeGen

