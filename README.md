# Zenolith

Zenolith is currently a Zig 0.17 fixed-storage layout engine for ZPUI/Lythra experiments.

It is not a GUI toolkit, renderer, widget system, platform layer, text shaper, or editor API. The goal is to provide Taffy-inspired flex layout correctness with a small Zig-native storage/API shape that can later back ZPUI's element layout pass.

See [DESIGN.md](DESIGN.md) for the storage model, units, algorithm phases, and V0 omissions.

## Test

```sh
zig build test --summary all
```
