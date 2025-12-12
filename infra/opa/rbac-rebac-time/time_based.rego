package envoy.authz.time_based

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload

default allow = false

# Business hours: Mon-Fri 9am-5pm UTC
allowed {
    # Get current time
    now := time.now_ns()
    
    # Parse to clock hour (0-23)
    [hour, _, _] := time.clock([now, "UTC"])
    
    # Check business hours
    hour >= 9
    hour < 17
    
    # Check weekday (0=Sunday, 1=Monday, ..., 6=Saturday)
    weekday := time.weekday([now, "UTC"])
    weekday != "Saturday"
    weekday != "Sunday"
}

# Admins bypass time restrictions
allowed {
    jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass time restrictions
allowed {
    input.attributes.request.http.path == "/health"
}
