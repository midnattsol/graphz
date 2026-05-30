//! Edge insertion — the primary mutation path.
//!
//! Accepts `anytype` to avoid circular imports with graph.zig.

const constants = @import("constants.zig");
const types = @import("types.zig");
const pool = @import("pool.zig");
const adjacency = @import("adjacency.zig");
const rcu = @import("rcu.zig");

pub fn addEdge(graph_state: anytype, src: types.NodeId, dest: types.NodeId, relation: u16, flags: u16) types.GraphError!void {
    if (src.index >= graph_state.node_count or dest.index >= graph_state.node_count) return error.InvalidNode;

    var src_node = pool.nodeAt(graph_state, src);
    const src_active_slot: u1 = src_node.loadActiveSlot();
    const src_staging_slot: u1 = 1 - src_active_slot;
    src_node.slots[src_staging_slot] = src_node.slots[src_active_slot];
    const src_adj = &src_node.slots[src_staging_slot];

    var dst_node = pool.nodeAt(graph_state, dest);
    const dst_active_slot: u1 = dst_node.loadActiveSlot();
    const dst_staging_slot: u1 = 1 - dst_active_slot;
    dst_node.slots[dst_staging_slot] = dst_node.slots[dst_active_slot];
    const dst_adj = &dst_node.slots[dst_staging_slot];

    if (adjacency.hasEdgeInAdj(graph_state, src_node.slots[src_active_slot], dest.index)) {
        return error.EdgeAlreadyExists;
    }

    var old_block_fwd: ?u32 = null;
    var block_fwd_idx: u32 = undefined;
    if (src_adj.block_count_fwd == 0) {
        block_fwd_idx = try pool.allocBlockFwd(graph_state);
        src_adj.first_block_fwd = block_fwd_idx;
        src_adj.block_count_fwd = 1;
    } else {
        const tail = adjacency.tailBlockIndex(graph_state, src_adj, .fwd);
        const tail_block = pool.edgeBlockFwdAt(graph_state, tail);
        const live = @popCount(tail_block.mask);
        if (live == 64) {
            block_fwd_idx = try pool.allocBlockFwd(graph_state);
            if (block_fwd_idx == tail + 1) {
                src_adj.block_count_fwd += 1;
            } else {
                try adjacency.appendGroupToAdj(graph_state, src_adj, block_fwd_idx, .fwd);
            }
        } else {
            old_block_fwd = tail;
            block_fwd_idx = try pool.allocBlockFwd(graph_state);
            pool.edgeBlockFwdAt(graph_state, block_fwd_idx).* = tail_block.*;

            if (src_adj.block_count_fwd == 1) {
                src_adj.first_block_fwd = block_fwd_idx;
            } else {
                adjacency.removeTailFromAdj(graph_state, src_adj, .fwd);
                try adjacency.appendGroupToAdj(graph_state, src_adj, block_fwd_idx, .fwd);
            }
        }
    }

    {
        const fwd_block = pool.edgeBlockFwdAt(graph_state, block_fwd_idx);
        const live = @popCount(fwd_block.mask);
        var insertion_point: u7 = 0;
        var search_end: u7 = @intCast(live);
        while (insertion_point < search_end) {
            const probe: u7 = insertion_point + (search_end - insertion_point) / 2;
            if (fwd_block.edges[probe].dest < dest.index) {
                insertion_point = probe + 1;
            } else if (fwd_block.edges[probe].dest == dest.index) {
                return error.EdgeAlreadyExists;
            } else {
                search_end = probe;
            }
        }
        var shift: u7 = @intCast(live);
        while (shift > insertion_point) {
            fwd_block.edges[shift] = fwd_block.edges[shift - 1];
            shift -= 1;
        }
        fwd_block.edges[insertion_point] = types.Edge{ .dest = dest.index, .relation = relation, .flags = @bitCast(flags) };
        fwd_block.mask = constants.denseMask(@intCast(live + 1));
    }

    var old_block_rev: ?u32 = null;
    var block_rev_idx: u32 = undefined;
    if (dst_adj.block_count_rev == 0) {
        block_rev_idx = try pool.allocBlockRev(graph_state);
        dst_adj.first_block_rev = block_rev_idx;
        dst_adj.block_count_rev = 1;
    } else {
        const tail = adjacency.tailBlockIndex(graph_state, dst_adj, .rev);
        const tail_block = pool.edgeBlockRevAt(graph_state, tail);
        const live = @popCount(tail_block.mask);
        if (live == 64) {
            block_rev_idx = try pool.allocBlockRev(graph_state);
            if (block_rev_idx == tail + 1) {
                dst_adj.block_count_rev += 1;
            } else {
                try adjacency.appendGroupToAdj(graph_state, dst_adj, block_rev_idx, .rev);
            }
        } else {
            old_block_rev = tail;
            block_rev_idx = try pool.allocBlockRev(graph_state);
            pool.edgeBlockRevAt(graph_state, block_rev_idx).* = tail_block.*;
            if (dst_adj.block_count_rev == 1) {
                dst_adj.first_block_rev = block_rev_idx;
            } else {
                adjacency.removeTailFromAdj(graph_state, dst_adj, .rev);
                try adjacency.appendGroupToAdj(graph_state, dst_adj, block_rev_idx, .rev);
            }
        }
    }

    {
        const rev_block = pool.edgeBlockRevAt(graph_state, block_rev_idx);
        const live = @popCount(rev_block.mask);
        var insertion_point: u7 = 0;
        var search_end: u7 = @intCast(live);
        while (insertion_point < search_end) {
            const probe: u7 = insertion_point + (search_end - insertion_point) / 2;
            if (rev_block.sources[probe] < src.index) {
                insertion_point = probe + 1;
            } else {
                search_end = probe;
            }
        }
        var shift: u7 = @intCast(live);
        while (shift > insertion_point) {
            rev_block.sources[shift] = rev_block.sources[shift - 1];
            shift -= 1;
        }
        rev_block.sources[insertion_point] = src.index;
        rev_block.mask = constants.denseMask(@intCast(live + 1));
    }

    dst_node.storeActiveSlot(dst_staging_slot);
    src_node.storeActiveSlot(src_staging_slot);

    if (old_block_fwd) |idx| try rcu.retireBlockFwd(graph_state, idx);
    if (old_block_rev) |idx| try rcu.retireBlockRev(graph_state, idx);

    _ = graph_state.edge_count.fetchAdd(1, .monotonic);
    rcu.bumpEpoch(graph_state);
    rcu.reclaimRetired(graph_state);
}
