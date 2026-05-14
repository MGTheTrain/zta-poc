## TODO: Key Decisions to be Made for Distributed System

| Decision Title | Status | Owner | Description | Comments |
|---|---|---|---|---|
| Service Discovery and Load Balancing | Completed | Architecture Team | Locked into Kubernetes-native DNS and Istio Envoy routing via ServiceEntry based on ADR-001. | Do not introduce Consul; stick to Istio-native service discovery mechanisms. |
| Data Consistency and Distributed Transactions | Pending | Platform Engineering | Decide on consistency model (strong vs. eventual) and distributed transaction protocol (e.g. saga). | Evaluate how OPA/OpenFGA policy caching handles eventually consistent database updates. |
| API Gateway Design | In-Progress | Security Team | Evaluate standardizing on the Kubernetes Gateway API (using existing httproute.yaml charts) vs. adding an edge gateway (e.g., Kong). | Assess security model (OAuth, JWT) continuity from edge through the Istio Ingress Gateway. |
| Fault Tolerance and Resilience Patterns | In-Progress | Platform Engineering | Implement circuit breakers, retries, timeouts, and bulkhead patterns. | Do not use legacy application libraries like Hystrix. Enforce these patterns natively via Istio DestinationRule CRDs. |
| Message Queuing and Event Streaming | Pending | Platform Engineering | Evaluate message brokers like Kafka, RabbitMQ, or NATS for async communication. | Critical: Define how asynchronous workers validate user JWTs or context after the HTTP session terminates. |
| Identity and Access Management (IAM) | Completed | Security Team | Service identity and authorization infrastructure finalized using Keycloak (OIDC/JWT), Istio (RequestAuthentication), and OPA. | Future scope strictly handles token propagation and fine-grained ReBAC/OpenFGA evaluation hooks. |
| Data Partitioning and Sharding Strategy | Pending | Platform Engineering | Define strategy for partitioning data (e.g. by customer ID) and sharding databases. | Align data residency rules with context-aware OPA/ABAC policies. |
| Logging, Monitoring and Observability | In-Progress | Platform Engineering | Implement centralized logging, metrics collection, and distributed tracing. | Integrate Istio proxy metrics natively with Prometheus and Jaeger to audit OPA evaluation latency. |
| Deployment Strategy and CI/CD Pipeline | Pending | Platform Engineering | Decide on CI/CD tools and progressive delivery strategies (Blue-Green, Canary, Feature Flags). | Leverage Istio VirtualService weight adjustments for automated traffic-shifting canary releases. |
| Scaling Strategy | Pending | Architecture Team | Choose horizontal vs. vertical scaling and implement auto-scaling via HPA templates included in Helm charts. | Profile resource overhead of Envoy sidecars (~100MB+/pod) when designing cluster scaling triggers. |
| Data Encryption and Privacy | Completed | Security Team | Enforce STRICT mTLS at the transport layer using Istio PeerAuthentication as mandated by ADR-002. | Future scope shifts to validating compliance frameworks (GDPR, HIPAA) for data-at-rest. |
| Service Level Objectives (SLOs), SLIs and SLAs | Pending | Architecture Team | Define SLOs, SLIs, and SLAs for critical services. | Factor in the latency added by synchronous out-of-process OPA ext_authz network hops. |
| Edge Computing and CDN Integration | Pending | Platform Engineering | Evaluate need for edge computing or CDN for reduced latency. | Ensure edge security architectures gracefully pass token identities down to the local service mesh. |
| Data Backup and Disaster Recovery | Pending | Platform Engineering | Design backup and disaster recovery strategy. | Ensure stateful workloads (like the Keycloak cluster storage) maintain high availability across failures. |

------------------------------
## How to Use This Table:

* Status: Use this column to track whether each decision is pending, in-progress, or completed.
* Owner: Assign the team or individual responsible for making each decision. Modernized to reflect Platform Engineering / Security ownership over traditional DevOps.
* Description: Brief description of what needs to be decided.
* Comments: Real-world technical constraints, dependencies, and rules derived directly from the active PoC codebase.

------------------------------
## Example Usage in an ADR:
You can reference this TODO table in any ADR as a way to ensure that each decision is captured and followed up on. For instance:
------------------------------
## Context and Problem Statement:
In our distributed system, there are several architectural decisions yet to be finalized. These decisions impact various aspects of system security, resilience, scalability, and operational complexity.
## Decision Drivers:

* Ensure all decisions are aligned with Zero Trust principles.
* Maintain scalability and fault tolerance at a system-wide level.
* Minimize operational complexity, leveraging infrastructure capabilities established during the PoC phase.
