# Zero Trust Architecture PoC

![Status](https://img.shields.io/badge/status-WIP-yellow)

Zero Trust implementation demonstrating JWT authentication, policy-based authorization, and sidecar pattern across Go, Python and C# services using Envoy, Keycloak and OPA.

## TODO

### Kubernetes + Service Mesh
- [ ] Kind devcontainer setup
- [ ] Istio integration with automatic sidecar injection
- [ ] EnvoyFilter CRDs
- [ ] mTLS between services
- [ ] Istio + OPA integration

## Quick Start

```bash
# Start all services (Keycloak auto-configures from realm.json)
make start

# Load policies
make use-one      # RBAC only
make use-three    # RBAC + Simple ReBAC + Time-based

# Run tests (auto-detects loaded policy set)
make test         # Integration tests via Envoy
make test-opa     # Direct OPA policy tests

# View active policies
make list-policies
```

**Access Points:**
- Keycloak: http://localhost:8180 (admin/admin)
- Go Service: http://localhost:9001
- Python Service: http://localhost:9002
- C# Service: http://localhost:9003
- OPA: http://localhost:8181

## What's Included

**Zero Trust Stack:**
- **Keycloak** - Identity provider & JWT issuer (auto-configured)
- **OPA** - Policy decision point (hot-reloadable policies)
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

**Test Users:**
- alice / password (admin role)
- bob / password (user role)

## Policy Sets

### use-one: RBAC Only
Simple role-based access control

**Rules:**
- Admin: Full access
- User: GET only, no /admin/*, can access own resources
- Anonymous: /health only

### use-three: RBAC + Simple ReBAC + Time
Adds resource ownership and time-based restrictions

**Additional Rules:**
- Users can only access `/users/{their-id}/*`
- Business hours enforcement (Mon-Fri 9am-5pm UTC)
- Admins bypass all restrictions

## Test Results

```bash
make test
```

**Expected output:**
- ✅ Admin (alice): Full access to all endpoints
- ✅ User (bob): GET only, blocked from /admin/*, can access own resources
- ✅ Anonymous: 401 except /health
- ✅ Simple ReBAC: Bob blocked from Alice's resources

## Authorization Matrix

| Endpoint | Admin | User | Anonymous |
|----------|-------|------|-----------|
| `GET /` | ✅ | ✅ | ❌ |
| `GET /health` | ✅ | ✅ | ✅ |
| `GET /api/data` | ✅ | ✅ | ❌ |
| `POST /api/data` | ✅ | ❌ | ❌ |
| `GET /admin/users` | ✅ | ❌ | ❌ |
| `GET /users/{bob-id}/profile` | ✅ | ✅ (own) | ❌ |
| `GET /users/{alice-id}/profile` | ✅ | ❌ | ❌ |

## Available Commands

```bash
Usage: make [target]

Available targets:
  help            Show this help
  use-one         Use basic RBAC policies
  use-three       Use RBAC + ReBAC + Time-based policies
  list-policies   List current policies
  build           Rebuild all services
  start           Start all services
  stop            Stop all services
  restart         Restart all services
  logs            Show logs
  clean           Stop and remove everything
  test            Auto-detect policy set and run appropriate tests
  open-keycloak   Open Keycloak in browser
  test-opa        Test OPA policies directly (detects use-one/use-three)
```

## Troubleshooting

**No policies loaded?**
```bash
make use-three  # Load policy set
make list-policies
```

**Tests failing?**
```bash
docker logs opa --tail 50        # Check OPA
docker logs keycloak --tail 50   # Check Keycloak
make clean && make start         # Fresh start
```

**403 Forbidden?**
- Check loaded policies: `make list-policies`
- View OPA decisions: `docker logs opa -f | grep Decision`
- Verify JWT at [jwt.io](https://jwt.io)

**Port conflicts?**
Edit `docker-compose.yml` port mappings

## Key Features

- **Auto-configuration** - Keycloak realm imported on first start
- **Hot-reload policies** - Switch policies instantly without restart
- **Auto-detecting tests** - Single command tests all scenarios
- **Simple ReBAC support** - Users can only access their own resources
- **Time-based access** - Business hours enforcement
- **Zero Trust** - Never trust, always verify

## Advanced ABAC (Future Enhancements)

**Currently Implemented & Tested:** 
- Time-based access control (business hours)
- Resource-based access (ReBAC - user ownership)
- Role-based access control (RBAC)

**Policy Examples Included (requires additional setup):**
- IP allowlisting - Needs corporate network configuration
- MFA requirements - Needs Keycloak MFA enrollment
- Rate limiting - Needs Redis/external service
- Geofencing - Needs IP geolocation API
- Custom JWT claims - Needs Keycloak user mappers

**See:** 
- [Advanced rego policy implementations](opa/advanced/)
- [Advanced ABAC Examples](docs/ABAC-EXAMPLES.md)

## Resources

### Standards & Principles
- [NCSC Zero Trust Principles](https://www.ncsc.gov.uk/collection/zero-trust-architecture)
- [NIST SP 800-207](https://csrc.nist.gov/publications/detail/sp/800-207/final)
- [Zero Trust Architecture Design Principles (GitHub)](https://github.com/ukncsc/zero-trust-architecture)
- [MAPPING-TO-PRINCIPLES.md](docs/MAPPING-TO-PRINCIPLES.md) - How this PoC implements NCSC principles

### Technical Documentation
- [Envoy External Authorization](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
- [OPA Envoy Plugin](https://www.openpolicyagent.org/docs/latest/envoy-introduction/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

## Production Considerations

This PoC can be migrated to Kubernetes:

- **Local testing:** Use Istio/Linkerd for automatic sidecar injection
- **Cloud deployment:** Use EnvoyFilter CRDs, Styra DAS for policy management
- **Best practices:** Enable mTLS, use cert-manager, persistent Keycloak storage, OpenTelemetry tracing