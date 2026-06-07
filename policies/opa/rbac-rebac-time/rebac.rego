package envoy.authz.rebac

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload
import input.attributes.request.http as http_request

default allowed := false

# Users can only access their own resources
# Pattern: /users/{user_id}/profile or /api/users/{user_id}/data
allowed if {
	# Extract user ID from path
	path_parts := split(http_request.path, "/")

	# Check if path contains user ID
	count(path_parts) >= 3
	path_parts[1] == "users"

	# User ID in path must match JWT subject
	path_parts[2] == jwt_payload.sub
}

# Admins can access all resources
allowed if {
	jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass resource checks
allowed if {
	not regex.match("/users/[^/]+/", http_request.path)
}

# Health endpoint
allowed if {
	http_request.path == "/health"
}
