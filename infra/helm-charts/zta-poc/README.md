# zta-poc — umbrella chart

Single deployable unit for the Zero Trust Architecture PoC on Kubernetes.

## What's in here

```
zta-poc/                       (this chart — orchestration only)
├── Chart.yaml                 deps: zta-platform + 3 service charts
├── values.yaml                source of truth for the k8s deploy
└── templates/
    ├── gateway.yaml           Istio Gateway
    ├── virtualservices.yaml   per-service VirtualService
    ├── service-entry-opa.yaml ServiceEntry → OPA
    ├── request-authentication.yaml
    ├── authorization-policy.yaml  delegates to OPA via ext_authz
    ├── hook-rbac.yaml         ServiceAccount + Role + RoleBinding for hooks
    ├── hook-patch-meshconfig.yaml  pre-install: patch configmap/istio
    └── hook-restart-services.yaml  post-install: roll service deployments

zta-platform/                  (sibling subchart)
├── Chart.yaml
├── values.yaml
├── files/
│   ├── keycloak/              demo-realm.json (staged from configs/)
│   └── opa-policies/          policy bundles (staged from policies/opa-k8s/)
│       ├── rbac/
│       ├── rbac-rebac-time/
│       └── advanced/
└── templates/
    ├── opa-deployment.yaml
    ├── opa-service.yaml
    ├── opa-policies-configmap.yaml
    ├── keycloak-deployment.yaml
    ├── keycloak-service.yaml
    └── keycloak-realm-configmap.yaml
```

## Why two charts

- The umbrella holds resources that **tie subcharts together** (Istio CRDs that
  reference both OPA and the service Deployments).
- `zta-platform` holds the OPA + Keycloak workloads themselves. It's a separate
  chart because they're conceptually their own component and could be lifted
  into another project as-is.
- The three service charts are unchanged leaf charts under
  `infra/helm-charts/services/`.

## Why Istio is NOT a dependency

Istio's own docs recommend keeping `istio-base`, `istiod`, and the gateway as
three independent Helm releases so CRDs install before controllers, and
controllers install before gateways. Folding any of them into a subchart
fights the tool. So `scripts/deploy-to-kind.sh` installs Istio first, then
calls `helm upgrade --install` on this umbrella.

## Staging

The chart's `files/` directory has to be populated before `helm install`,
because Helm's `Files.Glob` can't read content outside the chart directory.
`scripts/deploy-to-kind.sh` handles this — it copies:

  policies/opa-k8s/<set>/*.rego  →  infra/helm-charts/zta-platform/files/opa-policies/<set>/
  configs/keycloak/demo-realm.json → infra/helm-charts/zta-platform/files/keycloak/

This is the same trick rucio-storage-testbed uses for its `files/` tree.

## Switching policy sets

```sh
helm upgrade --reuse-values \
  --set zta-platform.opa.policySet=rbac \
  zta-poc ./infra/helm-charts/zta-poc
```

The OPA Pod's annotation includes a checksum of the policies ConfigMap,
so a new policy set forces a Pod roll without further intervention.
