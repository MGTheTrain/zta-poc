#!/bin/bash
set -e

source "$(dirname "$0")/common.sh"

GO_SERVICE="http://localhost:9001"
PYTHON_SERVICE="http://localhost:9002"
CSHARP_SERVICE="http://localhost:9003"

test_endpoint() {
    local token=$1
    local url=$2
    local method=${3:-GET}
    local expected=$4
    
    echo -n "  Testing $method $url ... "
    
    if [ -z "$token" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method "$url")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method -H "Authorization: Bearer $token" "$url")
    fi
    
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" == "$expected" ]; then
        echo "✅ $http_code"
    else
        echo "❌ Expected $expected, got $http_code"
    fi
}

test_admin() {
    echo "🧪 Test: Admin Access"
    ADMIN_TOKEN=$(get_token "alice" "password") || exit 1
    
    test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/api/data" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/admin/users" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/api/data" "POST" "200"

    test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/api/data" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/admin/users" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/api/data" "POST" "200"

    test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/api/data" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/admin/users" "GET" "200"
    test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/api/data" "POST" "200"
}

test_user() {
    echo "🧪 Test: User Access (GET only)"
    USER_TOKEN=$(get_token "bob" "password") || exit 1
    
    test_endpoint "$USER_TOKEN" "$GO_SERVICE/" "GET" "200"
    test_endpoint "$USER_TOKEN" "$GO_SERVICE/api/data" "GET" "200"
    test_endpoint "$USER_TOKEN" "$GO_SERVICE/api/data" "POST" "403"
    test_endpoint "$USER_TOKEN" "$GO_SERVICE/admin/users" "GET" "403"

    test_endpoint "$USER_TOKEN" "$PYTHON_SERVICE/" "GET" "200"
    test_endpoint "$USER_TOKEN" "$PYTHON_SERVICE/api/data" "GET" "200"
    test_endpoint "$USER_TOKEN" "$PYTHON_SERVICE/api/data" "POST" "403"
    test_endpoint "$USER_TOKEN" "$PYTHON_SERVICE/admin/users" "GET" "403"

    test_endpoint "$USER_TOKEN" "$CSHARP_SERVICE/" "GET" "200"
    test_endpoint "$USER_TOKEN" "$CSHARP_SERVICE/api/data" "GET" "200"
    test_endpoint "$USER_TOKEN" "$CSHARP_SERVICE/api/data" "POST" "403"
    test_endpoint "$USER_TOKEN" "$CSHARP_SERVICE/admin/users" "GET" "403"
}

test_rebac() {
    echo "🧪 Test: Resource-Based Access (ReBAC)"
    ALICE_TOKEN=$(get_token "alice" "password") || exit 1
    BOB_TOKEN=$(get_token "bob" "password") || exit 1
    
    ALICE_ID=$(get_user_id "$ALICE_TOKEN")
    BOB_ID=$(get_user_id "$BOB_TOKEN")
    
    test_endpoint "$BOB_TOKEN" "$GO_SERVICE/users/$BOB_ID/profile" "GET" "200"
    test_endpoint "$BOB_TOKEN" "$GO_SERVICE/users/$ALICE_ID/profile" "GET" "403"
    test_endpoint "$ALICE_TOKEN" "$GO_SERVICE/users/$BOB_ID/profile" "GET" "200"

    test_endpoint "$BOB_TOKEN" "$PYTHON_SERVICE/users/$BOB_ID/profile" "GET" "200"
    test_endpoint "$BOB_TOKEN" "$PYTHON_SERVICE/users/$ALICE_ID/profile" "GET" "403"
    test_endpoint "$ALICE_TOKEN" "$PYTHON_SERVICE/users/$BOB_ID/profile" "GET" "200"

    test_endpoint "$BOB_TOKEN" "$CSHARP_SERVICE/users/$BOB_ID/profile" "GET" "200"
    test_endpoint "$BOB_TOKEN" "$CSHARP_SERVICE/users/$ALICE_ID/profile" "GET" "403"
    test_endpoint "$ALICE_TOKEN" "$CSHARP_SERVICE/users/$BOB_ID/profile" "GET" "200"
}

test_denied() {
    echo "🧪 Test: Access Denial"
    test_endpoint "" "$GO_SERVICE/" "GET" "401"
    test_endpoint "" "$GO_SERVICE/api/data" "GET" "401"
    test_endpoint "" "$GO_SERVICE/health" "GET" "200"

    test_endpoint "" "$PYTHON_SERVICE/" "GET" "401"
    test_endpoint "" "$PYTHON_SERVICE/api/data" "GET" "401"
    test_endpoint "" "$PYTHON_SERVICE/health" "GET" "200"

    test_endpoint "" "$CSHARP_SERVICE/" "GET" "401"
    test_endpoint "" "$CSHARP_SERVICE/api/data" "GET" "401"
    test_endpoint "" "$CSHARP_SERVICE/health" "GET" "200"
}

# Main execution
echo "🔍 Detecting active policy set..."
POLICY_SET=$(detect_policy_set)

case $POLICY_SET in
    none)
        echo "❌ No policies loaded in OPA"
        echo "💡 Run 'make use-one' first"
        exit 1
        ;;
    use-one)
        echo "✅ Detected: RBAC only"
        echo ""
        test_admin
        echo ""
        test_user
        echo ""
        test_denied
        ;;
    use-three)
        echo "✅ Detected: RBAC + ReBAC + Time"
        echo ""
        test_admin
        echo ""
        test_user
        echo ""
        test_rebac
        echo ""
        test_denied
        ;;
    use-seven)
        echo "✅ Detected: Full ABAC"
        echo ""
        test_admin
        echo ""
        test_user
        echo ""
        test_denied
        ;;
esac

echo ""
echo "✅ All tests complete!"