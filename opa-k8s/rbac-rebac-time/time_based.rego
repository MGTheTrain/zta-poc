package envoy.authz.time_based

import input.attributes.request.http as http_request

# JWT payload extraction (shared with main authz)
jwt_payload := payload {
    auth_header := http_request.headers.authorization
    auth_header != ""
    startswith(auth_header, "Bearer ")
    token := substring(auth_header, 7, -1)
    parts := split(token, ".")
    payload := json.unmarshal(base64url.decode(parts[1]))
}

jwt_payload := {} {
    not http_request.headers.authorization
}

default allowed = false

# Business hours: Mon-Fri 9am-5pm UTC
allowed {
    now := time.now_ns()
    [hour, _, _] := time.clock([now, "UTC"])
    hour >= 9
    hour < 17
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
    http_request.path == "/health"
}