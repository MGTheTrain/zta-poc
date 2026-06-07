package envoy.authz.rbac

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload
import input.attributes.request.http as http_request

default allowed := false

# Admin role: full access
allowed if {
	jwt_payload.realm_access.roles[_] == "admin"
}

# User role: GET only, no /admin paths
allowed if {
	jwt_payload.realm_access.roles[_] == "user"
	http_request.method == "GET"
	not startswith(http_request.path, "/admin")
}

# Service accounts: /api/* only
allowed if {
	jwt_payload.resource_access.account.roles[_] == "service"
	startswith(http_request.path, "/api/")
}
