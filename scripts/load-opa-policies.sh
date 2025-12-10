#!/bin/bash
set -e

POLICY_SET=${1:-rbac}
OPA_URL="http://localhost:8181"

echo "🔄 Loading OPA policies: $POLICY_SET"

case $POLICY_SET in
    rbac|use-one)
        echo "📋 Loading RBAC-only policies..."
        curl -s -X PUT "$OPA_URL/v1/policies/authz" \
            --data-binary @opa/rbac/authz.rego
        echo "✅ RBAC policy loaded"
        ;;
        
    rbac-rebac-time|use-three)
        echo "📋 Loading RBAC + ReBAC + Time policies..."
        
        # Upload orchestrator
        curl -s -X PUT "$OPA_URL/v1/policies/authz" \
            --data-binary @opa/rbac-rebac-time/authz.rego
        
        # Upload sub-policies
        for policy in rbac rebac time_based; do
            curl -s -X PUT "$OPA_URL/v1/policies/$policy" \
                --data-binary @opa/rbac-rebac-time/$policy.rego
        done
        
        echo "✅ RBAC + ReBAC + Time policies loaded"
        ;;
        
    advanced|use-seven)
        echo "📋 Loading full ABAC policies..."
        
        curl -s -X PUT "$OPA_URL/v1/policies/authz" \
            --data-binary @opa/advanced/authz.rego
        
        for policy in rbac rebac time_based ip_allowlist mfa rate_limit geofencing; do
            curl -s -X PUT "$OPA_URL/v1/policies/$policy" \
                --data-binary @opa/advanced/$policy.rego
        done
        
        echo "✅ Full ABAC policies loaded"
        ;;
        
    *)
        echo "❌ Unknown policy set: $POLICY_SET"
        echo "Usage: $0 [rbac|rbac-rebac-time|advanced]"
        exit 1
        ;;
esac

echo ""
echo "📋 Loaded policies:"
curl -s "$OPA_URL/v1/policies" | jq -r '.result[].id' | sed 's/^/  - /'