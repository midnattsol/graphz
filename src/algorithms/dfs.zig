const std = @import("std");
const graph = @import("../graph.zig");

/// Iterative Depth-First Search (DFS) using an explicit stack.
/// Returns a slice of nodes in the order they were first visited.
/// The exact order depends on neighbor ordering and stack behavior;
/// there is no single canonical order.
pub fn dfs(g: anytype, start: graph.NodeId, allocator: std.mem.Allocator) ![]graph.NodeId {
    comptime {
        if (!@hasDecl(@TypeOf(g), "neighbors"))
            @compileError("Graph must have fn neighbors(self, NodeId) []NodeId");
        if (!@hasDecl(@TypeOf(g), "nodeCount"))
            @compileError("Graph must have fn nodeCount(self) usize");
    }

    const node_count = g.nodeCount();
    if (start.index >= node_count) return error.InvalidNode;

    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var stack: std.ArrayList(graph.NodeId) = .empty;
    defer stack.deinit(allocator);
    var order: std.ArrayList(graph.NodeId) = .empty;
    errdefer order.deinit(allocator);

    visited[start.index] = true;
    try stack.append(allocator, start);
    try order.append(allocator, start);

    while (stack.items.len > 0) {
        const current = stack.pop();
        for (g.neighbors(current)) |v| {
            if (!visited[v.index]) {
                visited[v.index] = true;
                try stack.append(allocator, v);
                try order.append(allocator, v);
            }
        }
    }
    return order.toOwnedSlice(allocator);
}

// ==================== Tests ====================

test "dfs visits all reachable nodes from start" {
    const Node = struct { id: u32 };
    var builder = graph.GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .id = 0 });
    const n1 = try builder.addNode(.{ .id = 1 });
    const n2 = try builder.addNode(.{ .id = 2 });
    const n3 = try builder.addNode(.{ .id = 3 });
    const n4 = try builder.addNode(.{ .id = 4 });

    // Graph: 0->1, 0->2, 1->3, 2->4
    try builder.addEdge(n0, n1, {});
    try builder.addEdge(n0, n2, {});
    try builder.addEdge(n1, n3, {});
    try builder.addEdge(n2, n4, {});

    var g = try builder.freeze(std.testing.allocator);
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    // The order must start with n0
    try std.testing.expectEqual(n0.index, order[0].index);

    // All nodes reachable from n0 are n0,n1,n2,n3,n4 (the whole graph)
    var found = std.AutoArrayHashMap(usize, void).init(std.testing.allocator);
    defer found.deinit();
    for (order) |node| try found.put(node.index, {});
    try std.testing.expectEqual(@as(usize, 5), found.count());
    try std.testing.expect(found.contains(n0.index));
    try std.testing.expect(found.contains(n1.index));
    try std.testing.expect(found.contains(n2.index));
    try std.testing.expect(found.contains(n3.index));
    try std.testing.expect(found.contains(n4.index));
}

test "dfs on unconnected graph visits only reachable component" {
    const Node = struct { id: u32 };
    var builder = graph.GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .id = 0 });
    const n1 = try builder.addNode(.{ .id = 1 });
    const n2 = try builder.addNode(.{ .id = 2 });
    const n3 = try builder.addNode(.{ .id = 3 });

    // Component 1: 0->1
    try builder.addEdge(n0, n1, {});
    // Component 2: 2->3
    try builder.addEdge(n2, n3, {});

    var g = try builder.freeze(std.testing.allocator);
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    // Only n0 and n1 should be visited
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expect(order[0].index == n0.index);
    try std.testing.expect(order[1].index == n1.index);
}

test "dfs on a graph with a cycle still terminates" {
    const Node = struct { id: u32 };
    var builder = graph.GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .id = 0 });
    const n1 = try builder.addNode(.{ .id = 1 });
    const n2 = try builder.addNode(.{ .id = 2 });

    // 0->1, 1->2, 2->0 (cycle)
    try builder.addEdge(n0, n1, {});
    try builder.addEdge(n1, n2, {});
    try builder.addEdge(n2, n0, {});

    var g = try builder.freeze(std.testing.allocator);
    defer g.deinit(std.testing.allocator);

    const order = try dfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    // All nodes reachable, should be 3 nodes, no duplicates
    try std.testing.expectEqual(@as(usize, 3), order.len);
    var found = std.AutoArrayHashMap(usize, void).init(std.testing.allocator);
    defer found.deinit();
    for (order) |node| try found.put(node.index, {});
    try std.testing.expectEqual(@as(usize, 3), found.count());
}

test "dfs returns error on invalid start node" {
    const Node = struct { id: u32 };
    var builder = graph.GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    _ = try builder.addNode(.{ .id = 0 });

    var g = try builder.freeze(std.testing.allocator);
    defer g.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidNode, dfs(g, graph.NodeId{ .index = 1 }, std.testing.allocator));
}
