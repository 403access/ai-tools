# Performance work

This folder records the performance analysis for the two clients in this
repository:

- the macOS menu bar app (`Sources/OpenCodeBar`)
- the iOS/iPadOS app (`Sources/OpenCodeBarMobile`)

Both talk to the same hub and share the model and formatting code, so most hot
paths were the same. The work was split into a measured baseline and a
post-change report so the effect of each change is visible.

| Document | Contents |
| --- | --- |
| [before.md](before.md) | Baseline analysis: method, hot paths, measurements, and why they mattered. |
| [after.md](after.md) | What changed, after measurements, validation, and what is left. |

## Reproducing the numbers

The benchmark compiles the shared Foundation-level model code and drives it
with synthetic data. It does not need a hub, OpenCode, or a simulator.

```sh
Scripts/perf-benchmark.sh
```

Results are indicative microbenchmark numbers on one machine; they are useful
for comparing before/after and for catching regressions, not as a guarantee of
end-to-end frame time. Build validation:

```sh
make build          # macOS
make test           # macOS unit tests
make mobile-build   # iOS simulator build
```
