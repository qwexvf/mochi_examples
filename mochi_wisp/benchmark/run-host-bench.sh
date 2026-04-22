#!/usr/bin/env bash
# Benchmark mochi against Node.js GraphQL servers.
# Runs two rounds: no document cache, then with document cache.
# All servers run in Docker for a fair comparison.
#
# Usage:
#   ./run-host-bench.sh              # full run (simple + medium, both cache modes)
#   DURATION=30s ./run-host-bench.sh # custom duration

DURATION="${DURATION:-10s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
WARMUP="${WARMUP:-3s}"

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE="$BENCH_DIR/docker-compose.yml"

declare -A URLS=(
  [mochi]="http://localhost:4000/graphql"
  [mercurius]="http://localhost:4001/graphql"
  [apollo]="http://localhost:4002/graphql"
  [yoga]="http://localhost:4003/graphql"
  [bun+yoga]="http://localhost:4004/graphql"
)
SERVER_ORDER=("mochi" "bun+yoga" "mercurius" "yoga" "apollo")

# ── Helpers ──────────────────────────────────────────────────────────────────

port_open() {
  ss -tlnp 2>/dev/null | grep -qE ":$1[[:space:]]"
}

wait_port() {
  local port="$1" name="$2" timeout="${3:-60}"
  for i in $(seq 1 "$timeout"); do
    if port_open "$port"; then
      printf "  ✓ %-20s ready\n" "$name"
      return 0
    fi
    sleep 1
  done
  printf "  ✗ %-20s timed out after %ds\n" "$name" "$timeout"
  return 1
}

start_all() {
  local doc_cache="$1"
  docker compose --file "$COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
  DOCUMENT_CACHE="$doc_cache" docker compose --file "$COMPOSE" up -d --build >/dev/null 2>&1 || true
  wait_port 4000 "mochi (erlang)" 60
  wait_port 4001 "mercurius" 30
  wait_port 4002 "apollo" 30
  wait_port 4003 "yoga (node)" 30
  wait_port 4004 "bun + yoga" 30
}

run_wrk() {
  local script="$1" url="$2"
  wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" \
      -s "$BENCH_DIR/wrk/${script}.lua" "$url" 2>/dev/null \
    | awk '/Latency/{lat=$2} /Requests\/sec/{rps=$2} END{printf "%s\t%s", rps, lat}'
}

warmup() {
  for name in "${SERVER_ORDER[@]}"; do
    wrk -t2 -c20 -d"$WARMUP" -s "$BENCH_DIR/wrk/simple.lua" "${URLS[$name]}" >/dev/null 2>&1 || true
  done
}

print_query_results() {
  local script="$1"
  echo ""
  printf "  %-22s  %12s   %s\n" "server" "req/sec" "latency"
  printf "  %-22s  %12s   %s\n" "------" "-------" "-------"
  for name in "${SERVER_ORDER[@]}"; do
    result=$(run_wrk "$script" "${URLS[$name]}")
    rps=$(echo "$result" | cut -f1)
    lat=$(echo "$result" | cut -f2)
    printf "  %-22s  %12s   %s\n" "$name" "$rps" "$lat"
  done
}

print_round() {
  local label="$1"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $label"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ${THREADS} threads / ${CONNECTIONS} connections / ${DURATION}"

  echo ""
  echo "  Simple query: { users { id name } }"
  print_query_results "simple"

  echo ""
  echo "  Medium query: { users { id name email posts { id title } } }"
  print_query_results "medium"
}

cleanup() {
  echo ""
  echo "Cleaning up..."
  docker compose --file "$COMPOSE" down --remove-orphans >/dev/null 2>&1 || true
  echo "Done."
}

trap cleanup EXIT

# ── Round 1: no document cache ───────────────────────────────────────────────

echo ""
echo "Starting servers (no document cache)..."
start_all "false"

echo ""
echo "Warming up (${WARMUP})..."
warmup

print_round "NO DOCUMENT CACHE"

# ── Round 2: with document cache ─────────────────────────────────────────────

echo ""
echo ""
echo "Restarting servers (with document cache)..."
start_all "true"

echo ""
echo "Warming up (${WARMUP})..."
warmup

print_round "WITH DOCUMENT CACHE"
