const std = @import("std");
const graph = @import("graph.zig");

const Allocator = std.mem.Allocator;

/// Compile-time check: the graph type must expose `neighbors` (returning
/// a NeighborIterator with `.next()`) and `nodeCount`.  Algorithms use
/// duck-typing so they work with any type that satisfies this interface.
pub fn requireNeighborsAndNodeCount(comptime G: type) void {
    if (!@hasDecl(G, "neighbors"))
        @compileError("Graph must expose fn neighbors(self, NodeId) NeighborIterator");
    if (!@hasDecl(G, "nodeCount"))
        @compileError("Graph must expose fn nodeCount(self) usize");
}

/// Validate that `start` refers to an existing node.
pub fn validateNode(graph_value: anytype, start: graph.NodeId) !void {
    comptime requireNeighborsAndNodeCount(@TypeOf(graph_value));
    if (start.index >= graph_value.nodeCount()) return error.InvalidNode;
}

/// Build a test graph with `node_count` nodes and the given directed edges.
/// The edge list is interpreted at comptime so it costs nothing at runtime.
pub fn buildTestGraph(
    allocator: Allocator,
    comptime node_count: u32,
    comptime edges: []const [2]u32,
) !graph.Graph {
    var graph_instance = try graph.Graph.init(allocator);

    var node_ids: [node_count]graph.NodeId = undefined;
    for (0..node_count) |i| {
        node_ids[i] = try graph_instance.addNode();
    }

    for (edges) |e| {
        try graph_instance.addEdge(node_ids[e[0]], node_ids[e[1]], 0, 0);
    }

    return graph_instance;
}
