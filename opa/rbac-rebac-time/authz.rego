package envoy.authz

import data.envoy.authz.rbac
import data.envoy.authz.time_based
import data.envoy.authz.rebac

import input.attributes.request.http as http_request
import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"] as jwt_metadata

default allow = false

# Extract JWT claims (shared across all policies)
jwt_payload := jwt_metadata.jwt_payload

# Health endpoints are always accessible
allow {
    http_request.path == "/health"
}

# Main authorization logic - all checks must pass
allow {
    rbac.allowed                        # Role-based
    rebac.allowed                    # Resource ownership check
    time_based.allowed                # Business hours check
}

# Decision log for debugging
decision := {
    "allow": allow,
    "user": jwt_payload.preferred_username,
    "path": http_request.path,
    "checks": {
        "rbac": rbac.allowed,
        "rebac": rebac.allowed,
        "time_based": time_based.allowed
    }
}
