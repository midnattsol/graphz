//! RCU-style reader/writer synchronization and block retirement.

pub fn readerEnter(graph_state: anytype) u64 {
    _ = graph_state.active_readers.fetchAdd(1, .monotonic);
    return graph_state.epoch.load(.acquire);
}

pub fn readerExit(graph_state: anytype) void {
    _ = graph_state.active_readers.fetchSub(1, .monotonic);
}

pub fn retireBlockFwd(graph_state: anytype, block_idx: u32) !void {
    const current_epoch = graph_state.epoch.load(.acquire);
    try graph_state.retired_blocks_fwd.append(graph_state.allocator, .{ .block = block_idx, .epoch = current_epoch });
}

pub fn retireBlockRev(graph_state: anytype, block_idx: u32) !void {
    const current_epoch = graph_state.epoch.load(.acquire);
    try graph_state.retired_blocks_rev.append(graph_state.allocator, .{ .block = block_idx, .epoch = current_epoch });
}

pub fn bumpEpoch(graph_state: anytype) void {
    _ = graph_state.epoch.fetchAdd(1, .monotonic);
}

pub fn reclaimRetired(graph_state: anytype) void {
    if (graph_state.active_readers.load(.acquire) > 0) return;
    const safe_epoch = graph_state.epoch.load(.acquire) -| 2;

    while (graph_state.retired_blocks_fwd.items.len > 0) {
        if (graph_state.retired_blocks_fwd.items[0].epoch > safe_epoch) break;
        graph_state.free_blocks_fwd.append(graph_state.allocator, graph_state.retired_blocks_fwd.orderedRemove(0).block) catch {};
    }
    while (graph_state.retired_blocks_rev.items.len > 0) {
        if (graph_state.retired_blocks_rev.items[0].epoch > safe_epoch) break;
        graph_state.free_blocks_rev.append(graph_state.allocator, graph_state.retired_blocks_rev.orderedRemove(0).block) catch {};
    }
}
