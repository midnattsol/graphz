const std = @import("std");
const types = @import("types.zig");

/// Entries per page — chosen to fit in common cache sizes.
pub const NODES_PER_PAGE: u32 = 256; // 256 × 60 B ≈ 15 KB — fits in L2 cache.
pub const EDGE_BLOCKS_PER_PAGE: u32 = 64; // 64 × 520 B ≈ 33 KB — fits in L1 cache.
pub const EDGE_GROUPS_PER_PAGE: u32 = 128; // 128 × 12 B = 1536 B.

/// Sentinel value marking the end of an EdgeBlockGroup chain.
pub const END_OF_CHAIN: u32 = 0xFFFF_FFFF;

/// Compute the occupancy mask for a given live count. Handles the
/// edge cases live_count == 0 (mask = 0) and live_count == 64
/// (mask = 0xFFFF_FFFF_FFFF_FFFF) which would be UB with a bare shift.
pub fn denseMask(live_count: u6) u64 {
    if (live_count == 0) return 0;
    if (live_count == 64) return 0xFFFF_FFFF_FFFF_FFFF;
    return (@as(u64, 1) << live_count) - 1;
}

/// Minimum occupancy per non-tail block (75% of 64).
pub const MIN_OCCUPANCY: u6 = 48;

/// Maximum number of groups per node before repair is required.
pub const MAX_GROUPS_PER_NODE: u16 = 4;

/// Resolve a flat index into page and slot for any pool.
/// `per_page` must be the matching *_PER_PAGE constant.
pub inline fn pageOf(idx: u32, comptime per_page: u32) u32 {
    return idx / per_page;
}
pub inline fn slotOf(idx: u32, comptime per_page: u32) u32 {
    return idx % per_page;
}
pub inline fn makeIndex(page: u32, slot: u32, comptime per_page: u32) u32 {
    return page * per_page + slot;
}

comptime {
    std.debug.assert(@sizeOf(types.EdgeBlockFwd) == 520);
    std.debug.assert(@sizeOf(types.EdgeBlockRev) == 264);
    std.debug.assert(@sizeOf(types.EdgeBlockGroup) == 12);
}
