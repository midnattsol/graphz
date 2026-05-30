const std = @import("std");

// ── Basic types ──────────────────────────────────────────────────────

/// Opaque node identifier. Flat u32 index; internally resolved to
/// (page = index >> 8, slot = index & 255).
pub const NodeId = struct { index: u32 };

pub const GraphError = error{
    OutOfMemory,
    InvalidNode,
    EdgeAlreadyExists,
    CorruptGraph,
    ConcurrentMutation,
    UnsupportedOperation,
    RepairRequired,
};

/// Per-node boolean flags. Backed by u32 so that NodeAdj measures 28 bytes
/// (multiple of 4), keeping all u32 fields naturally aligned.
pub const NodeFlags = packed struct(u32) {
    needs_repair_fwd: bool,
    needs_repair_rev: bool,
    removed: bool,
    _reserved: u29 = 0,
};

/// Edge-level boolean flags. 16 bits packed alongside relation and dst.
/// Unused in v0; reserved for future features (pinned, hidden, traversed...).
pub const EdgeFlags = packed struct(u16) {
    _unused: u16 = 0,
};

/// A single directed edge. 8 bytes: 4-byte dst + 2-byte relation label
/// + 2-byte packed flags. Larger properties (weights, timestamps) go in
/// external columnar arrays keyed by (src, dst) pair (see RFC §10).
pub const Edge = packed struct {
    dest: u32,
    relation: u16,
    flags: EdgeFlags,
};

// ── Per-node adjacency descriptor ────────────────────────────────────

/// Describes where the node's forward and reverse edge blocks live,
/// how many there are, and whether they are contiguous or grouped.
/// `degree` is NOT stored — it is computed from `@popCount(block.mask)`.
pub const NodeAdj = packed struct {
    first_block_fwd: u32,
    block_count_fwd: u16,
    group_count_fwd: u16,
    first_group_fwd: u32,

    first_block_rev: u32,
    block_count_rev: u16,
    group_count_rev: u16,
    first_group_rev: u32,

    flags: NodeFlags,
};

/// RCU double-buffer. Two NodeAdj slots + atomic flag.
/// Readers: load(.acquire) → read slots[active], no locks.
/// Writers: copy slots[active] → slots[staging] → mutate → flip(.release).
/// Copy-on-write: blocks are never mutated in-place; mutations copy
/// affected blocks to private copies before publishing.
pub const NodeBuffer = struct {
    /// Stored as u8 because Zig atomics only support byte-width integers.
    /// Invariant: value is always 0 or 1.
    active_slot_raw: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    slots: [2]NodeAdj,

    pub fn loadActiveSlot(self: *const NodeBuffer) u1 {
        const raw = self.active_slot_raw.load(.acquire);
        std.debug.assert(raw <= 1);
        return @intCast(raw);
    }

    pub fn storeActiveSlot(self: *NodeBuffer, slot: u1) void {
        self.active_slot_raw.store(@as(u8, slot), .release);
    }
};

// ── Edge blocks ──────────────────────────────────────────────────────

/// 64 outgoing edges (520 bytes). Dense storage: live entries occupy
/// slots [0, live_count) with no holes. `mask = denseMask(live_count)`.
/// Sorted by dst for binary-search lookup. Iteration via `@ctz(mask)` +
/// `mask &= mask - 1` with zero branches.
pub const EdgeBlockFwd = extern struct {
    mask: u64,
    edges: [64]Edge,
};

/// 64 incoming source node IDs (264 bytes). Same mask logic as
/// EdgeBlockFwd, but payload is u32 (half the size) — reverse adjacency
/// only needs the source, not relation or flags.
pub const EdgeBlockRev = extern struct {
    mask: u64,
    sources: [64]u32,
};

// ── Contiguous edge block group ──────────────────────────────────────

/// A chainable span of physically contiguous edge blocks. 0xFFFF_FFFF = end.
/// 12 bytes aligned: avoids cache-line splits during chain traversal.
/// Nodes with contiguous blocks use `group_count_* = 0` (fast path).
pub const EdgeBlockGroup = extern struct {
    start: u32,
    next: u32,
    count: u16,
    _pad: u16 = 0,
};

/// Tracks a retired block index and the epoch when it was retired.
pub const RetiredBlock = struct {
    block: u32,
    epoch: u64,
};

/// Validation violation type. Returned by `debugValidate`.
pub const Violation = union(enum) {
    degree_mismatch: struct { node: u32, expected: u32, actual: u32 },
    occupancy_below_threshold: struct { node: u32, block: u32, occupancy: u32 },
    mask_bit_out_of_range: struct { node: u32, block: u32 },
    invalid_dst: struct { node: u32, block: u32, slot: u32, dst: u32 },
    forward_reverse_mismatch: struct { node: u32, dst: u32 },
    unsorted_block: struct { node: u32, block: u32, slot: u32 },
    blockgroup_chain_cycle: struct { node: u32, group: u32 },
    blockgroup_overlap: struct { node: u32, group_a: u32, group_b: u32 },
    block_double_owned: struct { block: u32 },
    block_orphaned_in_free_list: struct { block: u32 },
    repair_debt_invalid_node: struct { entry: u32 },
    edge_count_mismatch: struct { expected: u64, actual: u64 },
    retired_block_reachable: struct { block: u32, node: u32 },
};
