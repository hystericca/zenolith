const std = @import("std");
const layout = @import("../layout.zig");

const Limits = layout.Limits{ .nodes = 32, .children = 64, .flex_items = 64 };
const Storage = layout.Storage(Limits);
const Tree = layout.Tree(Limits);

fn expectNear(actual: layout.Point, expected: layout.Point) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.001);
}

fn expectRect(tree: *const Tree, id: layout.NodeId, x: layout.Point, y: layout.Point, width: layout.Point, height: layout.Point) !void {
    const actual = try tree.layout(id);
    try expectNear(actual.location.x, x);
    try expectNear(actual.location.y, y);
    try expectNear(actual.size.width, width);
    try expectNear(actual.size.height, height);
}

fn fixed(width: layout.Point, height: layout.Point) layout.Style {
    return .{ .size = layout.StyleSize.points(width, height) };
}

test "fixed row" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .flex_direction = .row, .align_items = .start });
    const a = try tree.newNode(fixed(20, 10));
    const b = try tree.newNode(fixed(30, 10));
    try tree.setChildren(root, &.{ a, b });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, root, 0, 0, 100, 20);
    try expectRect(&tree, a, 0, 0, 20, 10);
    try expectRect(&tree, b, 20, 0, 30, 10);
}

test "fixed column" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(40, 80), .flex_direction = .column, .align_items = .start });
    const a = try tree.newNode(fixed(10, 20));
    const b = try tree.newNode(fixed(10, 30));
    try tree.setChildren(root, &.{ a, b });
    try tree.computeLayout(root, layout.AvailableSize.definite(40, 80));

    try expectRect(&tree, a, 0, 0, 10, 20);
    try expectRect(&tree, b, 0, 20, 10, 30);
}

test "gap" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{
        .size = layout.StyleSize.points(100, 20),
        .flex_direction = .row,
        .align_items = .start,
        .gap = .{ .width = layout.Length.pt(5), .height = layout.Length.zero() },
    });
    const a = try tree.newNode(fixed(10, 10));
    const b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(root, &.{ a, b });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, a, 0, 0, 10, 10);
    try expectRect(&tree, b, 15, 0, 10, 10);
}

test "padding and border offset child content" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{
        .size = layout.StyleSize.points(100, 50),
        .padding = layout.StyleEdges.all(5),
        .border = layout.StyleEdges.all(2),
        .align_items = .start,
    });
    const child = try tree.newNode(fixed(10, 10));
    try tree.setChildren(root, &.{child});
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 50));

    try expectRect(&tree, child, 7, 7, 10, 10);
}

test "flex grow" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .align_items = .start });
    const a = try tree.newNode(.{ .flex_basis = layout.Length.pt(20), .flex_grow = 1, .size = .{ .height = layout.Length.pt(10) } });
    const b = try tree.newNode(.{ .flex_basis = layout.Length.pt(20), .flex_grow = 2, .size = .{ .height = layout.Length.pt(10) } });
    try tree.setChildren(root, &.{ a, b });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, a, 0, 0, 40, 10);
    try expectRect(&tree, b, 40, 0, 60, 10);
}

test "flex shrink" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(150, 20), .align_items = .start });
    const a = try tree.newNode(fixed(100, 10));
    const b = try tree.newNode(fixed(100, 10));
    try tree.setChildren(root, &.{ a, b });
    try tree.computeLayout(root, layout.AvailableSize.definite(150, 20));

    try expectRect(&tree, a, 0, 0, 75, 10);
    try expectRect(&tree, b, 75, 0, 75, 10);
}

test "min max clamp" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(200, 20), .align_items = .start });
    const child = try tree.newNode(.{
        .flex_basis = layout.Length.pt(20),
        .flex_grow = 1,
        .min_size = .{ .width = layout.Length.pt(30) },
        .max_size = .{ .width = layout.Length.pt(50) },
        .size = .{ .height = layout.Length.pt(10) },
    });
    try tree.setChildren(root, &.{child});
    try tree.computeLayout(root, layout.AvailableSize.definite(200, 20));

    try expectRect(&tree, child, 0, 0, 50, 10);
}

test "align center end stretch" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const center_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 100), .align_items = .center });
    const centered = try tree.newNode(fixed(10, 20));
    try tree.setChildren(center_root, &.{centered});

    const end_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 100), .align_items = .end });
    const ended = try tree.newNode(fixed(10, 20));
    try tree.setChildren(end_root, &.{ended});

    const stretch_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 100), .align_items = .stretch });
    const stretched = try tree.newNode(.{ .size = .{ .width = layout.Length.pt(10) } });
    try tree.setChildren(stretch_root, &.{stretched});

    try tree.computeLayout(center_root, layout.AvailableSize.definite(100, 100));
    try tree.computeLayout(end_root, layout.AvailableSize.definite(100, 100));
    try tree.computeLayout(stretch_root, layout.AvailableSize.definite(100, 100));

    try expectRect(&tree, centered, 0, 40, 10, 20);
    try expectRect(&tree, ended, 0, 80, 10, 20);
    try expectRect(&tree, stretched, 0, 0, 10, 100);
}

test "justify start center end between" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const start_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .justify_content = .start, .align_items = .start });
    const start_a = try tree.newNode(fixed(10, 10));
    const start_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(start_root, &.{ start_a, start_b });

    const center_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .justify_content = .center, .align_items = .start });
    const center_a = try tree.newNode(fixed(10, 10));
    const center_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(center_root, &.{ center_a, center_b });

    const end_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .justify_content = .end, .align_items = .start });
    const end_a = try tree.newNode(fixed(10, 10));
    const end_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(end_root, &.{ end_a, end_b });

    const between_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .justify_content = .space_between, .align_items = .start });
    const between_a = try tree.newNode(fixed(10, 10));
    const between_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(between_root, &.{ between_a, between_b });

    try tree.computeLayout(start_root, layout.AvailableSize.definite(100, 20));
    try tree.computeLayout(center_root, layout.AvailableSize.definite(100, 20));
    try tree.computeLayout(end_root, layout.AvailableSize.definite(100, 20));
    try tree.computeLayout(between_root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, start_a, 0, 0, 10, 10);
    try expectRect(&tree, start_b, 10, 0, 10, 10);
    try expectRect(&tree, center_a, 40, 0, 10, 10);
    try expectRect(&tree, center_b, 50, 0, 10, 10);
    try expectRect(&tree, end_a, 80, 0, 10, 10);
    try expectRect(&tree, end_b, 90, 0, 10, 10);
    try expectRect(&tree, between_a, 0, 0, 10, 10);
    try expectRect(&tree, between_b, 90, 0, 10, 10);
}

test "justify around and evenly" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const around_root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .justify_content = .space_around, .align_items = .start });
    const around_a = try tree.newNode(fixed(10, 10));
    const around_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(around_root, &.{ around_a, around_b });

    const evenly_root = try tree.newNode(.{ .size = layout.StyleSize.points(110, 20), .justify_content = .space_evenly, .align_items = .start });
    const evenly_a = try tree.newNode(fixed(10, 10));
    const evenly_b = try tree.newNode(fixed(10, 10));
    try tree.setChildren(evenly_root, &.{ evenly_a, evenly_b });

    try tree.computeLayout(around_root, layout.AvailableSize.definite(100, 20));
    try tree.computeLayout(evenly_root, layout.AvailableSize.definite(110, 20));

    try expectRect(&tree, around_a, 20, 0, 10, 10);
    try expectRect(&tree, around_b, 70, 0, 10, 10);
    try expectRect(&tree, evenly_a, 30, 0, 10, 10);
    try expectRect(&tree, evenly_b, 70, 0, 10, 10);
}

test "absolute child" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 100), .align_items = .start });
    const flow = try tree.newNode(fixed(20, 20));
    const absolute = try tree.newNode(.{
        .position = .absolute,
        .inset = .{ .left = layout.Length.pt(10), .top = layout.Length.pt(20), .right = .auto, .bottom = .auto },
        .size = layout.StyleSize.points(30, 40),
    });
    try tree.setChildren(root, &.{ flow, absolute });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 100));

    try expectRect(&tree, flow, 0, 0, 20, 20);
    try expectRect(&tree, absolute, 10, 20, 30, 40);
}

fn measureText(_: ?*anyopaque, _: layout.NodeId, _: layout.LayoutInput) layout.Error!layout.Size {
    return .{ .width = 42, .height = 9 };
}

test "measured text leaf" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .align_items = .start });
    const text = try tree.newLeaf(.{}, .{ .func = measureText });
    try tree.setChildren(root, &.{text});
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, text, 0, 0, 42, 9);
}

test "percent size" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(200, 100), .align_items = .start });
    const child = try tree.newNode(.{ .size = layout.StyleSize.percent(0.5, 0.25) });
    try tree.setChildren(root, &.{child});
    try tree.computeLayout(root, layout.AvailableSize.definite(200, 100));

    try expectRect(&tree, child, 0, 0, 100, 25);
}

test "display none is excluded from flex flow" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .align_items = .start });
    const hidden = try tree.newNode(.{ .display = .none, .size = layout.StyleSize.points(50, 10) });
    const visible = try tree.newNode(fixed(10, 10));
    try tree.setChildren(root, &.{ hidden, visible });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));

    try expectRect(&tree, hidden, 0, 0, 0, 0);
    try expectRect(&tree, visible, 0, 0, 10, 10);
}

test "display none clears stale child layout after style update" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{ .size = layout.StyleSize.points(100, 20), .align_items = .start });
    const child = try tree.newNode(fixed(10, 10));
    try tree.setChildren(root, &.{child});
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));
    try expectRect(&tree, child, 0, 0, 10, 10);

    try tree.setStyle(child, .{ .display = .none, .size = layout.StyleSize.points(10, 10) });
    try tree.computeLayout(root, layout.AvailableSize.definite(100, 20));
    try expectRect(&tree, child, 0, 0, 0, 0);
}

test "capacity errors" {
    const SmallLimits = layout.Limits{ .nodes = 1, .children = 0, .flex_items = 0 };
    var storage = layout.Storage(SmallLimits){};
    var tree = layout.Tree(SmallLimits).init(&storage);
    _ = try tree.newNode(.{});
    try std.testing.expectError(layout.Error.CapacityExceeded, tree.newNode(.{}));
}

test "tree invariant errors" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    const root = try tree.newNode(.{});
    const a = try tree.newNode(.{});
    const b = try tree.newNode(.{});

    try std.testing.expectError(layout.Error.CycleDetected, tree.setChildren(root, &.{root}));
    try std.testing.expectError(layout.Error.DuplicateChild, tree.setChildren(root, &.{ a, a }));

    try tree.setChildren(root, &.{a});
    try std.testing.expectError(layout.Error.ChildrenAlreadySet, tree.setChildren(root, &.{b}));
    try std.testing.expectError(layout.Error.AlreadyHasParent, tree.setChildren(b, &.{a}));
}

test "invalid size errors" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    try std.testing.expectError(layout.Error.InvalidSize, tree.newNode(.{ .padding = layout.StyleEdges.all(-1) }));
    try std.testing.expectError(layout.Error.InvalidSize, tree.newNode(.{ .size = layout.StyleSize.points(-1, 1) }));
    try std.testing.expectError(layout.Error.InvalidSize, tree.newNode(.{ .flex_basis = layout.Length.pt(-1) }));
}

test "invalid inset errors" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    try std.testing.expectError(layout.Error.InvalidSize, tree.newNode(.{ .inset = .{ .left = layout.Length.pt(std.math.inf(f32)) } }));
}

test "invalid node errors" {
    var storage = Storage{};
    var tree = Tree.init(&storage);
    try std.testing.expectError(layout.Error.InvalidNode, tree.layout(.{ .index = 99 }));
}
