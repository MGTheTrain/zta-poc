## ABAC Examples

**RBAC (Role-Based):**
```rego
jwt_payload.realm_access.roles[_] == "admin"  # ✅ Pure RBAC
```

**ABAC (Attribute-Based):**
```rego
# Combines role + HTTP method attribute
jwt_payload.realm_access.roles[_] == "user"
http_request.method == "GET"  # ← Attribute check

# Combines role + path attribute
not startswith(http_request.path, "/admin")  # ← Attribute check
```

---

## Can Envoy + OPA Do Full ABAC? **YES!** 🎯

Envoy forwards **tons of attributes** to OPA beyond just JWT claims. You have access to:

### 1. **Request Attributes**
```rego
# HTTP method, path, headers
http_request.method
http_request.path
http_request.headers["user-agent"]
http_request.headers["x-forwarded-for"]
http_request.body  # Request body (if enabled)

# Query parameters
input.parsed_query.page
input.parsed_query.limit
```

### 2. **JWT Claims (Identity Attributes)**
```rego
jwt_payload.sub                    # User ID
jwt_payload.email
jwt_payload.preferred_username
jwt_payload.realm_access.roles     # Roles
jwt_payload.custom_claims.department
jwt_payload.custom_claims.clearance_level
```

### 3. **Network Attributes**
```rego
input.attributes.source.address.socketAddress.address  # Client IP
input.attributes.destination.address.socketAddress.portValue
```

### 4. **Time-Based Attributes**
```rego
input.attributes.request.time  # Request timestamp
```

### 5. **External Data Sources**
OPA can fetch data from external APIs:
```rego
allow {
    # Query external service for user's current location
    response := http.send({
        "method": "GET",
        "url": "http://user-service/api/users/location",
        "headers": {"Authorization": input.request.http.headers.authorization}
    })
    response.body.country == "US"
}
```

---

## Advanced ABAC Examples

### **Example 1: Time-Based Access**
```rego
# Only allow access during business hours
allow {
    jwt_payload.realm_access.roles[_] == "user"
    time.now_ns() > time.parse_rfc3339_ns("2025-12-09T09:00:00Z")
    time.now_ns() < time.parse_rfc3339_ns("2025-12-09T17:00:00Z")
}
```

### **Example 2: IP Allowlist**
```rego
# Only allow from corporate IPs
allow {
    jwt_payload.realm_access.roles[_] == "admin"
    client_ip := input.attributes.source.address.socketAddress.address
    net.cidr_contains("10.0.0.0/8", client_ip)
}
```

### **Example 3: Resource-Based (ReBAC)**
```rego
# Users can only access their own resources
allow {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    # Extract resource ID from path: /users/123/profile
    path_parts := split(http_request.path, "/")
    path_parts[2] == jwt_payload.sub  # User ID must match
}
```

### **Example 4: Custom JWT Claims**
Add custom claims in Keycloak (user mappers), then:
```rego
# Only allow users from engineering department
allow {
    jwt_payload.realm_access.roles[_] == "user"
    jwt_payload.department == "engineering"
}

# Clearance-based access
allow {
    jwt_payload.clearance_level >= 3
    startswith(http_request.path, "/classified")
}
```

### **Example 5: Multi-Factor Requirements**
```rego
# Require MFA for sensitive endpoints
allow {
    jwt_payload.realm_access.roles[_] == "admin"
    startswith(http_request.path, "/admin/config")
    jwt_payload.acr >= "2"  # Authentication Context Reference (MFA level)
}
```

### **Example 6: Rate Limiting by User**
```rego
# Allow only 100 requests per hour per user
allow {
    jwt_payload.realm_access.roles[_] == "user"
    count([r | r := data.request_log[_]; r.user == jwt_payload.sub; r.time > time.now_ns() - 3600000000000]) < 100
}
```