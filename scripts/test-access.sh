#!/bin/bash
set -e

KEYCLOAK_URL="http://localhost:8180"
GO_SERVICE="http://localhost:9001"
PYTHON_SERVICE="http://localhost:9002"
CSHARP_SERVICE="http://localhost:9003"

get_token() {
    local username=$1
    local password=$2
    curl -s -X POST "$KEYCLOAK_URL/realms/demo/protocol/openid-connect/token" \
      -d "client_id=demo-client" \
      -d "username=$username" \
      -d "password=$password" \
      -d "grant_type=password" | jq -r '.access_token'
}

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
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" == "$expected" ]; then
        echo "✅ $http_code"
    else
        echo "❌ Expected $expected, got $http_code"
        echo "   Response: $body"
    fi
}

case ${1:-admin} in
    admin)
        echo "🧪 Testing ADMIN user (alice)"
        echo "Getting token..."
        ADMIN_TOKEN=$(get_token "alice" "password")
        
        if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
            echo "❌ Failed to get admin token. Run 'make setup-keycloak' first."
            exit 1
        fi
        
        echo ""
        echo "📋 Go Service:"
        test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/api/data" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/admin/users" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$GO_SERVICE/api/data" "POST" "200"
        
        echo ""
        echo "📋 Python Service:"
        test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/api/data" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$PYTHON_SERVICE/admin/users" "GET" "200"
        
        echo ""
        echo "📋 C# Service:"
        test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/api/data" "GET" "200"
        test_endpoint "$ADMIN_TOKEN" "$CSHARP_SERVICE/admin/users" "GET" "200"
        ;;
        
    user)
        echo "🧪 Testing REGULAR USER (bob)"
        echo "Getting token..."
        USER_TOKEN=$(get_token "bob" "password")
        
        if [ -z "$USER_TOKEN" ] || [ "$USER_TOKEN" == "null" ]; then
            echo "❌ Failed to get user token. Run 'make setup-keycloak' first."
            exit 1
        fi
        
        echo ""
        echo "📋 Should ALLOW (GET requests):"
        test_endpoint "$USER_TOKEN" "$GO_SERVICE/" "GET" "200"
        test_endpoint "$USER_TOKEN" "$GO_SERVICE/api/data" "GET" "200"
        
        echo ""
        echo "📋 Should DENY (POST/PUT/DELETE and admin endpoints):"
        test_endpoint "$USER_TOKEN" "$GO_SERVICE/api/data" "POST" "403"
        test_endpoint "$USER_TOKEN" "$GO_SERVICE/admin/users" "GET" "403"
        test_endpoint "$USER_TOKEN" "$PYTHON_SERVICE/admin/users" "GET" "403"
        ;;
        
    denied)
        echo "🧪 Testing ACCESS DENIAL scenarios"
        
        echo ""
        echo "📋 Should DENY (no token):"
        test_endpoint "" "$GO_SERVICE/" "GET" "401"
        test_endpoint "" "$PYTHON_SERVICE/api/data" "GET" "401"
        
        echo ""
        echo "📋 Should ALLOW (health endpoint without token):"
        test_endpoint "" "$GO_SERVICE/health" "GET" "200"
        test_endpoint "" "$PYTHON_SERVICE/health" "GET" "200"
        ;;
esac

echo ""
echo "✅ Tests complete!"