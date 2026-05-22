# graphz

A generic directed-graph library for Zig.

- **CSR** (Compressed Sparse Row) — compact, read-only graphs with O(1) neighbor access
- **Typed** — generic over node data `T` and edge weights `W`
- **Builder** — construct graphs dynamically, then `freeze()` into the static representation
- **Bidirectional** — forward and reverse edge access (`neighbors` / `inNeighbors`)

```zig
const gz = @import("graphz");

var builder = gz.GraphBuilder(City, f64).init(allocator);
defer builder.deinit();

const lima = try builder.addNode(.{ .name = "Lima" });
const cusco = try builder.addNode(.{ .name = "Cusco" });
try builder.addEdge(lima, cusco, 573.0);

const graph = try builder.freeze(allocator);
defer graph.deinit(allocator);

for (graph.neighbors(lima)) |n| {
    // n is cusco
}
```

## Algorithms

- BFS
- DFS

## Usage

```sh
zig build test      # run tests
zig build run       # run the CLI
```

## CI

CI installs and runs Zig `0.16.0` explicitly in Woodpecker.

## Requirements

Zig 0.16.0
