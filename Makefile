.PHONY: help start stop restart logs clean setup-keycloak test-admin test-user test-denied keycloak

help: ## Show this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

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
	@echo " Run 'make setup-keycloak' to configure Keycloak realm and users"

stop: ## Stop all services
	@docker compose down

restart: stop start ## Restart all services

logs: ## Show logs
	@docker compose logs -f

clean: ## Stop and remove everything
	@docker compose down -v
	@docker system prune -f

setup-keycloak: ## Configure Keycloak (realm, users, roles)
	@echo " Configuring Keycloak..."
	@bash scripts/setup-keycloak.sh
	@echo " Keycloak configured"

test-admin: ## Test with admin token (should access everything)
	@echo " Testing with admin user..."
	@bash scripts/test-access.sh admin

test-user: ## Test with regular user (GET only)
	@echo " Testing with regular user..."
	@bash scripts/test-access.sh user

test-denied: ## Test denied access scenarios
	@echo " Testing access denial..."
	@bash scripts/test-access.sh denied

keycloak: ## Open Keycloak in browser
	@echo "Opening Keycloak..."
	@open http://localhost:8180 2>/dev/null || xdg-open http://localhost:8180 2>/dev/null || echo "Open http://localhost:8180 in your browser"
