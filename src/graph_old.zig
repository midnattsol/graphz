//! A generic graph implementation using Compressed Sparse Row (CSR) format.
//! Provides a builder pattern for constructing graphs and freezing them into
//! an efficient, read-only structure.
//! Supports optional edge weights via a type parameter `W`.

const std = @import("std");

/// An opaque identifier for a node in the graph.
/// The actual index is internal; users should treat it as an opaque handle.
pub const NodeId = struct {
    index: usize,
};

/// Internal representation of a directed edge used during graph construction.
fn Edge(comptime W: type) type {
    return struct {
        from: NodeId,
        to: NodeId,
        weight: W,
    };
}

/// A read-only graph stored in CSR (Compressed Sparse Row) format.
/// This structure is memory-efficient and offers O(1) neighbor access.
///
/// The graph owns its node data, offset array, edge array and weight array.
/// Use `deinit` to free memory.
pub fn StaticGraph(comptime T: type, comptime W: type) type {
    return struct {
        const Self = @This();

        nodes: []T,
        offsets: []usize,
        edges: []NodeId,
        weights: []W,
        rev_offsets: []usize,
        rev_edges: []NodeId,
        node_ids: []NodeId,

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.nodes);
            allocator.free(self.offsets);
            allocator.free(self.edges);
            allocator.free(self.weights);
            allocator.free(self.rev_offsets);
            allocator.free(self.rev_edges);
            allocator.free(self.node_ids);
        }

        /// Returns the node data for the given node id.
        pub fn getNode(self: Self, node: NodeId) T {
            return self.nodes[node.index];
        }

        /// Returns true if `node` is a valid node identifier in this graph.
        /// All other accessors assume a valid NodeId; validate first when
        /// receiving ids from untrusted sources.
        pub fn hasNode(self: Self, node: NodeId) bool {
            return node.index < self.nodes.len;
        }

        /// Returns a slice of outgoing neighbor `NodeId`s for the given node.
        /// Assumes `node` is valid; use `hasNode` to check first if needed.
        pub fn neighbors(self: Self, node: NodeId) []NodeId {
            const start = self.offsets[node.index];
            const end = self.offsets[node.index + 1];
            return self.edges[start..end];
        }

        /// Returns a slice of weights for the outgoing edges of the given node.
        /// The slice has the same length as `neighbors(node)`.
        /// Assumes `node` is valid.
        pub fn weightsForNode(self: Self, node: NodeId) []W {
            const start = self.offsets[node.index];
            const end = self.offsets[node.index + 1];
            return self.weights[start..end];
        }

        /// Returns the total number of nodes in the graph.
        pub fn nodeCount(self: Self) usize {
            return self.nodes.len;
        }

        /// Returns the total number of edges in the graph.
        pub fn edgeCount(self: Self) usize {
            return self.edges.len;
        }

        /// Returns a slice of all node identifiers in the graph.
        pub fn nodeIds(self: Self) []NodeId {
            return self.node_ids;
        }

        /// Returns the number of outgoing edges for the given node.
        /// Assumes `node` is valid.
        pub fn outDegree(self: Self, node: NodeId) usize {
            return self.offsets[node.index + 1] - self.offsets[node.index];
        }

        /// Returns a slice of incoming neighbor `NodeId`s for the given node.
        /// Assumes `node` is valid.
        pub fn inNeighbors(self: Self, node: NodeId) []NodeId {
            const start = self.rev_offsets[node.index];
            const end = self.rev_offsets[node.index + 1];
            return self.rev_edges[start..end];
        }

        /// Returns the number of incoming edges for the given node.
        /// Assumes `node` is valid.
        pub fn inDegree(self: Self, node: NodeId) usize {
            return self.rev_offsets[node.index + 1] - self.rev_offsets[node.index];
        }
    };
}

/// A graph builder that accumulates nodes and edges dynamically.
/// After all additions, call `freeze` to produce a compact `StaticGraph`.
/// The weight type `W` can be `void` to indicate an unweighted graph.
pub fn GraphBuilder(comptime T: type, comptime W: type) type {
    const EdgeType = Edge(W);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        nodes: std.ArrayList(T),
        edges: std.ArrayList(EdgeType),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .nodes = .empty,
                .edges = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.allocator);
            self.edges.deinit(self.allocator);
        }

        pub fn addNode(self: *Self, node: T) !NodeId {
            const id = NodeId{ .index = self.nodes.items.len };
            try self.nodes.append(self.allocator, node);
            return id;
        }

        pub fn hasNode(self: *const Self, id: NodeId) bool {
            return id.index < self.nodes.items.len;
        }

        /// Returns the node data associated with `id`, or null if `id` is invalid.
        pub fn getNode(self: *const Self, id: NodeId) ?T {
            return if (self.hasNode(id)) self.nodes.items[id.index] else null;
        }

        /// Adds a directed edge from `from` to `to` with given `weight`.
        /// If `W == void`, `weight` can be `{}` and is ignored.
        pub fn addEdge(self: *Self, from: NodeId, to: NodeId, weight: W) !void {
            if (!self.hasNode(from) or !self.hasNode(to)) {
                return error.InvalidNode;
            }
            try self.edges.append(self.allocator, .{
                .from = from,
                .to = to,
                .weight = weight,
            });
        }

        pub fn nodeCount(self: *const Self) usize {
            return self.nodes.items.len;
        }

        pub fn edgeCount(self: *const Self) usize {
            return self.edges.items.len;
        }

        fn computeOutDegrees(self: *const Self, allocator: std.mem.Allocator) ![]usize {
            var out = try allocator.alloc(usize, self.nodes.items.len);
            @memset(out, 0);
            for (self.edges.items) |e| {
                out[e.from.index] += 1;
            }
            return out;
        }

        fn computeInDegrees(self: *const Self, allocator: std.mem.Allocator) ![]usize {
            var inp = try allocator.alloc(usize, self.nodes.items.len);
            @memset(inp, 0);
            for (self.edges.items) |e| {
                inp[e.to.index] += 1;
            }
            return inp;
        }

        pub fn freeze(self: *const Self, allocator: std.mem.Allocator) !StaticGraph(T, W) {
            const node_count = self.nodes.items.len;
            const edge_count = self.edges.items.len;

            // Build forward CSR
            const out_degrees = try self.computeOutDegrees(allocator);
            defer allocator.free(out_degrees);

            var offsets = try allocator.alloc(usize, node_count + 1);
            errdefer allocator.free(offsets);

            offsets[0] = 0;
            for (0..node_count) |i| {
                offsets[i + 1] = offsets[i] + out_degrees[i];
            }

            var edges_slice = try allocator.alloc(NodeId, edge_count);
            errdefer allocator.free(edges_slice);
            var weights_slice = try allocator.alloc(W, edge_count);
            errdefer allocator.free(weights_slice);

            var pos = try allocator.alloc(usize, node_count);
            defer allocator.free(pos);
            @memcpy(pos, offsets[0..node_count]);

            for (self.edges.items) |edge| {
                const from_idx = edge.from.index;
                const target = pos[from_idx];
                edges_slice[target] = edge.to;
                weights_slice[target] = edge.weight;
                pos[from_idx] = target + 1;
            }

            // Build reverse CSR
            const in_degrees = try self.computeInDegrees(allocator);
            defer allocator.free(in_degrees);

            var rev_offsets = try allocator.alloc(usize, node_count + 1);
            errdefer allocator.free(rev_offsets);

            rev_offsets[0] = 0;
            for (0..node_count) |i| {
                rev_offsets[i + 1] = rev_offsets[i] + in_degrees[i];
            }

            var rev_edges_slice = try allocator.alloc(NodeId, edge_count);
            errdefer allocator.free(rev_edges_slice);

            // Reuse pos array for reverse placement
            @memcpy(pos, rev_offsets[0..node_count]);

            for (self.edges.items) |edge| {
                const to_idx = edge.to.index;
                const target = pos[to_idx];
                rev_edges_slice[target] = edge.from;
                pos[to_idx] = target + 1;
            }

            const nodes_slice = try allocator.duplicate(T, self.nodes.items);
            errdefer allocator.free(nodes_slice);

            var node_ids_slice = try allocator.alloc(NodeId, node_count);
            errdefer allocator.free(node_ids_slice);
            for (0..node_count) |i| {
                node_ids_slice[i] = NodeId{ .index = i };
            }

            return StaticGraph(T, W){
                .nodes = nodes_slice,
                .offsets = offsets,
                .edges = edges_slice,
                .weights = weights_slice,
                .rev_offsets = rev_offsets,
                .rev_edges = rev_edges_slice,
                .node_ids = node_ids_slice,
            };
        }
    };
}

// ==================== Tests ====================

test "builder getNode" {
    const Node = struct { name: []const u8 };
    var builder = GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const a = try builder.addNode(.{ .name = "A" });
    const b = try builder.addNode(.{ .name = "B" });

    try std.testing.expectEqualStrings("A", builder.getNode(a).?.name);
    try std.testing.expectEqualStrings("B", builder.getNode(b).?.name);
    try std.testing.expectEqual(@as(@TypeOf(builder.getNode(a)), null), builder.getNode(NodeId{ .index = 999 }));
}

test "static graph hasNode and getNode" {
    const Node = struct { value: i32 };
    var builder = GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .value = 10 });
    const n1 = try builder.addNode(.{ .value = 20 });

    var graph = try builder.freeze(std.testing.allocator);
    defer graph.deinit(std.testing.allocator);

    try std.testing.expect(graph.hasNode(n0));
    try std.testing.expect(graph.hasNode(n1));
    try std.testing.expect(!graph.hasNode(NodeId{ .index = 2 }));

    try std.testing.expectEqual(@as(i32, 10), graph.getNode(n0).value);
    try std.testing.expectEqual(@as(i32, 20), graph.getNode(n1).value);
}

test "builder can add edges (unweighted)" {
    const Node = struct { name: []const u8 };
    var builder = GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const almeria = try builder.addNode(.{ .name = "Almeria" });
    const krakow = try builder.addNode(.{ .name = "Krakow" });
    try builder.addEdge(almeria, krakow, {});

    try std.testing.expectEqual(@as(usize, 2), builder.nodeCount());
    try std.testing.expectEqual(@as(usize, 1), builder.edgeCount());
}

test "freeze produces correct CSR graph (unweighted)" {
    const Node = struct { name: []const u8 };
    var builder = GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const a = try builder.addNode(.{ .name = "A" });
    const b = try builder.addNode(.{ .name = "B" });
    const c = try builder.addNode(.{ .name = "C" });
    const d = try builder.addNode(.{ .name = "D" });

    try builder.addEdge(a, b, {});
    try builder.addEdge(a, c, {});
    try builder.addEdge(b, d, {});

    var graph = try builder.freeze(std.testing.allocator);
    defer graph.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("A", graph.nodes[0].name);
    try std.testing.expectEqualStrings("B", graph.nodes[1].name);
    try std.testing.expectEqualStrings("C", graph.nodes[2].name);
    try std.testing.expectEqualStrings("D", graph.nodes[3].name);

    const expected_offsets = [_]usize{ 0, 2, 3, 3, 3 };
    try std.testing.expectEqualSlices(usize, &expected_offsets, graph.offsets);

    try std.testing.expectEqual(b.index, graph.edges[0].index);
    try std.testing.expectEqual(c.index, graph.edges[1].index);
    try std.testing.expectEqual(d.index, graph.edges[2].index);

    const neighbors_a = graph.neighbors(a);
    try std.testing.expectEqual(@as(usize, 2), neighbors_a.len);
    try std.testing.expectEqual(b.index, neighbors_a[0].index);
    try std.testing.expectEqual(c.index, neighbors_a[1].index);

    const neighbors_b = graph.neighbors(b);
    try std.testing.expectEqual(@as(usize, 1), neighbors_b.len);
    try std.testing.expectEqual(d.index, neighbors_b[0].index);
}

test "weighted graph" {
    const Node = struct { id: u32 };
    var builder = GraphBuilder(Node, f64).init(std.testing.allocator);
    defer builder.deinit();

    const n0 = try builder.addNode(.{ .id = 0 });
    const n1 = try builder.addNode(.{ .id = 1 });
    const n2 = try builder.addNode(.{ .id = 2 });

    try builder.addEdge(n0, n1, 1.5);
    try builder.addEdge(n0, n2, 2.5);
    try builder.addEdge(n1, n2, 0.5);

    var graph = try builder.freeze(std.testing.allocator);
    defer graph.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), graph.nodes.len);
    try std.testing.expectEqual(@as(usize, 3), graph.edges.len);
    try std.testing.expectEqual(@as(usize, 3), graph.weights.len);

    const expected_offsets = [_]usize{ 0, 2, 3, 3 };
    try std.testing.expectEqualSlices(usize, &expected_offsets, graph.offsets);

    // Check weights for node 0
    const w0 = graph.weightsForNode(n0);
    try std.testing.expectEqual(@as(usize, 2), w0.len);
    try std.testing.expectEqual(1.5, w0[0]);
    try std.testing.expectEqual(2.5, w0[1]);

    // Check weights for node 1
    const w1 = graph.weightsForNode(n1);
    try std.testing.expectEqual(@as(usize, 1), w1.len);
    try std.testing.expectEqual(0.5, w1[0]);
}

test "reverse CSR: inNeighbors and inDegree" {
    const Node = struct { id: u32 };
    var builder = GraphBuilder(Node, void).init(std.testing.allocator);
    defer builder.deinit();

    const a = try builder.addNode(.{ .id = 0 });
    const b = try builder.addNode(.{ .id = 1 });
    const c = try builder.addNode(.{ .id = 2 });

    // a -> b, a -> c, b -> c
    try builder.addEdge(a, b, {});
    try builder.addEdge(a, c, {});
    try builder.addEdge(b, c, {});

    var graph = try builder.freeze(std.testing.allocator);
    defer graph.deinit(std.testing.allocator);

    // out-degree
    try std.testing.expectEqual(@as(usize, 2), graph.outDegree(a));
    try std.testing.expectEqual(@as(usize, 1), graph.outDegree(b));
    try std.testing.expectEqual(@as(usize, 0), graph.outDegree(c));

    // in-degree
    try std.testing.expectEqual(@as(usize, 0), graph.inDegree(a));
    try std.testing.expectEqual(@as(usize, 1), graph.inDegree(b));
    try std.testing.expectEqual(@as(usize, 2), graph.inDegree(c));

    // in-neighbors of c should be [a, b]
    const in_c = graph.inNeighbors(c);
    try std.testing.expectEqual(@as(usize, 2), in_c.len);
    var has_a = false;
    var has_b = false;
    for (in_c) |n| {
        if (n.index == a.index) has_a = true;
        if (n.index == b.index) has_b = true;
    }
    try std.testing.expect(has_a);
    try std.testing.expect(has_b);
}
