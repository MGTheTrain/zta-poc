package envoy.authz.rate_limit

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload

default allowed = false

# Rate limit: 100 requests per hour per user
# NOTE: This is a simplified implementation
# Production should use Redis or external rate limit service

allowed {
    # Check if user has exceeded rate limit
    user_id := jwt_payload.sub
    
    # Get request count from data (populated by OPA data API)
    request_count := count([r | r := data.rate_limit[user_id][_]; 
                             r.timestamp > time.now_ns() - 3600000000000])
    
    request_count < 100
}

# Admins bypass rate limits
allowed {
    jwt_payload.realm_access.roles[_] == "admin"
}

# Health endpoint
allowed {
    input.attributes.request.http.path == "/health"
}

# NOTE: To make this work in production, you need:
# 1. External rate limit service (Redis)
# 2. OPA data push from rate limit service
# 3. Or use Envoy's rate limit filter instead
