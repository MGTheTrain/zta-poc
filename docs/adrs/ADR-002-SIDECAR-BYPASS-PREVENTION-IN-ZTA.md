---
parent: Decisions
nav_order: 002
title: Sidecar Bypass Prevention Strategy
status: proposed
date: 2025-12-14
decision-makers: Architecture Team, Security Team
consulted: Platform Engineering, Development Teams
informed: All Engineering
---

# Sidecar Bypass Prevention: Defense-in-Depth Strategy

## Context and Problem Statement

In our Istio-based Zero Trust Architecture PoC, Envoy sidecars enforce JWT validation and OPA authorization policies. However, the sidecar architecture introduces bypass risks through two attack vectors: (1) direct network connections to application ports bypassing the proxy, and (2) API-level access via `kubectl exec` to containers. How do we prevent sidecar bypass while maintaining reasonable operational complexity for a PoC environment?

## Decision Drivers

* **Zero Trust Principle**: Never trust, always verify—assume breach and prevent lateral movement
* **Defense in Depth**: Multiple independent security layers required (single-layer protection insufficient)
* **Attack Vector Coverage**: Must address both network-level and API-level bypass attempts
* **Kubernetes Native**: Leverage platform security primitives where possible
* **PoC Constraints**: Balance security rigor with operational complexity appropriate for demonstration
* **Auditability**: Enable detection and logging of bypass attempts for forensic analysis

## Considered Options

* **Network Policies Only** - Kubernetes NetworkPolicy to restrict pod-to-pod traffic
* **STRICT mTLS Only** - Istio PeerAuthentication in STRICT mode requiring mutual TLS
* **RBAC Only** - Kubernetes RBAC to restrict `kubectl exec` access
* **Defense-in-Depth (Combined)** - Network Policies + STRICT mTLS + RBAC together
* **Service-Level Authorization** - Fallback authentication/authorization in each application

## Decision Outcome

Chosen option: **Defense-in-Depth (Combined approach)**, because single-layer defenses leave exploitable gaps while layered security ensures an attacker must bypass network isolation, cryptographic authentication, AND API access controls. Network Policies prevent direct pod-to-pod connections, STRICT mTLS provides cryptographic assurance even if network policies fail, and RBAC blocks API-level container access via `kubectl exec`.

This approach aligns with Zero Trust principles: even if one layer is compromised or misconfigured, the remaining layers continue to enforce security policies.

### Consequences

* Good, because network-level isolation physically blocks direct application port access
* Good, because cryptographic mTLS validation provides defense even if network policies are bypassed
* Good, because RBAC restrictions prevent API-level bypass through Kubernetes API, a critical gap in network-only approaches
* Good, because Kubernetes-native mechanisms require no additional infrastructure components
* Good, because multiple independent failure domains—attacker must compromise network, certificates, AND API authorization
* Bad, because network policies increase configuration complexity and debugging difficulty
* Bad, because RBAC restrictions impact developer workflows, requiring breakglass procedures for legitimate debugging
* Bad, because multiple security layers increase operational overhead and troubleshooting complexity
* Neutral, because monitoring and audit logging recommended but not implemented in PoC scope

### Confirmation

Decision validated through:
- Network policy enforcement verified by testing direct pod-to-pod connection attempts (expected: connection refused)
- STRICT mTLS mode verified through Istio configuration inspection (expected: plaintext traffic rejected)
- RBAC verified by attempting `kubectl exec` as non-privileged user (expected: Forbidden error)
- End-to-end application functionality maintained through Istio Gateway with all security layers active
- Automated test suites passing with all policies enabled

Supporting validation scripts documented in repository for reproducibility.

## Pros and Cons of the Options

### Network Policies Only

* Good, because prevents direct network-level bypass at the packet level
* Good, because Kubernetes-native with no additional components required
* Good, because CNI-level enforcement provides strong isolation guarantees
* Good, because policy violations can be logged by network plugin for audit
* Bad, because CNI-dependent—requires compatible network plugin (Calico, Cilium; kindnet supports NetworkPolicy)
* Bad, because complex debugging when legitimate traffic blocked by misconfiguration
* Bad, because does NOT prevent API-level bypass via `kubectl exec` to application container
* Bad, because localhost connections within pod remain possible if attacker gains container access

### STRICT mTLS Only

* Good, because cryptographic identity verification at transport layer
* Good, because defense persists even if network policies bypassed or misconfigured
* Good, because Istio-native configuration with automatic certificate management
* Good, because mutual authentication ensures both client and server identity validation
* Bad, because does NOT prevent localhost connections within same pod
* Bad, because does NOT prevent API-level bypass via `kubectl exec`
* Bad, because certificate management introduces operational complexity (though automated by Istio)
* Neutral, because requires trust in Istio CA or external certificate authority

### RBAC Only

* Good, because prevents API-level bypass through Kubernetes API server
* Good, because Kubernetes-native RBAC with auditable access logs
* Good, because fine-grained control over container exec permissions
* Good, because essential defense often overlooked in network-focused security
* Bad, because restricts legitimate developer workflows requiring breakglass procedures
* Bad, because does NOT prevent network-level bypass if attacker gains pod network access
* Bad, because requires careful permission design to balance security and operational needs
* Neutral, because organizational RBAC policies may conflict with development practices

### Defense-in-Depth (Combined)

* Good, because multiple independent security layers—attacker must bypass network, crypto, AND API controls
* Good, because aligns with Zero Trust architecture principles
* Good, because comprehensive coverage of network-level, transport-level, and API-level attacks
* Good, because each layer provides value independently while strengthening overall security
* Good, because graceful degradation—misconfiguration of one layer doesn't eliminate all protection
* Bad, because highest configuration complexity of all options
* Bad, because debugging requires understanding interactions between multiple security systems
* Bad, because increases operational overhead for deployment and maintenance
* Bad, because developer friction from combined restrictions may require sophisticated breakglass procedures

### Service-Level Authorization

* Good, because last line of defense if infrastructure security fails
* Good, because independent of mesh or platform configuration
* Good, because provides application-specific authorization logic
* Bad, because requires code changes in every application
* Bad, because violates Zero Trust principle of centralized policy enforcement
* Bad, because not scalable—duplicates authorization logic across services
* Bad, because conflicts with OPA-based centralized policy architecture
* Neutral, because may be appropriate for defense-in-depth but not as primary mechanism

## More Information

**Decision Rationale**:
Single-layer defenses create exploitable gaps. An attacker who bypasses Network Policies through misconfiguration still faces mTLS rejection. An attacker with valid certificates still cannot use `kubectl exec` without RBAC permissions. This layered approach ensures no single point of failure.

**Attack Vector Coverage**:
- **Network-level bypass** (direct pod-to-pod connection): Blocked by Network Policies
- **Transport-level bypass** (no TLS certificate): Blocked by STRICT mTLS  
- **API-level bypass** (`kubectl exec`): Blocked by RBAC
- **Combined attack** (all three): Requires compromising network isolation, obtaining valid certificates, AND having Kubernetes API permissions

**Production Considerations**:
- Implement audit logging for `kubectl exec` attempts and Network Policy violations
- Design breakglass procedures for emergency debugging access
- Consider time-limited elevated permissions via tools like Teleport or Boundary
- Monitor for policy violations and failed mTLS handshakes as potential attack indicators

**Related Decisions**:
- ADR-001: Service Mesh Selection (Istio) - Provides STRICT mTLS capability

**Key Resources**:
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Istio PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/)
- [NIST SP 800-207 Zero Trust Architecture](https://csrc.nist.gov/publications/detail/sp/800-207/final)

**Re-evaluation Triggers**:
- If developer friction from RBAC restrictions becomes severe, consider more sophisticated access management
- If Network Policy debugging becomes prohibitive, evaluate CNI plugin alternatives or mesh-only security
- If transitioning to Istio Ambient Mesh (sidecar-less), re-evaluate bypass vectors