# Advanced ABAC examples

Reference snippets showing what's possible when you combine OPA with the
attributes Envoy/Istio forward in the ext_authz request.

> **Note:** Most snippets below are *illustrative*. The runnable policies
> in [`policies/opa/advanced/`](../policies/opa/advanced/) implement
> several of these patterns with the caveats called out inline.

## Quick taxonomy

**RBAC — role-based**
```rego
jwt_payload.realm_access.roles[_] == "admin"
```

**ABAC — adds request and identity attributes**
```rego
jwt_payload.realm_access.roles[_] == "user"
http_request.method == "GET"                     # request attribute
not startswith(http_request.path, "/admin")      # request attribute
```

ABAC is RBAC plus *any other attribute* — HTTP method, path, headers,
client IP, time of day, custom JWT claims, external lookups. Below is
what's available and how each is consumed.

## Attributes Envoy and Istio forward to OPA

### Request
```rego
http_request.method                              # GET, POST, ...
http_request.path                                # /api/data
http_request.headers["user-agent"]
http_request.headers["x-forwarded-for"]
http_request.body                                # only if Envoy is told to forward bodies
input.parsed_query.page                          # query string params
```

### JWT claims (identity)
```rego
jwt_payload.sub
jwt_payload.email
jwt_payload.preferred_username
jwt_payload.realm_access.roles
jwt_payload.department                           # only if added via Keycloak user mapper
jwt_payload.clearance_level                      # same
```

### Network
```rego
input.attributes.source.address.socketAddress.address       # client IP
input.attributes.destination.address.socketAddress.portValue
```

### Time
Use `time.now_ns()` and friends from OPA's standard library; the
`input.attributes.request.time` field that Envoy forwards works too but
is harder to feed back into OPA's time builtins.

### External data
OPA can call out via `http.send`, but **`http.send` is restricted by
default** in recent OPA releases. To enable it, start OPA with
`--set capabilities.builtins.http.send.allow=true` (or supply a
capabilities file). For most production setups it's cleaner to push
data into OPA via the bundle API or `kube-mgmt` and reference
`data.*` instead.

---

## Patterns

### Business hours

The simple "is now between 9 and 17 UTC" check, mirroring what
[`policies/opa/rbac-rebac-time/time_based.rego`](../policies/opa/rbac-rebac-time/time_based.rego)
actually ships:

```rego
allowed {
    now := time.now_ns()
    [hour, _, _] := time.clock([now, "UTC"])
    hour >= 9
    hour < 23
    weekday := time.weekday([now, "UTC"])
    weekday != "Saturday"
    weekday != "Sunday"
}
```

A literal one-day window using parsed RFC3339 timestamps is occasionally
useful (e.g. "freeze access on this specific date"):

```rego
allow {
    time.now_ns() > time.parse_rfc3339_ns("2026-12-09T09:00:00Z")
    time.now_ns() < time.parse_rfc3339_ns("2026-12-09T17:00:00Z")
}
```

### IP allowlist

```rego
allow {
    client_ip := input.attributes.source.address.socketAddress.address
    net.cidr_contains("10.0.0.0/8", client_ip)
}
```

Note that in Kubernetes the client IP visible to OPA is often the Istio
ingress gateway's pod IP, not the real client — you'll need to consult
`X-Forwarded-For` or enable [Istio externalTrafficPolicy: Local](https://istio.io/latest/docs/tasks/security/authorization/authz-ingress/)
preservation.

### Resource ownership (ReBAC)

The pattern that's actually in use; matches the path parts to the JWT
`sub` claim:

```rego
allow {
    jwt_payload.realm_access.roles[_] == "user"
    http_request.method == "GET"
    path_parts := split(http_request.path, "/")
    count(path_parts) >= 3
    path_parts[1] == "users"
    path_parts[2] == jwt_payload.sub
}
```

### Custom JWT claims

Custom claims require a Keycloak user mapper or protocol mapper to land
in the JWT. Once they do:

```rego
allow {
    jwt_payload.realm_access.roles[_] == "user"
    jwt_payload.department == "engineering"
}

allow {
    jwt_payload.clearance_level >= 3
    startswith(http_request.path, "/classified")
}
```

### MFA / step-up authentication

The `acr` claim (Authentication Context Class Reference) indicates how
the user authenticated. Keycloak emits `"1"` for password-only,
`"2"` once an OTP/WebAuthn factor was used.

```rego
allow {
    jwt_payload.realm_access.roles[_] == "admin"
    startswith(http_request.path, "/admin/config")
    jwt_payload.acr == "2"
}
```

> `acr` values are **strings**, not ints, so use `==` rather than `>=`.
> Earlier ABAC literature shows `acr >= "2"` — that works in OPA because
> string comparison is lexicographic, but it's brittle. Compare to the
> exact value(s) you accept.

### Rate limiting (illustrative)

OPA can count items it has in its `data` document, but it has no
built-in way to *receive* request events from Envoy. So this pattern
only works if you have an external pusher (your own rate-limit service,
or Envoy's own ratelimit filter feeding stats back into OPA via the
bundle API):

```rego
allow {
    jwt_payload.realm_access.roles[_] == "user"
    count([r |
        r := data.request_log[_]
        r.user == jwt_payload.sub
        r.time > time.now_ns() - 3600000000000        # 1h in ns
    ]) < 100
}
```

For real rate limiting reach for [Envoy's global rate-limit filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/rate_limit_filter)
backed by a Redis-based service — OPA is the wrong layer.

### External lookup

If `http.send` is enabled in your OPA capabilities:

```rego
allow {
    response := http.send({
        "method": "GET",
        "url": "http://user-service/api/users/location",
        "headers": {"Authorization": input.attributes.request.http.headers.authorization}
    })
    response.body.country == "US"
}
```

Three things to know before relying on this:
1. The call is **synchronous and on the hot path** — every authorization
   decision waits for it. Cache aggressively (`cache: true` in the
   `http.send` object).
2. If the external service is down, the rule fails closed (request
   denied). Make sure that's the behavior you want.
3. Bundle-API-pushed data scales better for anything you can pre-compute.

## Where to go next

- Runnable variants: [`policies/opa/advanced/`](../policies/opa/advanced/)
- Real ABAC in production guidance: [OPA docs — Envoy](https://www.openpolicyagent.org/docs/latest/envoy-introduction/)
- Keycloak protocol mappers for custom claims: [Keycloak admin docs](https://www.keycloak.org/docs/latest/server_admin/#_protocol-mappers)
