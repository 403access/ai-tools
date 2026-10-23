#!/usr/bin/env bash
set -euo pipefail

# Microbenchmarks for the pure model/series/formatting code the two apps share.
# It intentionally compiles only Foundation-level files (plus the hub client
# types the models reference) so it can run on any Mac without a hub or a
# simulator. Results are indicative, not a substitute for Instruments.
#
# Usage: Scripts/perf-benchmark.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/perf-benchmark"

mkdir -p "$ROOT/.build"
swiftc -O -o "$OUT" \
  "$ROOT"/Sources/OpenCodeBar/Models/*.swift \
  "$ROOT/Sources/OpenCodeBar/Support/Formatters.swift" \
  "$ROOT/Sources/OpenCodeBar/Core/HubAPI.swift" \
  "$ROOT/Sources/OpenCodeBar/Core/HubAPI+Endpoints.swift" \
  "$ROOT/Sources/OpenCodeBar/Core/HubAPI+Transport.swift" \
  "$ROOT/Sources/OpenCodeBar/Core/HubModels.swift" \
  "$ROOT/Sources/OpenCodeBar/Core/DeviceIdentity.swift" \
  "$ROOT/Scripts/PerfBenchmark.swift"

"$OUT"
