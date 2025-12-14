---
parent: Decisions
nav_order: 002
title: Sidecar Bypass Prevention in Zero Trust PoC
status: accepted
date: 2025-12-14
---

# Sidecar Bypass Prevention: Network Policies + mTLS + RBAC

## Context and Problem Statement

In our Istio-based ZTA PoC, Envoy/Istio sidecars enforce JWT validation and OPA authorization. However, attackers or misconfigured services could bypass sidecars through two attack vectors:

1. **Network-level bypass**: Direct connection to application ports (e.g., `localhost:8080`)
2. **API-level bypass**: Using `kubectl exec` to access containers directly

How do we prevent both network and API-level sidecar bypass while maintaining simplicity for a PoC?

## Decision Drivers

* **Zero Trust Principle**: Never trust, always verify - assume breach
* **Defense in Depth**: Multiple security layers (network + crypto + API access)
* **PoC Constraints**: Keep complexity reasonable for demonstration
* **Kubernetes Native**: Leverage platform capabilities
* **Auditability**: Log and detect bypass attempts
* **API Security**: Restrict administrative access to containers

## Considered Options

1. **Kubernetes Network Policies** - Block direct pod-to-pod traffic
2. **Service Mesh Enforced mTLS** - Require mTLS at mesh boundary
3. **RBAC for kubectl exec** - Restrict API-level container access
4. **Service-Level AuthN/AuthZ** - Fallback auth in services
5. **API Gateway Edge Security** - Centralized gateway enforcement
6. **Audit Logging and Monitoring** - Detect bypass attempts

## Decision Outcome

Chosen options: **Kubernetes Network Policies + Istio STRICT mTLS + RBAC** (layered approach)

**Network Defense**: Network Policies
- Block direct access to application ports
- Allow only sidecar-to-service communication

**Cryptographic Defense**: STRICT mTLS
- Enforce mTLS at mesh level
- Reject non-mTLS traffic

**API Defense**: RBAC Restrictions
- Deny `kubectl exec` for non-admin users
- Prevent API-level container access

### Consequences

* **Good**: Strong network-level isolation (bypass physically blocked)
* **Good**: mTLS provides cryptographic assurance of identity
* **Good**: RBAC prevents API-level bypass via kubectl exec
* **Good**: Kubernetes-native, no additional infrastructure
* **Good**: Defense in depth - multiple layers must fail
* **Good**: Comprehensive security across network, crypto and API layers
* **Bad**: Network policies add YAML complexity
* **Bad**: Debugging becomes harder (legitimate traffic blocked if misconfigured)
* **Bad**: RBAC restricts developer workflows (may need breakglass procedures)
* **Neutral**: Monitoring still recommended but not critical path

### Confirmation

Success criteria:
- Network policy blocks direct pod access (tested via `kubectl exec` to app container)
- STRICT mTLS rejects plaintext traffic
- RBAC denies kubectl exec for non-admin users
- Services still accessible via Istio Gateway
- Automated tests pass with all policies enabled
- Audit logs capture kubectl exec attempts

Post-Decision Testing:
- Network policy tests: `scripts/test-network-policies.sh` (**TODO**)
- RBAC tests: `scripts/test-rbac-restrictions.sh` (**TODO**)
- mTLS verification: `scripts/verify-mtls.sh` (**TODO**)

## Threat Model

### Attack Vector 1: Network-Level Bypass

**Scenario**: Compromised container attempts direct network connection

```
Attacker in pod → curl localhost:8080/api/data
                              ↓
Network Policy → BLOCKS (Ingress restricted to sidecar only)
                              ↓
Attack FAILED (Connection refused)
```

**Mitigation**: Kubernetes Network Policies

### Attack Vector 2: API-Level Bypass

**Scenario**: Attacker with Kubernetes access uses kubectl exec

```
Attacker → kubectl exec -it <pod> -- curl localhost:8080/api/data
                              ↓
RBAC → BLOCKS (User lacks pods/exec permission)
                              ↓
Attack FAILED (Forbidden: User cannot exec into pods)
```

**Mitigation**: Kubernetes RBAC

### Attack Vector 3: mTLS Bypass (if Network Policy fails)

**Scenario**: Network policy misconfigured, attacker connects directly

```
Attacker → Direct connection to pod IP:8080
                              ↓
STRICT mTLS → BLOCKS (No valid certificate)
                              ↓
Attack FAILED (TLS handshake failed)
```

**Mitigation**: Istio STRICT mTLS mode

## Pros and Cons of the Options

### Option 1: Kubernetes Network Policies

* **Good**: Prevents bypass at network layer (strong isolation)
* **Good**: Kubernetes-native, no additional tools
* **Good**: Auditable (policy violations logged by CNI)
* **Bad**: CNI-dependent (Calico, Cilium required; Kind uses kindnet which supports NetworkPolicy)
* **Bad**: Complex to debug (requires network troubleshooting)
* **Limitation**: Does NOT prevent kubectl exec (API-level access)
* **Implementation**: 
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: deny-direct-access
    namespace: default
  spec:
    podSelector:
      matchLabels:
        security: zta-enabled
    policyTypes:
      - Ingress
    ingress:
      # Allow only from Istio sidecars
      - from:
        - podSelector:
            matchLabels:
              app: istio-ingressgateway
        - podSelector:
            matchLabels:
              istio: ingressgateway
        ports:
          - protocol: TCP
            port: 8080
  ```

### Option 2: Service Mesh STRICT mTLS

* **Good**: Cryptographic identity verification
* **Good**: Works even if network policy bypassed
* **Good**: Istio-native (simple config)
* **Bad**: Doesn't prevent localhost bypass within pod
* **Bad**: Requires certificate management (handled by Istio)
* **Limitation**: Does NOT prevent kubectl exec (API-level access)
* **Implementation**:
  ```yaml
  apiVersion: security.istio.io/v1beta1
  kind: PeerAuthentication
  metadata:
    name: default
    namespace: default
  spec:
    mtls:
      mode: STRICT
  ```

### Option 3: RBAC for `kubectl exec`

* **Good**: Prevents API-level bypass via kubectl exec
* **Good**: Kubernetes-native RBAC
* **Good**: Auditable (Kubernetes audit logs)
* **Good**: Essential for defense in depth
* **Bad**: Restricts developer workflows (requires breakglass procedures)
* **Bad**: Doesn't prevent network-level bypass (needs Network Policies)
* **Implementation**:
  ```yaml
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: no-exec-role
  rules:
    - apiGroups: [""]
      resources: ["pods", "pods/log"]
      verbs: ["get", "list", "watch"]
    # Explicitly deny exec
    - apiGroups: [""]
      resources: ["pods/exec"]
      verbs: []  # No verbs = denied
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: developers-no-exec
  subjects:
    - kind: Group
      name: developers
      apiGroup: rbac.authorization.k8s.io
  roleRef:
    kind: ClusterRole
    name: no-exec-role
    apiGroup: rbac.authorization.k8s.io
  ```

### Option 4: Service-Level AuthN/AuthZ (Fallback)

* **Good**: Last line of defense if mesh fails
* **Good**: Independent of infrastructure
* **Bad**: Code changes required in each service
* **Bad**: Defeats purpose of centralized policy (OPA)
* **Bad**: Not scalable for PoC
* **Decision**: NOT implemented (conflicts with ZTA centralized policy)

### Option 5: API Gateway Edge Security

* **Good**: Centralized enforcement point
* **Good**: Works for external traffic
* **Bad**: Single point of failure
* **Bad**: Doesn't help with pod-to-pod or API-level bypass
* **Bad**: Already have Istio Gateway
* **Decision**: NOT needed (Istio Gateway sufficient)

### Option 6: Audit Logging and Monitoring

* **Good**: Detects anomalies and bypass attempts
* **Good**: Forensics and compliance
* **Good**: Captures kubectl exec attempts
* **Bad**: Reactive, not preventive
* **Bad**: Requires monitoring infrastructure
* **Decision**: RECOMMENDED for production (not enforced in PoC)

## Implementation Plan

### Phase 1: Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-direct-access
  namespace: default
spec:
  podSelector:
    matchLabels:
      security: zta-enabled
  policyTypes:
    - Ingress
  ingress:
    # Allow only from Istio components
    - from:
      - podSelector:
          matchLabels:
            app: istio-ingressgateway
      - namespaceSelector:
          matchLabels:
            name: istio-system
      ports:
        - protocol: TCP
          port: 8080
```

### Phase 2: STRICT mTLS

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
```

### Phase 3: RBAC Restrictions

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer-restricted
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services"]
    verbs: ["get", "list", "watch"]
  # No pods/exec permission
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developers-binding
subjects:
  - kind: Group
    name: system:authenticated
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: developer-restricted
  apiGroup: rbac.authorization.k8s.io
```

### Phase 4: Audit Logging (Production)

```yaml
# Enable Kubernetes audit logging in kube-apiserver
--audit-log-path=/var/log/kubernetes/audit.log
--audit-policy-file=/etc/kubernetes/audit-policy.yaml

# Audit policy to capture exec attempts
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    verbs: ["create"]
    resources:
      - group: ""
        resources: ["pods/exec"]
```

## Verification Commands

### Test 1: Network Policy Blocks Direct Access

```bash
# Should FAIL (connection refused)
kubectl exec -it <pod> -c <app-container> -- curl localhost:8080/api/data
# Expected: Connection refused or timeout (blocked by Network Policy)
```

### Test 2: RBAC Blocks kubectl exec

```bash
# As non-admin user, should FAIL
kubectl exec -it <pod> -- /bin/sh
# Expected: Error from server (Forbidden): pods "..." is forbidden: 
#           User "developer" cannot create resource "pods/exec"
```

### Test 3: mTLS Enforced

```bash
# Check mTLS mode
istioctl x describe pod <pod-name> | grep mTLS
# Expected: mTLS: STRICT
```

### Test 4: Legitimate Traffic Works

```bash
# Via Istio Gateway with JWT, should SUCCEED
curl -H "Authorization: Bearer $TOKEN" http://$GATEWAY/api/data
# Expected: 200 OK (or 403 if policy denies)
```

### Test 5: Audit Logs Capture Attempts

```bash
# Check audit logs for exec attempts
kubectl logs -n kube-system kube-apiserver-* | grep "pods/exec"
# Expected: Audit entries showing exec attempts and RBAC denials
```

## Tradeoffs Explained

| Mitigation | Network Bypass | API Bypass | Complexity | PoC Fit |
|------------|----------------|------------|------------|---------|
| Network Policies | ⭐⭐⭐⭐⭐ | ❌ No | ⭐⭐⭐ | ✅ Good |
| STRICT mTLS | ⭐⭐⭐⭐ | ❌ No | ⭐⭐ | ✅ Good |
| RBAC | ❌ No | ⭐⭐⭐⭐⭐ | ⭐⭐ | ✅ Critical |
| Service-Level Auth | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ❌ Violates ZTA |
| API Gateway | ⭐⭐⭐ | ❌ No | ⭐⭐⭐ | ⚠️ Redundant |
| Monitoring | ⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ⚠️ Future |

## More Information

**Resources**:
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kubernetes Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security/)
- [Istio PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/)
- [NIST SP 800-207](https://csrc.nist.gov/publications/detail/sp/800-207/final) - Zero Trust Architecture

**Future Enhancements**:
1. **OPA Gatekeeper**: Admission control for pod security policies
2. **Falco**: Runtime threat detection for container escapes
3. **Pod Security Admission**: Enforce security standards at pod creation
4. **Service mesh observability**: Kiali + Jaeger for traffic visualization

**Further denied Alternatives**:
- **OPA Gatekeeper only**: Admission control doesn't prevent runtime bypass
- **Envoy RBAC**: Redundant with OPA authorization

---

**Migration Path**:
- **Phase 0 (Current)**: Sidecar bypass possible (network + API)
- **Phase 1**: Add Network Policies (blocks network bypass)
- **Phase 2**: Enable STRICT mTLS (crypto-level defense)
- **Phase 3**: Implement RBAC (blocks API bypass)
- **Phase 4**: Add audit logging (detection + forensics)

**Decision Rationale**:

Network Policies + STRICT mTLS + RBAC provide comprehensive defense-in-depth:

1. **Network Policies**: Prevent network-level bypass (pods can't connect directly)
2. **STRICT mTLS**: Cryptographic assurance even if network policy fails
3. **RBAC**: Prevent API-level bypass via kubectl exec (critical gap in original decision)

**Why all three layers?**
- Network Policies alone: Vulnerable to kubectl exec
- mTLS alone: Doesn't prevent localhost or kubectl exec
- RBAC alone: Doesn't prevent network-level bypass

**Combined**: An attacker must bypass network isolation, obtain valid mTLS certificates AND have Kubernetes API exec permissions.

**Production Considerations**:
- **Breakglass procedures**: Emergency admin access for debugging
- **Audit all exec attempts**: Kubernetes audit logs + SIEM integration
- **Least privilege**: Grant exec only to specific namespaces/pods
- **Time-limited access**: Temporary elevated permissions via tools like Teleport

This layered approach aligns with Zero Trust principles and provides strong guarantees against sidecar bypass.