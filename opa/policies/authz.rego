package envoy.authz

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"] as jwt_metadata

default allow = false

# Extract JWT claims
jwt_payload := jwt_metadata.jwt_payload

# Admin role can access everything
allow {
    jwt_payload.realm_access.roles[_] == "admin"
}

# User role: GET only, NO /admin/* paths
allow {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    not startswith(http_request.path, "/admin")
}

# Service accounts can call /api/* endpoints
allow {
    jwt_payload.resource_access.account.roles[_] == "service"
    startswith(http_request.path, "/api/")
}

# Health endpoints are always accessible (no JWT required for monitoring)
allow {
    http_request.path == "/health"
}

# Debug: Log the decision
decision := {"allow": allow, "user": jwt_payload.preferred_username, "roles": jwt_payload.realm_access.roles, "path": http_request.path}