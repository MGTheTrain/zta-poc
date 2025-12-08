# Zero Trust Architecture PoC

![Status](https://img.shields.io/badge/status-WIP-yellow)

Zero Trust implementation demonstrating JWT authentication, policy-based authorization and sidecar pattern across Go, Python and C# services using Envoy, Keycloak and OPA.

## TODO

### Kubernetes + Service Mesh
- [ ] **Kind devcontainer setup** - Local Kubernetes environment with Kind cluster
- [ ] **Istio integration** - Replace manual Envoy sidecars with Istio automatic injection
- [ ] **EnvoyFilter CRDs** - Convert Envoy configs to Kubernetes-native resources
- [ ] **mTLS between services** - Service-to-service encryption
- [ ] **Istio + OPA integration** - Deploy OPA as EnvoyFilter extension

### Advanced ABAC Examples
Current implementation: **RBAC + basic ABAC** (role + path + method)

**Planned enhancements:**
- [ ] **Time-based access control** - Business hours restrictions
- [ ] **IP allowlisting** - Corporate network requirements
- [ ] **Resource-based access (ReBAC)** - Users access only their own resources
- [ ] **Custom JWT claims** - Department, clearance level, cost center
- [ ] **Multi-factor requirements** - MFA enforcement for sensitive endpoints
- [ ] **Rate limiting per user** - Per-user request quotas
- [ ] **External data sources** - OPA queries to user/location services
- [ ] **Geofencing** - Location-based access restrictions

**See:** [Advanced ABAC Examples](docs/ABAC-EXAMPLES.md) for implementation details

## Quick Start

```bash
# Start everything
make start

# Configure Keycloak (realm, users, roles)
make setup-keycloak

# Generate test traffic and verify authorization
make test-admin     # ✅ Full access
make test-user      # ✅ GET only, no /admin/*
make test-denied    # ✅ No auth = 401

# Access UIs
make keycloak       # http://localhost:8180 (admin/admin)
```

## What's Included

**Zero Trust Stack:**
- **Keycloak** (port 8180) - Identity provider & JWT issuer
- **OPA** (port 8181) - Policy decision point
- **Envoy Sidecars** - JWT validation & authorization per service

**Example Services:**
| Language | Port | Endpoint |
|----------|------|----------|
| Go | 9001 | http://localhost:9001/api/data |
| Python (FastAPI) | 9002 | http://localhost:9002/api/data |
| C# (ASP.NET) | 9003 | http://localhost:9003/api/data |

**Architecture:**
```
Client → Envoy [JWT Validation → OPA Authorization] → Backend Service
```

**Why Zero Trust?**
- Never trust, always verify
- Least privilege access control
- Defense in depth
- Cloud-native security

## Viewing Authorization Decisions

### 1. OPA Decision Logs
```bash
docker logs opa -f | grep "Decision Log"
# Shows: user, roles, path, allow/deny decision
```

### 2. Test Different Scenarios

**Admin (alice) - Full Access:**
```bash
make test-admin
# ✅ GET/POST/PUT/DELETE all endpoints
# ✅ Access /admin/* routes
```

**User (bob) - Read-Only:**
```bash
make test-user
# ✅ GET / and /api/*
# ❌ POST/PUT/DELETE blocked
# ❌ /admin/* blocked
```

**No Authentication:**
```bash
make test-denied
# ❌ All endpoints blocked (401)
# ✅ /health always accessible
```

### 3. Authorization Matrix

| Endpoint | Admin | User | Anonymous |
|----------|-------|------|-----------|
| `GET /` | ✅ | ✅ | ❌ |
| `GET /health` | ✅ | ✅ | ✅ |
| `GET /api/data` | ✅ | ✅ | ❌ |
| `POST /api/data` | ✅ | ❌ | ❌ |
| `GET /admin/users` | ✅ | ❌ | ❌ |

## Development

**Available Commands:**
```bash
Usage: make [target]

Available targets:
  help            Show this help
  start           Start all services
  stop            Stop all services
  restart         Restart all services
  logs            Show logs
  clean           Stop and remove everything
  setup-keycloak  Configure Keycloak (realm, users, roles)
  test-admin      Test with admin token (should access everything)
  test-user       Test with regular user (GET only)
  test-denied     Test denied access scenarios
  keycloak        Open Keycloak in browser
```

## Troubleshooting

**No authorization data?**
1. Check OPA: `docker logs opa --tail 50`
2. Check Envoy: `docker logs go-service-envoy --tail 50`
3. Verify tokens: Decode at [jwt.io](https://jwt.io)

**403 Forbidden?**
1. Check OPA policy: `cat opa/policies/authz.rego`
2. View decision logs: `docker logs opa -f | grep Decision`
3. Verify JWT roles in token payload

**Port conflicts?**
Edit port mappings in `docker-compose.yml`

## Resources

### Standards & Principles
- [NCSC Zero Trust Principles](https://www.ncsc.gov.uk/collection/zero-trust-architecture) - Practical implementation guide
- [NIST SP 800-207](https://csrc.nist.gov/publications/detail/sp/800-207/final) - Zero Trust Architecture standard
- [Zero Trust Architecture Design Principles (GitHub Repository)](https://github.com/ukncsc/zero-trust-architecture) – Source repository containing the NCSC’s Zero Trust principles, documentation and diagrams
- [MAPPING-TO-PRINCIPLES.md](docs/MAPPING-TO-PRINCIPLES.md) - How this PoC implements NCSC principles

### Technical Documentation
- [Envoy External Authorization](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
- [OPA Envoy Plugin](https://www.openpolicyagent.org/docs/latest/envoy-introduction/)
- [OPA ABAC Examples](https://www.openpolicyagent.org/docs/latest/policy-reference/#http) - Advanced policy patterns
- [Keycloak Documentation](https://www.keycloak.org/documentation)

## Production / Kubernetes Considerations

This PoC can be migrated to Kubernetes:

- **Local testing:** Use Istio/Linkerd for automatic sidecar injection; convert to Kubernetes manifests.
- **Cloud/On-prem:** Deploy on managed Kubernetes; use EnvoyFilter CRDs, Styra DAS for policy management.
- **Best practices:** Enable mTLS between services, use cert-manager for TLS, persistent storage for Keycloak, distributed tracing with OpenTelemetry.