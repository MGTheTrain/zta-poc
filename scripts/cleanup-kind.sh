#!/bin/bash
#
# cleanup-kind.sh — tear down the ZTA PoC from a kind cluster.
#
# Most resources are now owned by the zta-poc umbrella release, so a single
# `helm uninstall` cleans them up. The script still removes Istio
# separately (kept out of the umbrella by design — see ADR) and scrubs the
# istio-injection label and Istio namespaces.
#
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Cleanup ZTA PoC on Kind                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── 1. Umbrella release ────────────────────────────────────────────────────
echo -e "${YELLOW}1. Uninstalling zta-poc umbrella release...${NC}"
if helm list -n default -q | grep -q "^zta-poc$"; then
    helm uninstall zta-poc -n default 2>/dev/null || true
    echo -e "${GREEN}✓ zta-poc uninstalled${NC}"
else
    echo -e "${BLUE}  zta-poc not installed, skipping${NC}"
fi
echo ""

# ─── 2. Istio releases ──────────────────────────────────────────────────────
echo -e "${YELLOW}2. Uninstalling Istio releases...${NC}"

for entry in \
    "istio-ingressgateway:istio-ingress" \
    "istiod:istio-system" \
    "istio-base:istio-system"; do
    release="${entry%%:*}"
    ns="${entry##*:}"
    if helm list -n "${ns}" -q 2>/dev/null | grep -q "^${release}$"; then
        echo -e "${BLUE}  Uninstalling ${release} (${ns})...${NC}"
        helm uninstall "${release}" -n "${ns}" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ Istio releases uninstalled${NC}"
echo ""

# ─── 3. Stragglers ──────────────────────────────────────────────────────────
echo -e "${YELLOW}3. Removing istio-injection label and Istio namespaces...${NC}"
kubectl label namespace default istio-injection- 2>/dev/null || true
kubectl delete namespace istio-ingress --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace istio-system --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ Namespaces removed${NC}"
echo ""

# ─── 4. Completed / failed pods ─────────────────────────────────────────────
echo -e "${YELLOW}4. Cleaning up completed/failed pods...${NC}"
kubectl delete pod --field-selector=status.phase==Succeeded \
    --all-namespaces --ignore-not-found=true 2>/dev/null || true
kubectl delete pod --field-selector=status.phase==Failed \
    --all-namespaces --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ Terminal pods removed${NC}"
echo ""

# ─── 5. Istio CRDs (informational only) ─────────────────────────────────────
ISTIO_CRDS=$(kubectl get crd -o name 2>/dev/null | grep 'istio.io' || true)
if [ -n "${ISTIO_CRDS}" ]; then
    echo -e "${YELLOW}Note: Istio CRDs still present.${NC}"
    echo "  Delete with: kubectl get crd -o name | grep istio.io | xargs kubectl delete"
fi
echo ""

# ─── Summary ────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                       Cleanup Complete                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Default namespace:${NC}"
kubectl get pods -n default 2>/dev/null || echo "  (empty)"
echo ""
echo -e "${YELLOW}Next:${NC}"
echo "  Redeploy:  make k8s-deploy"