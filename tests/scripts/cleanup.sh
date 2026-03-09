#!/usr/bin/env bash
# cleanup.sh - Remove all network test resources from Kyma cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="network-test"

echo "=== Kyma Network Test Cleanup ==="
echo "Removing resources from namespace: ${NAMESPACE}"
echo ""

echo "▶ Deleting EnvoyFilter (QUIC)..."
kubectl delete -f "${ROOT_DIR}/k8s/gateway/05-envoyfilter-quic.yaml" \
  --ignore-not-found=true

echo "▶ Deleting DestinationRules..."
kubectl delete -f "${ROOT_DIR}/k8s/gateway/07-destination-rule.yaml" \
  --ignore-not-found=true

echo "▶ Deleting VirtualService..."
kubectl delete -f "${ROOT_DIR}/k8s/gateway/06-virtual-service.yaml" \
  --ignore-not-found=true

echo "▶ Deleting Gateway..."
kubectl delete -f "${ROOT_DIR}/k8s/gateway/04-gateway.yaml" \
  --ignore-not-found=true

echo "▶ Deleting backend deployments..."
kubectl delete -f "${ROOT_DIR}/k8s/backend/01-h2-backend.yaml" \
  --ignore-not-found=true
kubectl delete -f "${ROOT_DIR}/k8s/backend/02-h1-backend.yaml" \
  --ignore-not-found=true

echo "▶ Deleting namespace ${NAMESPACE}..."
kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true

echo ""
echo "=== Cleanup complete ==="
