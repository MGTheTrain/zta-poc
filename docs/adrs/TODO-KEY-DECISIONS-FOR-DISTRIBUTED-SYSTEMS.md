### TODO: Key Decisions to be Made for Distributed System

| Decision Title                                      | Status  | Owner                | Description                                                                                                                                | Comments                                                         |
| --------------------------------------------------- | ------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| **Service Discovery and Load Balancing**            | Pending | Architecture Team    | Choose between Kubernetes native service discovery vs. external service discovery tools (e.g. Consul). Determine load balancing strategy. | Review service discovery tools compatibility with Istio.         |
| **Data Consistency and Distributed Transactions**   | Pending | Platform Engineering | Decide on consistency model (strong vs. eventual) and distributed transaction protocol (e.g. saga).                                       | Evaluate impact on latency and consistency.                      |
| **API Gateway Design**                              | Pending | Security Team        | Select between centralized API Gateway (e.g. Kong) or decentralized approach. Define security model (OAuth, JWT).                         | Assess future scalability needs.                                 |
| **Fault Tolerance and Resilience Patterns**         | Pending | DevOps               | Implement circuit breakers, retries, timeouts and bulkhead patterns.                                                                      | Need to investigate tools for resilience (e.g. Istio, Hystrix). |
| **Message Queuing and Event Streaming**             | Pending | Platform Engineering | Evaluate message brokers like Kafka, RabbitMQ or NATS for async communication.                                                            | Consider durability and message processing guarantees.           |
| **Identity and Access Management (IAM)**            | Pending | Security Team        | Decide on service identity (SPIFFE, JWT, OAuth) and authorization model (RBAC, ABAC, PBAC).                                                | Align IAM with Zero Trust principles.                            |
| **Data Partitioning and Sharding Strategy**         | Pending | Platform Engineering | Define strategy for partitioning data (e.g. by customer ID) and sharding databases.                                                       | Consider scalability and latency.                                |
| **Logging, Monitoring and Observability**          | Pending | DevOps               | Implement centralized logging, monitoring and distributed tracing (e.g. Prometheus, Jaeger).                                             | Need to integrate with existing observability stack.             |
| **Deployment Strategy and CI/CD Pipeline**          | Pending | DevOps               | Decide on CI/CD tools and deployment strategies (Blue-Green, Canary, Feature Flags).                                                       | Ensure minimal downtime during deployments.                      |
| **Scaling Strategy**                                | Pending | Architecture Team    | Choose horizontal vs. vertical scaling and implement auto-scaling.                                                                         | Assess costs and performance implications.                       |
| **Data Encryption and Privacy**                     | Pending | Security Team        | Decide on encryption standards for data-at-rest and data-in-transit.                                                                       | Ensure compliance with GDPR, HIPAA, etc.                         |
| **Service Level Objectives (SLOs), SLIs and SLAs** | Pending | Architecture Team    | Define SLOs, SLIs and SLAs for critical services.                                                                                         | Align with business needs for uptime and performance.            |
| **Edge Computing and CDN Integration**              | Pending | Platform Engineering | Evaluate need for edge computing or CDN for reduced latency.                                                                               | Assess integration with service mesh and platform.               |
| **Data Backup and Disaster Recovery**               | Pending | Platform Engineering | Design backup and disaster recovery strategy.                                                                                              | Ensure high availability and fault tolerance.                    |

---

### How to Use This Table:

* **Status**: Use this column to track whether each decision is pending, in-progress or completed.
* **Owner**: Assign the team or individual responsible for making each decision.
* **Description**: Brief description of what needs to be decided.
* **Comments**: Add any specific notes, concerns or dependencies related to the decision.

---

### Example Usage in an ADR:

You can reference this **TODO** table in any ADR as a way to ensure that each decision is captured and followed up on. For instance:

---

### Context and Problem Statement:

In our distributed system, there are several architectural decisions yet to be finalized. These decisions impact various aspects of system security, resilience, scalability and operational complexity.

### Decision Drivers:

* Ensure all decisions are aligned with **Zero Trust** principles.
* Maintain scalability and fault tolerance at a system-wide level.
* Minimize operational complexity, especially during the PoC phase.