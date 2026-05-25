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
pub fn validateNode(g: anytype, start: graph.NodeId) !void {
    comptime requireNeighborsAndNodeCount(@TypeOf(g));
    if (start.index >= g.nodeCount()) return error.InvalidNode;
}

/// Build a test graph with `node_count` nodes and the given directed edges.
/// The edge list is interpreted at comptime so it costs nothing at runtime.
///
/// Pool capacities are derived from `node_count` and `edges.len` with a
/// safety margin so that tests never hit `GraphFull`.
pub fn buildTestGraph(
    allocator: Allocator,
    comptime node_count: u32,
    comptime edges: []const [2]u32,
) !graph.Graph {
    // Safe upper bounds: worst case one block per node plus one per edge.
    const max_blocks: u32 = @intCast(edges.len * 2 + node_count);
    const max_runs: u32 = @intCast(node_count / 4 + 8);

    const config = graph.GraphConfig{
        .profile = .normal,
        .max_nodes = node_count,
        .max_blocks = max_blocks,
        .max_rev_blocks = max_blocks,
        .max_runs = max_runs,
        .max_rev_runs = max_runs,
    };

    var builder = try graph.GraphBuilder.init(config, allocator);
    defer builder.deinit(allocator);

    var node_ids: [node_count]graph.NodeId = undefined;
    for (0..node_count) |i| {
        node_ids[i] = try builder.addNode();
    }

    for (edges) |e| {
        try builder.addEdge(node_ids[e[0]], node_ids[e[1]], .{
            .edge_type = 0,
            .flags = 0,
        });
    }

    return builder.freeze(allocator);
}
