# ZTA PoC — developer commands

SHELL       := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

export PROJECT_ROOT   ?= $(CURDIR)
export OPA_POLICY_SET ?= rbac-rebac-time

RUNTIME ?= compose

COMPOSE_FILE   ?= infra/compose/docker-compose.yml
COMPOSE        := docker compose -f $(COMPOSE_FILE)
UMBRELLA_CHART := ./infra/helm-charts/zta-poc

PYTEST ?= pytest

# ── Runtime abstraction ─────────────────────────────────────────────

ifeq ($(RUNTIME),compose)
else ifeq ($(RUNTIME),k8s)
else
$(error Unsupported RUNTIME='$(RUNTIME)' (expected compose|k8s))
endif

# ── Help ────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show available targets
	@echo ''
	@echo 'Zero Trust Architecture PoC'
	@echo ''
	@echo '  PROJECT_ROOT   = $(PROJECT_ROOT)'
	@echo '  OPA_POLICY_SET = $(OPA_POLICY_SET)'
	@echo '  RUNTIME        = $(RUNTIME)'
	@echo ''
	@echo 'Usage:'
	@echo '  make <target> [RUNTIME=compose|k8s]'
	@echo ''
	@awk 'BEGIN {FS = ":.*?## "}; /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Common ──────────────────────────────────────────────────────────

.PHONY: open-keycloak list-policies test-opa lint
open-keycloak: ## Open Keycloak in browser
	@open http://localhost:8180 2>/dev/null || \
	 xdg-open http://localhost:8180 2>/dev/null || \
	 echo "Open http://localhost:8180"

list-policies: ## List policies currently loaded in OPA
	@curl -s http://localhost:8181/v1/policies | jq -r '.result[].id // "No policies"'

test-opa: ## Test OPA policies directly
	@bash scripts/test-opa-policy.sh

lint: ## Run pre-commit hooks
	@pre-commit run --all-files

# ── Runtime lifecycle ───────────────────────────────────────────────

.PHONY: start stop restart logs clean rebuild forward wait-healthy test
start: ## Start the platform
ifeq ($(RUNTIME),compose)
	@echo " Starting Zero Trust Architecture PoC..."
	@echo "   PROJECT_ROOT=$(PROJECT_ROOT)"
	@echo "   OPA_POLICY_SET=$(OPA_POLICY_SET)"
	@$(COMPOSE) up -d --build
	@echo " Waiting for services to be healthy..."
	@$(MAKE) -s wait-healthy
	@echo ""
	@echo " Access Points:"
	@echo "  Keycloak:       http://localhost:8180 (admin/admin)"
	@echo "  Go Service:     http://localhost:9001"
	@echo "  Python Service: http://localhost:9002"
	@echo "  C# Service:     http://localhost:9003"
	@echo "  OPA:            http://localhost:8181"
else
	@bash scripts/deploy-to-kind.sh
endif

stop: ## Stop the platform
ifeq ($(RUNTIME),compose)
	@$(COMPOSE) down
else
	@bash scripts/cleanup-kind.sh
endif

restart: stop start ## Restart the platform

logs: ## Follow platform logs
ifeq ($(RUNTIME),compose)
	@$(COMPOSE) logs -f
else
	@echo "Use kubectl logs for specific pods:"
	@kubectl get pods -n default
endif

rebuild: ## Rebuild service docker images
ifeq ($(RUNTIME),compose)
	@$(COMPOSE) build
else
	@echo "Rebuild not applicable for k8s — handled by deploy-to-kind.sh"
endif

forward: ## Port-forward dashboards (k8s only)
ifeq ($(RUNTIME),k8s)
	@bash scripts/port-forward-in-kind.sh --all
else
	@echo "Docker runtime exposes services on host ports directly"
endif

wait-healthy: ## Block until Keycloak + OPA + at least one service respond (max 120s)
	@echo " Waiting for stack to be healthy..."
	@for i in $$(seq 1 60); do \
	  kc=$$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8180/realms/demo 2>/dev/null || echo 000); \
	  opa=$$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:8181/v1/policies 2>/dev/null || echo 000); \
	  echo "  [$$i] keycloak=$$kc opa=$$opa"; \
	  if [ "$$kc" = "200" ] && [ "$$opa" = "200" ]; then \
	    echo " ✓ stack is healthy"; exit 0; \
	  fi; \
	  sleep 2; \
	done; \
	echo " ✗ stack did not become healthy in 120s"; exit 1

test: ## Run service + OPA policy tests
	$(PYTEST) tests/ --env=$(RUNTIME)

# ── Policy switching ────────────────────────────────────────────────

.PHONY: use-one use-three
use-one: ## Switch OPA to basic RBAC policies
	@echo " Switching OPA to policies/opa/rbac..."
	@bash scripts/load-opa-policies.sh rbac $(RUNTIME)
	@echo " OPA now serving 'rbac'"

use-three: ## Switch OPA to RBAC + ReBAC + Time-based policies
	@echo " Switching OPA to policies/opa/rbac-rebac-time..."
	@bash scripts/load-opa-policies.sh rbac-rebac-time $(RUNTIME)
	@echo " OPA now serving 'rbac-rebac-time'"

# ── K8s extras (no docker equivalent) ───────────────────────────────

.PHONY: forward-bg forward-stop redeploy
forward-bg: ## Background port-forward (k8s only; writes PID to /tmp/zta-pf.pid)
ifeq ($(RUNTIME),k8s)
	@bash scripts/port-forward-in-kind.sh --all > /tmp/zta-pf.log 2>&1 & echo $$! > /tmp/zta-pf.pid
else
	@echo "forward-bg is k8s-only"
endif

forward-stop: ## Stop background port-forwards
ifeq ($(RUNTIME),k8s)
	@if [ -f /tmp/zta-pf.pid ]; then kill $$(cat /tmp/zta-pf.pid) 2>/dev/null || true; rm -f /tmp/zta-pf.pid; fi
else
	@echo "forward-stop is k8s-only"
endif
