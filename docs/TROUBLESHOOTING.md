# Troubleshooting Commands

## Quick Start (Both Environments)

### Docker Compose
```bash
# 1. Start services
make compose-start

# 2. Load policies
make compose-use-three

# 3. Run automated tests
make compose-test
```

### Kubernetes (Kind)
```bash
# 1. Deploy infrastructure and services
make k8s-deploy

# 2. Port-forward (in separate terminal)
make k8s-forward

# 3. Load policies
make k8s-use-one      # RBAC only
make k8s-use-three    # RBAC + ReBAC + Time-based

# 4. Run automated tests (auto-detects K8s and loaded policies)
make k8s-test
```

## Essential Troubleshooting Commands

### Check Service Status

**Docker Compose:**
```bash
# View all containers
docker compose ps

# Check specific service logs
docker logs keycloak --tail 50
docker logs opa --tail 50
docker logs go-service-envoy --tail 50

# Follow logs in real-time
docker compose logs -f
```

**Kubernetes:**
```bash
# View all pods
kubectl get pods -A

# Check pod status
kubectl get pods -l security=zta-enabled

# Check logs
kubectl logs -l app=keycloak
kubectl logs -l app=opa
kubectl logs -l app.kubernetes.io/name=go-service -c go-service
kubectl logs -l app.kubernetes.io/name=go-service -c istio-proxy

# Describe pod for events
kubectl describe pod <pod-name>
```

### Verify Connectivity

**Docker Compose:**
```bash
# Test without auth (should get 401)
curl -v http://localhost:9001/api/data

# Test with token
TOKEN=$(curl -s -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token \
  -d 'client_id=demo-client' -d 'username=alice' -d 'password=password' \
  -d 'grant_type=password' | jq -r '.access_token')
curl -v -H "Authorization: Bearer $TOKEN" http://localhost:9001/api/data
```

**Kubernetes:**
```bash
# Check Gateway
kubectl get gateway -n default

# Check VirtualServices
kubectl get virtualservice -n default

# Test without auth (should get 401)
curl -v -H 'Host: go-service.local' http://localhost:8080/api/data

# Test with token
TOKEN=$(curl -s -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token \
  -d 'client_id=demo-client' -d 'username=alice' -d 'password=password' \
  -d 'grant_type=password' | jq -r '.access_token')
curl -v -H 'Host: go-service.local' -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/data
```

### Check OPA Policies

**Both environments:**
```bash
# List loaded policies
curl -s http://localhost:8181/v1/policies | jq -r '.result[].id'

# Or use make target
make list-policies

# View specific policy
curl -s http://localhost:8181/v1/policies/authz | jq .

# Test policy decision
curl -s -X POST http://localhost:8181/v1/data/envoy/authz/allow \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "attributes": {
        "request": {
          "http": {
            "method": "GET",
            "path": "/api/data"
          }
        }
      }
    }
  }' | jq .
```

### Verify Keycloak

**Both environments:**
```bash
# Get token (should return JWT)
curl -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token \
  -d 'client_id=demo-client' \
  -d 'username=alice' \
  -d 'password=password' \
  -d 'grant_type=password' | jq .

# Decode JWT at jwt.io or:
TOKEN=$(curl -s -X POST http://localhost:8180/realms/demo/protocol/openid-connect/token \
  -d 'client_id=demo-client' -d 'username=alice' -d 'password=password' \
  -d 'grant_type=password' | jq -r '.access_token')
PAYLOAD=$(echo $TOKEN | cut -d'.' -f2)
PADDED=$(printf '%s' "$PAYLOAD"; rem=$(( ${#PAYLOAD} % 4 )); [ $rem -ne 0 ] && printf '%*s' $((4 - rem)) '' | tr ' ' '=' )
echo "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null

# Open Keycloak admin console
make open-keycloak
# Login: admin/admin
```

### Istio/Envoy Debugging (Kubernetes only)

```bash
# Check Istio installation
kubectl get pods -n istio-system
kubectl get pods -n istio-ingress

# View Istio proxy config
kubectl exec -it <pod-name> -c istio-proxy -- curl localhost:15000/config_dump

# Check mTLS status
istioctl x describe pod <pod-name>

# View Envoy clusters
kubectl exec -it <pod-name> -c istio-proxy -- curl localhost:15000/clusters

# Check certificate
kubectl exec -it <pod-name> -c istio-proxy -- curl localhost:15000/certs
```

### Network Debugging

**Docker Compose:**
```bash
# Test internal connectivity
docker exec go-service-envoy curl http://localhost:8080/health

# Check Envoy admin interface
curl http://localhost:9901/stats
curl http://localhost:9901/clusters
```

**Kubernetes:**
```bash
# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://go-service:8080/health

# Check service endpoints
kubectl get endpoints

# Test Istio Gateway
kubectl port-forward -n istio-ingress svc/istio-ingressgateway 8080:80 &
curl -v -H 'Host: go-service.local' http://localhost:8080/health
```

## Common Issues

### Issue: 401 Unauthorized

**Docker Compose:**
```bash
# Check if Envoy is validating JWT
docker logs go-service-envoy | grep -i jwt

# Verify token is valid
PAYLOAD=$(echo $TOKEN | cut -d'.' -f2)
PADDED=$(printf '%s' "$PAYLOAD"; rem=$(( ${#PAYLOAD} % 4 )); [ $rem -ne 0 ] && printf '%*s' $((4 - rem)) '' | tr ' ' '=' )
echo "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null
```

**Kubernetes:**
```bash
# Check if Istio is configured for JWT
kubectl get requestauthentication -n default

# Check Istio proxy logs
kubectl logs <pod-name> -c istio-proxy | grep -i jwt
```

### Issue: 403 Forbidden

```bash
# Check OPA decision
curl -s http://localhost:8181/v1/data/envoy/authz/allow | jq .

# View OPA decision logs
docker logs opa -f | grep Decision  # Docker Compose
kubectl logs -l app=opa -f | grep Decision  # Kubernetes

# Verify token has correct roles
PAYLOAD=$(echo $TOKEN | cut -d'.' -f2)
PADDED=$(printf '%s' "$PAYLOAD"; rem=$(( ${#PAYLOAD} % 4 )); [ $rem -ne 0 ] && printf '%*s' $((4 - rem)) '' | tr ' ' '=' )
echo "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r .realm_access.roles
```

### Issue: Port-forward not working (Kubernetes)

```bash
# Check if services exist
kubectl get svc

# Kill existing port-forwards
pkill -f "port-forward"

# Restart port-forward
make k8s-forward

# Manual port-forward with verbose
kubectl port-forward -v=9 -n istio-ingress svc/istio-ingressgateway 8080:80
```

### Issue: Services not starting (Kubernetes)

```bash
# Check pod events
kubectl get events --sort-by='.lastTimestamp'

# Check if images are loaded
docker exec kind-control-plane crictl images | grep zta-poc

# Redeploy
make k8s-clean
make k8s-deploy
```

## Reset Everything

**Docker Compose:**
```bash
make compose-clean
make compose-start
make compose-use-three
```

**Kubernetes:**
```bash
make k8s-clean
make k8s-deploy
```