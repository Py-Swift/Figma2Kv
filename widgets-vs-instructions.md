# Widgets vs Canvas Instructions

Two ways to render a 3×3 grid of 9 colored shapes. Same visual result, very different cost.

---

## The key difference: Kivy Properties vs C instruction slots

Every `Widget` uses `EventDispatcher`. When a widget is created, Kivy calls `property.link()` for every declared Kivy property (`pos`, `size`, `size_hint`, `opacity`, …), which allocates a `PropertyStorage` object per property per instance and wires it into the observer/binding system. That overhead exists whether you use those properties or not.

Canvas instructions (`Color`, `Rectangle`, `Ellipse`, …) are Cython objects. Their attributes are plain C-level struct fields — no `PropertyStorage`, no observer lists, no binding machinery. `rect.pos = (x, y)` is a direct memory write.

---

## Approach A — GridLayout with 9 Widget children

```python
class MyShape(Widget):
    state = BooleanProperty(True)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.rect_or_circle = RectOrCircle(pos=self.pos, size=self.size, state=self.state)
        self.canvas.before.add(Color(1, 0, 0, 1))
        self.canvas.before.add(self.rect_or_circle)

grid = GridLayout(cols=3)
for _ in range(9):
    grid.add_widget(MyShape())
```

9 full `Widget` instances, each with its own `BooleanProperty(state)`, 28 Kivy `PropertyStorage` objects, 3 `CanvasBase` objects, a `WeakProxy`, a `__storage` dict, and a `RectOrCircle` instruction group. Plus the `GridLayout` itself.

---

## Approach B — 1 Widget with all 9 as canvas instructions

`instructions.py` defines `RectOrCircle` — a `ConditionalInstruction(InstructionGroup)` that holds a `SmoothEllipse` and a `Rectangle` and swaps between them on `.state`. No widget, no `PropertyStorage`, no `CanvasBase` overhead. Just C-level instruction objects.

One widget, 9 `RectOrCircle` groups added directly to its canvas:

```python
class NineShapes(Widget):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        cb = self.canvas.before
        for _ in range(9):
            cb.add(Color(1, 0, 0, 1))
            cb.add(RectOrCircle(pos=(0, 0), size=(50, 50)))
```

Toggling a shape: `rect_or_circle.state = False` — calls `remove` + `add` on a C-level list, nothing else allocated.

**Total: ~52 objects.**

---

## Summary

| | Approach A | Approach B |
|---|---|---|
| Objects allocated | ~373 | ~52 |
| Kivy PropertyStorage objects | ~297 (across 10 widget instances) | 28 (one widget) |
| Layout pass | repositions/resizes all 9 children on layout change | none |
| Touch dispatch nodes | 10 | 1 |
| Moving a shape | property set → dispatch → layout | direct C write |
| Toggling shape variant | redraw canvas | `group.remove/add` — 0 allocs |

---

## Canvas instruction reference

Shapes available for the instruction approach and their parameter counts:

| Instruction | Category | Params | Key params |
|---|---|---|---|
| `Color` | Color | 6 | `r`, `g`, `b`, `a`, `rgba`, `group` |
| `Rectangle` | Shape | 4 | `pos`, `size`, `texture`, `source` |
| `Ellipse` | Shape | 6 | `pos`, `size`, `angle_start`, `angle_end`, `segments`, `texture` |
| `Line` | Shape | 15 | `points`, `width`, `cap`, `joint`, `close`, `rectangle`, `circle`… |
| `Bezier` | Shape | 5 | `points`, `loop`, `dash_length`, `dash_offset`, `precision` |
| `Triangle` | Shape | 1 | `points` |
| `Rotate` | Context | 3 | `angle`, `axis`, `origin` |
| `Translate` | Context | 3 | `x`, `y`, `z` |
| `Scale` | Context | 4 | `x`, `y`, `z`, `origin` |
| `PushMatrix` | Context | 0 | — |
| `PopMatrix` | Context | 0 | — |

---

## Next: figma2kv InstructionGroup generation

For Figma frames that are purely visual (no interaction, no text, no scroll), figma2kv should offer a second output mode that emits Python like `instructions.py` instead of `.kv`:

1. Walk the node tree
2. Map each RECTANGLE/ELLIPSE/VECTOR node → `Color` + `Rectangle`/`Ellipse`/`Line`
3. Wrap conditional nodes (e.g., visible toggle) in a `ConditionalInstruction(InstructionGroup)` subclass
4. Emit a single `Widget` subclass that builds the full instruction tree in `__init__`
5. Expose `pos`/`size` setters that propagate to the relevant instructions

This collapses an entire Figma component frame into ~1 Widget object + N instruction objects, instead of N Widget objects each with full layout/event overhead.
