.PHONY: help compose-build compose-start compose-stop compose-restart compose-logs compose-clean compose-test open-keycloak use-one use-three list-policies test-opa \
        k8s-deploy k8s-test k8s-clean k8s-forward

help: ## Show this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Common targets (work for both):'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## \[Common\]/ {printf "  \033[35m%-18s\033[0m %s\n", $$1, substr($$2, 10)}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Docker Compose targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## \[Compose\]/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, substr($$2, 11)}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Kubernetes targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^k8s-[a-zA-Z_-]+:.*?## \[K8s\]/ {printf "  \033[33m%-18s\033[0m %s\n", $$1, substr($$2, 7)}' $(MAKEFILE_LIST)

# Common Targets (Both Docker Compose and Kubernetes)

list-policies: ## [Common] List current policies
	@echo " Policies loaded in OPA:"
	@curl -s http://localhost:8181/v1/policies | jq -r '.result[].id // "No policies"'

open-keycloak: ## [Common] Open Keycloak in browser
	@echo " Opening Keycloak..."
	@open http://localhost:8180 2>/dev/null || xdg-open http://localhost:8180 2>/dev/null || echo "Open http://localhost:8180"

test-opa: ## [Common] Test OPA policies directly
	@bash scripts/test-opa-policy.sh

# Docker Compose Targets

compose-build: ## [Compose] Rebuild all services
	@echo " Rebuilding all services..."
	@docker compose build
	@echo " Build complete"

compose-start: ## [Compose] Start all services
	@echo " Starting Zero Trust Architecture PoC..."
	@docker compose up -d
	@echo " Waiting for services to be healthy..."
	@sleep 10
	@echo " Services started"
	@echo ""
	@echo " Access Points:"
	@echo "  Keycloak:       http://localhost:8180 (admin/admin)"
	@echo "  Go Service:     http://localhost:9001"
	@echo "  Python Service: http://localhost:9002"
	@echo "  C# Service:     http://localhost:9003"
	@echo "  OPA:            http://localhost:8181"
	@echo ""

compose-stop: ## [Compose] Stop all services
	@docker compose down

compose-restart: compose-stop compose-start ## [Compose] Restart all services

compose-logs: ## [Compose] Show logs
	@docker compose logs -f

compose-clean: ## [Compose] Stop and remove everything
	@docker compose down -v
	@docker system prune -f

compose-test: ## [Compose] Run integration tests
	@bash scripts/test-internal-services.sh docker

compose-use-one: ## [Compose] Use basic RBAC policies
	@bash scripts/load-opa-policies.sh rbac docker

compose-use-three: ## [Compose] Use RBAC + ReBAC + Time-based policies
	@bash scripts/load-opa-policies.sh rbac-rebac-time docker

# Kubernetes Targets

k8s-deploy: ## [K8s] Deploy services with Istio
	@bash scripts/deploy-to-kind.sh

k8s-test: ## [K8s] Test Kubernetes deployment
	@bash scripts/test-internal-services.sh k8s

k8s-forward: ## [K8s] Port-forward all services
	@bash scripts/port-forward-in-kind.sh --all

k8s-clean: ## [K8s] Cleanup Kind resources
	@bash scripts/cleanup-kind.sh

k8s-use-one: ## [K8s] Use basic RBAC policies
	@bash scripts/load-opa-policies.sh rbac k8s

k8s-use-three: ## [K8s] Use RBAC + ReBAC + Time-based policies
	@bash scripts/load-opa-policies.sh rbac-rebac-time k8s