#!/usr/bin/env bash
# run-tests.sh - Run all network tests locally
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

: "${TEST_DOMAIN:?Please set TEST_DOMAIN}"
BASE_URL="https://network-test.${TEST_DOMAIN}"

PAYLOAD_SIZE="${PAYLOAD_SIZE:-1048576}"   # 1MB default
VUS="${VUS:-20}"
DURATION="${DURATION:-120s}"

RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

echo "=== Kyma Network Test Runner ==="
echo "Base URL     : ${BASE_URL}"
echo "Payload size : ${PAYLOAD_SIZE} bytes"
echo "VUs          : ${VUS}"
echo "Duration     : ${DURATION}"
echo ""

# ─── Wait for endpoint ────────────────────────────────────────
echo "▶ Waiting for endpoint to be reachable..."
for i in $(seq 1 30); do
  if curl -skf --max-time 5 "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "  Endpoint ready after ${i} attempt(s)"
    break
  fi
  echo "  Attempt ${i}/30..."
  sleep 10
done

# ─── QUIC / Protocol checks via curl ──────────────────────────
echo ""
echo "▶ [1/4] Protocol check: HTTP/1.1 → H1.1 backend"
curl -sv --http1.1 "${BASE_URL}/h1/" 2>&1 | tee "${RESULTS_DIR}/h1-curl.txt" | \
  grep -E "^[<>*]" | grep -E "HTTP|backend|protocol" || true

echo ""
echo "▶ [2/4] Protocol check: HTTP/2 → H2 backend"
curl -sv --http2 "${BASE_URL}/h2/" 2>&1 | tee "${RESULTS_DIR}/h2-curl.txt" | \
  grep -E "^[<>*]" | grep -E "HTTP|backend|protocol|h2" || true

echo ""
echo "▶ [3/4] Alt-Svc header check (HTTP/3 QUIC advertisement)"
ALT_SVC=$(curl -sk --http2 -I "${BASE_URL}/" | grep -i "alt-svc" || echo "")
echo "  Alt-Svc: ${ALT_SVC:-<not found>}"
if echo "${ALT_SVC}" | grep -qi "h3"; then
  echo "  ✓ QUIC/HTTP3 advertised"
else
  echo "  ⚠ Alt-Svc h3 not found (check EnvoyFilter)"
fi

# Optional: HTTP/3 test with curl-quic
if curl --version 2>&1 | grep -qi "HTTP3\|quic\|nghttp3"; then
  echo ""
  echo "▶ [3b] HTTP/3 (QUIC) test"
  curl -sv --http3 "${BASE_URL}/" 2>&1 | tee "${RESULTS_DIR}/quic-curl.txt" | \
    grep -E "^[<>*]" | grep -E "HTTP|protocol|quic|h3" || true
else
  echo "  (curl HTTP/3 not available; install curl with quiche or ngtcp2 for QUIC test)"
fi

# ─── k6 performance tests ─────────────────────────────────────
if ! command -v k6 &>/dev/null; then
  echo ""
  echo "▶ k6 not found. Install from https://k6.io/docs/getting-started/installation/"
  exit 0
fi

echo ""
echo "▶ [4/4] k6 protocol negotiation test"
k6 run \
  --env BASE_URL="${BASE_URL}" \
  --out json="${RESULTS_DIR}/protocol-check-raw.json" \
  "${ROOT_DIR}/tests/k6/01-protocol-check.js"

echo ""
echo "▶ k6 throughput benchmark (H2 vs H1.1)"
k6 run \
  --env BASE_URL="${BASE_URL}" \
  --env PAYLOAD_SIZE="${PAYLOAD_SIZE}" \
  --env VUS="${VUS}" \
  --env DURATION="${DURATION}" \
  --out json="${RESULTS_DIR}/throughput-raw.json" \
  "${ROOT_DIR}/tests/k6/02-throughput.js"

echo ""
echo "▶ k6 stress ramp test"
k6 run \
  --env BASE_URL="${BASE_URL}" \
  --out json="${RESULTS_DIR}/stress-raw.json" \
  "${ROOT_DIR}/tests/k6/03-stress.js" || true

echo ""
echo "=== Test complete. Results in: ${RESULTS_DIR}/ ==="
ls -lh "${RESULTS_DIR}/"
