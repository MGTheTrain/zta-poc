package envoy.authz.geofencing

import input.attributes.metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload as jwt_payload
import input.attributes.request.http as http_request

default allowed = false

# Allowed countries for data access
allowed_countries := ["US", "CA", "GB", "DE"]

# Check user's country from JWT custom claim
allowed {
    jwt_payload.country
    jwt_payload.country == allowed_countries[_]
}

# Admins bypass geofencing
allowed {
    jwt_payload.realm_access.roles[_] == "admin"
}

# Public endpoints bypass geofencing
allowed {
    http_request.path == "/health"
}

# If no country claim, default allow (graceful degradation)
allowed {
    not jwt_payload.country
}

# NOTE: To implement this, you need:
# 1. Add country claim to JWT in Keycloak (user mapper)
# 2. Or query external IP geolocation service:
#
# country_from_ip(ip) := country {
#     response := http.send({
#         "method": "GET",
#         "url": sprintf("http://ip-api.com/json/%s", [ip])
#     })
#     country := response.body.countryCode
# }
