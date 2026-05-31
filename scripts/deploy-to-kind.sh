#!/bin/bash
#
# deploy-to-kind.sh — install the ZTA PoC into a kind cluster.
#
# Pipeline:
#   1. Install Istio (three releases, see ADR for why they stay separate)
#   2. Label default namespace for sidecar injection
#   3. Stage the policy + realm files into the umbrella chart's files/
#   4. `helm upgrade --install zta-poc` — does everything else
#
# Previously this script was ~400 lines of inline kubectl/heredoc YAML.
# Most of that is now declarative in infra/helm-charts/zta-poc/.
#
set -euo pipefail

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Versions
ISTIO_VERSION="1.24.2"
ISTIO_GATEWAY_VERSION="1.28.1"

# Chart paths
UMBRELLA_CHART="./infra/helm-charts/zta-poc"

# Policy set to deploy with initially. Override:
#   POLICY_SET=rbac ./scripts/deploy-to-kind.sh
POLICY_SET="${POLICY_SET:-rbac-rebac-time}"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Deploy ZTA PoC on Kind                                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── 1. Istio ──────────────────────────────────────────────────────────────
echo -e "${YELLOW}🕸️  Installing Istio ${ISTIO_VERSION}...${NC}"

helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install istio-base istio/base \
    -n istio-system --create-namespace \
    --version "${ISTIO_VERSION}" --set defaultRevision=default \
    --wait --timeout 3m >/dev/null

helm upgrade --install istiod istio/istiod \
    -n istio-system --version "${ISTIO_VERSION}" \
    --wait --timeout 3m >/dev/null

kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f - >/dev/null

helm upgrade --install istio-ingressgateway istio/gateway \
    -n istio-ingress --version "${ISTIO_GATEWAY_VERSION}" \
    --wait --timeout 3m >/dev/null

echo -e "${GREEN}✓ Istio installed${NC}"
echo ""

# ─── 2. Namespace injection ─────────────────────────────────────────────────
echo -e "${YELLOW}🏷  Enabling sidecar injection on 'default'...${NC}"
kubectl label namespace default istio-injection=enabled --overwrite >/dev/null
echo -e "${GREEN}✓ Namespace labeled${NC}"
echo ""

# ─── 3. Stage chart files ──────────────────────────────────────────────────
# Helm's Files.Glob only reads inside the chart directory, so we copy the
# policy + realm sources into the chart's files/ before running helm.
# Same pattern rucio-storage-testbed uses.
bash scripts/stage-chart-files.sh
echo ""

# ─── 4. Helm install the umbrella ──────────────────────────────────────────
echo -e "${YELLOW}⎈ Installing zta-poc umbrella chart...${NC}"
echo -e "${BLUE}  Policy set: ${POLICY_SET}${NC}"

helm dependency update "${UMBRELLA_CHART}" >/dev/null

helm upgrade --install zta-poc "${UMBRELLA_CHART}" \
    --namespace default \
    --set "zta-platform.opa.policySet=${POLICY_SET}" \
    --wait --timeout 5m

echo -e "${GREEN}✓ zta-poc deployed${NC}"
echo ""

# ─── Summary ───────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Deployment Complete                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Releases:${NC}"
helm list -n istio-system 2>/dev/null | tail -n +2 || true
helm list -n istio-ingress 2>/dev/null | tail -n +2 || true
helm list -n default 2>/dev/null | tail -n +2 || true
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Port-forward:         make k8s-forward"
echo "  2. Switch policy set:    make k8s-use-one  (or k8s-use-three)"
echo "  3. Run tests:            make k8s-test"
echo ""
