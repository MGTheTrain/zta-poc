package envoy.authz.mfa

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload

default allowed = false

# Sensitive endpoints require MFA
sensitive_paths := [
    "/admin/config",
    "/admin/users",
    "/api/financial",
    "/api/pii"
]

# Check if path requires MFA
requires_mfa {
    startswith(http_request.path, sensitive_paths[_])
}

# Allow if MFA is satisfied
allowed {
    requires_mfa
    # ACR (Authentication Context Class Reference) level 2+ means MFA
    jwt_payload.acr >= "2"
}

# Allow if path doesn't require MFA
allowed {
    not requires_mfa
}

# Health endpoint
allowed {
    http_request.path == "/health"
}
