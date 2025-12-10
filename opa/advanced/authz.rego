package envoy.authz

import data.envoy.authz.rbac
import data.envoy.authz.time_based
import data.envoy.authz.ip_allowlist
import data.envoy.authz.rebac
import data.envoy.authz.mfa
import data.envoy.authz.rate_limit
import data.envoy.authz.geofencing

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"] as jwt_metadata

default allow = false

# Extract JWT claims (shared across all policies)
jwt_payload := jwt_metadata.jwt_payload

# Extract client IP
client_ip := input.attributes.source.address.socketAddress.address

# Health endpoints are always accessible
allow {
    http_request.path == "/health"
}

# Main authorization logic - all checks must pass
allow {
    rbac.allowed                      # Role-based check
    time_based.allowed                # Business hours check
    ip_allowlist.allowed             # Network check
    rebac.allowed                    # Resource ownership check
    mfa.allowed                      # MFA requirement check
    rate_limit.allowed               # Rate limit check
    geofencing.allowed               # Location check
}

# Decision log for debugging
decision := {
    "allow": allow,
    "user": jwt_payload.preferred_username,
    "path": http_request.path,
    "checks": {
        "rbac": rbac.allowed,
        "time_based": time_based.allowed,
        "ip_allowlist": ip_allowlist.allowed,
        "rebac": rebac.allowed,
        "mfa": mfa.allowed,
        "rate_limit": rate_limit.allowed,
        "geofencing": geofencing.allowed
    }
}
