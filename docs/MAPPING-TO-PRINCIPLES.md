# NCSC Zero Trust Principles → Implementation Mapping

This PoC demonstrates the [NCSC Zero Trust Architecture Design Principles](https://www.ncsc.gov.uk/collection/zero-trust-architecture) with production-ready implementations in both Docker Compose and Kubernetes/Istio environments.

## Principle 1: Know your architecture
**Implementation:**
- Architecture diagrams in `README.md` for both Docker Compose and Kubernetes
- All components documented: Envoy/Istio, OPA, Keycloak, 3 microservices
- **Docker Compose:** Service discovery via Docker DNS
- **Kubernetes:** Service discovery via CoreDNS + Istio service mesh
- **Istio Integration:** ServiceEntry maps `opa-ext-authz-grpc.local` → `opa.default.svc.cluster.local:9191`

**Architecture Flow (Kubernetes):**
```
Client → Istio Gateway → Service Pod [Istio Sidecar + OPA Authorization] → Backend Service
         ↓
         RequestAuthentication (JWT validation)
         ↓
         AuthorizationPolicy CUSTOM (delegates to OPA)
         ↓
         ServiceEntry (resolves OPA service)
```

**Test:** 
- Docker: `make compose-start && docker ps`
- Kubernetes: `make k8s-deploy && kubectl get all -A`

## Principle 2: Know your identities
**Implementation:**
- **User identities:** Keycloak realm with users (alice/admin, bob/user)
- **Service identities (Docker):** Each service has unique identity via dedicated Envoy sidecar
- **Service identities (Kubernetes):** Istio SPIFFE IDs (`spiffe://cluster.local/ns/default/sa/go-service`)
- **mTLS:** Istio automatic mutual TLS between services
- **Device identities:** Not implemented (device health would use Keycloak device flow)

**Kubernetes Identity Verification:**
```bash
# Check service identity
kubectl exec <pod> -c istio-proxy -- curl localhost:15000/certs

# Verify mTLS
istioctl x describe pod <pod-name>
```

**Test:** 
- Docker: `make compose-start` (Keycloak auto-configures users)
- Kubernetes: `make k8s-deploy` (includes mTLS configuration)

## Principle 3: Assess user behaviour and service health
**Implementation:**
- **User behaviour:** 
  - JWT claims include roles, username, subject ID
  - OPA decision logs capture user, path, method, allow/deny
  - Request patterns visible in Envoy/Istio access logs
- **Service health:** 
  - `/health` endpoints on all services (exempt from authentication)
  - Kubernetes liveness/readiness probes
  - Istio health checks
- **Future:** Add anomaly detection in OPA policies (unusual access patterns)

**Monitoring:**
```bash
# OPA decision logs (both environments)
docker logs opa -f | grep Decision                    # Docker
kubectl logs -l app=opa -f | grep -i decision        # Kubernetes

# Istio metrics (Kubernetes)
kubectl exec <pod> -c istio-proxy -- curl localhost:15000/stats
```

## Principle 4: Use policies to authorise requests
**Implementation:**
- **Policy Engine:** OPA with declarative Rego policies
- **Docker Compose:** Policies in `opa/policies/` (3 policy sets)
- **Kubernetes:** Policies in `opa-k8s/` (RBAC-only and combined sets)

**Policy Sets:**
1. **RBAC only** (`use-one`/`k8s-use-one`):
   - Admins: Full access (200)
   - Users: GET only, no /admin/* (200/403)
   - Anonymous: 401 Unauthorized
   - Proper HTTP status codes (401 vs 403)

2. **RBAC + ReBAC + Time** (`use-three`/`k8s-use-three`):
   - All RBAC rules
   - Users can only access `/users/{their-sub}/*`
   - Business hours enforcement (Mon-Fri 9am-5pm UTC)
   - Admins bypass all restrictions

**Integration:**
- **Docker:** Envoy ext_authz filter calls OPA directly
- **Kubernetes:** Istio AuthorizationPolicy CUSTOM delegates to OPA via ServiceEntry

**Test:** 
```bash
# Docker Compose
make compose-test  # Auto-detects loaded policies

# Kubernetes
make k8s-test      # Auto-detects loaded policies
```

## Principle 5: Authenticate & authorise everywhere
**Implementation:**
- **Authentication (Docker):** 
  - Envoy JWT validation on every request
  - JWKS URI: Keycloak public keys
  - Returns 401 for missing/invalid JWT

- **Authentication (Kubernetes):** 
  - Istio RequestAuthentication validates JWT format
  - JWKS URI: `http://keycloak.default.svc.cluster.local:8080/realms/demo/protocol/openid-connect/certs`
  - Sets `requestPrincipal` for downstream policies

- **Authorization (Both):** 
  - OPA ext_authz filter on every request
  - Returns 401 for missing JWT, 403 for insufficient permissions
  - No bypass: Services not exposed directly

- **No trusted network:** 
  - All requests validated regardless of source
  - Kubernetes NetworkPolicies (future enhancement)

**Docker Config:** `envoy/go-service-envoy.yaml` filters  
**Kubernetes Config:** 
```yaml
RequestAuthentication: jwt-auth
AuthorizationPolicy: delegate-to-opa
ServiceEntry: opa-ext-authz-grpc
```

**Verification:**
```bash
# Docker: Check Envoy filter chain
curl http://localhost:9901/config_dump | jq '.configs[].http_filters'

# Kubernetes: Check Istio proxy config
kubectl exec <pod> -c istio-proxy -- curl localhost:15000/config_dump | \
  jq '.configs[].dynamic_listeners[].active_state.listener.filter_chains[].filters[].typed_config.http_filters[] | select(.name == "envoy.filters.http.ext_authz")'
```

## Principle 6: Focus monitoring on users, devices, services
**Implementation:**
- **OPA decision logs (structured JSON):**
  - User: `preferred_username` from JWT
  - Action: HTTP method + path
  - Decision: allow/deny with reason
  - Response codes: 200/401/403
  - Policy checks: RBAC, ReBAC, Time-based results

- **Envoy/Istio access logs:**
  - HTTP method, status, latency
  - Request ID for correlation
  - User-Agent, source IP

- **Kubernetes additions:**
  - Istio telemetry (Prometheus metrics)
  - Service mesh observability
  - Distributed tracing ready (OpenTelemetry)

- **Future:** 
  - Integrate with OpenTelemetry for full observability
  - Correlate OPA decisions with service traces
  - Grafana dashboards for authorization patterns

**Monitor:** 
```bash
# Docker
docker logs opa -f | grep Decision

# Kubernetes
kubectl logs -l app=opa -f | grep -i decision

# Sample decision log
{
  "decision_id": "abc123",
  "input": {
    "attributes": {
      "request": {
        "http": {
          "method": "POST",
          "path": "/api/data",
          "headers": {"authorization": "Bearer ..."}
        }
      }
    }
  },
  "result": false,
  "user": "bob",
  "checks": {
    "rbac": false,
    "rebac": true,
    "time_based": true
  }
}
```

## Principle 7: Don't trust any network
**Implementation:**
- **Assumption:** Network is hostile (no network-based trust)
- **Encryption:**
  - Docker: TLS termination at Envoy sidecars
  - Kubernetes: Istio automatic mTLS between services
  - External traffic: TLS at Istio Gateway (production: HTTPS ingress)

- **Validation:** 
  - JWT verified cryptographically (RSA signatures)
  - Not based on network position, source IP, or VPN
  - All services validate every request

- **Kubernetes mTLS:**
  - Automatic SPIFFE identity (`spiffe://cluster.local/ns/default/sa/<service>`)
  - Mutual authentication between services
  - Certificate rotation handled by Istio

**Verify mTLS (Kubernetes):**
```bash
# Check PeerAuthentication
kubectl get peerauthentication -A

# View service certificates
kubectl exec <pod> -c istio-proxy -- curl localhost:15000/certs

# Verify mTLS mode
istioctl x describe pod <pod-name>
```

**Note:** 
- ✅ **Kubernetes:** Full mTLS implemented via Istio
- ⚠️ **Docker:** TLS termination only (mTLS between services not implemented)

## Principle 8: Choose services designed for zero trust
**Implementation:**
- **Envoy/Istio:** 
  - Built for zero trust architectures
  - JWT validation (RFC 7519)
  - ext_authz filter for external authorization
  - mTLS with certificate rotation (Istio)
  - SPIFFE/SPIRE identity framework (Istio)

- **OPA:** 
  - Policy-as-code (version controlled)
  - Testable policies (`make test-opa`)
  - Declarative Rego language
  - gRPC ext_authz API
  - Auditable decision logs

- **Keycloak:** 
  - Standards-based (OAuth2/OIDC, SAML)
  - JWT issuer with JWKS endpoint
  - Supports device flows, MFA, custom claims
  - Centralized identity management

- **All services:** 
  - Stateless (12-factor apps)
  - Cloud-native (containerized)
  - Sidecar-compatible
  - Health check endpoints
  - Kubernetes-ready with Istio injection

**Standards Compliance:**
- JWT (RFC 7519)
- OIDC (OpenID Connect)
- SPIFFE (Secure Production Identity Framework)
- gRPC ext_authz (Envoy standard)
- Istio AuthorizationPolicy (Kubernetes standard)

---

## Implementation Matrix

| Principle | Docker Compose | Kubernetes | Status |
|-----------|---------------|------------|--------|
| **1. Know architecture** | ✅ Documented | ✅ Documented + Istio | Complete |
| **2. Identities** | ✅ Users + Services | ✅ Users + mTLS SPIFFE | Complete |
| **3. Assess behaviour** | ✅ OPA logs | ✅ OPA + Istio metrics | Complete |
| **4. Policy authorization** | ✅ OPA RBAC/ReBAC/Time | ✅ OPA RBAC/ReBAC/Time | Complete |
| **5. AuthN/Z everywhere** | ✅ Envoy + OPA | ✅ Istio + OPA | Complete |
| **6. Monitoring** | ⚠️ Basic logs | ⚠️ Logs + Istio telemetry | Partial |
| **7. Don't trust network** | ⚠️ TLS only | ✅ Full mTLS | Complete (K8s) |
| **8. Zero trust services** | ✅ Envoy/OPA/Keycloak | ✅ Istio/OPA/Keycloak | Complete |

## What's Complete (Production-Ready)

### Docker Compose
- ✅ JWT authentication with proper 401/403 status codes
- ✅ Policy-based authorization (RBAC + ReBAC + Time)
- ✅ Envoy sidecar pattern
- ✅ Hot-reload policies
- ✅ Automated testing
- ⚠️ TLS termination only (no mTLS between services)
- ⚠️ Basic logging (no full observability stack)

### Kubernetes
- ✅ **Istio service mesh integration**
- ✅ **Automatic mTLS with SPIFFE identities**
- ✅ **RequestAuthentication for JWT validation**
- ✅ **AuthorizationPolicy CUSTOM with ServiceEntry**
- ✅ **Proper HTTP status codes (401/403)**
- ✅ **Multi-policy composition (RBAC + ReBAC + Time)**
- ✅ Hot-reload policies
- ✅ Automated testing with policy detection
- ⚠️ Basic logging (ready for OpenTelemetry integration)

## What's Missing (for production)

**Both Environments:**
- ❌ Device health attestation
- ❌ Continuous verification (periodic re-auth)
- ❌ Full observability stack (OpenTelemetry)
- ❌ Anomaly detection in OPA policies
- ❌ Network policies (Kubernetes) / Network segmentation (Docker)

**Docker Compose Only:**
- ❌ mTLS between services (use Kubernetes for this)
- ❌ Service identity rotation

**Kubernetes Only:**
- ⚠️ OpenTelemetry integration (ready but not configured)
- ⚠️ Advanced Istio features (traffic splitting, circuit breaking)

## Migration Path: Docker → Kubernetes

This PoC demonstrates a clear migration path:

1. **Development (Docker Compose):**
   - Rapid iteration on policies
   - Test Envoy + OPA integration
   - Validate JWT flows
   - Debug policy logic

2. **Production (Kubernetes):**
   - Deploy with `make k8s-deploy`
   - Automatic mTLS via Istio
   - ServiceEntry for OPA resolution
   - Production-grade orchestration
   - Rolling updates, health checks
   - Observability ready

**Key Architectural Difference:**
- Docker: Manual Envoy sidecar configuration
- Kubernetes: Automatic Istio sidecar injection + AuthorizationPolicy

Both use **identical OPA policies** - just different policy loading commands (`make compose-use-one` vs `make k8s-use-one`).

## Compliance Notes

This implementation demonstrates:
- ✅ **NCSC ZTA principles 1-8** (with noted gaps)
- ✅ **NIST SP 800-207** implicit trust zones → zero trust
- ✅ **OAuth2/OIDC standards** for authentication
- ✅ **Kubernetes security best practices** (when using K8s deployment)
- ✅ **Service mesh patterns** (Istio)

**For production compliance:**
- Add OpenTelemetry for full observability
- Implement NetworkPolicies (Kubernetes)
- Enable Istio AuthorizationPolicy for defense in depth
- Add device health checks (Keycloak device flow)
- Implement continuous verification policies in OPA