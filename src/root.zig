// root.zig
const graph = @import("graph.zig");

// Algorithms
const bfs = @import("algorithms/bfs.zig");
const dfs = @import("algorithms/dfs.zig");

pub const NodeId = graph.NodeId;
pub const GraphBuilder = graph.GraphBuilder;
pub const StaticGraph = graph.StaticGraph;
