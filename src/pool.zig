//! Page-based pool allocation and accessors for edge blocks and groups.

const std = @import("std");
const constants = @import("constants.zig");
const types = @import("types.zig");

pub fn nodeAt(graph_state: anytype, id: types.NodeId) *types.NodeBuffer {
    const page_index = constants.pageOf(id.index, constants.NODES_PER_PAGE);
    return &graph_state.node_pages.items[page_index][constants.slotOf(id.index, constants.NODES_PER_PAGE)];
}

pub fn nodeAtConst(graph_state: anytype, id: types.NodeId) *const types.NodeBuffer {
    const page_index = constants.pageOf(id.index, constants.NODES_PER_PAGE);
    return &graph_state.node_pages.items[page_index][constants.slotOf(id.index, constants.NODES_PER_PAGE)];
}

pub fn edgeBlockFwdAt(graph_state: anytype, block_index: u32) *types.EdgeBlockFwd {
    const page_index = constants.pageOf(block_index, constants.EDGE_BLOCKS_PER_PAGE);
    return &graph_state.edge_blocks_fwd.items[page_index][constants.slotOf(block_index, constants.EDGE_BLOCKS_PER_PAGE)];
}

pub fn edgeBlockFwdAtConst(graph_state: anytype, block_index: u32) *const types.EdgeBlockFwd {
    const page_index = constants.pageOf(block_index, constants.EDGE_BLOCKS_PER_PAGE);
    return &graph_state.edge_blocks_fwd.items[page_index][constants.slotOf(block_index, constants.EDGE_BLOCKS_PER_PAGE)];
}

pub fn edgeBlockRevAt(graph_state: anytype, block_index: u32) *types.EdgeBlockRev {
    const page_index = constants.pageOf(block_index, constants.EDGE_BLOCKS_PER_PAGE);
    return &graph_state.edge_blocks_rev.items[page_index][constants.slotOf(block_index, constants.EDGE_BLOCKS_PER_PAGE)];
}

pub fn edgeBlockRevAtConst(graph_state: anytype, block_index: u32) *const types.EdgeBlockRev {
    const page_index = constants.pageOf(block_index, constants.EDGE_BLOCKS_PER_PAGE);
    return &graph_state.edge_blocks_rev.items[page_index][constants.slotOf(block_index, constants.EDGE_BLOCKS_PER_PAGE)];
}

pub fn groupAt(graph_state: anytype, group_index: u32) *types.EdgeBlockGroup {
    const page_index = constants.pageOf(group_index, constants.EDGE_GROUPS_PER_PAGE);
    return &graph_state.edge_block_groups.items[page_index][constants.slotOf(group_index, constants.EDGE_GROUPS_PER_PAGE)];
}

pub fn groupAtConst(graph_state: anytype, group_index: u32) *const types.EdgeBlockGroup {
    const page_index = constants.pageOf(group_index, constants.EDGE_GROUPS_PER_PAGE);
    return &graph_state.edge_block_groups.items[page_index][constants.slotOf(group_index, constants.EDGE_GROUPS_PER_PAGE)];
}

pub fn allocBlockFwd(graph_state: anytype) !u32 {
    if (graph_state.free_blocks_fwd.items.len > 0) {
        if (graph_state.free_blocks_fwd.pop()) |idx| return idx;
    }

    const block_index = graph_state.block_fwd_count;
    graph_state.block_fwd_count += 1;

    if (block_index % constants.EDGE_BLOCKS_PER_PAGE == 0) {
        const new_page = try graph_state.allocator.alloc(types.EdgeBlockFwd, constants.EDGE_BLOCKS_PER_PAGE);
        @memset(new_page, std.mem.zeroes(types.EdgeBlockFwd));
        try graph_state.edge_blocks_fwd.append(graph_state.allocator, new_page);
    }
    return block_index;
}

pub fn allocBlockRev(graph_state: anytype) !u32 {
    if (graph_state.free_blocks_rev.items.len > 0) {
        if (graph_state.free_blocks_rev.pop()) |idx| return idx;
    }

    const block_index = graph_state.block_rev_count;
    graph_state.block_rev_count += 1;

    if (block_index % constants.EDGE_BLOCKS_PER_PAGE == 0) {
        const new_page = try graph_state.allocator.alloc(types.EdgeBlockRev, constants.EDGE_BLOCKS_PER_PAGE);
        @memset(new_page, std.mem.zeroes(types.EdgeBlockRev));
        try graph_state.edge_blocks_rev.append(graph_state.allocator, new_page);
    }
    return block_index;
}

pub fn allocGroup(graph_state: anytype) !u32 {
    if (graph_state.free_groups.items.len > 0) {
        if (graph_state.free_groups.pop()) |idx| return idx;
    }

    const group_index = graph_state.group_count;
    graph_state.group_count += 1;

    if (group_index % constants.EDGE_GROUPS_PER_PAGE == 0) {
        const new_page = try graph_state.allocator.alloc(types.EdgeBlockGroup, constants.EDGE_GROUPS_PER_PAGE);
        @memset(new_page, std.mem.zeroes(types.EdgeBlockGroup));
        try graph_state.edge_block_groups.append(graph_state.allocator, new_page);
    }
    return group_index;
}

pub fn freeGroup(graph_state: anytype, group_index: u32) void {
    graph_state.free_groups.append(graph_state.allocator, group_index) catch {};
}
