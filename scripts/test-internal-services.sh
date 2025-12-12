#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/common.sh"

# Parse environment
ENV=${1:-docker}

if [[ "$ENV" != "docker" && "$ENV" != "k8s" ]]; then
    echo "❌ Invalid environment: $ENV"
    echo "Usage: $0 [docker|k8s]"
    exit 1
fi

# Set service URLs
if [[ "$ENV" == "k8s" ]]; then
    GO_SERVICE="http://localhost:8080"
    PYTHON_SERVICE="http://localhost:8080"
    CSHARP_SERVICE="http://localhost:8080"

    GO_HOST="go-service.local"
    PYTHON_HOST="python-service.local"
    CSHARP_HOST="csharp-service.local"
else
    GO_SERVICE="http://localhost:9001"
    PYTHON_SERVICE="http://localhost:9002"
    CSHARP_SERVICE="http://localhost:9003"

    GO_HOST=""
    PYTHON_HOST=""
    CSHARP_HOST=""
fi

export GO_SERVICE PYTHON_SERVICE CSHARP_SERVICE
export GO_HOST PYTHON_HOST CSHARP_HOST

echo "🔍 Testing environment: $ENV"
echo ""

test_endpoint() {
    local token="$1"
    local service="$2"
    local path="$3"
    local method="${4:-GET}"
    local expected="$5"

    local url=""
    local -a host_header
    host_header=()

    case "$service" in
        go)
            url="${GO_SERVICE}${path}"
            [[ -n "$GO_HOST" ]] && host_header+=(-H "Host: $GO_HOST")
            ;;
        python)
            url="${PYTHON_SERVICE}${path}"
            [[ -n "$PYTHON_HOST" ]] && host_header+=(-H "Host: $PYTHON_HOST")
            ;;
        csharp)
            url="${CSHARP_SERVICE}${path}"
            [[ -n "$CSHARP_HOST" ]] && host_header+=(-H "Host: $CSHARP_HOST")
            ;;
        *)
            echo "Unknown service: $service"
            return 1
            ;;
    esac

    echo -n "  Testing $method ${service}${path} … "

    local response=""
    if [[ -z "$token" ]]; then
        response=$(curl -sS -w "\n%{http_code}" -X "$method" ${host_header[@]+"${host_header[@]}"} "$url")
    else
        response=$(curl -sS -w "\n%{http_code}" -X "$method" ${host_header[@]+"${host_header[@]}"} \
            -H "Authorization: Bearer $token" "$url")
    fi

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [[ "$http_code" == "$expected" ]]; then
        echo "✅ $http_code"
    else
        echo "❌ Expected $expected, got $http_code"
    fi
}

test_admin() {
    echo "🧪 Test: Admin Access"
    ADMIN_TOKEN=$(get_token "alice" "password") || exit 1

    for svc in go python csharp; do
        test_endpoint "$ADMIN_TOKEN" "$svc" "/" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$svc" "/api/data" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$svc" "/admin/users" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$svc" "/api/data" "POST" "200"
    done
}

test_user() {
    echo "🧪 Test: User Access (GET only)"
    USER_TOKEN=$(get_token "bob" "password") || exit 1

    for svc in go python csharp; do
        test_endpoint "$USER_TOKEN" "$svc" "/" "GET" "200"
        test_endpoint "$USER_TOKEN" "$svc" "/api/data" "GET" "200"
        test_endpoint "$USER_TOKEN" "$svc" "/api/data" "POST" "403"
        test_endpoint "$USER_TOKEN" "$svc" "/admin/users" "GET" "403"
    done
}

test_rebac() {
    echo "🧪 Test: Resource-Based Access (ReBAC)"

    ALICE_TOKEN=$(get_token "alice" "password") || exit 1
    BOB_TOKEN=$(get_token "bob" "password") || exit 1

    ALICE_ID=$(get_user_id "$ALICE_TOKEN")
    BOB_ID=$(get_user_id "$BOB_TOKEN")

    for svc in go python csharp; do
        test_endpoint "$BOB_TOKEN" "$svc" "/users/$BOB_ID/profile" "GET" "200"
        test_endpoint "$BOB_TOKEN" "$svc" "/users/$ALICE_ID/profile" "GET" "403"
        test_endpoint "$ALICE_TOKEN" "$svc" "/users/$BOB_ID/profile" "GET" "200"
    done
}

test_denied() {
    echo "🧪 Test: Access Denial"

    for svc in go python csharp; do
        test_endpoint "" "$svc" "/" "GET" "401"
        test_endpoint "" "$svc" "/api/data" "GET" "401"
        test_endpoint "" "$svc" "/health" "GET" "200"
    done
}

echo "🔍 Detecting active policy set..."
POLICY_SET=$(detect_policy_set)

case "$POLICY_SET" in
    none)
        echo "❌ No policies loaded in OPA"
        echo "💡 Run 'make use-one' first"
        exit 1
        ;;
    use-one)
        echo "✅ RBAC only"
        test_admin
        test_user
        test_denied
        ;;
    use-three)
        echo "✅ RBAC + ReBAC + Time"
        test_admin
        test_user
        test_rebac
        test_denied
        ;;
    use-seven)
        echo "✅ Full ABAC"
        test_admin
        test_user
        test_denied
        ;;
    *)
        echo "❌ Unknown policy set: $POLICY_SET"
        exit 1
        ;;
esac

echo ""
echo "✅ All tests complete ($ENV)!"
