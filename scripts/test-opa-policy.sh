#!/bin/bash
set -e

source "$(dirname "$0")/common.sh"

echo "🧪 OPA Policy Testing"
echo ""

ALICE_TOKEN=$(get_token "alice" "password") || exit 1
BOB_TOKEN=$(get_token "bob" "password") || exit 1

ALICE_ID=$(get_user_id "$ALICE_TOKEN")
BOB_ID=$(get_user_id "$BOB_TOKEN")

echo "✅ Tokens obtained"
echo "Alice (admin): $ALICE_ID"
echo "Bob (user): $BOB_ID"
echo ""

test_opa() {
    local test_name=$1
    local token=$2
    local path=$3
    local method=$4
    local expected=$5
    
    echo -n "  $test_name ... "
    
    # Use new decode_jwt function that strips newlines
    JWT_JSON=$(decode_jwt "$token")
    
    REQUEST=$(jq -n \
        --argjson jwt "$JWT_JSON" \
        --arg path "$path" \
        --arg method "$method" \
        '{
            input: {
                attributes: {
                    request: {
                        http: {
                            path: $path,
                            method: $method
                        }
                    },
                    metadataContext: {
                        filterMetadata: {
                            "envoy.filters.http.jwt_authn": {
                                jwt_payload: $jwt
                            }
                        }
                    }
                }
            }
        }')
    
    RESULT=$(curl -s -X POST "$OPA_URL/v1/data/envoy/authz/allow" \
        -H "Content-Type: application/json" \
        -d "$REQUEST" | jq -r '.result')
    
    if [ "$RESULT" = "$expected" ]; then
        echo "✅ $RESULT"
    else
        echo "❌ Expected $expected, got $RESULT"
    fi
}

POLICY_SET=$(detect_policy_set)
echo "📋 Active Policy: $POLICY_SET"
echo ""

echo "📋 Test 1: RBAC"
test_opa "Alice (admin) → /api/data" "$ALICE_TOKEN" "/api/data" "GET" "true"
test_opa "Bob (user) → /api/data GET" "$BOB_TOKEN" "/api/data" "GET" "true"
test_opa "Bob (user) → /api/data POST" "$BOB_TOKEN" "/api/data" "POST" "false"
test_opa "Bob (user) → /admin/users" "$BOB_TOKEN" "/admin/users" "GET" "false"
echo ""

if [ "$POLICY_SET" != "use-seven" ]; then
    echo "📋 Test 2: ReBAC"
    test_opa "Bob → own profile" "$BOB_TOKEN" "/users/$BOB_ID/profile" "GET" "true"
    test_opa "Bob → Alice's profile" "$BOB_TOKEN" "/users/$ALICE_ID/profile" "GET" "false"
    test_opa "Alice → Bob's profile" "$ALICE_TOKEN" "/users/$BOB_ID/profile" "GET" "true"
    echo ""
fi

echo "✅ OPA policy tests complete!"