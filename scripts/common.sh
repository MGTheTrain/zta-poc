#!/bin/bash

KEYCLOAK_URL="http://localhost:8180"
OPA_URL="http://localhost:8181"

get_token() {
    local username=$1
    local password=$2
    local response=$(curl -s -X POST "$KEYCLOAK_URL/realms/demo/protocol/openid-connect/token" \
      -d "client_id=demo-client" \
      -d "username=$username" \
      -d "password=$password" \
      -d "grant_type=password")
    
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "❌ Failed to get token" >&2
        return 1
    fi
    
    local token=$(echo "$response" | jq -r '.access_token')
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "❌ Failed to get token for $username" >&2
        return 1
    fi
    
    echo "$token"
}

get_user_id() {
    local token=$1
    payload=$(echo $token | cut -d'.' -f2)
    padded=$(printf '%s' "$payload"; rem=$(( ${#payload} % 4 )); [ $rem -ne 0 ] && printf '%*s' $((4 - rem)) '' | tr ' ' '=' )
    echo "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '.sub'
}

decode_jwt() {
    local token=$1
    payload=$(echo $token | cut -d'.' -f2)
    padded=$(printf '%s' "$payload"; rem=$(( ${#payload} % 4 )); [ $rem -ne 0 ] && printf '%*s' $((4 - rem)) '' | tr ' ' '=' )
    echo "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null | tr -d '\n' | jq -c .
}

detect_policy_set() {
    POLICIES=$(curl -s "$OPA_URL/v1/policies" | jq -r '.result[].id' 2>/dev/null || echo "")
    
    if [ -z "$POLICIES" ]; then
        echo "none"
        return
    fi
    
    if echo "$POLICIES" | grep -q "geofencing"; then
        echo "use-seven"
    elif echo "$POLICIES" | grep -q "time_based\|rebac"; then
        echo "use-three"
    else
        echo "use-one"
    fi
}