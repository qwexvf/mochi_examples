# mochi benchmark

Compares mochi (Gleam/Erlang) against Node.js GraphQL servers under HTTP load.
All servers run in Docker for a fair comparison.

## Servers

| server | stack | port |
|--------|-------|------|
| mochi | Gleam + BEAM (mist) | 4000 |
| bun + yoga | Bun + GraphQL Yoga | 4004 |
| yoga | Node.js + GraphQL Yoga | 4003 |
| mercurius | Node.js + Fastify + Mercurius | 4001 |
| apollo | Node.js + Apollo Server | 4002 |

## Requirements

- Docker
- [wrk](https://github.com/wg/wrk)

## Usage

```bash
./run-host-bench.sh              # full run (simple + medium, both cache modes)
DURATION=30s ./run-host-bench.sh # custom duration
CONNECTIONS=200 ./run-host-bench.sh
```

Runs two rounds — no document cache, then with document cache — with a warmup pass before each.

## Results (2025-04-22, 4 threads / 100 connections / 10s)

### No document cache

| server | simple req/sec | simple latency | medium req/sec | medium latency |
|--------|---------------|----------------|----------------|----------------|
| mochi | 22,910 | 4.37ms | 11,647 | 8.56ms |
| bun+yoga | 13,412 | 7.44ms | 7,303 | 13.66ms |
| yoga | 9,927 | 12.36ms | 4,747 | 24.74ms |
| mercurius | 4,612 | 30.49ms | 2,719 | 50.89ms |
| apollo | 3,487 | 38.74ms | 1,880 | 72.53ms |

### With document cache

| server | simple req/sec | simple latency | medium req/sec | medium latency |
|--------|---------------|----------------|----------------|----------------|
| mochi | 19,046 | 5.25ms | 10,601 | 9.41ms |
| bun+yoga | 11,037 | 9.04ms | 6,954 | 14.35ms |
| mercurius | 9,497 | 15.15ms | 4,692 | 25.02ms |
| yoga | 8,993 | 11.25ms | 4,618 | 25.42ms |
| apollo | 6,778 | 18.29ms | 2,628 | 49.00ms |

Queries:
- **Simple**: `{ users { id name } }`
- **Medium**: `{ users { id name email posts { id title } } }`

## What this measures

This benchmark measures end-to-end HTTP throughput for each GraphQL server:
JSON parsing → GraphQL parse → validation → execution → JSON serialization.

The main difference between mochi and the Node.js servers is not raw parse speed
but concurrency model. BEAM runs each request on its own lightweight process
scheduled across all CPU cores. Node.js runs on a single event loop thread, so
CPU-bound work (parsing, execution) serializes under concurrent load.

Mercurius's `cache: false` disables its response cache, not necessarily its
internal parse optimizations, so its "no cache" numbers may be slightly
better than a true cold-parse baseline.
