const std = @import("std");
const constants = @import("constants.zig");
const types = @import("types.zig");

// ── Implementation modules ───────────────────────────────────────────────
const pool = @import("pool.zig");
const adjacency = @import("adjacency.zig");
const rcu = @import("rcu.zig");
const mutation = @import("mutation.zig");

// ── Re-exports ───────────────────────────────────────────────────────────
pub const NodeId = types.NodeId;
pub const GraphError = types.GraphError;
pub const NodeFlags = types.NodeFlags;
pub const EdgeFlags = types.EdgeFlags;
pub const Edge = types.Edge;
pub const NodeAdj = types.NodeAdj;
pub const NodeBuffer = types.NodeBuffer;
pub const EdgeBlockFwd = types.EdgeBlockFwd;
pub const EdgeBlockRev = types.EdgeBlockRev;
pub const EdgeBlockGroup = types.EdgeBlockGroup;
pub const RetiredBlock = types.RetiredBlock;
pub const Violation = types.Violation;

pub const NODES_PER_PAGE = constants.NODES_PER_PAGE;
pub const EDGE_BLOCKS_PER_PAGE = constants.EDGE_BLOCKS_PER_PAGE;
pub const EDGE_GROUPS_PER_PAGE = constants.EDGE_GROUPS_PER_PAGE;

// ── Graph ────────────────────────────────────────────────────────────────

pub const Graph = struct {
    allocator: std.mem.Allocator,

    /// Node pages. 256 NodeBuffer per page (~15 KB). Never moved.
    node_pages: std.ArrayList([]types.NodeBuffer),

    /// Forward edge block pages. 64 EdgeBlockFwd per page (~33 KB).
    edge_blocks_fwd: std.ArrayList([]types.EdgeBlockFwd),

    /// Reverse edge block pages. 64 EdgeBlockRev per page (~17 KB).
    edge_blocks_rev: std.ArrayList([]types.EdgeBlockRev),

    /// Edge block group pages. 128 EdgeBlockGroup per page (~1.5 KB).
    edge_block_groups: std.ArrayList([]types.EdgeBlockGroup),

    /// LIFO free lists — indices of freed blocks/groups ready for reuse.
    free_blocks_fwd: std.ArrayList(u32),
    free_blocks_rev: std.ArrayList(u32),
    free_groups: std.ArrayList(u32),

    /// Retired blocks — copied out during RCU mutations.
    retired_blocks_fwd: std.ArrayList(types.RetiredBlock),
    retired_blocks_rev: std.ArrayList(types.RetiredBlock),

    /// Repair debt queues — node indices below occupancy threshold.
    repair_fwd: std.ArrayList(u32),
    repair_rev: std.ArrayList(u32),

    /// Total number of nodes that have been created.
    node_count: u32 = 0,

    /// Monotonic counters — total blocks/groups ever allocated.
    block_fwd_count: u32 = 0,
    block_rev_count: u32 = 0,
    group_count: u32 = 0,

    /// Global live edge count — atomic for lock-free `edgeCount()`.
    edge_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Global epoch for retired block reclamation.
    epoch: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Number of readers currently active in any epoch.
    active_readers: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    // ── Lifecycle ─────────────────────────────────────────────────────

    pub fn init(allocator: std.mem.Allocator) !Graph {
        var self = Graph{
            .allocator = allocator,
            .node_pages = .empty,
            .edge_blocks_fwd = .empty,
            .edge_blocks_rev = .empty,
            .edge_block_groups = .empty,
            .free_blocks_fwd = .empty,
            .free_blocks_rev = .empty,
            .free_groups = .empty,
            .retired_blocks_fwd = .empty,
            .retired_blocks_rev = .empty,
            .repair_fwd = .empty,
            .repair_rev = .empty,
            .node_count = 0,
        };

        const first_page = try allocator.alloc(types.NodeBuffer, constants.NODES_PER_PAGE);
        @memset(first_page, std.mem.zeroes(types.NodeBuffer));
        try self.node_pages.append(allocator, first_page);
        return self;
    }

    pub fn deinit(self: *Graph) void {
        const alloc = self.allocator;
        for (self.node_pages.items) |page| alloc.free(page);
        for (self.edge_blocks_fwd.items) |page| alloc.free(page);
        for (self.edge_blocks_rev.items) |page| alloc.free(page);
        for (self.edge_block_groups.items) |page| alloc.free(page);

        self.node_pages.deinit(alloc);
        self.edge_blocks_fwd.deinit(alloc);
        self.edge_blocks_rev.deinit(alloc);
        self.edge_block_groups.deinit(alloc);

        self.free_blocks_fwd.deinit(alloc);
        self.free_blocks_rev.deinit(alloc);
        self.free_groups.deinit(alloc);
        self.retired_blocks_fwd.deinit(alloc);
        self.retired_blocks_rev.deinit(alloc);
        self.repair_fwd.deinit(alloc);
        self.repair_rev.deinit(alloc);
    }

    // ── Node API ──────────────────────────────────────────────────────

    pub fn addNode(self: *Graph) !types.NodeId {
        const index = self.node_count;
        const page = constants.pageOf(index, constants.NODES_PER_PAGE);

        if (page == self.node_pages.items.len) {
            const new_page = try self.allocator.alloc(types.NodeBuffer, constants.NODES_PER_PAGE);
            @memset(new_page, std.mem.zeroes(types.NodeBuffer));
            try self.node_pages.append(self.allocator, new_page);
        }

        self.node_count += 1;
        return types.NodeId{ .index = index };
    }

    pub fn nodeCount(self: *const Graph) usize {
        return self.node_count;
    }

    pub fn edgeCount(self: *const Graph) u64 {
        return self.edge_count.load(.acquire);
    }

    pub fn hasNode(self: *const Graph, id: types.NodeId) bool {
        return id.index < self.node_count;
    }

    // ── Pool methods ──────────────────────────────────────────────────

    pub fn allocBlockFwd(self: *Graph) !u32 {
        return pool.allocBlockFwd(self);
    }
    pub fn allocBlockRev(self: *Graph) !u32 {
        return pool.allocBlockRev(self);
    }
    pub fn allocGroup(self: *Graph) !u32 {
        return pool.allocGroup(self);
    }
    pub fn freeGroup(self: *Graph, idx: u32) void {
        pool.freeGroup(self, idx);
    }

    // ── Adjacency methods ─────────────────────────────────────────────

    pub fn appendGroupToAdj(self: *Graph, adj: *types.NodeAdj, new_block: u32, comptime dir: enum { fwd, rev }) !void {
        return adjacency.appendGroupToAdj(self, adj, new_block, dir);
    }
    pub fn tailBlockIndex(self: *Graph, adj: *const types.NodeAdj, comptime dir: enum { fwd, rev }) u32 {
        return adjacency.tailBlockIndex(self, adj, dir);
    }
    pub fn removeTailFromAdj(self: *Graph, adj: *types.NodeAdj, comptime dir: enum { fwd, rev }) void {
        adjacency.removeTailFromAdj(self, adj, dir);
    }
    pub fn hasEdgeInAdj(self: *const Graph, adj: types.NodeAdj, target: u32) bool {
        return adjacency.hasEdgeInAdj(self, adj, target);
    }

    // ── RCU methods ───────────────────────────────────────────────────

    pub fn readerEnter(self: *Graph) u64 {
        return rcu.readerEnter(self);
    }
    pub fn readerExit(self: *Graph) void {
        rcu.readerExit(self);
    }
    pub fn retireBlockFwd(self: *Graph, block_idx: u32) !void {
        return rcu.retireBlockFwd(self, block_idx);
    }
    pub fn retireBlockRev(self: *Graph, block_idx: u32) !void {
        return rcu.retireBlockRev(self, block_idx);
    }
    pub fn bumpEpoch(self: *Graph) void {
        rcu.bumpEpoch(self);
    }
    pub fn reclaimRetired(self: *Graph) void {
        rcu.reclaimRetired(self);
    }

    // ── Mutation ──────────────────────────────────────────────────────

    pub fn addEdge(self: *Graph, src: types.NodeId, dest: types.NodeId, relation: u16, flags: u16) GraphError!void {
        return mutation.addEdge(self, src, dest, relation, flags);
    }
};
