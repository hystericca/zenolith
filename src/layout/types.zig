const std = @import("std");

pub const Point = f32;

pub const Error = error{
    CapacityExceeded,
    InvalidNode,
    AlreadyHasParent,
    ChildrenAlreadySet,
    CycleDetected,
    DuplicateChild,
    InvalidSize,
    NumericOverflow,
};

pub const NodeId = extern struct {
    index: u32,

    pub fn format(
        self: NodeId,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("NodeId({d})", .{self.index});
    }
};

pub const Point2 = struct {
    x: Point = 0,
    y: Point = 0,

    pub const zero: Point2 = .{};
};

pub const Size = struct {
    width: Point = 0,
    height: Point = 0,

    pub const zero: Size = .{};

    pub fn init(width: Point, height: Point) Size {
        return .{ .width = width, .height = height };
    }

    pub fn main(self: Size, direction: FlexDirection) Point {
        return if (direction.isRow()) self.width else self.height;
    }

    pub fn cross(self: Size, direction: FlexDirection) Point {
        return if (direction.isRow()) self.height else self.width;
    }

    pub fn setMain(self: *Size, direction: FlexDirection, value: Point) void {
        if (direction.isRow()) {
            self.width = value;
        } else {
            self.height = value;
        }
    }

    pub fn setCross(self: *Size, direction: FlexDirection, value: Point) void {
        if (direction.isRow()) {
            self.height = value;
        } else {
            self.width = value;
        }
    }
};

pub const Rect = extern struct {
    x: Point = 0,
    y: Point = 0,
    width: Point = 0,
    height: Point = 0,

    pub fn init(x: Point, y: Point, width: Point, height: Point) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn size(self: Rect) Size {
        return .{ .width = self.width, .height = self.height };
    }
};

pub const MaybeSize = struct {
    width: ?Point = null,
    height: ?Point = null,

    pub const none: MaybeSize = .{};

    pub fn init(width: ?Point, height: ?Point) MaybeSize {
        return .{ .width = width, .height = height };
    }

    pub fn fromSize(size: Size) MaybeSize {
        return .{ .width = size.width, .height = size.height };
    }

    pub fn main(self: MaybeSize, direction: FlexDirection) ?Point {
        return if (direction.isRow()) self.width else self.height;
    }

    pub fn cross(self: MaybeSize, direction: FlexDirection) ?Point {
        return if (direction.isRow()) self.height else self.width;
    }

    pub fn setMain(self: *MaybeSize, direction: FlexDirection, value: ?Point) void {
        if (direction.isRow()) {
            self.width = value;
        } else {
            self.height = value;
        }
    }

    pub fn setCross(self: *MaybeSize, direction: FlexDirection, value: ?Point) void {
        if (direction.isRow()) {
            self.height = value;
        } else {
            self.width = value;
        }
    }

    pub fn orElse(self: MaybeSize, fallback: MaybeSize) MaybeSize {
        return .{
            .width = self.width orelse fallback.width,
            .height = self.height orelse fallback.height,
        };
    }

    pub fn unwrapOr(self: MaybeSize, fallback: Size) Size {
        return .{
            .width = self.width orelse fallback.width,
            .height = self.height orelse fallback.height,
        };
    }
};

pub const AvailableSpace = union(enum) {
    definite: Point,
    min_content,
    max_content,

    pub fn points(value: Point) AvailableSpace {
        return .{ .definite = value };
    }

    pub fn intoMaybe(self: AvailableSpace) ?Point {
        return switch (self) {
            .definite => |value| value,
            .min_content, .max_content => null,
        };
    }

    pub fn mapDefinite(self: AvailableSpace, amount: Point) AvailableSpace {
        return switch (self) {
            .definite => |value| .{ .definite = value - amount },
            .min_content => .min_content,
            .max_content => .max_content,
        };
    }
};

pub const AvailableSize = struct {
    width: AvailableSpace = .max_content,
    height: AvailableSpace = .max_content,

    pub fn definite(width: Point, height: Point) AvailableSize {
        return .{ .width = .{ .definite = width }, .height = .{ .definite = height } };
    }

    pub fn intoMaybe(self: AvailableSize) MaybeSize {
        return .{ .width = self.width.intoMaybe(), .height = self.height.intoMaybe() };
    }

    pub fn main(self: AvailableSize, direction: FlexDirection) AvailableSpace {
        return if (direction.isRow()) self.width else self.height;
    }

    pub fn cross(self: AvailableSize, direction: FlexDirection) AvailableSpace {
        return if (direction.isRow()) self.height else self.width;
    }
};

pub const Edges = struct {
    left: Point = 0,
    right: Point = 0,
    top: Point = 0,
    bottom: Point = 0,

    pub const zero: Edges = .{};

    pub fn all(value: Point) Edges {
        return .{ .left = value, .right = value, .top = value, .bottom = value };
    }

    pub fn horizontal(self: Edges) Point {
        return self.left + self.right;
    }

    pub fn vertical(self: Edges) Point {
        return self.top + self.bottom;
    }

    pub fn mainStart(self: Edges, direction: FlexDirection) Point {
        return if (direction.isRow()) self.left else self.top;
    }

    pub fn mainEnd(self: Edges, direction: FlexDirection) Point {
        return if (direction.isRow()) self.right else self.bottom;
    }

    pub fn crossStart(self: Edges, direction: FlexDirection) Point {
        return if (direction.isRow()) self.top else self.left;
    }

    pub fn crossEnd(self: Edges, direction: FlexDirection) Point {
        return if (direction.isRow()) self.bottom else self.right;
    }

    pub fn mainSum(self: Edges, direction: FlexDirection) Point {
        return self.mainStart(direction) + self.mainEnd(direction);
    }

    pub fn crossSum(self: Edges, direction: FlexDirection) Point {
        return self.crossStart(direction) + self.crossEnd(direction);
    }
};

pub const Length = union(enum) {
    auto,
    points: Point,
    percent: Point,

    pub fn pt(value: Point) Length {
        return .{ .points = value };
    }

    pub fn pct(fraction: Point) Length {
        return .{ .percent = fraction };
    }

    pub fn zero() Length {
        return .{ .points = 0 };
    }

    pub fn resolve(self: Length, basis: ?Point) ?Point {
        return switch (self) {
            .auto => null,
            .points => |value| value,
            .percent => |fraction| if (basis) |known| known * fraction else null,
        };
    }

    pub fn resolveOrZero(self: Length, basis: ?Point) Point {
        return self.resolve(basis) orelse 0;
    }

    pub fn isAuto(self: Length) bool {
        return switch (self) {
            .auto => true,
            else => false,
        };
    }
};

pub const StyleSize = struct {
    width: Length = .auto,
    height: Length = .auto,

    pub fn auto() StyleSize {
        return .{};
    }

    pub fn points(width: Point, height: Point) StyleSize {
        return .{ .width = Length.pt(width), .height = Length.pt(height) };
    }

    pub fn percent(width: Point, height: Point) StyleSize {
        return .{ .width = Length.pct(width), .height = Length.pct(height) };
    }

    pub fn zero() StyleSize {
        return .{ .width = Length.zero(), .height = Length.zero() };
    }

    pub fn resolve(self: StyleSize, basis: MaybeSize) MaybeSize {
        return .{
            .width = self.width.resolve(basis.width),
            .height = self.height.resolve(basis.height),
        };
    }

    pub fn main(self: StyleSize, direction: FlexDirection) Length {
        return if (direction.isRow()) self.width else self.height;
    }

    pub fn cross(self: StyleSize, direction: FlexDirection) Length {
        return if (direction.isRow()) self.height else self.width;
    }
};

pub const StyleEdges = struct {
    left: Length = .{ .points = 0 },
    right: Length = .{ .points = 0 },
    top: Length = .{ .points = 0 },
    bottom: Length = .{ .points = 0 },

    pub fn zero() StyleEdges {
        return .{};
    }

    pub fn auto() StyleEdges {
        return .{ .left = .auto, .right = .auto, .top = .auto, .bottom = .auto };
    }

    pub fn all(value: Point) StyleEdges {
        const length = Length.pt(value);
        return .{ .left = length, .right = length, .top = length, .bottom = length };
    }

    pub fn horizontalVertical(horizontal: Point, vertical: Point) StyleEdges {
        return .{
            .left = Length.pt(horizontal),
            .right = Length.pt(horizontal),
            .top = Length.pt(vertical),
            .bottom = Length.pt(vertical),
        };
    }

    pub fn resolveOrZero(self: StyleEdges, basis: ?Point) Edges {
        return .{
            .left = self.left.resolveOrZero(basis),
            .right = self.right.resolveOrZero(basis),
            .top = self.top.resolveOrZero(basis),
            .bottom = self.bottom.resolveOrZero(basis),
        };
    }

    pub fn resolveMaybe(self: StyleEdges, basis_width: ?Point, basis_height: ?Point) MaybeEdges {
        return .{
            .left = self.left.resolve(basis_width),
            .right = self.right.resolve(basis_width),
            .top = self.top.resolve(basis_height),
            .bottom = self.bottom.resolve(basis_height),
        };
    }
};

pub const MaybeEdges = struct {
    left: ?Point = null,
    right: ?Point = null,
    top: ?Point = null,
    bottom: ?Point = null,

    pub fn nonAuto(self: MaybeEdges) Edges {
        return .{
            .left = self.left orelse 0,
            .right = self.right orelse 0,
            .top = self.top orelse 0,
            .bottom = self.bottom orelse 0,
        };
    }
};

pub const Display = enum {
    flex,
    none,
};

pub const Position = enum {
    relative,
    absolute,
};

pub const FlexDirection = enum {
    row,
    column,

    pub fn isRow(self: FlexDirection) bool {
        return self == .row;
    }
};

pub const AlignItems = enum {
    start,
    end,
    flex_start,
    flex_end,
    center,
    baseline,
    stretch,
};

pub const JustifyContent = enum {
    start,
    end,
    flex_start,
    flex_end,
    center,
    stretch,
    space_between,
    space_around,
    space_evenly,
};

pub const Style = struct {
    display: Display = .flex,
    position: Position = .relative,
    inset: StyleEdges = StyleEdges.auto(),
    size: StyleSize = StyleSize.auto(),
    min_size: StyleSize = StyleSize.auto(),
    max_size: StyleSize = StyleSize.auto(),
    margin: StyleEdges = StyleEdges.zero(),
    padding: StyleEdges = StyleEdges.zero(),
    border: StyleEdges = StyleEdges.zero(),
    gap: StyleSize = StyleSize.zero(),
    flex_direction: FlexDirection = .row,
    flex_basis: Length = .auto,
    flex_grow: Point = 0,
    flex_shrink: Point = 1,
    align_items: AlignItems = .stretch,
    align_self: ?AlignItems = null,
    justify_content: JustifyContent = .flex_start,
};

pub const Layout = struct {
    order: u32 = 0,
    location: Point2 = .{},
    size: Size = .{},
    padding: Edges = .{},
    border: Edges = .{},
    margin: Edges = .{},

    pub const zero: Layout = .{};

    pub fn rect(self: Layout) Rect {
        return .{
            .x = self.location.x,
            .y = self.location.y,
            .width = self.size.width,
            .height = self.size.height,
        };
    }

    pub fn contentSize(self: Layout) Size {
        return .{
            .width = @max(0, self.size.width - self.padding.horizontal() - self.border.horizontal()),
            .height = @max(0, self.size.height - self.padding.vertical() - self.border.vertical()),
        };
    }
};

pub const LayoutInput = struct {
    known_size: MaybeSize = .{},
    parent_size: MaybeSize = .{},
    available_space: AvailableSize = .{},
};

pub const MeasureFn = *const fn (context: ?*anyopaque, node: NodeId, input: LayoutInput) Error!Size;

pub const Measure = struct {
    func: MeasureFn,
    context: ?*anyopaque = null,
};

pub fn finite(value: Point) bool {
    return std.math.isFinite(value);
}
