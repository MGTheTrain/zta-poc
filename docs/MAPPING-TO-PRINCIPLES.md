# NCSC Zero Trust Principles → Implementation Mapping

This PoC maps the [NCSC Zero Trust Architecture Design Principles](https://www.ncsc.gov.uk/collection/zero-trust-architecture)
to what the Docker Compose and Kubernetes runtimes actually implement.
It's an honest accounting — what's working, what's aspirational, and
what's missing for production.

For component layout and request flow, see [ARCHITECTURE.md](ARCHITECTURE.md).
For policy detail, see [POLICIES.md](POLICIES.md).

## Principle 1 — Know your architecture

- Component layout and request flow documented in [ARCHITECTURE.md](ARCHITECTURE.md).
- Compose: service discovery via Docker DNS.
- Kubernetes: service discovery via CoreDNS; OPA reached from
  istio-proxies via a `ServiceEntry` that maps the synthetic hostname
  `opa-ext-authz-grpc.local` to `opa.default.svc.cluster.local:9191`.

**Smoke checks:**
- Compose: `make compose-start && docker compose -f infra/compose/docker-compose.yml ps`
- Kubernetes: `make k8s-deploy && kubectl get all -A`

## Principle 2 — Know your identities

| Layer | Compose | Kubernetes |
|---|---|---|
| End-user | Keycloak users (alice → admin, bob → user) | Same |
| Workload | No cryptographic identity — services sit behind dedicated Envoy proxies, but no per-service cert | SPIFFE SVIDs (`spiffe://cluster.local/ns/default/sa/<service>`), rotated by istiod |
| Device | Not implemented | Not implemented |

```bash
# k8s: inspect a pod's SVID
kubectl exec <pod> -c istio-proxy -- curl -s localhost:15000/certs | jq

# k8s: describe pod's mesh identity and mTLS posture
istioctl x describe pod <pod>
```

## Principle 3 — Assess user behaviour and service health

- OPA decision logs capture user, method, path, allow/deny per request.
- Envoy/Istio access logs capture method, status, latency, request ID.
- All services expose `/health` (exempt from authn).
- Kubernetes pod probes: the chart sets readiness/liveness on the demo
  services; Istio's istio-proxy has its own readiness probe at `:15021/healthz/ready`.
- Anomaly detection in OPA — not implemented.

```bash
# OPA decision log stream
docker logs opa -f | grep -i decision           # compose
kubectl logs -l app=opa -f | grep -i decision   # k8s

# Istio proxy stats
kubectl exec <pod> -c istio-proxy -- curl -s localhost:15000/stats | head
```

## Principle 4 — Use policies to authorise requests

- **Policy engine:** OPA, Rego policies.
- **Compose policies:** [`policies/opa/`](../policies/opa/) — three sets: `rbac`, `rbac-rebac-time`, `advanced`.
- **Kubernetes policies:** [`policies/opa-k8s/`](../policies/opa-k8s/) — two sets: `rbac`, `rbac-rebac-time`.

The two policy trees express the **same authorization logic** but
diverge in two technical details:

1. **Response shape.** Compose's Envoy ext_authz filter expects a dict
   (`{allowed, http_status, body}`) so Envoy can render the HTTP
   response. Istio's AuthorizationPolicy CUSTOM expects a plain bool.
2. **JWT source.** Compose policies parse the `Authorization` header
   themselves; k8s policies read the pre-parsed payload from
   `metadataContext.filterMetadata["envoy.filters.http.jwt_authn"].jwt_payload`,
   which istio-proxy populates via the `jwt_authn` filter.

Policy detail and authorization matrix: [POLICIES.md](POLICIES.md).

| Set | Compose target | k8s target | Rules |
|---|---|---|---|
| RBAC | `make compose-use-one` | `make k8s-use-one` | Admin: all. User: GET-only, no `/admin`. Anonymous: 401. |
| RBAC + ReBAC + Time | `make compose-use-three` | `make k8s-use-three` | + Users may only access `/users/{their-sub}/*`. + Business hours (Mon-Fri 09–17 UTC). Admins bypass. |

```bash
make compose-test           # runs pytest against compose
make k8s-test               # runs pytest against k8s
make test-opa               # OPA-direct policy tests (no service layer)
```

## Principle 5 — Authenticate & authorise everywhere

| | Compose | Kubernetes |
|---|---|---|
| JWT validation | Envoy `jwt_authn` filter, JWKS from Keycloak | Istio `RequestAuthentication`, JWKS from `keycloak.default.svc.cluster.local:8080/realms/demo/protocol/openid-connect/certs` |
| Missing/invalid JWT | OPA policy returns 401 dict; Envoy renders | RequestAuthentication rejects with 401 *before* OPA is consulted |
| Authorization | OPA via Envoy ext_authz | OPA via Istio AuthorizationPolicy CUSTOM + ServiceEntry |
| Direct bypass possible? | No external port; services not published | Yes by pod IP if you're inside the cluster — see "What's missing" |

## Principle 6 — Focus monitoring on users, devices, services

OPA decision logs are structured JSON. The exact shape depends on which
policy variant is loaded; here's a sketch of what the multi-policy
(`rbac-rebac-time`) `decision` rule emits:

```json
{
  "decision_id": "...",
  "user": "bob",
  "path": "/admin/users",
  "checks": {"rbac": false, "rebac": true, "time_based": true},
  "result": false
}
```

The single-policy RBAC variant has no nested `checks` field.

```bash
docker logs opa -f | grep -i decision
kubectl logs -l app=opa -f | grep -i decision
```

**Not yet wired:** OpenTelemetry, Prometheus scraping, Grafana
dashboards. The mesh emits stats at `:15020` per proxy if you want to
hook a Prometheus instance up manually.

## Principle 7 — Don't trust any network

- **JWT verification is cryptographic** (RSA signature against Keycloak
  JWKS) and happens at every hop — that's the load-bearing part of "no
  network trust" here.
- **Transport encryption status:**
  - Compose: **plaintext HTTP** between client, Envoy, and the
    application container. No TLS, no mTLS. The PoC runs on localhost.
  - Kubernetes: Istio auto-mTLS works in **PERMISSIVE** mode by default,
    which accepts mTLS *and* plaintext. The umbrella chart does not
    currently ship a `PeerAuthentication` resource forcing STRICT mode.
    To require mTLS, add a STRICT PeerAuthentication — tracked as open
    work.

```bash
# Confirm current mTLS posture
kubectl get peerauthentication -A
istioctl x describe pod <pod>
```

## Principle 8 — Choose services designed for zero trust

- **Envoy / Istio:** JWT (RFC 7519), ext_authz filter, SPIFFE-compliant
  workload identity (Istio), automatic cert rotation.
- **OPA:** policy-as-code, gRPC ext_authz API, decision logs.
- **Keycloak:** OAuth2/OIDC standards, JWKS, supports MFA and custom
  claims via protocol mappers.
- **Demo services:** stateless, containerized, `/health` endpoint,
  Istio-injection-compatible.

Standards in use: JWT (RFC 7519), OIDC, SPIFFE, gRPC ext_authz, Istio
AuthorizationPolicy. **Note:** `make test-opa` runs pytest against OPA's
REST API; it does *not* invoke OPA's own `opa test` framework.

## Implementation matrix

| Principle | Compose | Kubernetes |
|---|---|---|
| 1. Know architecture | Documented | Documented |
| 2. Identities (user) | ✅ | ✅ |
| 2. Identities (workload) | ❌ no cert | ✅ SPIFFE SVID |
| 3. Behaviour / health | Logs + `/health` | Logs + `/health` + pod probes |
| 4. Policy authorization | ✅ OPA | ✅ OPA |
| 5. AuthN/Z everywhere | ✅ at each Envoy | ✅ at each sidecar |
| 6. Monitoring | OPA + access logs | OPA + access logs + Istio stats |
| 7. Encryption in transit | ❌ plaintext | ⚠️ Istio PERMISSIVE, not STRICT |
| 8. ZT-native components | ✅ | ✅ |

## What's missing for production

**Both runtimes:**
- Device health attestation
- Continuous verification / token re-evaluation
- Centralized observability (OpenTelemetry, Prometheus, dashboards)
- Anomaly detection in policy

**Compose only:**
- Any transport encryption (the PoC is plaintext-on-localhost)
- Workload identity / cert rotation

**Kubernetes only:**
- `PeerAuthentication` STRICT to make mTLS mandatory
- `NetworkPolicy` to block direct pod-IP access and enforce the sidecar
  as the only network path
- RBAC restrictions on `kubectl exec` (defense against API-level bypass)
- TLS on the Istio Gateway (currently HTTP)
- OpenTelemetry hookup

See [ADR-002](adrs/ADR-002-SIDECAR-BYPASS-PREVENTION-IN-ZTA.md) for the
bypass-prevention discussion and the tracked work to close these gaps.

## Migration path: Compose → Kubernetes

Compose is the inner-loop development environment: fast iteration on
Rego, no cluster overhead, plaintext networking that's easy to inspect.

Kubernetes is where the zero-trust properties (workload identity,
mTLS, NetworkPolicy) become available. The two runtimes share the same
Keycloak realm and the same logical policy, just expressed in
transport-appropriate forms (see Principle 4).
