const std = @import("std");
const graph = @import("../graph.zig");
const utils = @import("../utils.zig");

/// Iterative Depth-First Search (DFS) using an explicit stack.
/// Returns a slice of nodes in the order they were first visited.
pub fn dfs(g: anytype, start: graph.NodeId, allocator: std.mem.Allocator) ![]graph.NodeId {
    comptime utils.requireNeighborsAndNodeCount(@TypeOf(g));
    try utils.validateNode(g, start);

    const node_count = g.nodeCount();
    var visited = try std.DynamicBitSetUnmanaged.initEmpty(allocator, node_count);
    defer visited.deinit(allocator);

    var stack = try std.ArrayList(graph.NodeId).initCapacity(allocator, node_count);
    defer stack.deinit(allocator);
    var order: std.ArrayList(graph.NodeId) = .empty;
    errdefer order.deinit(allocator);

    visited.set(start.index);
    try stack.append(allocator, start);
    try order.append(allocator, start);

    while (stack.items.len > 0) {
        const current = stack.pop();
        for (g.neighbors(current)) |v| {
            if (!visited.isSet(v.index)) {
                visited.set(v.index);
                try stack.append(allocator, v);
                try order.append(allocator, v);
            }
        }
    }
    return order.toOwnedSlice(allocator);
}

// ==================== Tests ====================

test "dfs visits all reachable nodes from start" {
    var g = try utils.buildTestGraph(std.testing.allocator, 5, &.{
        .{ 0, 1 }, .{ 0, 2 }, .{ 1, 3 }, .{ 2, 4 },
    });
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, .{ .index = 0 }, std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 0), order[0].index);

    var found = std.AutoArrayHashMap(usize, void).init(std.testing.allocator);
    defer found.deinit();
    for (order) |n| try found.put(n.index, {});
    try std.testing.expectEqual(@as(usize, 5), found.count());
    for (0..5) |i| try std.testing.expect(found.contains(i));
}

test "dfs on unconnected graph visits only reachable component" {
    var g = try utils.buildTestGraph(std.testing.allocator, 4, &.{
        .{ 0, 1 }, .{ 2, 3 },
    });
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, .{ .index = 0 }, std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expect(order[0].index == 0);
    try std.testing.expect(order[1].index == 1);
}

test "dfs on a graph with a cycle still terminates" {
    var g = try utils.buildTestGraph(std.testing.allocator, 3, &.{
        .{ 0, 1 }, .{ 1, 2 }, .{ 2, 0 },
    });
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, .{ .index = 0 }, std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 3), order.len);
    var found = std.AutoArrayHashMap(usize, void).init(std.testing.allocator);
    defer found.deinit();
    for (order) |n| try found.put(n.index, {});
    try std.testing.expectEqual(@as(usize, 3), found.count());
}

test "dfs returns error on invalid start node" {
    var g = try utils.buildTestGraph(std.testing.allocator, 1, &.{});
    defer g.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidNode, dfs(g, .{ .index = 99 }, std.testing.allocator));
}
