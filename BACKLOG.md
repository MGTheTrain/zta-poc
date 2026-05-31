# Roadmap

Things deliberately deferred. Each item has a "trigger" — the condition
that would make it worth doing now rather than later.

## Short-term

### Drop the `--v0-compatible` flag from OPA
**Status**: deferred
**Trigger**: when next touching policies for unrelated reasons, or when
upgrading past OPA v1.x where the flag is removed.

We currently launch OPA with `--v0-compatible` so the existing Rego v0
syntax (`allow { ... }` without the `if` keyword) keeps parsing under
OPA v1.x. Migrating the policies to v1 syntax (`allow if { ... }`,
explicit `contains` for partial set rules) lets us drop the flag.
Mechanical change but easy to break — wait until there's a real reason
to be in the rego files.

Affected files:
- `infra/compose/docker-compose.yml` (OPA `command:` block)
- `infra/helm-charts/zta-platform/values.yaml` (OPA args)
- `infra/helm-charts/zta-platform/templates/opa-deployment.yaml` (args)
- Every `.rego` file under `policies/`

### Ship the manifests claimed by ADR-002
**Status**: deferred
**Trigger**: when the PoC is presented as a security demo rather than a
pattern reference.

ADR-002 commits the project to a defense-in-depth approach (Network
Policies + STRICT PeerAuthentication + restrictive RBAC), but the
umbrella chart doesn't currently ship any of those. Add:

- `PeerAuthentication` with `mtls.mode: STRICT` (cluster-wide and per-namespace)
- `NetworkPolicy` resources scoping pod-to-pod traffic to expected paths
- `Role` / `RoleBinding` blocking `kubectl exec` for non-privileged users
- Validation steps in the test suite that confirm each layer rejects bypass attempts

## Medium-term

### Unify the compose and k8s policy trees
**Status**: deferred
**Trigger**: when adding a new transport (Linkerd, Cilium) or a third
policy variant — duplication will start hurting then.

`policies/opa/` and `policies/opa-k8s/` say nearly the same thing
differently because of two transport contracts (Envoy ext_authz expects
`{allowed, http_status, body}`; Istio CUSTOM AuthorizationPolicy expects
a bool). The actual rule logic is duplicated. Refactor into:

```
policies/
├── shared/           # rbac.rego, rebac.rego, time_based.rego
└── transports/
    ├── compose/      # thin facade returning dict
    └── k8s/          # thin facade returning bool
```

See the in-repo discussion for the full sketch.

## Long-term

### Evaluate Istio Ambient Mesh vs. classic sidecars

**Status**: deferred
**Trigger**: when reconsidering mesh selection (resource pressure,
operational toil from sidecar lifecycle, or new project where the
default isn't already chosen).

Open question: would the PoC be better served by Istio's sidecarless
Ambient Mesh (ztunnel for L4, Waypoint Proxy for L7) than the current
classic-sidecar architecture from ADR-001? Ambient changes where OPA
runs and how it's reached:

```
Classic sidecar:
  Pod Ingress ──> Envoy sidecar ──(gRPC/localhost)──> OPA sidecar
                  (sub-ms, isolated to pod)

Ambient (L7 via Waypoint):
  Pod Ingress ──> ztunnel (L4 mTLS) ──> Waypoint (L7) ──(gRPC/network)──> central OPA
                  (network hop, OPA scaled per-namespace)
```

The tradeoffs map to a separate ADR. Sketch:

- **Latency**: classic wins (localhost vs. cluster network hop).
- **Resource footprint**: ambient wins (one OPA per namespace instead of one per pod).
- **L7 capability**: equivalent. Both terminate TLS and parse JWT/headers in an Envoy-derived proxy.
- **Where eBPF-only meshes fit**: not a substitute for Waypoint when L7 policy is needed — Cilium has to redirect to an Envoy node proxy anyway, losing the kernel-fast-path advantage for the L7-policy traffic.

The eBPF-only path was considered and is not preferred for this use
case: OPA's L7 work (JWT decoding, body inspection, HTTP method/path
matching) ultimately needs an Envoy-class proxy. Ambient makes that
separation explicit (ztunnel vs. Waypoint); Cilium ends up with the
same architecture less explicitly.

Open the ADR when one of the triggers above fires. Until then, classic
sidecars per ADR-001 stand.
