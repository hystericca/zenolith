# Zenolith Layout Engine V0

Zenolith is currently a renderer/framework-independent layout engine. It is meant to complement ZPUI/Lythra by owning only layout: style input, tree storage, measurement, and computed boxes.

The intended integration boundary is ZPUI's element layout pass. ZPUI keeps frame storage, scene compilation, clips, hits, text shaping, masks, windows, platform code, and paint styles. Lythra keeps editor state and projects that state into ZPUI. Zenolith only answers: given a tree of layout styles plus measured intrinsic content, what rectangles should each node occupy?

## Units

The public unit is a logical point: `pub const Point = f32`.

The engine does not know about device pixels, scale factors, renderers, windows, input, widgets, or text shaping. A caller that measures text returns logical-point sizes through a `MeasureFn`.

## Storage

The primary API is fixed storage:

```zig
const limits = zenolith.Limits{ .nodes = 128, .children = 512, .flex_items = 256 };
var storage = zenolith.Storage(limits){};
var tree = zenolith.Tree(limits).init(&storage);
```

Storage is split into dense arrays:

- `nodes`: style, parent, child range, optional measure callback
- `layouts`: computed layout results, stored separately from style
- `children`: dense child-id ranges per parent
- `flex_items`: explicit scratch storage for flex algorithm phases

The hot layout path does not allocate heap memory. Nested flex layout takes scratch frames from the fixed `flex_items` array and returns them before unwinding.

`NodeId` is a small integer handle. V0 does not recycle node ids or include generations; invalid ids are still checked against current storage bounds and return `error.InvalidNode`.

## Errors

The public error set is intentionally small:

- `CapacityExceeded`
- `InvalidNode`
- `AlreadyHasParent`
- `ChildrenAlreadySet`
- `CycleDetected`
- `DuplicateChild`
- `InvalidSize`
- `NumericOverflow`

Sizes, padding, borders, gaps, flex grow, and flex shrink must be finite. Non-negative layout dimensions are enforced. Margins may be negative, but must still be finite.

## Style And Layout

`Style` is authored input. `Layout` is computed output. They are separate arrays in storage. For ZPUI adapters, prefer qualified names or the aliases `LayoutStyle` and `ComputedLayout` to avoid confusion with ZPUI's paint `ui.style.Style` and authored `element.Layout`.

V0 style covers:

- `display`: `flex`, `none`
- `position`: `relative`, `absolute`
- `flex_direction`: `row`, `column`
- `size`, `min_size`, `max_size`: `auto`, points, percent
- `padding`, `border`, `margin`
- `gap`
- `flex_basis`, `flex_grow`, `flex_shrink`
- `align_items`, `align_self`
- `justify_content`
- `inset` for absolute positioning

## Algorithm Shape

The flex path follows the Taffy/spec phase order in a simplified one-line form:

1. Resolve container constants: padding, border, min/max, known outer and inner size.
2. Generate flex items, excluding `position.absolute` and `display.none`.
3. Determine available main and cross space from known sizes and the incoming `AvailableSpace`.
4. Determine each item’s flex base size and hypothetical main size.
5. Collect flex lines. V0 always creates one line.
6. Resolve grow/shrink flexible lengths with min/max freezing.
7. Compute hypothetical cross sizes.
8. Apply stretch and cross-axis alignment.
9. Apply main-axis justification and write final child layouts.
10. Lay out absolute children after in-flow children.

Measured leaves call `MeasureFn` only when a dimension is not otherwise known. The callback receives known content dimensions, parent size, and available space. Measure functions should be pure and idempotent: flex layout may call them more than once for the same node while resolving base and cross sizes.

## V0 Skips

V0 intentionally skips:

- wrapping and multi-line align-content
- reverse directions
- baseline alignment beyond treating it as start
- grid, block layout, floats, overflow, scrollbars, aspect ratio
- CSS box-sizing modes
- id recycling/generations
- cache invalidation beyond direct recomputation
- pixel rounding or renderer-scale snapping

The old experimental widget/renderer files and assets were removed from this repository. They overlapped ZPUI and were not Zig 0.17-compatible; keeping them around made Zenolith look like a competing GUI stack instead of the layout-only package it is meant to become.

These are left out to keep the storage model small and the flex algorithm legible before expanding toward broader Taffy parity.
