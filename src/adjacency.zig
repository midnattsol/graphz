//! Adjacency chain manipulation — groups, block traversal, and edge search.

const constants = @import("constants.zig");
const types = @import("types.zig");
const pool = @import("pool.zig");

pub fn searchEdgeInBlock(block: *const types.EdgeBlockFwd, target: u32) ?u7 {
    const live: u6 = @intCast(@popCount(block.mask));
    if (live == 0) return null;
    if (target < block.edges[0].dest or target > block.edges[live - 1].dest) return null;

    var low: u7 = 0;
    var high: u7 = @intCast(live);
    while (low < high) {
        const probe: u7 = low + (high - low) / 2;
        if (block.edges[probe].dest < target) {
            low = probe + 1;
        } else if (block.edges[probe].dest == target) {
            return probe;
        } else {
            high = probe;
        }
    }
    return null;
}

pub fn appendGroupToAdj(graph_state: anytype, adjacency_header: *types.NodeAdj, new_block: u32, comptime dir: enum { fwd, rev }) !void {
    const new_group_index = try pool.allocGroup(graph_state);
    pool.groupAt(graph_state, new_group_index).* = types.EdgeBlockGroup{ .start = new_block, .count = 1, .next = constants.END_OF_CHAIN };

    const group_count = if (dir == .fwd) adjacency_header.group_count_fwd else adjacency_header.group_count_rev;
    const first_group = if (dir == .fwd) adjacency_header.first_group_fwd else adjacency_header.first_group_rev;
    const first_block = if (dir == .fwd) adjacency_header.first_block_fwd else adjacency_header.first_block_rev;
    const block_count = if (dir == .fwd) adjacency_header.block_count_fwd else adjacency_header.block_count_rev;

    if (group_count == 0) {
        const prefix_group_index = try pool.allocGroup(graph_state);
        pool.groupAt(graph_state, prefix_group_index).* = types.EdgeBlockGroup{ .start = first_block, .count = block_count, .next = new_group_index };
        if (dir == .fwd) {
            adjacency_header.first_group_fwd = prefix_group_index;
            adjacency_header.group_count_fwd = 2;
        } else {
            adjacency_header.first_group_rev = prefix_group_index;
            adjacency_header.group_count_rev = 2;
        }
    } else {
        var group_index = first_group;
        while (true) {
            const group = pool.groupAt(graph_state, group_index);
            if (group.next == constants.END_OF_CHAIN) {
                pool.groupAt(graph_state, group_index).next = new_group_index;
                break;
            }
            group_index = group.next;
        }
        if (dir == .fwd) {
            adjacency_header.group_count_fwd += 1;
        } else {
            adjacency_header.group_count_rev += 1;
        }
    }
}

pub fn tailBlockIndex(graph_state: anytype, adjacency_header: *const types.NodeAdj, comptime dir: enum { fwd, rev }) u32 {
    const first = if (dir == .fwd) adjacency_header.first_block_fwd else adjacency_header.first_block_rev;
    const total = if (dir == .fwd) adjacency_header.block_count_fwd else adjacency_header.block_count_rev;
    const groups = if (dir == .fwd) adjacency_header.group_count_fwd else adjacency_header.group_count_rev;
    const first_group = if (dir == .fwd) adjacency_header.first_group_fwd else adjacency_header.first_group_rev;

    if (groups == 0) return first + total - 1;

    var group_index = first_group;
    while (true) {
        const group = pool.groupAt(graph_state, group_index);
        if (group.next == constants.END_OF_CHAIN) return group.start + group.count - 1;
        group_index = group.next;
    }
}

pub fn removeTailFromAdj(graph_state: anytype, adjacency_header: *types.NodeAdj, comptime dir: enum { fwd, rev }) void {
    if ((if (dir == .fwd) adjacency_header.group_count_fwd else adjacency_header.group_count_rev) > 0) {
        const first_group = if (dir == .fwd) adjacency_header.first_group_fwd else adjacency_header.first_group_rev;
        var group_index = first_group;
        while (true) {
            const group = pool.groupAt(graph_state, group_index);
            if (group.next == constants.END_OF_CHAIN) {
                pool.groupAt(graph_state, group_index).count -= 1;
                break;
            }
            group_index = group.next;
        }
    } else {
        if (dir == .fwd) {
            adjacency_header.block_count_fwd -= 1;
        } else {
            adjacency_header.block_count_rev -= 1;
        }
    }
}

pub fn hasEdgeInAdj(graph_state: anytype, adjacency_header: types.NodeAdj, target: u32) bool {
    if (adjacency_header.block_count_fwd == 0) return false;

    if (adjacency_header.group_count_fwd == 0) {
        const first_block = adjacency_header.first_block_fwd;
        var block_offset: u32 = 0;
        while (block_offset < adjacency_header.block_count_fwd) : (block_offset += 1) {
            if (searchEdgeInBlock(pool.edgeBlockFwdAtConst(graph_state, first_block + block_offset), target) != null) return true;
        }
        return false;
    }

    var group_index = adjacency_header.first_group_fwd;
    while (true) {
        const group = pool.groupAtConst(graph_state, group_index);
        var block_offset: u32 = 0;
        while (block_offset < group.count) : (block_offset += 1) {
            if (searchEdgeInBlock(pool.edgeBlockFwdAtConst(graph_state, group.start + block_offset), target) != null) return true;
        }
        if (group.next == constants.END_OF_CHAIN) return false;
        group_index = group.next;
    }
}
