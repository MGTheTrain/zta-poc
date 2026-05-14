# ZTA PoC — developer commands
#
# PROJECT_ROOT anchors bind-mount paths in infra/compose/docker-compose.yml.
# It defaults to the repo root so running `make` outside a devcontainer
# Just Works; inside a devcontainer it's wired via remoteEnv in
# .devcontainer/devcontainer.json.
#
# OPA_POLICY_SET selects which folder under policies/opa/ gets mounted
# into the OPA container (rbac | rbac-rebac-time | advanced). The
# compose-use-* and k8s-use-* targets toggle it for you.

SHELL       := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

export PROJECT_ROOT   ?= $(CURDIR)
export OPA_POLICY_SET ?= rbac-rebac-time

COMPOSE_FILE := infra/compose/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_FILE)

UMBRELLA_CHART := ./infra/helm-charts/zta-poc

.PHONY: help compose-build compose-start compose-stop compose-restart compose-logs compose-clean compose-test \
        compose-use-one compose-use-three \
        open-keycloak list-policies test-opa \
        k8s-deploy k8s-test k8s-clean k8s-forward k8s-use-one k8s-use-three

help: ## Show this help
	@echo 'Usage: make [target]'
	@echo ''
	@echo "  PROJECT_ROOT   = $(PROJECT_ROOT)"
	@echo "  OPA_POLICY_SET = $(OPA_POLICY_SET)"
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

compose-build: ## [Compose] Rebuild all services (only the three backend services build locally; Envoy/Keycloak/OPA use upstream images)
	@echo " Rebuilding all services..."
	@$(COMPOSE) build
	@echo " Build complete"

compose-start: ## [Compose] Start all services
	@echo " Starting Zero Trust Architecture PoC..."
	@echo "   PROJECT_ROOT=$(PROJECT_ROOT)"
	@echo "   OPA_POLICY_SET=$(OPA_POLICY_SET)"
	@$(COMPOSE) up -d
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
	@$(COMPOSE) down

compose-restart: compose-stop compose-start ## [Compose] Restart all services

compose-logs: ## [Compose] Show logs
	@$(COMPOSE) logs -f

compose-clean: ## [Compose] Stop and remove everything
	@$(COMPOSE) down -v
	@docker system prune -f

compose-test: ## [Compose] Run integration tests
	@bash scripts/test-internal-services.sh docker

compose-use-one: ## [Compose] Use basic RBAC policies (remounts policies/opa/rbac into OPA)
	@echo " Switching OPA to policies/opa/rbac ..."
	@OPA_POLICY_SET=rbac $(COMPOSE) up -d --no-deps --force-recreate opa
	@echo " OPA now serving the 'rbac' policy set"

compose-use-three: ## [Compose] Use RBAC + ReBAC + Time-based policies (remounts policies/opa/rbac-rebac-time into OPA)
	@echo " Switching OPA to policies/opa/rbac-rebac-time ..."
	@OPA_POLICY_SET=rbac-rebac-time $(COMPOSE) up -d --no-deps --force-recreate opa
	@echo " OPA now serving the 'rbac-rebac-time' policy set"

# Kubernetes Targets

k8s-deploy: ## [K8s] Deploy ZTA PoC umbrella chart on a kind cluster (Istio + zta-poc)
	@bash scripts/deploy-to-kind.sh

k8s-clean: ## [K8s] Tear down the ZTA PoC and Istio (helm uninstall + namespace cleanup)
	@bash scripts/cleanup-kind.sh

k8s-redeploy: ## [K8s] Uninstall + install (full reset) ZTA PoC and Istio on a kind cluster
	@bash scripts/cleanup-kind.sh
	@bash scripts/deploy-to-kind.sh

k8s-test: ## [K8s] Run integration tests against the k8s deployment
	@bash scripts/test-internal-services.sh k8s

k8s-forward: ## [K8s] Port-forward all services
	@bash scripts/port-forward-in-kind.sh --all

k8s-use-one: ## [K8s] Use basic RBAC policies
	@bash scripts/load-opa-policies.sh rbac k8s

k8s-use-three: ## [K8s] Use RBAC + ReBAC + Time-based policies
	@bash scripts/load-opa-policies.sh rbac-rebac-time k8s