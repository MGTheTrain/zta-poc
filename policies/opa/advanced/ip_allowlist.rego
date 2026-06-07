package envoy.authz.ip_allowlist

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload
import input.attributes.source.address.socketAddress.address as client_ip

default allowed := false

# Corporate network CIDR ranges
corporate_networks := [
	"10.0.0.0/8", # Internal network
	"172.16.0.0/12", # VPN range
	"192.168.0.0/16", # Office networks
]

# Check if client IP is in corporate network
allowed if {
	net.cidr_contains(corporate_networks[_], client_ip)
}

# Admins can access from anywhere
allowed if {
	jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass IP checks
allowed if {
	input.attributes.request.http.path == "/health"
}

# Allow localhost (for testing)
allowed if {
	client_ip == "127.0.0.1"
	client_ip == "::1"
}
