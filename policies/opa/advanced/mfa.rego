package envoy.authz.mfa

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload
import input.attributes.request.http as http_request

default allowed := false

# Sensitive endpoints require MFA
sensitive_paths := [
	"/admin/config",
	"/admin/users",
	"/api/financial",
	"/api/pii",
]

# Check if path requires MFA
requires_mfa if {
	startswith(http_request.path, sensitive_paths[_])
}

# Allow if MFA is satisfied
allowed if {
	requires_mfa

	# ACR (Authentication Context Class Reference) level 2+ means MFA
	jwt_payload.acr >= "2"
}

# Allow if path doesn't require MFA
allowed if {
	not requires_mfa
}

# Health endpoint
allowed if {
	http_request.path == "/health"
}
