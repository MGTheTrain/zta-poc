package envoy.authz

import data.envoy.authz.rbac
import data.envoy.authz.time_based
import data.envoy.authz.rebac

import input.attributes.request.http as http_request

default allow = {
    "allowed": false,
    "http_status": 401,
    "body": "Unauthorized: Missing or invalid JWT"
}

# JWT payload extraction (matches rbac/authz.rego)
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

# Health endpoints (always allowed)
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

# Main authorization - all checks must pass
allow := {"allowed": true} {
    jwt_payload != {}
    rbac.allowed
    rebac.allowed
    time_based.allowed
}

# Return 403 if RBAC fails
allow := {
    "allowed": false,
    "http_status": 403,
    "body": "Forbidden: RBAC check failed"
} {
    jwt_payload != {}
    not rbac.allowed
}

# Return 403 if ReBAC fails
allow := {
    "allowed": false,
    "http_status": 403,
    "body": "Forbidden: ReBAC check failed"
} {
    jwt_payload != {}
    not rebac.allowed
}

# Return 403 if time-based check fails
allow := {
    "allowed": false,
    "http_status": 403,
    "body": "Forbidden: Outside business hours"
} {
    jwt_payload != {}
    not time_based.allowed
}

# Decision log
decision := {
    "allow": allow,
    "user": object.get(jwt_payload, "preferred_username", "unknown"),
    "path": http_request.path,
    "checks": {
        "rbac": rbac.allowed,
        "rebac": rebac.allowed,
        "time_based": time_based.allowed
    }
}