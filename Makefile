.PHONY: help start build stop restart logs clean test open-keycloak use-one use-three list-policies

help: ## Show this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

use-one: ## Use basic RBAC policies
	@bash scripts/load-opa-policies.sh rbac

use-three: ## Use RBAC + ReBAC + Time-based policies
	@bash scripts/load-opa-policies.sh rbac-rebac-time

list-policies: ## List current policies
	@echo " Policies loaded in OPA:"
	@curl -s http://localhost:8181/v1/policies | jq -r '.result[].id // "No policies"'

build: ## Rebuild all services
	@echo " Rebuilding all services..."
	@docker compose build --no-cache
	@echo " Build complete"

start: ## Start all services
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

stop: ## Stop all services
	@docker compose down

restart: stop start ## Restart all services

logs: ## Show logs
	@docker compose logs -f

clean: ## Stop and remove everything
	@docker compose down -v
	@docker system prune -f

test: ## Auto-detect policy set and run appropriate tests
	@bash scripts/test-internal-services.sh

open-keycloak: ## Open Keycloak in browser
	@echo "Opening Keycloak..."
	@open http://localhost:8180 2>/dev/null || xdg-open http://localhost:8180 2>/dev/null || echo "Open http://localhost:8180 in your browser"

test-opa: ## Test OPA policies directly (detects use-one/use-three)
	@bash scripts/test-opa-policy.sh