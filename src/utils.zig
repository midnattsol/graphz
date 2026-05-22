const std = @import("std");
const graph = @import("graph.zig");

const Allocator = std.mem.Allocator;

/// Compile-time check: the graph type must expose `neighbors` and `nodeCount`.
pub fn requireNeighborsAndNodeCount(comptime Graph: type) void {
    if (!@hasDecl(Graph, "neighbors"))
        @compileError("Graph must have fn neighbors(self, NodeId) []NodeId");
    if (!@hasDecl(Graph, "nodeCount"))
        @compileError("Graph must have fn nodeCount(self) usize");
}

/// Validate that `start` refers to an existing node.
pub fn validateNode(g: anytype, start: graph.NodeId) !void {
    comptime requireNeighborsAndNodeCount(@TypeOf(g));
    if (start.index >= g.nodeCount()) return error.InvalidNode;
}

/// Build a graph with `node_count` nodes (each `{ .id = i }`) and the given
/// directed edges. The edge list is interpreted at comptime so it costs
/// nothing at runtime.
pub fn buildTestGraph(allocator: Allocator, comptime node_count: usize, comptime edges: []const [2]usize) !graph.StaticGraph(struct { id: usize }, void) {
    const Node = struct { id: usize };
    var builder = graph.GraphBuilder(Node, void).init(allocator);
    defer builder.deinit();

    var node_ids: [node_count]graph.NodeId = undefined;
    for (0..node_count) |i| {
        node_ids[i] = try builder.addNode(.{ .id = i });
    }

    for (edges) |e| {
        try builder.addEdge(node_ids[e[0]], node_ids[e[1]], {});
    }

    return builder.freeze(allocator);
}
