//! A small, fixed-storage, Taffy-inspired flex layout engine.

pub const types = @import("layout/types.zig");
pub const tree = @import("layout/tree.zig");

pub const AlignItems = types.AlignItems;
pub const AvailableSize = types.AvailableSize;
pub const AvailableSpace = types.AvailableSpace;
pub const Display = types.Display;
pub const Edges = types.Edges;
pub const Error = types.Error;
pub const FlexDirection = types.FlexDirection;
pub const JustifyContent = types.JustifyContent;
pub const Layout = types.Layout;
pub const LayoutInput = types.LayoutInput;
pub const Length = types.Length;
pub const Measure = types.Measure;
pub const MeasureFn = types.MeasureFn;
pub const MaybeSize = types.MaybeSize;
pub const NodeId = types.NodeId;
pub const Point = types.Point;
pub const Point2 = types.Point2;
pub const Position = types.Position;
pub const Rect = types.Rect;
pub const Size = types.Size;
pub const Style = types.Style;
pub const StyleEdges = types.StyleEdges;
pub const StyleSize = types.StyleSize;

pub const ComputedLayout = types.Layout;
pub const LayoutStyle = types.Style;

pub const Limits = tree.Limits;
pub const Storage = tree.Storage;
pub const Tree = tree.Tree;

test {
    _ = types;
    _ = tree;
    _ = @import("layout/tests.zig");
}
