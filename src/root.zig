//! Root module for the Zigraph graph library.
//!
//! Exports the RB-CSR graph engine, builder, algorithms, and supporting types.
//! See RFC.md for the full design specification.

const graph = @import("graph.zig");

// ── Core types ────────────────────────────────────────────────────────
pub const NodeId = graph.NodeId;
pub const EdgeMeta = graph.EdgeMeta;
pub const Edge = graph.Edge;
pub const NodeFlags = graph.NodeFlags;

// ── Configuration ─────────────────────────────────────────────────────
pub const GraphProfile = graph.GraphProfile;
pub const GraphConfig = graph.GraphConfig;

// ── Graph engine ──────────────────────────────────────────────────────
pub const Graph = graph.Graph;
pub const GraphBuilder = graph.GraphBuilder;
pub const GraphError = graph.GraphError;
pub const Violation = graph.Violation;

// ── Algorithms ────────────────────────────────────────────────────────
pub const bfs = @import("algorithms/bfs.zig").bfs;
pub const dfs = @import("algorithms/dfs.zig").dfs;
pub const hasCycle = @import("algorithms/cycle.zig").hasCycle;

test {
    _ = @import("algorithms/bfs.zig");
    _ = @import("algorithms/dfs.zig");
    _ = @import("algorithms/cycle.zig");
}
