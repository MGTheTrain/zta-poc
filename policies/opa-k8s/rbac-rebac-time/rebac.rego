package envoy.authz.rebac

import input.attributes.request.http as http_request

# JWT payload extraction (shared with main authz)
jwt_payload := payload if {
	auth_header := http_request.headers.authorization
	auth_header != ""
	startswith(auth_header, "Bearer ")
	token := substring(auth_header, 7, -1)
	parts := split(token, ".")
	payload := json.unmarshal(base64url.decode(parts[1]))
}

jwt_payload := {} if {
	not http_request.headers.authorization
}

default allowed := false

# Users can only access their own resources
# Pattern: /users/{user_id}/profile or /api/users/{user_id}/data
allowed if {
	path_parts := split(http_request.path, "/")
	count(path_parts) >= 3
	path_parts[1] == "users"
	path_parts[2] == jwt_payload.sub
}

# Admins can access all resources
allowed if {
	jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass resource checks (not /users/*)
allowed if {
	not regex.match("^/users/[^/]+/", http_request.path)
}

# Health endpoint
allowed if {
	http_request.path == "/health"
}
