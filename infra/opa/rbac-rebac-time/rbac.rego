package envoy.authz.rbac

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload

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
