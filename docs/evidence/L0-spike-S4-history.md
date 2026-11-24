# L0 spike S4: history

This file is maintained by hand. `make spike-s4` writes only the generated results in [`L0-spike-S4.md`](L0-spike-S4.md) and never touches this file.

## Run history

Three complete runs on 2026-11-23 (UTC), all PASS. The generated file held run 3 when this history was split out on 2026-11-24. Worst values across all runs: **EndpointSlice 651 ms, real traffic 405 ms** (both from the first run).

| Run | Slice max (ms) | Traffic max (ms) |
|---|---:|---:|
| 1 | 651 | 405 |
| 2 | 281 | 177 |
| 3 | 247 | 173 |

**Scope:** the backends are small test servers and the Endpoints were patched by `kubectl`, not Patroni. Real failover timing is measured in L2.
