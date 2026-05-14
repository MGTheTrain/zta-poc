# Zero Trust Architecture PoC

Zero Trust implementation demonstrating JWT authentication, policy-based
authorization and service mesh integration across Go, Python and C#
services using Istio, OPA and Keycloak.

## Quick Start

### Docker Compose
```bash
make compose-start
make compose-use-three   # or compose-use-one
make compose-test
make compose-clean
```

### Kubernetes (kind)
```bash
make k8s-deploy
make k8s-forward          # in another terminal
make k8s-use-three        # or k8s-use-one
make k8s-test
make k8s-clean
```

### Make targets

```bash
Usage: make [target]

  PROJECT_ROOT   = /Users/marvingajek/Documents/poc-repos/zta-poc
  OPA_POLICY_SET = rbac-rebac-time

Common targets (work for both):
  list-policies      List current policies
  open-keycloak      Open Keycloak in browser
  test-opa           Test OPA policies directly
  wait-healthy       Block until Keycloak + OPA + at least one service answer (max 120s)

Docker Compose targets:
  compose-build      Rebuild all services (only the three backend services build locally; Envoy/Keycloak/OPA use upstream images)
  compose-start      Start all services
  compose-stop       Stop all services
  compose-restart    Restart all services
  compose-logs       Show logs
  compose-clean      Stop and remove everything
  compose-test       Run service + OPA policy tests against the compose stack
  compose-use-one    Use basic RBAC policies (remounts policies/opa/rbac into OPA)
  compose-use-three  Use RBAC + ReBAC + Time-based policies (remounts policies/opa/rbac-rebac-time into OPA)

Kubernetes targets:
  k8s-deploy         Deploy ZTA PoC umbrella chart on a kind cluster (Istio + zta-poc)
  k8s-clean          Tear down the ZTA PoC and Istio (helm uninstall + namespace cleanup)
  k8s-redeploy       Uninstall + install (full reset) ZTA PoC and Istio on a kind cluster
  k8s-test           Run service + OPA policy tests against the k8s deployment
  k8s-forward        Port-forward all services
  k8s-forward-bg     Same, but background — writes PID to /tmp/zta-pf.pid
  k8s-forward-stop   Kill the background port-forwards
  k8s-use-one        Use basic RBAC policies
  k8s-use-three      Use RBAC + ReBAC + Time-based policies

Development:
  lint               Run pre-commit hooks on specific files
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Policy sets and authorization matrix](docs/POLICIES.md)
- [Advanced ABAC examples](docs/ABAC-EXAMPLES.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [NCSC Zero Trust principles mapping](docs/MAPPING-TO-PRINCIPLES.md)
- [Production considerations](docs/PRODUCTION.md)

## ADRs

- [ADR-001: Service Mesh Selection](docs/adrs/ADR-001-SERVICE-MESH-SELECTION.md)
- [ADR-002: Sidecar Bypass Prevention](docs/adrs/ADR-002-SIDECAR-BYPASS-PREVENTION-IN-ZTA.md)
- [TODO: Distributed System Decisions](docs/adrs/TODO-KEY-DECISIONS-FOR-DISTRIBUTED-SYSTEMS.md)
