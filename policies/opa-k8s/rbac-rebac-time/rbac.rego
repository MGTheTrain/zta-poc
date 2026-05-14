package envoy.authz.rbac

import input.attributes.request.http as http_request

# JWT payload extraction (shared with main authz)
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

default allowed = false

# Admin role: full access
allowed {
    jwt_payload.realm_access.roles[_] == "admin"
}

# User role: GET only, no /admin paths
allowed {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    not startswith(http_request.path, "/admin")
}

# Service accounts: /api/* only
allowed {
    jwt_payload.resource_access.account.roles[_] == "service"
    startswith(http_request.path, "/api/")
}