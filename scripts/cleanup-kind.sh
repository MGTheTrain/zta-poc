#!/bin/bash
set -e

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Kind Cluster Cleanup Script                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Uninstall Service Helm releases
echo -e "${YELLOW}1. Uninstalling service Helm releases...${NC}"
SERVICE_RELEASES=(
    "python-service"
    "go-service"
    "csharp-service"
)

for release in "${SERVICE_RELEASES[@]}"; do
    if helm list -q | grep -q "^${release}$"; then
        echo -e "${BLUE}  Uninstalling ${release}...${NC}"
        helm uninstall "${release}" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ Service releases uninstalled${NC}"
echo ""

# 2. Uninstall Infrastructure Helm releases
echo -e "${YELLOW}2. Uninstalling infrastructure Helm releases...${NC}"

# Uninstall Istio components (in reverse order of installation)
if helm list -n istio-ingress -q | grep -q "^istio-ingressgateway$"; then
    echo -e "${BLUE}  Uninstalling Istio Ingress Gateway...${NC}"
    helm uninstall istio-ingressgateway -n istio-ingress 2>/dev/null || true
fi

if helm list -n istio-system -q | grep -q "^istiod$"; then
    echo -e "${BLUE}  Uninstalling Istiod...${NC}"
    helm uninstall istiod -n istio-system 2>/dev/null || true
fi

if helm list -n istio-system -q | grep -q "^istio-base$"; then
    echo -e "${BLUE}  Uninstalling Istio base...${NC}"
    helm uninstall istio-base -n istio-system 2>/dev/null || true
fi

echo -e "${GREEN}✓ Infrastructure releases uninstalled${NC}"
echo ""

# 3. Clean up OPA resources
echo -e "${YELLOW}3. Cleaning up OPA resources...${NC}"
kubectl delete deployment opa -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete service opa -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete configmap opa-policy -n default --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ OPA resources cleaned${NC}"
echo ""

# 4. Clean up Keycloak resources
echo -e "${YELLOW}4. Cleaning up Keycloak resources...${NC}"
kubectl delete deployment keycloak -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete service keycloak -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete configmap keycloak-realm-config -n default --ignore-not-found=true 2>/dev/null || true
echo -e "${GREEN}✓ Keycloak resources cleaned${NC}"
echo ""

# 5. Clean up Istio resources
echo -e "${YELLOW}5. Cleaning up Istio resources...${NC}"

# Delete VirtualServices
echo -e "${BLUE}  Deleting VirtualServices...${NC}"
kubectl delete virtualservice go-service -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete virtualservice python-service -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete virtualservice csharp-service -n default --ignore-not-found=true 2>/dev/null || true

# Delete shared Gateway
kubectl delete gateway zta-gateway -n default --ignore-not-found=true 2>/dev/null || true

# Delete AuthorizationPolicies
kubectl delete authorizationpolicy delegate-to-opa -n default --ignore-not-found=true 2>/dev/null || true

# Delete RequestAuthentication
kubectl delete requestauthentication jwt-auth -n default --ignore-not-found=true 2>/dev/null || true

# Delete EnvoyFilters
kubectl delete envoyfilter opa-ext-authz -n istio-system --ignore-not-found=true 2>/dev/null || true

# Delete Istio CRDs (optional - comment out if you want to keep CRDs)
echo -e "${BLUE}  Deleting other Istio custom resources...${NC}"
kubectl delete destinationrules.networking.istio.io --all --all-namespaces --ignore-not-found=true 2>/dev/null || true
kubectl delete peerauthentications.security.istio.io --all --all-namespaces --ignore-not-found=true 2>/dev/null || true
kubectl delete authorizationpolicies.security.istio.io --all --all-namespaces --ignore-not-found=true 2>/dev/null || true

# Delete Istio namespaces
echo -e "${BLUE}  Deleting Istio namespaces...${NC}"
kubectl delete namespace istio-ingress --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace istio-system --ignore-not-found=true 2>/dev/null || true

# Remove Istio injection label
kubectl label namespace default istio-injection- --ignore-not-found=true 2>/dev/null || true

# Delete ServiceEntry
kubectl delete serviceentry opa-ext-authz-grpc -n default --ignore-not-found=true 2>/dev/null || true

# Delete EnvoyFilters (both locations)
kubectl delete envoyfilter opa-ext-authz -n istio-system --ignore-not-found=true 2>/dev/null || true
kubectl delete envoyfilter opa-ext-authz -n default --ignore-not-found=true 2>/dev/null || true

echo -e "${GREEN}✓ Istio resources cleaned${NC}"
echo ""

# 6. Delete all completed test pods
echo -e "${YELLOW}6. Cleaning up completed test pods...${NC}"
COMPLETED_PODS=$(kubectl get pods --field-selector=status.phase==Succeeded -o name 2>/dev/null || echo "")
if [ -n "$COMPLETED_PODS" ]; then
    COMPLETED_COUNT=$(echo "$COMPLETED_PODS" | wc -l)
    echo -e "${BLUE}  Deleting ${COMPLETED_COUNT} completed pods...${NC}"
    kubectl delete pod --field-selector=status.phase==Succeeded --ignore-not-found=true 2>/dev/null || true
    echo -e "${GREEN}✓ Completed pods deleted${NC}"
else
    echo -e "${GREEN}✓ No completed pods to clean${NC}"
fi
echo ""

# 7. Delete failed pods
echo -e "${YELLOW}7. Cleaning up failed pods...${NC}"
FAILED_PODS=$(kubectl get pods --field-selector=status.phase==Failed -o name 2>/dev/null || echo "")
if [ -n "$FAILED_PODS" ]; then
    FAILED_COUNT=$(echo "$FAILED_PODS" | wc -l)
    echo -e "${BLUE}  Deleting ${FAILED_COUNT} failed pods...${NC}"
    kubectl delete pod --field-selector=status.phase==Failed --ignore-not-found=true 2>/dev/null || true
    echo -e "${GREEN}✓ Failed pods deleted${NC}"
else
    echo -e "${GREEN}✓ No failed pods to clean${NC}"
fi
echo ""

# 8. Optional: Delete Istio CRDs completely
echo -e "${YELLOW}8. Checking for Istio CRDs...${NC}"
ISTIO_CRDS=$(kubectl get crd -o name 2>/dev/null | grep 'istio.io' || echo "")
if [ -n "$ISTIO_CRDS" ]; then
    echo -e "${YELLOW}  Found Istio CRDs (not deleting by default):${NC}"
    kubectl get crd | grep 'istio.io' 2>/dev/null || true
    echo -e "${YELLOW}  To delete CRDs, run: kubectl delete crd -l app=istio${NC}"
else
    echo -e "${GREEN}✓ No Istio CRDs found${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                      Cleanup Summary                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Current cluster state:${NC}"
echo ""
echo -e "${YELLOW}Pods in default namespace:${NC}"
kubectl get pods -n default 2>/dev/null || echo "None"
echo ""
echo -e "${YELLOW}Pods in istio-system:${NC}"
kubectl get pods -n istio-system 2>/dev/null || echo "None"
echo ""
echo -e "${YELLOW}Pods in istio-ingress:${NC}"
kubectl get pods -n istio-ingress 2>/dev/null || echo "None"
echo ""
echo -e "${YELLOW}Services:${NC}"
kubectl get svc -A 2>/dev/null || echo "None"
echo ""
echo -e "${YELLOW}Helm releases:${NC}"
echo "Default namespace:"
helm list 2>/dev/null || echo "None"
echo ""
echo "Istio-system namespace:"
helm list -n istio-system 2>/dev/null || echo "None"
echo ""
echo "Istio-ingress namespace:"
helm list -n istio-ingress 2>/dev/null || echo "None"
echo ""

echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  Deploy everything:  make k8s-deploy"
echo "  Port-forward:       make k8s-forward"
echo ""