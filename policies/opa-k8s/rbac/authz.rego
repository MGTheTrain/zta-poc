package envoy.authz

import input.attributes.request.http as http_request

default allow = {
    "allowed": false,
    "http_status": 401,
    "body": "Unauthorized: Missing or invalid JWT"
}

# JWT payload extraction
jwt_payload := payload {
    auth_header := http_request.headers.authorization
    auth_header != ""
    startswith(auth_header, "Bearer ")
    token := substring(auth_header, 7, -1)
    parts := split(token, ".")
    payload := json.unmarshal(base64url.decode(parts[1]))
}

jwt_payload := {} {
    not http_request.headers.authorization
}

# Health endpoint (public)
allow := {"allowed": true} {
    http_request.path == "/health"
}

# Return 401 if no JWT (except /health)
allow := {
    "allowed": false,
    "http_status": 401,
    "body": "Unauthorized: Missing JWT token"
} {
    http_request.path != "/health"
    jwt_payload == {}
}

# Admin role: full access
allow := {"allowed": true} {
    jwt_payload.realm_access.roles[_] == "admin"
}

# User role: GET only, no /admin/*
allow := {"allowed": true} {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    not startswith(http_request.path, "/admin")
}

# Return 403 for user trying POST
allow := {
    "allowed": false,
    "http_status": 403,
    "body": "Forbidden: Insufficient permissions"
} {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method != "GET"
}

# Return 403 for user trying /admin
allow := {
    "allowed": false,
    "http_status": 403,
    "body": "Forbidden: Insufficient permissions"
} {
    jwt_payload.realm_access.roles[_] == "user"
    startswith(http_request.path, "/admin")
}