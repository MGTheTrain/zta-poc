# Zero Trust Architecture PoC

Zero Trust implementation demonstrating JWT authentication, policy-based authorization and service mesh integration across Go, Python and C# services using Istio, OPA and Keycloak.

## Quick Start

### Docker Compose (Local Development)

```bash
# Start all services (Keycloak auto-configures from realm.json)
make compose-start

# Load policies
make compose-use-one      # RBAC only
make compose-use-three    # RBAC + ReBAC + Time-based

# Run tests (auto-detects loaded policy set)
make compose-test         # Integration tests via Envoy
make test-opa     # Direct OPA policy tests

# View active policies
make list-policies
```

### Kubernetes (Kind)

```bash
# Deploy infrastructure and services
make k8s-deploy

# Port-forward (in separate terminal)
make k8s-forward

# Load policies
make k8s-use-one      # RBAC only
make k8s-use-three    # RBAC + ReBAC + Time-based

# Run tests (auto-detects K8s and loaded policies)
make k8s-test

# View active policies
make list-policies
```

**Access Points (Docker Compose):**
- Keycloak: http://localhost:8180 (admin/admin)
- Go Service: http://localhost:9001
- Python Service: http://localhost:9002
- C# Service: http://localhost:9003
- OPA: http://localhost:8181

**Access Points (Kubernetes):**
- Keycloak: http://localhost:8180 (port-forwarded)
- Services: http://localhost:8080 (via Istio Gateway)
- OPA: http://localhost:8181 (port-forwarded)

## What's Included

**Zero Trust Stack:**
- **Keycloak** - Identity provider & JWT issuer (auto-configured)
- **OPA** - Policy decision point (hot-reloadable policies)
- **Envoy Sidecars** (Docker) / **Istio Service Mesh** (Kubernetes) - JWT validation & authorization

**Example Services:**
| Language | Docker Port | K8s Host | Endpoint |
|----------|-------------|----------|----------|
| Go | 9001 | go-service.local | /api/data |
| Python (FastAPI) | 9002 | python-service.local | /api/data |
| C# (ASP.NET) | 9003 | csharp-service.local | /api/data |

**Architecture:**

*Docker Compose:*
```
Client → Envoy [JWT Validation → OPA Authorization] → Backend Service
```

*Kubernetes:*
```
Client → Istio Gateway → Service Pod [Istio Sidecar + OPA Authorization] → Backend Service
```

**Test Users:**
- alice / password (admin role)
- bob / password (user role)

## Policy Sets

### use-one: RBAC Only
Simple role-based access control with proper HTTP status codes

**Rules:**
- Admin: Full access
- User: GET only, no /admin/*
- Anonymous: 401 Unauthorized
- Authenticated but insufficient permissions: 403 Forbidden

### use-three: RBAC + ReBAC + Time
Adds resource ownership and time-based restrictions

**Additional Rules:**
- Users can only access `/users/{their-id}/*`
- Business hours enforcement (Mon-Fri 9am-5pm UTC)
- Admins bypass all restrictions
- Proper 401/403 status codes maintained

## Test Results

```bash
make compose-test  # Docker Compose
make k8s-test      # Kubernetes
```

**Expected output (RBAC only):**
- ✅ Admin (alice): Full access to all endpoints (200)
- ✅ User (bob): GET only, blocked from POST/admin (200/403)
- ✅ Anonymous: 401 Unauthorized (except /health)
- ✅ Health endpoints: Public (200)

**Expected output (RBAC + ReBAC + Time):**
- ✅ All RBAC rules working
- ✅ Bob can access `/users/{bob-sub-id}/profile` (200)
- ✅ Bob blocked from `/users/{alice-sub-id}/profile` (403)
- ✅ Time-based restrictions working
- ✅ Admins bypass all restrictions

## Authorization Matrix

| Endpoint | Admin | User | Anonymous |
|----------|-------|------|-----------|
| `GET /` | ✅ 200 | ✅ 200 | ❌ 401 |
| `GET /health` | ✅ 200 | ✅ 200 | ✅ 200 |
| `GET /api/data` | ✅ 200 | ✅ 200 | ❌ 401 |
| `POST /api/data` | ✅ 200 | ❌ 403 | ❌ 401 |
| `GET /admin/users` | ✅ 200 | ❌ 403 | ❌ 401 |
| `GET /users/{bob-sub-id}/profile` | ✅ 200 | ✅ 200 (own) | ❌ 401 |
| `GET /users/{alice-sub-id}/profile` | ✅ 200 | ❌ 403 | ❌ 401 |

## Available Commands

```bash
Usage: make [target]

Common targets (work for both):
  list-policies      List current policies
  open-keycloak      Open Keycloak in browser
  test-opa           Test OPA policies directly

Docker Compose targets:
  compose-build      Rebuild all services
  compose-start      Start all services
  compose-stop       Stop all services
  compose-restart    Restart all services
  compose-logs       Show logs
  compose-clean      Stop and remove everything
  compose-test       Run integration tests
  compose-use-one    Use basic RBAC policies
  compose-use-three  Use RBAC + ReBAC + Time-based policies

Kubernetes targets:
  k8s-deploy         Deploy services with Istio
  k8s-test           Test Kubernetes deployment
  k8s-forward        Port-forward all services
  k8s-clean          Cleanup Kind resources
  k8s-use-one        Use basic RBAC policies
  k8s-use-three      Use RBAC + ReBAC + Time-based policies
```

## Key Features

- **Istio Integration** - Official Istio AuthorizationPolicy CUSTOM pattern
- **Proper HTTP Status Codes** - 401 for missing auth, 403 for insufficient permissions
- **Auto-configuration** - Keycloak realm imported on first start
- **Hot-reload policies** - Switch policies instantly without restart
- **Auto-detecting tests** - Single command tests all scenarios
- **ReBAC support** - Users can only access their own resources
- **Time-based access** - Business hours enforcement
- **ServiceEntry Resolution** - Proper service discovery for OPA
- **Zero Trust** - Never trust, always verify

## Architecture Details

### Docker Compose
- **Envoy sidecars** handle JWT validation and call OPA for authorization
- Each service has dedicated Envoy proxy (ports 9001-9003)
- OPA policies loaded via HTTP API

### Kubernetes
- **Istio service mesh** with automatic mTLS (SPIFFE identities)
- **RequestAuthentication** validates JWT format
- **AuthorizationPolicy CUSTOM** delegates to OPA via ServiceEntry
- **ServiceEntry** maps `opa-ext-authz-grpc.local` → `opa.default.svc.cluster.local:9191`
- OPA policies loaded via kubectl port-forward + HTTP API

## Troubleshooting

**No policies loaded?**
```bash
make compose-use-three              # Docker Compose
make k8s-use-three          # Kubernetes
make list-policies          # Check Docker or Kubernetes
```

**Tests failing?**
```bash
# Docker Compose
docker logs opa --tail 50
docker logs keycloak --tail 50
make compose-clean && make compose-start

# Kubernetes
kubectl logs -l app=opa --tail=50
kubectl logs -l app=keycloak --tail=50
make k8s-clean && make k8s-deploy
```

**403 Forbidden?**
- Check loaded policies
- View OPA decisions: `kubectl logs -l app=opa -f | grep Decision`
- Verify JWT roles at [jwt.io](https://jwt.io)

**401 Unauthorized (Kubernetes)?**
```bash
# Check RequestAuthentication
kubectl get requestauthentication jwt-auth -n default

# Check OPA is receiving requests
kubectl logs -l app=opa -f | grep -i decision

# Verify ServiceEntry
kubectl get serviceentry opa-ext-authz-grpc -n default
```

**OPA not receiving requests (Kubernetes)?**
```bash
# Verify ServiceEntry exists
kubectl get serviceentry opa-ext-authz-grpc -n default

# Check AuthorizationPolicy
kubectl get authorizationpolicy delegate-to-opa -n default

# Check pod labels
kubectl get pods -l security=zta-enabled --show-labels

# View Envoy stats
kubectl exec <pod-name> -c istio-proxy -- curl localhost:15000/stats | grep ext_authz
```

**Port conflicts?**
Edit `docker-compose.yml` port mappings

**For detailed troubleshooting, see:** [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Advanced ABAC (Future Enhancements)

**Currently Implemented & Tested:** 
- ✅ Time-based access control (business hours)
- ✅ Resource-based access (ReBAC - user ownership)
- ✅ Role-based access control (RBAC)
- ✅ Proper HTTP status codes (401/403)
- ✅ Kubernetes Istio integration

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
- [Service Mesh Selection ADR](docs/adrs/ADR-001-SERVICE-MESH-SELECTION.md)

### Technical Documentation
- [Istio External Authorization](https://istio.io/latest/docs/tasks/security/authorization/authz-custom/)
- [OPA Envoy Plugin](https://www.openpolicyagent.org/docs/latest/envoy-introduction/)
- [Envoy External Authorization](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

## Production Considerations

This PoC demonstrates production-ready patterns:

### Docker Compose → Kubernetes Migration
- ✅ **Completed** - Full Istio + OPA integration
- ✅ Automatic sidecar injection
- ✅ ServiceEntry for OPA resolution
- ✅ RequestAuthentication for JWT validation
- ✅ AuthorizationPolicy CUSTOM for OPA delegation
- ✅ Proper HTTP status codes (401/403)

### Production Deployment
- **Cloud/On-prem:** Deploy on managed/self-hosted Kubernetes
- **Best practices:** 
  - Enable mTLS between services
  - Use cert-manager for certificate rotation
  - Persistent storage for Keycloak
  - OPA policy versioning and GitOps
  - OpenTelemetry for observability
  - Resource limits and HPA
  - Network policies for pod-to-pod security
  - Istio AuthorizationPolicy for defense in depth

### Recommended Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    Production Setup                      │
├─────────────────────────────────────────────────────────┤
│ Ingress/Gateway (TLS termination)                       │
│   ↓                                                      │
│ Istio Gateway (mTLS + JWT validation)                   │
│   ↓                                                      │
│ Service Pods [Istio Sidecar + OPA Authorization]        │
│   ↓                                                      │
│ Backend Service (authenticated & authorized requests)   │
└─────────────────────────────────────────────────────────┘
```

## What Makes This Production-Ready

1. **Official Istio Pattern** - Uses `AuthorizationPolicy CUSTOM` with `ServiceEntry`
2. **Proper Status Codes** - 401 for authentication failures, 403 for authorization failures
3. **Multi-Policy Composition** - RBAC + ReBAC + Time checks work together
4. **Comprehensive Testing** - Automated tests for all scenarios
5. **Hot-Reload Policies** - Update authorization rules without service restart
6. **Zero Downtime** - Kubernetes rolling updates supported
7. **Observability Ready** - OPA decision logs for audit trail

## License

MIT