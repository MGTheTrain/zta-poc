# Architecture

How the components fit together in each runtime, and what they're responsible for.

## Components

| Component | Role | Runtime |
|---|---|---|
| Keycloak | Identity provider, JWT issuer | Both |
| OPA | Policy decision point | Both |
| Envoy sidecar | JWT validation + ext_authz call to OPA | Compose |
| Istio | Sidecar injection, JWT validation, ext_authz to OPA, mTLS | Kubernetes |
| Go / Python / C# services | Demo backends | Both |

The two runtimes use the same Keycloak realm, the same JWT format, and conceptually the same policies — but the *transport* between Envoy and OPA differs, which is why the policy files diverge slightly between `policies/opa/` and `policies/opa-k8s/`. See [POLICIES.md](POLICIES.md) for that detail.

## Docker Compose

```
Client
  │
  ▼
Envoy sidecar (one per service, ports 9001-9003)
  │  ├── jwt_authn filter      ← validates JWT against Keycloak JWKS, decodes payload to metadata
  │  └── ext_authz filter      ← gRPC call to OPA with request + metadata
  ▼
Backend service (Go/Python/C# on port 8080)
```

- Each service has its own dedicated Envoy container.
- Envoy reads its config from a bind-mounted YAML in `configs/envoy/`.
- OPA loads policies from a bind-mounted directory `policies/opa/${OPA_POLICY_SET}/` and serves them via the gRPC ext_authz plugin.

## Kubernetes (kind + Istio)

```
Client
  │
  ▼
Istio Ingress Gateway (port 8080)
  │
  ▼
VirtualService (routing by Host header: go-service.local etc.)
  │
  ▼
Service Pod
  ├── istio-proxy (sidecar, auto-injected)
  │     ├── RequestAuthentication  ← validates JWT format, sets principal
  │     └── AuthorizationPolicy CUSTOM  ← gRPC call to OPA
  └── application container (port 8080)
```

The pieces that wire OPA into the mesh:

- **RequestAuthentication `jwt-auth`** validates JWTs from Keycloak's JWKS.
- **AuthorizationPolicy `delegate-to-opa`** with `action: CUSTOM` delegates the decision to OPA.
- **ServiceEntry `opa-ext-authz-grpc`** maps the synthetic hostname `opa-ext-authz-grpc.local` (referenced in istiod's meshConfig) back to the real `opa.default.svc.cluster.local:9191`.
- **istiod's `meshConfig.extensionProviders`** declares the OPA provider — added by the umbrella chart's `hook-patch-meshconfig.yaml` Helm hook.

All four are deployed by the `zta-poc` umbrella chart. Istio itself is installed separately (see [ADR-001](adrs/ADR-001-SERVICE-MESH-SELECTION.md) and the umbrella chart README for why).

## Identity model

| Layer | Identity | How |
|---|---|---|
| End user | JWT `sub` claim | Issued by Keycloak (alice → admin, bob → user) |
| Service (compose) | Implicit per-container | Envoy sidecar in front of every service; no per-service cert |
| Service (k8s) | SPIFFE SVID | `spiffe://cluster.local/ns/default/sa/<service>`, issued by istiod, rotated automatically |

See [concepts/SPIFFE.md](concepts/SPIFFE.md) for what SPIFFE actually is.

## Where each piece lives in the repo

```
configs/envoy/                      ← per-service Envoy YAML (compose only)
configs/keycloak/demo-realm.json    ← Keycloak users + roles + client
policies/opa/<set>/                 ← compose policies (read JWT from header)
policies/opa-k8s/<set>/             ← k8s policies (read JWT from istio metadata)
infra/compose/docker-compose.yml    ← compose stack
infra/helm-charts/zta-poc/          ← umbrella chart (Istio CRDs + hooks)
infra/helm-charts/zta-platform/     ← OPA + Keycloak workloads
infra/helm-charts/services/         ← go/python/csharp leaf charts
services/{go,python,csharp}/        ← application source + Dockerfile
tests/                              ← pytest suite
scripts/                            ← deploy/teardown helpers
```

## Why two policy trees

The compose stack's Envoy and Kubernetes's Istio both forward JWT payload into metadata via `jwt_authn`, but **the response shape OPA must return differs**:

- Compose's `ext_authz` filter expects a dict response (`{"allowed": bool, "http_status": int, "body": str}`) so Envoy can construct the HTTP status/body for the client.
- Istio's `AuthorizationPolicy CUSTOM` calls OPA via gRPC and expects a boolean — Istio constructs the HTTP response itself.

So `policies/opa/*/authz.rego` returns dicts; `policies/opa-k8s/*/authz.rego` returns booleans. The actual policy *logic* (who's allowed what) is the same.

## Bypass-prevention layers (Kubernetes)

Listed for completeness; see [ADR-002](adrs/ADR-002-SIDECAR-BYPASS-PREVENTION-IN-ZTA.md) for the full reasoning. The umbrella chart currently ships the AuthorizationPolicy and RequestAuthentication; NetworkPolicies, PeerAuthentication STRICT, and RBAC restrictions on `kubectl exec` are open work tracked in [TODO-KEY-DECISIONS-FOR-DISTRIBUTED-SYSTEMS.md](adrs/TODO-KEY-DECISIONS-FOR-DISTRIBUTED-SYSTEMS.md).
