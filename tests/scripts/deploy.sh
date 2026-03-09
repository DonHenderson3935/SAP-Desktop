#!/usr/bin/env bash
# deploy.sh - Deploy network test resources to Kyma (local/manual use)
#
# Kyma Trial Instance: A83C07AB-169C-4CF6-89EC-A9F095B554E2
# API Server        : https://api.c-2a1d8cc.kyma.ondemand.com
# KubeconfigURL     : https://kyma-env-broker.cp.kyma.cloud.sap/kubeconfig/A83C07AB-169C-4CF6-89EC-A9F095B554E2
#
# Auth option A: BTP OAuth2 (auto-fetch kubeconfig)
#   export BTP_CLIENT_ID=...
#   export BTP_CLIENT_SECRET=...
#   export BTP_TOKEN_URL=https://<subaccount>.authentication.eu10.hana.ondemand.com
#
# Auth option B: Manual kubeconfig (already downloaded from Kyma Dashboard)
#   export KUBECONFIG=/path/to/kubeconfig.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NAMESPACE="network-test"
TEST_DOMAIN="${TEST_DOMAIN:-c-2a1d8cc.kyma.ondemand.com}"
KYMA_KUBECONFIG_URL="https://kyma-env-broker.cp.kyma.cloud.sap/kubeconfig/A83C07AB-169C-4CF6-89EC-A9F095B554E2"
IMAGE_TAG="${IMAGE_TAG:-ghcr.io/${GITHUB_ORG:-your-org}/ewp-kyma/echo-server:latest}"

# ─── Kubeconfig: BTP OAuth2 or manual ────────────────────────
if [ -z "${KUBECONFIG:-}" ]; then
  if [ -n "${BTP_CLIENT_ID:-}" ] && [ -n "${BTP_CLIENT_SECRET:-}" ] && [ -n "${BTP_TOKEN_URL:-}" ]; then
    echo "▶ Fetching kubeconfig via BTP OAuth2..."
    TOKEN=$(curl -sf -X POST "${BTP_TOKEN_URL}/oauth/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials&client_id=${BTP_CLIENT_ID}&client_secret=${BTP_CLIENT_SECRET}" \
      | jq -r '.access_token')

    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
      echo "ERROR: Failed to fetch BTP OAuth2 token" >&2
      exit 1
    fi

    TMP_KUBECONFIG=$(mktemp /tmp/kyma-kubeconfig-XXXXXX.yaml)
    curl -sf -H "Authorization: Bearer ${TOKEN}" \
      "${KYMA_KUBECONFIG_URL}" > "${TMP_KUBECONFIG}"
    export KUBECONFIG="${TMP_KUBECONFIG}"
    echo "  ✓ Kubeconfig fetched → ${TMP_KUBECONFIG}"
  else
    echo "ERROR: Provide either KUBECONFIG path or BTP_CLIENT_ID + BTP_CLIENT_SECRET + BTP_TOKEN_URL" >&2
    echo ""
    echo "Option A (BTP OAuth2):"
    echo "  export BTP_CLIENT_ID=..."
    echo "  export BTP_CLIENT_SECRET=..."
    echo "  export BTP_TOKEN_URL=https://<subaccount>.authentication.eu10.hana.ondemand.com"
    echo ""
    echo "Option B (manual kubeconfig from https://dashboard.kyma.cloud.sap):"
    echo "  export KUBECONFIG=/path/to/kubeconfig.yaml"
    exit 1
  fi
fi

echo "=== Kyma Network Test Deployment ==="
echo "Namespace  : ${NAMESPACE}"
echo "Domain     : ${TEST_DOMAIN}"
echo "Image      : ${IMAGE_TAG}"
echo "API Server : https://api.c-2a1d8cc.kyma.ondemand.com"
echo ""

# ─── Verify connectivity ──────────────────────────────────────
echo "▶ Verifying cluster connectivity..."
kubectl cluster-info --request-timeout=10s

# ─── Detect wildcard TLS secret ───────────────────────────────
echo "▶ Detecting Kyma wildcard TLS secret..."
TLS_SECRET=$(kubectl get secret -n istio-system \
  -o json 2>/dev/null \
  | jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name' \
  | grep -E "wildcard|kyma|gardener|shoot" | head -1 || echo "")
TLS_SECRET="${TLS_SECRET:-network-test-tls}"
echo "  Using TLS secret: ${TLS_SECRET}"

# ─── Substitute and apply manifests ───────────────────────────
TMP_DIR="$(mktemp -d)"
trap "rm -rf ${TMP_DIR}" EXIT

echo "▶ Substituting variables in manifests..."
for src in \
  "${ROOT_DIR}/k8s/backend/01-h2-backend.yaml" \
  "${ROOT_DIR}/k8s/backend/02-h1-backend.yaml" \
  "${ROOT_DIR}/k8s/gateway/04-gateway.yaml" \
  "${ROOT_DIR}/k8s/gateway/05-envoyfilter-quic.yaml" \
  "${ROOT_DIR}/k8s/gateway/06-virtual-service.yaml" \
  "${ROOT_DIR}/k8s/gateway/07-destination-rule.yaml"
do
  filename="$(basename "$src")"
  sed \
    -e "s|\${TEST_DOMAIN}|${TEST_DOMAIN}|g" \
    -e "s|ghcr.io/GITHUB_ORG/ewp-kyma/echo-server:latest|${IMAGE_TAG}|g" \
    -e "s|GITHUB_ORG|${GITHUB_ORG:-your-org}|g" \
    -e "s|network-test-tls|${TLS_SECRET}|g" \
    "$src" > "${TMP_DIR}/${filename}"
done

echo "▶ Applying namespace..."
kubectl apply -f "${ROOT_DIR}/k8s/00-namespace.yaml"

echo "▶ Deploying backends..."
kubectl apply -f "${TMP_DIR}/01-h2-backend.yaml"
kubectl apply -f "${TMP_DIR}/02-h1-backend.yaml"

echo "▶ Applying Gateway, VirtualService, DestinationRules..."
kubectl apply -f "${TMP_DIR}/04-gateway.yaml"
kubectl apply -f "${TMP_DIR}/06-virtual-service.yaml"
kubectl apply -f "${TMP_DIR}/07-destination-rule.yaml"

echo "▶ Applying EnvoyFilter (QUIC/HTTP3)..."
kubectl apply -f "${TMP_DIR}/05-envoyfilter-quic.yaml"

echo "▶ Waiting for backends..."
kubectl rollout status deployment/echo-h2 -n "${NAMESPACE}" --timeout=180s
kubectl rollout status deployment/echo-h1 -n "${NAMESPACE}" --timeout=180s

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Endpoints:"
echo "  https://network-test.${TEST_DOMAIN}/                      → H2 backend (info)"
echo "  https://network-test.${TEST_DOMAIN}/h2/                   → H2 backend"
echo "  https://network-test.${TEST_DOMAIN}/h1/                   → H1.1 backend"
echo "  https://network-test.${TEST_DOMAIN}/health                → health check"
echo "  https://network-test.${TEST_DOMAIN}/throughput/h2?size=N  → H2 throughput"
echo "  https://network-test.${TEST_DOMAIN}/throughput/h1?size=N  → H1.1 throughput"
echo ""
echo "Dashboard: https://dashboard.kyma.cloud.sap/?kubeconfigID=A83C07AB-169C-4CF6-89EC-A9F095B554E2"
