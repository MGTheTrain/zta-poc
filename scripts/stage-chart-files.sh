#!/bin/bash
#
# stage-chart-files.sh — copy non-secret source-of-truth files into
# the zta-platform chart's files/ directory so Helm can slurp them
# with Files.Glob at install time.
#
# Sources:
#   policies/opa-k8s/<set>/*.rego  →  infra/helm-charts/zta-platform/files/opa-policies/<set>/
#   configs/keycloak/demo-realm.json → infra/helm-charts/zta-platform/files/keycloak/
#
# Idempotent: existing staged content is wiped before each run so
# removed-upstream files don't linger.
#
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PLATFORM_CHART="${PLATFORM_CHART:-infra/helm-charts/zta-platform}"

stage_files() {
    local src="$1"
    local dst="$2"
    if [ ! -d "${src}" ]; then
        echo -e "${YELLOW}  warning: ${src} does not exist, skipping${NC}"
        return
    fi
    # Wipe everything (including subdirs), then recreate empty and re-keep
    rm -rf "${dst}"
    mkdir -p "${dst}"
    touch "${dst}/.gitkeep"
    cp -R "${src}/." "${dst}/"
    echo -e "${BLUE}  ${src} → ${dst}${NC}"
}

echo -e "${YELLOW}📂 Staging chart files into ${PLATFORM_CHART}/files/...${NC}"

# OPA policies — stage every policy-set folder so a later
# `--set opa.policySet=...` works without re-staging.
for set in rbac rbac-rebac-time advanced; do
    if [ -d "policies/opa-k8s/${set}" ]; then
        stage_files "policies/opa-k8s/${set}" \
                    "${PLATFORM_CHART}/files/opa-policies/${set}"
    fi
done

# Keycloak realm
stage_files "configs/keycloak" "${PLATFORM_CHART}/files/keycloak"

echo -e "${GREEN}✓ Staging complete${NC}"
