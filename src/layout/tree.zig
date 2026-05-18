const std = @import("std");
const types = @import("types.zig");

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
pub const MaybeSize = types.MaybeSize;
pub const NodeId = types.NodeId;
pub const Point = types.Point;
pub const Point2 = types.Point2;
pub const Position = types.Position;
pub const Size = types.Size;
pub const Style = types.Style;

pub const Limits = struct {
    nodes: usize,
    children: usize,
    flex_items: usize,
};

const Node = struct {
    parent: ?NodeId = null,
    child_start: usize = 0,
    child_count: usize = 0,
    style: Style = .{},
    measure: ?Measure = null,
};

const FlexItem = struct {
    node: NodeId,
    order: u32,
    margin: Edges,
    padding: Edges,
    border: Edges,
    min_size: MaybeSize,
    max_size: MaybeSize,
    style_size: MaybeSize,
    align_self: AlignItems,
    flex_grow: Point,
    flex_shrink: Point,
    flex_basis: Point,
    inner_flex_basis: Point,
    target_size: Size = .{},
    outer_target_size: Size = .{},
    hypothetical_size: Size = .{},
    frozen: bool = false,
    violation: Point = 0,
};

pub fn Storage(comptime limits: Limits) type {
    return struct {
        nodes: [limits.nodes]Node = undefined,
        layouts: [limits.nodes]Layout = undefined,
        children: [limits.children]NodeId = undefined,
        flex_items: [limits.flex_items]FlexItem = undefined,
        node_count: usize = 0,
        child_count: usize = 0,
        flex_used: usize = 0,

        pub fn reset(self: *@This()) void {
            self.node_count = 0;
            self.child_count = 0;
            self.flex_used = 0;
            for (self.nodes[0..]) |*node| node.* = .{};
            for (self.layouts[0..]) |*layout| layout.* = Layout.zero;
        }
    };
}

pub fn Tree(comptime limits: Limits) type {
    return struct {
        storage: *Storage(limits),

        const Self = @This();

        pub fn init(storage: *Storage(limits)) Self {
            storage.reset();
            return .{ .storage = storage };
        }

        pub fn reset(self: *Self) void {
            self.storage.reset();
        }

        pub fn newNode(self: *Self, node_style: Style) Error!NodeId {
            try validateStyle(node_style);
            if (self.storage.node_count >= limits.nodes) return Error.CapacityExceeded;
            const id: NodeId = .{ .index = @intCast(self.storage.node_count) };
            self.storage.nodes[self.storage.node_count] = .{ .style = node_style };
            self.storage.layouts[self.storage.node_count] = Layout.zero;
            self.storage.node_count += 1;
            return id;
        }

        pub fn newLeaf(self: *Self, node_style: Style, measure: Measure) Error!NodeId {
            const id = try self.newNode(node_style);
            self.storage.nodes[id.index].measure = measure;
            return id;
        }

        pub fn setMeasure(self: *Self, id: NodeId, measure: ?Measure) Error!void {
            const record = try self.nodePtr(id);
            record.measure = measure;
        }

        pub fn setStyle(self: *Self, id: NodeId, node_style: Style) Error!void {
            try validateStyle(node_style);
            const record = try self.nodePtr(id);
            record.style = node_style;
        }

        pub fn setChildren(self: *Self, parent: NodeId, child_ids_input: []const NodeId) Error!void {
            _ = try self.nodePtr(parent);
            if (self.storage.nodes[parent.index].child_count != 0) return Error.ChildrenAlreadySet;
            if (self.storage.child_count + child_ids_input.len > limits.children) return Error.CapacityExceeded;

            for (child_ids_input, 0..) |child, index| {
                _ = try self.nodePtr(child);
                if (self.storage.nodes[child.index].parent != null) return Error.AlreadyHasParent;
                try self.validateNoCycle(parent, child);
                for (child_ids_input[0..index]) |previous| {
                    if (previous.index == child.index) return Error.DuplicateChild;
                }
            }

            const start = self.storage.child_count;
            for (child_ids_input, 0..) |child, i| {
                self.storage.children[start + i] = child;
                self.storage.nodes[child.index].parent = parent;
            }
            self.storage.child_count += child_ids_input.len;
            self.storage.nodes[parent.index].child_start = start;
            self.storage.nodes[parent.index].child_count = child_ids_input.len;
        }

        pub fn appendChild(self: *Self, parent: NodeId, child: NodeId) Error!void {
            _ = try self.nodePtr(parent);
            _ = try self.nodePtr(child);
            if (self.storage.nodes[child.index].parent != null) return Error.AlreadyHasParent;
            try self.validateNoCycle(parent, child);
            if (self.storage.child_count >= limits.children) return Error.CapacityExceeded;

            var parent_node = &self.storage.nodes[parent.index];
            if (parent_node.child_count == 0) {
                parent_node.child_start = self.storage.child_count;
            } else if (parent_node.child_start + parent_node.child_count != self.storage.child_count) {
                return Error.ChildrenAlreadySet;
            }

            self.storage.children[self.storage.child_count] = child;
            self.storage.child_count += 1;
            parent_node.child_count += 1;
            self.storage.nodes[child.index].parent = parent;
        }

        pub fn computeLayout(self: *Self, root: NodeId, available_space: AvailableSize) Error!void {
            _ = try self.nodePtr(root);
            try validateAvailableSize(available_space);

            const root_style = self.storage.nodes[root.index].style;
            if (root_style.display == .none) {
                try self.writeHidden(root);
                return;
            }

            const parent_size = available_space.intoMaybe();
            var known_size = root_style.size.resolve(parent_size).orElse(available_space.intoMaybe());
            known_size = clampMaybeSize(
                known_size,
                root_style.min_size.resolve(parent_size),
                root_style.max_size.resolve(parent_size),
            );

            const size = try self.layoutNode(root, .{
                .known_size = known_size,
                .parent_size = parent_size,
                .available_space = available_space,
            }, .{});

            var root_layout = &self.storage.layouts[root.index];
            root_layout.location = .{};
            try validatePoint(root_layout.location);
            root_layout.size = size;
        }

        pub fn layout(self: *const Self, id: NodeId) Error!Layout {
            _ = try self.node(id);
            return self.storage.layouts[id.index];
        }

        pub fn getStyle(self: *const Self, id: NodeId) Error!Style {
            return (try self.node(id)).style;
        }

        pub fn childCount(self: *const Self, id: NodeId) Error!usize {
            return (try self.node(id)).child_count;
        }

        fn node(self: *const Self, id: NodeId) Error!*const Node {
            if (id.index >= self.storage.node_count) return Error.InvalidNode;
            return &self.storage.nodes[id.index];
        }

        fn nodePtr(self: *Self, id: NodeId) Error!*Node {
            if (id.index >= self.storage.node_count) return Error.InvalidNode;
            return &self.storage.nodes[id.index];
        }

        fn children(self: *const Self, id: NodeId) Error![]const NodeId {
            const n = try self.node(id);
            return self.storage.children[n.child_start .. n.child_start + n.child_count];
        }

        fn validateNoCycle(self: *const Self, parent: NodeId, child: NodeId) Error!void {
            var cursor: ?NodeId = parent;
            while (cursor) |ancestor| {
                if (ancestor.index == child.index) return Error.CycleDetected;
                cursor = self.storage.nodes[ancestor.index].parent;
            }
        }

        fn layoutNode(self: *Self, id: NodeId, input: LayoutInput, location: Point2) Error!Size {
            const n = try self.node(id);
            try validateStyle(n.style);
            try validateLayoutInput(input);
            try validatePoint(location);

            if (n.style.display == .none) {
                try self.writeHidden(id);
                return Size.zero;
            }

            const padding = try resolveBoxEdges(n.style.padding, input.parent_size.width, true);
            const border = try resolveBoxEdges(n.style.border, input.parent_size.width, true);
            const margin = try resolveMargin(n.style.margin, input.parent_size.width);

            var node_layout = &self.storage.layouts[id.index];
            node_layout.location = location;
            node_layout.padding = padding;
            node_layout.border = border;
            node_layout.margin = margin;

            const child_ids = try self.children(id);
            var has_layout_child = false;
            for (child_ids) |child| {
                const child_style = (try self.node(child)).style;
                if (child_style.display == .none) {
                    try self.writeHidden(child);
                } else {
                    has_layout_child = true;
                }
            }

            const size = if (has_layout_child)
                try self.layoutFlexContainer(id, input, padding, border)
            else
                try self.layoutLeaf(id, input, padding, border);

            node_layout = &self.storage.layouts[id.index];
            node_layout.location = location;
            node_layout.size = size;
            node_layout.padding = padding;
            node_layout.border = border;
            node_layout.margin = margin;
            return size;
        }

        fn layoutLeaf(self: *Self, id: NodeId, input: LayoutInput, padding: Edges, border: Edges) Error!Size {
            const n = try self.node(id);
            const node_style = n.style;
            const style_size = node_style.size.resolve(input.parent_size);
            const min_size = node_style.min_size.resolve(input.parent_size);
            const max_size = node_style.max_size.resolve(input.parent_size);
            const padding_border = Size.init(
                try checked(padding.horizontal() + border.horizontal()),
                try checked(padding.vertical() + border.vertical()),
            );

            var known = input.known_size.orElse(style_size);
            known = clampMaybeSize(known, min_size, max_size);
            var measured = Size.zero;

            if (known.width == null or known.height == null) {
                if (n.measure) |measure| {
                    const content_known = MaybeSize{
                        .width = if (known.width) |w| @max(0, w - padding_border.width) else null,
                        .height = if (known.height) |h| @max(0, h - padding_border.height) else null,
                    };
                    const content_available = subtractAvailable(input.available_space, padding_border);
                    measured = try measure.func(measure.context, id, .{
                        .known_size = content_known,
                        .parent_size = input.parent_size,
                        .available_space = content_available,
                    });
                    try validateSize(measured);
                }
            }

            var size = Size{
                .width = known.width orelse try checked(measured.width + padding_border.width),
                .height = known.height orelse try checked(measured.height + padding_border.height),
            };
            size = clampSize(size, min_size, max_size);
            size.width = @max(size.width, padding_border.width);
            size.height = @max(size.height, padding_border.height);
            try validateSize(size);
            return size;
        }

        fn layoutFlexContainer(self: *Self, id: NodeId, input: LayoutInput, padding: Edges, border: Edges) Error!Size {
            const n = try self.node(id);
            const node_style = n.style;
            const dir = node_style.flex_direction;
            const padding_border = Edges{
                .left = padding.left + border.left,
                .right = padding.right + border.right,
                .top = padding.top + border.top,
                .bottom = padding.bottom + border.bottom,
            };
            const padding_border_size = Size.init(padding_border.horizontal(), padding_border.vertical());
            const parent_size = input.parent_size;
            const style_size = node_style.size.resolve(parent_size);
            const min_size = node_style.min_size.resolve(parent_size);
            const max_size = node_style.max_size.resolve(parent_size);
            var outer_size = clampMaybeSize(input.known_size.orElse(style_size), min_size, max_size);
            var inner_size = MaybeSize{
                .width = if (outer_size.width) |width| @max(0, width - padding_border_size.width) else null,
                .height = if (outer_size.height) |height| @max(0, height - padding_border_size.height) else null,
            };

            const inner_parent_size = inner_size;
            var gap = Size{
                .width = node_style.gap.width.resolveOrZero(inner_size.width),
                .height = node_style.gap.height.resolveOrZero(inner_size.height),
            };
            try validateNonNegative(gap.width);
            try validateNonNegative(gap.height);

            const child_ids = try self.children(id);
            var item_count: usize = 0;
            for (child_ids) |child| {
                const child_node = try self.node(child);
                if (child_node.style.display == .none) {
                    try self.writeHidden(child);
                    continue;
                }
                if (child_node.style.position == .absolute) continue;
                item_count += 1;
            }

            if (self.storage.flex_used + item_count > limits.flex_items) return Error.CapacityExceeded;
            const item_start = self.storage.flex_used;
            self.storage.flex_used += item_count;
            defer self.storage.flex_used = item_start;

            var fill_index: usize = 0;
            for (child_ids, 0..) |child, order| {
                const child_node = try self.node(child);
                if (child_node.style.display == .none or child_node.style.position == .absolute) continue;
                self.storage.flex_items[item_start + fill_index] = try self.makeFlexItem(child, @intCast(order), node_style.align_items, inner_parent_size);
                fill_index += 1;
            }

            const items = self.storage.flex_items[item_start .. item_start + item_count];
            const main_gap = gap.main(dir);
            for (items) |*item| {
                try self.determineFlexBase(item, dir, inner_parent_size, input.available_space);
            }

            if (outer_size.main(dir) == null) {
                var main_sum: Point = padding_border_size.main(dir);
                if (items.len > 1) main_sum += main_gap * @as(Point, @floatFromInt(items.len - 1));
                for (items) |item| {
                    main_sum += item.hypothetical_size.main(dir) + item.margin.mainSum(dir);
                }
                outer_size.setMain(dir, main_sum);
                inner_size.setMain(dir, @max(0, main_sum - padding_border.mainSum(dir)));
            }

            if (inner_size.main(dir) == null) {
                const available_main = input.available_space.main(dir).intoMaybe() orelse 0;
                inner_size.setMain(dir, @max(0, available_main - padding_border.mainSum(dir)));
                outer_size.setMain(dir, inner_size.main(dir).? + padding_border.mainSum(dir));
            }

            const definite_inner_main = inner_size.main(dir).?;
            try self.resolveFlexibleLengths(items, dir, definite_inner_main, main_gap);

            var line_cross: Point = 0;
            for (items) |*item| {
                try self.determineCrossSize(item, dir, inner_parent_size, input.available_space);
                line_cross = @max(line_cross, item.outer_target_size.cross(dir));
            }

            if (outer_size.cross(dir) == null) {
                const cross = line_cross + padding_border.crossSum(dir);
                outer_size.setCross(dir, cross);
                inner_size.setCross(dir, @max(0, cross - padding_border.crossSum(dir)));
            } else if (inner_size.cross(dir) == null) {
                inner_size.setCross(dir, @max(0, outer_size.cross(dir).? - padding_border.crossSum(dir)));
            }

            var final_size = outer_size.unwrapOr(.{});
            final_size = clampSize(final_size, min_size, max_size);
            final_size.width = @max(final_size.width, padding_border_size.width);
            final_size.height = @max(final_size.height, padding_border_size.height);
            try validateSize(final_size);

            const definite_inner_cross = @max(0, final_size.cross(dir) - padding_border.crossSum(dir));
            for (items) |*item| {
                const child_style = (try self.node(item.node)).style;
                const cross_auto = child_style.size.cross(dir).isAuto();
                const alignment = item.align_self;
                if (alignment == .stretch and cross_auto) {
                    const stretched = clampPoint(
                        @max(0, definite_inner_cross - item.margin.crossSum(dir)),
                        item.min_size.cross(dir),
                        item.max_size.cross(dir),
                    );
                    item.target_size.setCross(dir, @max(stretched, item.padding.crossSum(dir) + item.border.crossSum(dir)));
                    item.outer_target_size.setCross(dir, item.target_size.cross(dir) + item.margin.crossSum(dir));
                }
            }

            gap = Size{
                .width = node_style.gap.width.resolveOrZero(if (dir.isRow()) definite_inner_main else definite_inner_cross),
                .height = node_style.gap.height.resolveOrZero(if (dir.isRow()) definite_inner_cross else definite_inner_main),
            };
            try self.positionFlexItems(items, dir, final_size, padding_border, node_style.justify_content, gap.main(dir));
            try self.layoutAbsoluteChildren(id, final_size, inner_size, padding, border);
            return final_size;
        }

        fn makeFlexItem(self: *Self, id: NodeId, order: u32, parent_align: AlignItems, parent_size: MaybeSize) Error!FlexItem {
            const n = try self.node(id);
            const node_style = n.style;
            const margin = try resolveMargin(node_style.margin, parent_size.width);
            const padding = try resolveBoxEdges(node_style.padding, parent_size.width, true);
            const border = try resolveBoxEdges(node_style.border, parent_size.width, true);
            return .{
                .node = id,
                .order = order,
                .margin = margin,
                .padding = padding,
                .border = border,
                .min_size = node_style.min_size.resolve(parent_size),
                .max_size = node_style.max_size.resolve(parent_size),
                .style_size = node_style.size.resolve(parent_size),
                .align_self = node_style.align_self orelse parent_align,
                .flex_grow = node_style.flex_grow,
                .flex_shrink = node_style.flex_shrink,
                .flex_basis = 0,
                .inner_flex_basis = 0,
            };
        }

        fn determineFlexBase(
            self: *Self,
            item: *FlexItem,
            dir: FlexDirection,
            parent_size: MaybeSize,
            available_space: AvailableSize,
        ) Error!void {
            const child_style = (try self.node(item.node)).style;
            const padding_border_main = item.padding.mainSum(dir) + item.border.mainSum(dir);
            const basis = child_style.flex_basis.resolve(parent_size.main(dir)) orelse item.style_size.main(dir);
            var base = basis orelse blk: {
                var known = item.style_size;
                known.setMain(dir, null);
                const measured = try self.layoutNode(item.node, .{
                    .known_size = known,
                    .parent_size = parent_size,
                    .available_space = available_space,
                }, .{});
                break :blk measured.main(dir);
            };
            base = @max(base, padding_border_main);
            item.flex_basis = base;
            item.inner_flex_basis = @max(0, base - padding_border_main);

            const clamped = clampPoint(base, item.min_size.main(dir), item.max_size.main(dir));
            item.hypothetical_size.setMain(dir, clamped);
            item.target_size.setMain(dir, clamped);
            item.outer_target_size.setMain(dir, clamped + item.margin.mainSum(dir));
        }

        fn resolveFlexibleLengths(self: *Self, items: []FlexItem, dir: FlexDirection, inner_main: Point, gap: Point) Error!void {
            _ = self;
            if (items.len == 0) return;
            const total_gap = gap * @as(Point, @floatFromInt(if (items.len > 1) items.len - 1 else 0));
            var total_hypothetical: Point = total_gap;
            for (items) |item| total_hypothetical += item.outer_target_size.main(dir);

            const growing = total_hypothetical < inner_main;
            const shrinking = total_hypothetical > inner_main;
            if (!growing and !shrinking) return;

            for (items) |*item| {
                item.frozen = false;
                item.target_size.setMain(dir, item.flex_basis);
                item.outer_target_size.setMain(dir, item.flex_basis + item.margin.mainSum(dir));
                if ((growing and item.flex_grow == 0) or (shrinking and item.flex_shrink == 0)) {
                    item.frozen = true;
                    const frozen = item.hypothetical_size.main(dir);
                    item.target_size.setMain(dir, frozen);
                    item.outer_target_size.setMain(dir, frozen + item.margin.mainSum(dir));
                }
            }

            while (true) {
                var unfrozen_count: usize = 0;
                var used: Point = total_gap;
                var grow_sum: Point = 0;
                var scaled_shrink_sum: Point = 0;
                for (items) |item| {
                    if (item.frozen) {
                        used += item.outer_target_size.main(dir);
                    } else {
                        unfrozen_count += 1;
                        used += item.flex_basis + item.margin.mainSum(dir);
                        grow_sum += item.flex_grow;
                        scaled_shrink_sum += item.flex_shrink * item.inner_flex_basis;
                    }
                }
                if (unfrozen_count == 0) break;

                const free_space = inner_main - used;
                if (growing and grow_sum > 0) {
                    for (items) |*item| {
                        if (!item.frozen) item.target_size.setMain(dir, item.flex_basis + free_space * (item.flex_grow / grow_sum));
                    }
                } else if (shrinking and scaled_shrink_sum > 0) {
                    for (items) |*item| {
                        if (!item.frozen) {
                            const scaled = item.flex_shrink * item.inner_flex_basis;
                            item.target_size.setMain(dir, item.flex_basis + free_space * (scaled / scaled_shrink_sum));
                        }
                    }
                }

                var total_violation: Point = 0;
                var had_violation = false;
                for (items) |*item| {
                    if (item.frozen) continue;
                    const unclamped = item.target_size.main(dir);
                    const clamped = @max(0, clampPoint(unclamped, item.min_size.main(dir), item.max_size.main(dir)));
                    item.violation = clamped - unclamped;
                    if (@abs(item.violation) > 0.0001) had_violation = true;
                    total_violation += item.violation;
                    item.target_size.setMain(dir, clamped);
                    item.outer_target_size.setMain(dir, clamped + item.margin.mainSum(dir));
                }

                if (!had_violation) {
                    for (items) |*item| {
                        if (!item.frozen) item.frozen = true;
                    }
                    break;
                }

                for (items) |*item| {
                    if (item.frozen) continue;
                    if (total_violation > 0) {
                        if (item.violation > 0) item.frozen = true;
                    } else if (total_violation < 0) {
                        if (item.violation < 0) item.frozen = true;
                    } else {
                        item.frozen = true;
                    }
                }
            }
        }

        fn determineCrossSize(
            self: *Self,
            item: *FlexItem,
            dir: FlexDirection,
            parent_size: MaybeSize,
            available_space: AvailableSize,
        ) Error!void {
            const padding_border_cross = item.padding.crossSum(dir) + item.border.crossSum(dir);
            const known_cross = item.style_size.cross(dir);
            var cross = known_cross orelse blk: {
                var known = MaybeSize.none;
                known.setMain(dir, item.target_size.main(dir));
                const measured = try self.layoutNode(item.node, .{
                    .known_size = known,
                    .parent_size = parent_size,
                    .available_space = available_space,
                }, .{});
                break :blk measured.cross(dir);
            };
            cross = clampPoint(@max(cross, padding_border_cross), item.min_size.cross(dir), item.max_size.cross(dir));
            item.hypothetical_size.setCross(dir, cross);
            item.target_size.setCross(dir, cross);
            item.outer_target_size.setCross(dir, cross + item.margin.crossSum(dir));
        }

        fn positionFlexItems(
            self: *Self,
            items: []FlexItem,
            dir: FlexDirection,
            container_size: Size,
            content_inset: Edges,
            justify: JustifyContent,
            gap_size: Point,
        ) Error!void {
            if (items.len == 0) return;
            const inner_main = @max(0, container_size.main(dir) - content_inset.mainSum(dir));
            const inner_cross = @max(0, container_size.cross(dir) - content_inset.crossSum(dir));

            var used_main: Point = 0;
            for (items) |item| used_main += item.outer_target_size.main(dir);
            if (items.len > 1) used_main += gap_size * @as(Point, @floatFromInt(items.len - 1));

            const free_space = inner_main - used_main;
            var cursor = content_inset.mainStart(dir) + justifyStartOffset(justify, free_space, items.len);
            const between = gap_size + justifyBetweenOffset(justify, free_space, items.len);

            for (items) |*item| {
                const alignment = item.align_self;
                const cross_offset = alignOffset(
                    alignment,
                    inner_cross,
                    item.target_size.cross(dir),
                    item.margin.crossStart(dir),
                    item.margin.crossEnd(dir),
                );
                const main_location = cursor + item.margin.mainStart(dir);
                const cross_location = content_inset.crossStart(dir) + cross_offset;
                const child_location = if (dir.isRow())
                    Point2{ .x = main_location, .y = cross_location }
                else
                    Point2{ .x = cross_location, .y = main_location };

                _ = try self.layoutNode(item.node, .{
                    .known_size = MaybeSize.fromSize(item.target_size),
                    .parent_size = .{
                        .width = @max(0, container_size.width - content_inset.horizontal()),
                        .height = @max(0, container_size.height - content_inset.vertical()),
                    },
                    .available_space = AvailableSize.definite(item.target_size.width, item.target_size.height),
                }, child_location);

                cursor += item.margin.mainStart(dir) + item.target_size.main(dir) + item.margin.mainEnd(dir) + between;
            }
        }

        fn layoutAbsoluteChildren(
            self: *Self,
            id: NodeId,
            container_size: Size,
            inner_size: MaybeSize,
            padding: Edges,
            border: Edges,
        ) Error!void {
            const child_ids = try self.children(id);
            const inset_basis = MaybeSize{
                .width = @max(0, container_size.width - border.horizontal()),
                .height = @max(0, container_size.height - border.vertical()),
            };
            for (child_ids) |child| {
                const child_node = try self.node(child);
                const node_style = child_node.style;
                if (node_style.display == .none) {
                    try self.writeHidden(child);
                    continue;
                }
                if (node_style.position != .absolute) continue;

                const margin = try resolveMargin(node_style.margin, inset_basis.width);
                const inset = node_style.inset.resolveMaybe(inset_basis.width, inset_basis.height);
                const child_style_size = node_style.size.resolve(inset_basis);
                const min_size = node_style.min_size.resolve(inset_basis);
                const max_size = node_style.max_size.resolve(inset_basis);
                var known = child_style_size;

                if (known.width == null) {
                    if (inset.left != null and inset.right != null) {
                        known.width = @max(0, inset_basis.width.? - inset.left.? - inset.right.? - margin.horizontal());
                    }
                }
                if (known.height == null) {
                    if (inset.top != null and inset.bottom != null) {
                        known.height = @max(0, inset_basis.height.? - inset.top.? - inset.bottom.? - margin.vertical());
                    }
                }
                known = clampMaybeSize(known, min_size, max_size);

                const measured = try self.layoutNode(child, .{
                    .known_size = known,
                    .parent_size = inner_size,
                    .available_space = AvailableSize.definite(inset_basis.width.?, inset_basis.height.?),
                }, .{});
                const final_size = clampSize(known.unwrapOr(measured), min_size, max_size);

                const x = if (inset.left) |left|
                    border.left + left + margin.left
                else if (inset.right) |right|
                    container_size.width - border.right - right - final_size.width - margin.right
                else
                    border.left + padding.left + margin.left;
                const y = if (inset.top) |top|
                    border.top + top + margin.top
                else if (inset.bottom) |bottom|
                    container_size.height - border.bottom - bottom - final_size.height - margin.bottom
                else
                    border.top + padding.top + margin.top;

                _ = try self.layoutNode(child, .{
                    .known_size = MaybeSize.fromSize(final_size),
                    .parent_size = inner_size,
                    .available_space = AvailableSize.definite(final_size.width, final_size.height),
                }, .{ .x = x, .y = y });
            }
        }

        fn writeHidden(self: *Self, id: NodeId) Error!void {
            _ = try self.node(id);
            self.storage.layouts[id.index] = Layout.zero;
            const child_ids = try self.children(id);
            for (child_ids) |child| try self.writeHidden(child);
        }
    };
}

fn validateStyle(style: Style) Error!void {
    try validateLength(style.size.width, true);
    try validateLength(style.size.height, true);
    try validateLength(style.min_size.width, true);
    try validateLength(style.min_size.height, true);
    try validateLength(style.max_size.width, true);
    try validateLength(style.max_size.height, true);
    try validateLength(style.flex_basis, true);
    try validateEdgeLengths(style.inset, false);
    try validateEdgeLengths(style.padding, true);
    try validateEdgeLengths(style.border, true);
    try validateEdgeLengths(style.margin, false);
    try validateLength(style.gap.width, true);
    try validateLength(style.gap.height, true);
    if (!types.finite(style.flex_grow) or !types.finite(style.flex_shrink)) return Error.InvalidSize;
    if (style.flex_grow < 0 or style.flex_shrink < 0) return Error.InvalidSize;
}

fn validateEdgeLengths(edges: types.StyleEdges, non_negative: bool) Error!void {
    try validateLength(edges.left, non_negative);
    try validateLength(edges.right, non_negative);
    try validateLength(edges.top, non_negative);
    try validateLength(edges.bottom, non_negative);
}

fn validateLength(length: Length, non_negative: bool) Error!void {
    switch (length) {
        .auto => {},
        .points => |value| {
            if (!types.finite(value)) return Error.InvalidSize;
            if (non_negative and value < 0) return Error.InvalidSize;
        },
        .percent => |value| {
            if (!types.finite(value)) return Error.InvalidSize;
            if (non_negative and value < 0) return Error.InvalidSize;
        },
    }
}

fn validateAvailableSize(size: AvailableSize) Error!void {
    if (size.width.intoMaybe()) |width| try validateNonNegative(width);
    if (size.height.intoMaybe()) |height| try validateNonNegative(height);
}

fn validateLayoutInput(input: LayoutInput) Error!void {
    if (input.known_size.width) |width| try validateNonNegative(width);
    if (input.known_size.height) |height| try validateNonNegative(height);
    if (input.parent_size.width) |width| try validateNonNegative(width);
    if (input.parent_size.height) |height| try validateNonNegative(height);
    try validateAvailableSize(input.available_space);
}

fn validateSize(size: Size) Error!void {
    try validateNonNegative(size.width);
    try validateNonNegative(size.height);
}

fn validatePoint(point: Point2) Error!void {
    if (!types.finite(point.x) or !types.finite(point.y)) return Error.NumericOverflow;
}

fn validateNonNegative(value: Point) Error!void {
    if (!types.finite(value) or value < 0) return Error.InvalidSize;
}

fn checked(value: Point) Error!Point {
    if (!types.finite(value)) return Error.NumericOverflow;
    return value;
}

fn resolveBoxEdges(edges: types.StyleEdges, basis: ?Point, non_negative: bool) Error!Edges {
    const resolved = edges.resolveOrZero(basis);
    if (non_negative) {
        try validateNonNegative(resolved.left);
        try validateNonNegative(resolved.right);
        try validateNonNegative(resolved.top);
        try validateNonNegative(resolved.bottom);
    }
    return resolved;
}

fn resolveMargin(edges: types.StyleEdges, basis: ?Point) Error!Edges {
    const resolved = edges.resolveOrZero(basis);
    if (!types.finite(resolved.left) or !types.finite(resolved.right) or !types.finite(resolved.top) or !types.finite(resolved.bottom)) {
        return Error.InvalidSize;
    }
    return resolved;
}

fn subtractAvailable(available: AvailableSize, amount: Size) AvailableSize {
    return .{
        .width = switch (available.width) {
            .definite => |value| .{ .definite = @max(0, value - amount.width) },
            .min_content => .min_content,
            .max_content => .max_content,
        },
        .height = switch (available.height) {
            .definite => |value| .{ .definite = @max(0, value - amount.height) },
            .min_content => .min_content,
            .max_content => .max_content,
        },
    };
}

fn clampPoint(value: Point, min_value: ?Point, max_value: ?Point) Point {
    var result = value;
    if (min_value) |min| result = @max(result, min);
    if (max_value) |max| result = @min(result, max);
    return result;
}

fn clampSize(size: Size, min_size: MaybeSize, max_size: MaybeSize) Size {
    return .{
        .width = clampPoint(size.width, min_size.width, max_size.width),
        .height = clampPoint(size.height, min_size.height, max_size.height),
    };
}

fn clampMaybeSize(size: MaybeSize, min_size: MaybeSize, max_size: MaybeSize) MaybeSize {
    return .{
        .width = if (size.width) |width| clampPoint(width, min_size.width, max_size.width) else null,
        .height = if (size.height) |height| clampPoint(height, min_size.height, max_size.height) else null,
    };
}

fn justifyStartOffset(justify: JustifyContent, free_space: Point, count: usize) Point {
    return switch (justify) {
        .start, .flex_start, .stretch, .space_between => 0,
        .end, .flex_end => free_space,
        .center => free_space / 2,
        .space_around => if (free_space > 0) free_space / @as(Point, @floatFromInt(count)) / 2 else free_space / 2,
        .space_evenly => if (free_space > 0) free_space / @as(Point, @floatFromInt(count + 1)) else free_space / 2,
    };
}

fn justifyBetweenOffset(justify: JustifyContent, free_space: Point, count: usize) Point {
    if (free_space <= 0) return 0;
    return switch (justify) {
        .space_between => if (count > 1) free_space / @as(Point, @floatFromInt(count - 1)) else 0,
        .space_around => free_space / @as(Point, @floatFromInt(count)),
        .space_evenly => free_space / @as(Point, @floatFromInt(count + 1)),
        else => 0,
    };
}

fn alignOffset(alignment: AlignItems, inner_cross: Point, child_cross: Point, margin_start: Point, margin_end: Point) Point {
    return switch (alignment) {
        .end, .flex_end => inner_cross - child_cross - margin_end,
        .center => (inner_cross - child_cross + margin_start - margin_end) / 2,
        .start, .flex_start, .baseline, .stretch => margin_start,
    };
}
