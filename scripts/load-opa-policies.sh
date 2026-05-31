#!/bin/bash
set -e

POLICY_SET=${1:-rbac}
ENVIRONMENT=${2:-docker} # docker or k8s
OPA_URL="http://localhost:8181"

echo "🔄 Loading OPA policies: $POLICY_SET ($ENVIRONMENT)"

echo "🗑️  Cleaning old policies..."
curl -s -X DELETE "$OPA_URL/v1/policies/policies/authz.rego" 2>/dev/null || true
curl -s -X DELETE "$OPA_URL/v1/policies/authz" 2>/dev/null || true
curl -s -X DELETE "$OPA_URL/v1/policies/rbac" 2>/dev/null || true
curl -s -X DELETE "$OPA_URL/v1/policies/rebac" 2>/dev/null || true
curl -s -X DELETE "$OPA_URL/v1/policies/time_based" 2>/dev/null || true

# Determine policy directory based on environment
if [ "$ENVIRONMENT" = "k8s" ]; then
    POLICY_DIR="policies/opa-k8s"
else
    POLICY_DIR="policies/opa"
fi

# First enumerate all policies and delete every one before pushing the new set
existing=$(curl -s "${OPA_URL}/v1/policies" | jq -r '.result[].id' 2>/dev/null || true)
for id in $existing; do
    curl -sf -X DELETE "${OPA_URL}/v1/policies/${id}" >/dev/null 2>&1 || true
done

case $POLICY_SET in
rbac | use-one)
    echo "📋 Loading RBAC-only policies from $POLICY_DIR/rbac/..."
    curl -s -X PUT "$OPA_URL/v1/policies/authz" \
        --data-binary @$POLICY_DIR/rbac/authz.rego
    echo "✅ RBAC policy loaded"
    ;;

rbac-rebac-time | use-three)
    echo "📋 Loading RBAC + ReBAC + Time policies from $POLICY_DIR/rbac-rebac-time/..."

    curl -s -X PUT "$OPA_URL/v1/policies/authz" \
        --data-binary @$POLICY_DIR/rbac-rebac-time/authz.rego

    for policy in rbac rebac time_based; do
        curl -s -X PUT "$OPA_URL/v1/policies/$policy" \
            --data-binary @$POLICY_DIR/rbac-rebac-time/$policy.rego
    done

    echo "✅ RBAC + ReBAC + Time policies loaded"
    ;;

*)
    echo "❌ Unknown policy set: $POLICY_SET"
    echo "Usage: $0 [rbac|rbac-rebac-time] [docker|k8s]"
    exit 1
    ;;
esac

echo ""
echo "📋 Loaded policies:"
curl -s "$OPA_URL/v1/policies" | jq -r '.result[].id' | sed 's/^/  - /'
