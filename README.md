# Zero Trust Architecture PoC

Zero Trust implementation demonstrating JWT authentication, policy-based
authorization, and service mesh integration across Go, Python, and C#
services using Istio, OPA, and Keycloak.

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

See `make help` for the full command list.

## Access points

(the two existing port tables, kept — they're the most-referenced thing in the file)

## Test users

- alice / password (admin)
- bob / password (user)

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
