

# Figma Kivy Canvas Instruction Designer

# research notes
* canvas-playground/src/canvas_playground/app.py
* canvas-playground/src/canvas_playground/instructions.py
* Figma2Kv/widgets-vs-instructions.md
* https://github.com/kivy/kivy/blob/master/kivy/graphics/instructions.pyx

# Phase 1: preparation research and prototyping
- Create KivyCanvasDesigner target in Figma2Kv that will generate instructions later in phases.
- Explore Kivy canvas instructions and how they can be used to represent Figma shapes as instructions instead of all is based on tons of widget instances. See `canvas-playground/` for experiments.
- Validated: one widget per shape costs ~34 objects minimum (28 `PropertyStorage` + 3 `CanvasBase` + `WeakProxy` + dict) before the canvas instructions even exist. 9 shapes as widgets = ~373 objects. 9 shapes as instructions on one widget = ~52 objects.

# Phase 2: design a mapping from Figma nodes to Kivy canvas instructions
- Define a mapping from Figma node types to Kivy canvas instructions: `RECTANGLE` → `Color` + `Rectangle`, `ELLIPSE` → `Color` + `Ellipse`, `VECTOR` → `Color` + `Line`, etc.
- Conditional visibility (Figma component variants, boolean layers) → wrap in `ConditionalInstruction(InstructionGroup)` as already implemented in `instructions.py`. Toggling is `remove` + `add` on a C-level list — zero allocations.
- For interactive nodes (e.g. buttons that need touch), emit a single `Widget` that contains all its child instructions — not one widget per child. The widget handles touch; the shapes are instructions on its canvas.
- Only emit a new `Color` instruction when the fill/stroke color actually changes from the previous shape — reuse the active color for consecutive same-colored shapes.

# Phase 3: implement the instruction generation in figma2kv
- Walk the Figma node tree and generate a single `Widget` subclass that builds the full instruction tree in its `__init__` method.
- Ensure that the generated code is efficient and does not create unnecessary objects or trigger layout passes when toggling visibility or moving shapes.
- Test the output by running the generated instructions in a Kivy app and comparing the visual output to the original Figma design.

```figma
# Widget (Frame)
    <canvas>
        * combine all frames groups etc into a single canvas instruction group
        * for each shape, emit a Color + Rectangle/Ellipse/Line instruction with the
            appropriate parameters (pos, size, color, etc)
        * only change the Color if the fill/stroke color changes, otherwise reuse the same Color instruction (by not adding a new one to the canvas)
```

# Phase 4: create InstructionGroup subclasses for groups ect in Figma

currently it just generate a Widget and instructions needs to be reusable through instructions, not just widgets...
and it should create InstructionGroup class for each group in Figma, so we can reuse them for variants and conditional visibility without needing to duplicate instructions or widgets.


# Phase 5: optimize instruction generation with Cython (when told to)

* later make instruction use cythons pure python mode to write directly to C-level instruction lists, bypassing Python objects entirely for max performance and zero GC overhead when toggling visibility or moving shapes. This will require a custom Cython extension that exposes the necessary Kivy internals for direct manipulation of the instruction lists.

* https://cython.readthedocs.io/en/latest/src/tutorial/pure.html#pure-python-mode

for AST generation / code generation use PySwiftAST.

* PySwiftAST







