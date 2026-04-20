#!/usr/bin/env bash
set -euo pipefail

DURATION="${DURATION:-10s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
WARMUP="${WARMUP:-3s}"
BENCH_DIR="$(dirname "$0")"
MOCHI_DIR="$(dirname "$0")/.."

declare -A SERVERS
SERVERS["mochi (erlang)"]="http://localhost:4000/graphql"
SERVERS["mercurius"]="http://localhost:4001/graphql"
SERVERS["apollo"]="http://localhost:4002/graphql"
SERVERS["yoga (node)"]="http://localhost:4003/graphql"
SERVERS["bun + yoga"]="http://localhost:4004/graphql"

PROBE='{"query":"{ __typename }"}'

wait_for() {
  local name="$1" url="$2"
  for i in $(seq 1 30); do
    if curl -sf -X POST "$url" \
         -H "Content-Type: application/json" \
         -d "$PROBE" >/dev/null 2>&1; then
      printf "  ✓ %-20s ready\n" "$name"
      return 0
    fi
    sleep 1
  done
  printf "  ✗ %-20s timed out after 30s\n" "$name"
  return 1
}

run_wrk() {
  local script="$1" url="$2"
  wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" \
      -s "$BENCH_DIR/wrk/$script.lua" "$url" 2>/dev/null \
    | grep -E "Requests/sec|Latency" \
    | awk '
        /Latency/     { lat=$2 }
        /Requests.sec/ { rps=$2 }
        END { printf "  %10s req/s   avg latency %s\n", rps, lat }
      '
}

start_mochi() {
  local cache="$1"
  pkill -f "mochi_wisp" 2>/dev/null || true
  pkill -f "beam.smp.*mochi_wisp" 2>/dev/null || true
  sleep 1
  MOCHI_CACHE="$cache" gleam run --chdir "$MOCHI_DIR" >/tmp/mochi_bench.log 2>&1 &
  for i in $(seq 1 30); do
    if curl -sf -X POST http://localhost:4000/graphql \
         -H "Content-Type: application/json" \
         -d "$PROBE" >/dev/null 2>&1; then
      printf "  ✓ %-20s ready\n" "mochi (erlang)"
      return 0
    fi
    sleep 1
  done
  printf "  ✗ mochi timed out\n"
  return 1
}

run_round() {
  local label="$1"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $label"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  echo ""
  echo "Warming up (${WARMUP})..."
  for url in "${SERVERS[@]}"; do
    wrk -t2 -c20 -d"$WARMUP" -s "$BENCH_DIR/wrk/simple.lua" "$url" >/dev/null 2>&1 || true
  done

  echo ""
  echo "  Simple query: { users { id name } }"
  echo "  ${THREADS} threads / ${CONNECTIONS} connections / ${DURATION}"
  echo "──────────────────────────────────────────────────────────"
  printf "  %-22s %s\n" "server" "result"
  echo "──────────────────────────────────────────────────────────"
  for name in "mochi (erlang)" "mercurius" "apollo" "yoga (node)" "bun + yoga"; do
    printf "  %-22s" "$name"
    run_wrk simple "${SERVERS[$name]}"
  done

  echo ""
  echo "  Medium query: { users { id name email posts { id title } } }"
  echo "  ${THREADS} threads / ${CONNECTIONS} connections / ${DURATION}"
  echo "──────────────────────────────────────────────────────────"
  printf "  %-22s %s\n" "server" "result"
  echo "──────────────────────────────────────────────────────────"
  for name in "mochi (erlang)" "mercurius" "apollo" "yoga (node)" "bun + yoga"; do
    printf "  %-22s" "$name"
    run_wrk medium "${SERVERS[$name]}"
  done
}

# ── Round 1: no document cache ─────────────────────────────────────────────

echo ""
echo "Starting competitors (no cache)..."
docker compose --file "$BENCH_DIR/docker-compose.yml" \
  --env-file "$BENCH_DIR/env/no-cache.env" up -d --build 2>&1 | grep -E "Started|error" || true

echo "Starting mochi (no cache)..."
start_mochi "false"

run_round "NO DOCUMENT CACHE"

# ── Round 2: with document cache ───────────────────────────────────────────

echo ""
echo ""
echo "Restarting competitors (with cache)..."
docker compose --file "$BENCH_DIR/docker-compose.yml" \
  --env-file "$BENCH_DIR/env/with-cache.env" up -d --build 2>&1 | grep -E "Started|error" || true

echo "Restarting mochi (with cache)..."
start_mochi "true"

run_round "WITH DOCUMENT CACHE"

# ── Cleanup ────────────────────────────────────────────────────────────────

echo ""
docker compose --file "$BENCH_DIR/docker-compose.yml" down 2>&1 | grep -v "^$" || true
pkill -f "beam.smp.*mochi_wisp" 2>/dev/null || true
echo "Done."
