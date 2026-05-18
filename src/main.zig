//! Zenolith's current public surface is the fixed-storage layout engine.

pub const layout = @import("layout.zig");

pub const AlignItems = layout.AlignItems;
pub const AvailableSize = layout.AvailableSize;
pub const AvailableSpace = layout.AvailableSpace;
pub const Display = layout.Display;
pub const Edges = layout.Edges;
pub const Error = layout.Error;
pub const FlexDirection = layout.FlexDirection;
pub const JustifyContent = layout.JustifyContent;
pub const Layout = layout.Layout;
pub const LayoutInput = layout.LayoutInput;
pub const Length = layout.Length;
pub const Limits = layout.Limits;
pub const Measure = layout.Measure;
pub const MeasureFn = layout.MeasureFn;
pub const MaybeSize = layout.MaybeSize;
pub const NodeId = layout.NodeId;
pub const Point = layout.Point;
pub const Point2 = layout.Point2;
pub const Position = layout.Position;
pub const Rect = layout.Rect;
pub const Size = layout.Size;
pub const Storage = layout.Storage;
pub const Style = layout.Style;
pub const StyleEdges = layout.StyleEdges;
pub const StyleSize = layout.StyleSize;
pub const Tree = layout.Tree;

pub const ComputedLayout = layout.ComputedLayout;
pub const LayoutStyle = layout.LayoutStyle;

test {
    _ = layout;
}
