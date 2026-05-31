# Zero Trust Architecture PoC

Zero Trust implementation demonstrating JWT authentication, policy-based
authorization and service mesh integration across Go, Python and C#
services using Istio, OPA and Keycloak.

## Backlog

Tracked future improvements and planned work items are maintained in [BACKLOG.md](./BACKLOG.md).

## Quick Start

### Docker Compose
```bash
export RUNTIME=docker

make start
make use-three   # or use-one
make test
make stop
```

### Kubernetes (kind)
```bash
export RUNTIME=k8s

make start
make forward          # in another terminal
make use-three        # or use-one
make test
make stop
```

### Make targets

```bash
Zero Trust Architecture PoC

  PROJECT_ROOT   = /Users/marvingajek/Documents/poc-repos/zta-poc
  OPA_POLICY_SET = rbac-rebac-time
  RUNTIME        = compose

Usage:
  make <target> [RUNTIME=compose|k8s]

  help                   Show available targets
  open-keycloak          Open Keycloak in browser
  list-policies          List policies currently loaded in OPA
  test-opa               Test OPA policies directly
  lint                   Run pre-commit hooks
  start                  Start the platform
  stop                   Stop the platform
  restart                Restart the platform
  logs                   Follow platform logs
  rebuild                Rebuild service docker images
  forward                Port-forward dashboards (k8s only)
  wait-healthy           Block until Keycloak + OPA + at least one service respond (max 120s)
  test                   Run service + OPA policy tests
  use-one                Switch OPA to basic RBAC policies
  use-three              Switch OPA to RBAC + ReBAC + Time-based policies
  forward-bg             Background port-forward (k8s only; writes PID to /tmp/zta-pf.pid)
  forward-stop           Stop background port-forwards
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
