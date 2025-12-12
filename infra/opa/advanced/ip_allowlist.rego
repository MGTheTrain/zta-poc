package envoy.authz.ip_allowlist

import input.attributes.source.address.socketAddress.address as client_ip
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload

default allowed = false

# Corporate network CIDR ranges
corporate_networks := [
    "10.0.0.0/8",      # Internal network
    "172.16.0.0/12",   # VPN range
    "192.168.0.0/16"   # Office networks
]

# Check if client IP is in corporate network
allowed {
    net.cidr_contains(corporate_networks[_], client_ip)
}

# Admins can access from anywhere
allowed {
    jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass IP checks
allowed {
    input.attributes.request.http.path == "/health"
}

# Allow localhost (for testing)
allowed {
    client_ip == "127.0.0.1"
    client_ip == "::1"
}
