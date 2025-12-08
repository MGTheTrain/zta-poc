#!/bin/bash
set -e

KEYCLOAK_URL="http://localhost:8180"
ADMIN_USER="admin"
ADMIN_PASS="admin"
REALM="demo"

echo "Waiting for Keycloak to be ready..."
until curl -sf "$KEYCLOAK_URL/health/ready" > /dev/null; do
    sleep 2
done

echo "Keycloak is ready!"

# Get admin token
echo "Getting admin token..."
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "Failed to get admin token"
    exit 1
fi

# Create demo realm
echo "Creating demo realm..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "'$REALM'",
    "enabled": true,
    "registrationAllowed": false,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true
  }' || echo "Realm might already exist"

# Create a client with direct access grants enabled
echo "Creating demo-client..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "demo-client",
    "name": "Demo Client",
    "description": "Client for direct access grants (password flow)",
    "enabled": true,
    "publicClient": true,
    "directAccessGrantsEnabled": true,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "serviceAccountsEnabled": false,
    "authorizationServicesEnabled": false,
    "redirectUris": ["*"],
    "webOrigins": ["*"],
    "protocol": "openid-connect"
  }' || echo "Client might already exist"

# Create roles
echo "Creating roles..."
for ROLE in admin user service; do
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/roles" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$ROLE\", \"description\": \"$ROLE role\"}" || echo "Role $ROLE might already exist"
done

# Create admin user (alice)
echo "Creating admin user (alice)..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "email": "alice@example.com",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{
      "type": "password",
      "value": "password",
      "temporary": false
    }]
  }' || echo "User alice might already exist"

# Get Alice's ID and assign admin role
echo "Assigning admin role to alice..."
ALICE_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/$REALM/users?username=alice" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')

if [ ! -z "$ALICE_ID" ] && [ "$ALICE_ID" != "null" ]; then
    ADMIN_ROLE=$(curl -s "$KEYCLOAK_URL/admin/realms/$REALM/roles/admin" \
        -H "Authorization: Bearer $TOKEN")
    
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users/$ALICE_ID/role-mappings/realm" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "[$ADMIN_ROLE]"
fi

# Create regular user (bob)
echo "Creating regular user (bob)..."
curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "bob",
    "email": "bob@example.com",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{
      "type": "password",
      "value": "password",
      "temporary": false
    }]
  }' || echo "User bob might already exist"

# Get Bob's ID and assign user role
echo "Assigning user role to bob..."
BOB_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/$REALM/users?username=bob" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')

if [ ! -z "$BOB_ID" ] && [ "$BOB_ID" != "null" ]; then
    USER_ROLE=$(curl -s "$KEYCLOAK_URL/admin/realms/$REALM/roles/user" \
        -H "Authorization: Bearer $TOKEN")
    
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users/$BOB_ID/role-mappings/realm" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "[$USER_ROLE]"
fi

echo ""
echo "  Keycloak configuration complete!"
echo ""
echo "  Configuration:"
echo "  Realm: $REALM"
echo "  Client ID: demo-client (with direct access grants enabled)"
echo ""
echo "  Users created:"
echo "  Admin user: alice / password (role: admin)"
echo "  Regular user: bob / password (role: user)"
echo ""
echo "  Test getting tokens:"
echo '  Admin:  curl -s -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token -d "client_id=demo-client" -d "username=alice" -d "password=password" -d "grant_type=password" | jq -r ".access_token"'
echo '  User:   curl -s -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token -d "client_id=demo-client" -d "username=bob" -d "password=password" -d "grant_type=password" | jq -r ".access_token"'
echo ""
echo " Keycloak Admin Console: http://localhost:8180/admin (admin/admin)"