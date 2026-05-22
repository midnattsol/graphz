// root.zig
const graph = @import("graph.zig");

// Algorithms
pub const bfs = @import("algorithms/bfs.zig").bfs;
pub const dfs = @import("algorithms/dfs.zig").dfs;
pub const hasCycle = @import("algorithms/cycle.zig").hasCycle;

pub const NodeId = graph.NodeId;
pub const GraphBuilder = graph.GraphBuilder;
pub const StaticGraph = graph.StaticGraph;
