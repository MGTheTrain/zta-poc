# NCSC Zero Trust Principles → Implementation Mapping

This PoC demonstrates the [NCSC Zero Trust Architecture Design Principles](https://www.ncsc.gov.uk/collection/zero-trust-architecture).

## Principle 1: Know your architecture
**Implementation:**
- Architecture diagram in `README.md`
- All components documented: Envoy, OPA, Keycloak, 3 microservices
- Service discovery via Docker Compose DNS

## Principle 2: Know your identities
**Implementation:**
- **User identities:** Keycloak realm with users (alice/admin, bob/user)
- **Service identities:** Each service has unique identity via mTLS (future enhancement)
- **Device identities:** Not implemented (device health would use Keycloak device flow)

**Test:** `make setup-keycloak` creates users with roles

## Principle 3: Assess user behaviour and service health
**Implementation:**
- **User behaviour:** JWT claims include roles, monitored by OPA
- **Service health:** `/health` endpoints on all services
- **Future:** Add anomaly detection in OPA policies

## Principle 4: Use policies to authorise requests
**Implementation:**
- **Policy Engine:** OPA with ABAC rules in `opa/policies/authz.rego`
- **Policies:**
  - Admins: Full access
  - Users: GET only, no /admin/*
  - Anonymous: /health only

**Test:** `make test-admin` vs `make test-user` shows policy enforcement

## Principle 5: Authenticate & authorise everywhere
**Implementation:**
- **Authentication:** Envoy JWT validation on every request (Keycloak JWKS)
- **Authorization:** OPA ext_authz filter on every request
- **No bypass:** Services not exposed directly, only via Envoy sidecars

**Config:** See `envoy/go-service-envoy.yaml` filters

## Principle 6: Focus monitoring on users, devices, services
**Implementation:**
- **OPA decision logs:** Shows user, roles, path, allow/deny
- **Envoy access logs:** HTTP method, status, latency
- **Future:** Integrate with OpenTelemetry for full observability

**Monitor:** `docker logs opa -f | grep Decision`

## Principle 7: Don't trust any network
**Implementation:**
- **Assumption:** Network is hostile (no network-based trust)
- **Encryption:** TLS termination at Envoy (future: mTLS between services)
- **Validation:** JWT verified cryptographically, not by network position

**Note:** mTLS between services not yet implemented

## Principle 8: Choose services designed for zero trust
**Implementation:**
- **Envoy:** Built for zero trust, supports JWT validation + ext_authz
- **OPA:** Policy-as-code, testable, version-controlled
- **Keycloak:** Standards-based (OAuth2/OIDC), supports device flows
- **All services:** Stateless, cloud-native, sidecar-compatible

**Standards:** JWT (RFC 7519), OIDC, gRPC ext_authz

---

## What's Missing (for production)
- ✅ Implemented: AuthN, AuthZ, policy-based access
- ⚠️ Partial: Monitoring (basic logs, needs full observability)
- ❌ Not implemented: Device health, mTLS, continuous verification