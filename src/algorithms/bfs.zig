const std = @import("std");
const graph = @import("../graph.zig");

pub fn bfs(g: anytype, start: graph.NodeId, allocator: std.mem.Allocator) ![]graph.NodeId {
    comptime {
        if (!@hasDecl(@TypeOf(g), "neighbors"))
            @compileError("Graph must have fn neighbors(self, NodeId) []NodeId");
        if (!@hasDecl(@TypeOf(g), "nodeCount"))
            @compileError("Graph must have fn nodeCount(self) usize");
    }

    const node_count = g.nodeCount();
    var visited = try allocator.alloc(bool, node_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var queue: std.ArrayList(graph.NodeId) = .empty;
    defer queue.deinit(allocator);
    var order: std.ArrayList(graph.NodeId) = .empty;
    errdefer order.deinit(allocator);

    visited[start.index] = true;
    try queue.append(allocator, start);
    try order.append(allocator, start);

    var head = 0;
    while (head < queue.items.len) {
        const current = queue.items[head];
        head += 1;
        for (g.neighbors(current)) |v| {
            if (!visited[v.index]) {
                visited[v.index] = true;
                try queue.append(allocator, v);
                try order.append(allocator, v);
            }
        }
    }
    return order.toOwnedSlice(allocator);
}

// ==================== Tests ====================

test "bfs order on a simple graph" {
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

    const order = try bfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(n0.index, order[0].index);
    var idx_n1: ?usize = null;
    var idx_n2: ?usize = null;
    var idx_n3: ?usize = null;
    var idx_n4: ?usize = null;
    for (order, 0..) |node, i| {
        if (node.index == n1.index) idx_n1 = i;
        if (node.index == n2.index) idx_n2 = i;
        if (node.index == n3.index) idx_n3 = i;
        if (node.index == n4.index) idx_n4 = i;
    }
    try std.testing.expect(idx_n1.? < idx_n3.?);
    try std.testing.expect(idx_n2.? < idx_n4.?);
}

test "bfs distances" {
    const Node = struct { id: u32 };
    var builder = graph.GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .id = 0 });
    const n1 = try builder.addNode(.{ .id = 1 });
    const n2 = try builder.addNode(.{ .id = 2 });
    const n3 = try builder.addNode(.{ .id = 3 });

    // 0 -> 1, 0 -> 2, 1 -> 2, 2 -> 3
    try builder.addEdge(n0, n1, {});
    try builder.addEdge(n0, n2, {});
    try builder.addEdge(n1, n2, {});
    try builder.addEdge(n2, n3, {});

    var g = try builder.freeze(std.testing.allocator);
    defer g.deinit(std.testing.allocator);

    const order = try bfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    var idx_n1: ?usize = null;
    var idx_n2: ?usize = null;
    var idx_n3: ?usize = null;
    for (order, 0..) |node, i| {
        if (node.index == n1.index) idx_n1 = i;
        if (node.index == n2.index) idx_n2 = i;
        if (node.index == n3.index) idx_n3 = i;
    }
    try std.testing.expect(idx_n1.? < idx_n3.?);
    try std.testing.expect(idx_n2.? < idx_n3.?);
}

test "bfs on unconnected graph visits only reachable component" {
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

    const order = try bfs(g, n0, std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expect(order[0].index == n0.index and order[1].index == n1.index);
}
