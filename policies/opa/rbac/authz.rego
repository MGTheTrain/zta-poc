package envoy.authz

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"] as jwt_metadata

default allow = false

# Extract JWT claims
jwt_payload := jwt_metadata.jwt_payload

# Health endpoints are always accessible
allow {
    http_request.path == "/health"
}

# Admin role: full access to everything
allow {
    jwt_payload.realm_access.roles[_] == "admin"
}

# User role: GET only, NO /admin/* paths
allow {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    not startswith(http_request.path, "/admin")
    # ReBAC: Users can only access their own resources
    check_resource_ownership
}

# Service accounts: /api/* only
allow {
    jwt_payload.resource_access.account.roles[_] == "service"
    startswith(http_request.path, "/api/")
}

# ReBAC helper: Check resource ownership
check_resource_ownership {
    # Extract user ID from path: /users/{user_id}/...
    path_parts := split(http_request.path, "/")
    count(path_parts) >= 3
    path_parts[1] == "users"
    # User ID in path must match JWT subject
    path_parts[2] == jwt_payload.sub
}

# ReBAC helper: Allow non-user-resource paths
check_resource_ownership {
    # If path doesn't match /users/{id}/, allow it
    not regex.match("^/users/[^/]+/", http_request.path)
}

# Debug decision log
decision := {
    "allow": allow,
    "user": jwt_payload.preferred_username,
    "roles": jwt_payload.realm_access.roles,
    "path": http_request.path,
    "method": http_request.method
}