#!/bin/bash
set -e

# Parse arguments
FORWARD_IAM=false
FORWARD_OPA=false
FORWARD_SVC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --iam)
            FORWARD_IAM=true
            shift
            ;;
        --opa)
            FORWARD_OPA=true
            shift
            ;;
        --svc|--services)
            FORWARD_SVC=true
            shift
            ;;
        --all)
            FORWARD_IAM=true
            FORWARD_OPA=true
            FORWARD_SVC=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--iam] [--opa] [--svc|--services] [--all]"
            exit 1
            ;;
    esac
done

# Default to all if nothing specified
if [ "$FORWARD_IAM" = false ] && [ "$FORWARD_OPA" = false ] && [ "$FORWARD_SVC" = false ]; then
    FORWARD_IAM=true
    FORWARD_OPA=true
    FORWARD_SVC=true
fi

# Trap to cleanup all background jobs on exit
cleanup() {
    echo ""
    echo "Stopping all port-forwards..."
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

echo "Starting port-forwards for ZTA PoC..."
echo ""

# Keycloak
if [ "$FORWARD_IAM" = true ]; then
    echo "Identity & Access Management:"
    echo "  Keycloak: http://localhost:8180 (admin/admin)"
    echo ""
    kubectl port-forward -n default svc/keycloak 8180:8080 &
fi

# OPA
if [ "$FORWARD_OPA" = true ]; then
    echo "Policy Engine:"
    echo "  OPA API:  http://localhost:8181"
    echo ""
    kubectl port-forward -n default svc/opa 8181:8181 &
fi

# Services via Istio Gateway
if [ "$FORWARD_SVC" = true ]; then
    echo "Services (via Istio Gateway):"
    echo "  Gateway:        http://localhost:8080"
    echo "  Go Service:     curl -H 'Host: go-service.local' http://localhost:8080/api/data"
    echo "  Python Service: curl -H 'Host: python-service.local' http://localhost:8080/api/data"
    echo "  C# Service:     curl -H 'Host: csharp-service.local' http://localhost:8080/api/data"
    echo ""
    
    kubectl port-forward -n istio-ingress svc/istio-ingressgateway 8080:80 &
fi

echo "Press Ctrl+C to stop all port-forwards"
echo ""

# Wait for all background jobs
wait