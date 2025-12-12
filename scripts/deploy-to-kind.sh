#!/bin/bash
set -e

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CLUSTER_NAME="kind"
SERVICES=("go-service" "python-service" "csharp-service")

# Chart versions
ISTIO_VERSION="1.24.2"
ISTIO_GATEWAY_VERSION="1.28.1"

OPA_VERSION="0.60.0-envoy"
KEYCLOAK_VERSION="23.0.4"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Setup & Deploy ZTA on Kind Cluster                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              INFRASTRUCTURE SETUP                             ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Add Helm repositories
echo -e "${YELLOW}📚 Step 1: Checking Helm repositories...${NC}"
REPOS_NEEDED=false

if ! helm repo list | grep -q "^istio"; then
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    REPOS_NEEDED=true
fi

[ "$REPOS_NEEDED" = true ] && helm repo update
echo -e "${GREEN}✓ Helm repositories configured${NC}"
echo ""

# Install Istio
echo -e "${YELLOW}🕸️  Step 2: Installing Istio ${ISTIO_VERSION}...${NC}"

if helm list -n istio-system | grep -q istio-base; then
    echo -e "${BLUE}  Istio base already installed, skipping...${NC}"
else
    helm install istio-base istio/base \
        -n istio-system --create-namespace \
        --version ${ISTIO_VERSION} --set defaultRevision=default \
        --wait --timeout 3m > /dev/null 2>&1 || true
fi

if helm list -n istio-system | grep -q istiod; then
    echo -e "${BLUE}  Istiod already installed, skipping...${NC}"
else
    helm install istiod istio/istiod \
        -n istio-system --version ${ISTIO_VERSION} \
        --wait --timeout 3m > /dev/null 2>&1 || true
fi

kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1 || true

if helm list -n istio-ingress | grep -q istio-ingressgateway; then
    echo -e "${BLUE}  Istio gateway already installed, skipping...${NC}"
else
    helm install istio-ingressgateway istio/gateway \
        -n istio-ingress --version ${ISTIO_GATEWAY_VERSION} \
        --wait --timeout 3m > /dev/null 2>&1 || true
fi

echo -e "${GREEN}✓ Istio installed${NC}"
echo ""

# Deploy OPA (NO ConfigMap - policies loaded dynamically)
echo -e "${YELLOW}🔐 Step 3: Deploying OPA...${NC}"

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
---
apiVersion: v1
kind: Service
metadata:
  name: opa
  namespace: default
spec:
  selector:
    app: opa
  ports:
  - name: http
    port: 8181
    targetPort: 8181
  - name: grpc
    port: 9191
    targetPort: 9191
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opa
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
    spec:
      containers:
      - name: opa
        image: openpolicyagent/opa:${OPA_VERSION}
        args:
        - "run"
        - "--server"
        - "--addr=0.0.0.0:8181"
        - "--diagnostic-addr=0.0.0.0:8282"
        - "--set=plugins.envoy_ext_authz_grpc.addr=:9191"
        - "--set=plugins.envoy_ext_authz_grpc.query=data.envoy.authz.allow"
        - "--set=decision_logs.console=true"
        ports:
        - name: http
          containerPort: 8181
        - name: grpc
          containerPort: 9191
        - name: diagnostic
          containerPort: 8282
        livenessProbe:
          httpGet:
            path: /health
            port: 8282
          initialDelaySeconds: 5
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /health?plugins
            port: 8282
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

if kubectl get deployment opa -n default &>/dev/null; then
    kubectl rollout status deployment/opa -n default --timeout=120s > /dev/null 2>&1 || {
        echo -e "${YELLOW}  OPA deployment exists but may not be ready, continuing...${NC}"
    }
else
    kubectl wait --for=condition=available --timeout=120s deployment/opa -n default > /dev/null 2>&1 || {
        echo -e "${YELLOW}  OPA starting (may take a moment)...${NC}"
        sleep 10
    }
fi

echo -e "${GREEN}✓ OPA deployed (policies loaded via 'make use-one/use-three')${NC}"
echo ""

# Install Keycloak
echo -e "${YELLOW}🔑 Step 4: Deploying Keycloak...${NC}"

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-realm-config
  namespace: default
data:
  demo-realm.json: |
    {
      "realm": "demo",
      "enabled": true,
      "sslRequired": "none",
      "clients": [
        {
          "clientId": "demo-client",
          "enabled": true,
          "publicClient": true,
          "directAccessGrantsEnabled": true,
          "standardFlowEnabled": true,
          "redirectUris": ["*"],
          "webOrigins": ["*"]
        }
      ],
      "roles": {
        "realm": [
          {"name": "admin", "description": "Administrator role"},
          {"name": "user", "description": "Standard user role"}
        ]
      },
      "users": [
        {
          "username": "alice",
          "enabled": true,
          "credentials": [{"type": "password", "value": "password", "temporary": false}],
          "realmRoles": ["admin"],
          "attributes": {"department": ["engineering"], "clearance_level": ["secret"]}
        },
        {
          "username": "bob",
          "enabled": true,
          "credentials": [{"type": "password", "value": "password", "temporary": false}],
          "realmRoles": ["user"],
          "attributes": {"department": ["sales"], "clearance_level": ["public"]}
        }
      ]
    }
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: default
spec:
  selector:
    app: keycloak
  ports:
  - name: http
    port: 8080
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}
        args:
        - "start-dev"
        - "--import-realm"
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "admin"
        - name: KC_HEALTH_ENABLED
          value: "true"
        - name: KC_METRICS_ENABLED
          value: "true"
        - name: KC_HTTP_RELATIVE_PATH
          value: "/"
        ports:
        - name: http
          containerPort: 8080
        volumeMounts:
        - name: realm-config
          mountPath: /opt/keycloak/data/import
          readOnly: true
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          limits:
            memory: 1Gi
            cpu: 1000m
          requests:
            memory: 512Mi
            cpu: 500m
      volumes:
      - name: realm-config
        configMap:
          name: keycloak-realm-config
EOF

if kubectl get deployment keycloak -n default &>/dev/null; then
    kubectl rollout status deployment/keycloak -n default --timeout=180s > /dev/null 2>&1 || {
        echo -e "${YELLOW}  Keycloak deployment exists but may not be ready, continuing...${NC}"
    }
else
    kubectl wait --for=condition=available --timeout=180s deployment/keycloak -n default > /dev/null 2>&1 || {
        echo -e "${YELLOW}  Keycloak starting (may take 1-2 minutes)...${NC}"
        sleep 15
    }
fi

echo -e "${GREEN}✓ Keycloak deployed${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              SERVICE DEPLOYMENT                               ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Create shared Gateway
echo -e "${YELLOW}🚪 Step 5: Creating Istio Gateway and VirtualServices...${NC}"
cat <<EOF | kubectl apply -f - > /dev/null
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: zta-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.local"
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: go-service
  namespace: default
spec:
  hosts:
  - go-service.local
  gateways:
  - zta-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: go-service
        port:
          number: 8080
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: python-service
  namespace: default
spec:
  hosts:
  - python-service.local
  gateways:
  - zta-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: python-service
        port:
          number: 8080
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: csharp-service
  namespace: default
spec:
  hosts:
  - csharp-service.local
  gateways:
  - zta-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: csharp-service
        port:
          number: 8080
EOF
kubectl label namespace default istio-injection=enabled --overwrite > /dev/null 2>&1
echo -e "${GREEN}✓ Gateway and VirtualServices created${NC}"
echo ""

# Build images
echo -e "${YELLOW}📦 Step 6: Building and loading images...${NC}"

for service in "${SERVICES[@]}"; do
    IMAGE_NAME="zta-poc-${service}:latest"
    
    if ! docker image inspect ${IMAGE_NAME} >/dev/null 2>&1; then
        docker build -t ${IMAGE_NAME} -f services/${service}/Dockerfile services/${service} > /dev/null
    fi
    
    if ! docker exec ${CLUSTER_NAME}-control-plane crictl images | grep -q "zta-poc-${service}"; then
        kind load docker-image ${IMAGE_NAME} --name ${CLUSTER_NAME}
    fi
done
echo -e "${GREEN}✓ Images ready${NC}"
echo ""

# Deploy services
echo -e "${YELLOW}⎈ Step 7: Deploying services...${NC}"
for service in "${SERVICES[@]}"; do
    case ${service} in
        go-service|python-service|csharp-service)
            SERVICE_PORT=8080
            REPO="zta-poc-${service}"
            ;;
    esac
    
    helm upgrade --install ${service} ./charts/services/${service} \
        --set image.repository=${REPO} \
        --set image.tag=latest \
        --set image.pullPolicy=Never \
        --set service.type=ClusterIP \
        --set service.port=${SERVICE_PORT} \
        --set service.targetPort=${SERVICE_PORT} \
        --set podLabels.security=zta-enabled \
        --set podLabels.version=v1 \
        --set-string podAnnotations."sidecar\.istio\.io/inject"="true" \
        --set istio.gateway.enabled=false \
        --set istio.virtualService.enabled=true \
        --set istio.virtualService.hosts[0]="${service}.local" \
        --set istio.virtualService.gateways[0]=zta-gateway \
        --set istio.virtualService.http[0].match[0].uri.prefix="/" \
        --set istio.virtualService.http[0].route[0].destination.host=${service} \
        --set istio.virtualService.http[0].route[0].destination.port.number=${SERVICE_PORT} \
        --set istio.mtls.enabled=true \
        --set istio.mtls.mode=STRICT \
        --set env[0].name=SERVICE_NAME \
        --set env[0].value=${service} \
        --set env[1].name=SERVICE_PORT \
        --set env[1].value=${SERVICE_PORT} \
        --wait --timeout 3m > /dev/null
done
echo -e "${GREEN}✓ Services deployed${NC}"


if ! kubectl get configmap istio -n istio-system -o yaml | grep -q "opa-ext-authz"; then
    kubectl patch configmap istio -n istio-system --type merge -p '{
      "data": {
        "mesh": "extensionProviders:\n- name: opa-ext-authz\n  envoyExtAuthzGrpc:\n    service: opa.default.svc.cluster.local\n    port: 9191\n"
      }
    }' > /dev/null
    
    # Restart istiod to pick up config
    kubectl rollout restart deployment/istiod -n istio-system > /dev/null 2>&1
    kubectl rollout status deployment/istiod -n istio-system --timeout=2m > /dev/null 2>&1
    echo -e "${GREEN}✓ Istio meshConfig updated and istiod restarted${NC}"
else
    echo -e "${BLUE}  OPA provider already configured${NC}"
fi
echo ""

# Configure OPA Authorization (WITHOUT RequestAuthentication - OPA handles JWT)
echo -e "${YELLOW}🔒 Step 8: Configuring OPA Authorization...${NC}"

# Step 8a: Configure meshConfig
if ! kubectl get configmap istio -n istio-system -o yaml | grep -q "opa-ext-authz-grpc"; then
    kubectl patch configmap istio -n istio-system --type merge -p '{
      "data": {
        "mesh": "extensionProviders:\n- name: opa-ext-authz-grpc\n  envoyExtAuthzGrpc:\n    service: opa-ext-authz-grpc.local\n    port: 9191\n"
      }
    }' > /dev/null
    
    kubectl rollout restart deployment/istiod -n istio-system > /dev/null 2>&1
    kubectl rollout status deployment/istiod -n istio-system --timeout=2m > /dev/null 2>&1
    echo -e "${GREEN}✓ Istio meshConfig updated${NC}"
else
    echo -e "${BLUE}  OPA provider already configured${NC}"
fi

# Step 8b: Create ServiceEntry for OPA
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
---
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: opa-ext-authz-grpc
  namespace: default
spec:
  hosts:
  - opa-ext-authz-grpc.local
  endpoints:
  - address: opa.default.svc.cluster.local
  ports:
  - name: grpc
    number: 9191
    protocol: GRPC
  resolution: DNS
  location: MESH_INTERNAL
EOF

# Step 8c: Create AuthorizationPolicy
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
---
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: default
spec:
  selector:
    matchLabels:
      security: zta-enabled
  jwtRules:
  - issuer: "http://localhost:8180/realms/demo"
    jwksUri: "http://keycloak.default.svc.cluster.local:8080/realms/demo/protocol/openid-connect/certs"
    forwardOriginalToken: true
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: delegate-to-opa
  namespace: default
spec:
  selector:
    matchLabels:
      security: zta-enabled
  action: CUSTOM
  provider:
    name: opa-ext-authz-grpc
  rules:
  - {}
EOF

# Step 8d: Restart services to pick up config
kubectl rollout restart deployment go-service python-service csharp-service > /dev/null 2>&1
kubectl rollout status deployment go-service --timeout=2m > /dev/null 2>&1
kubectl rollout status deployment python-service --timeout=2m > /dev/null 2>&1
kubectl rollout status deployment csharp-service --timeout=2m > /dev/null 2>&1

echo -e "${GREEN}✓ OPA authorization configured${NC}"
echo ""

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Deployment Complete                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}Infrastructure:${NC}"
echo "  Istio:      ${ISTIO_VERSION}"
echo "  Keycloak:   ${KEYCLOAK_VERSION}"
echo "  OPA:        ${OPA_VERSION}"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Port-forward (in separate terminal):  make k8s-forward"
echo "  2. Load policies:                        make k8s-use-one"
echo "  3. Run tests:                            make k8s-test"
echo ""

echo -e "${GREEN}✓ Setup complete${NC}"