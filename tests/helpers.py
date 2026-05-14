"""
Helpers for the ZTA PoC test suite.

Pure functions that mirror what scripts/common.sh used to expose to the
bash tests. They don't depend on pytest, so anything in here can be
reused from a python REPL or imported by ad-hoc scripts.
"""
from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Literal

import requests

# ---------------------------------------------------------------------------
# Endpoint configuration
# ---------------------------------------------------------------------------

Environment = Literal["docker", "k8s"]


@dataclass(frozen=True)
class Endpoints:
    """Where to reach each component for a given environment."""

    keycloak: str
    opa: str
    go: str
    python: str
    csharp: str
    # Host header to use when reaching a service. Empty for docker (each
    # service has its own port); set for k8s (all share the gateway port
    # and routing is by Host header).
    go_host: str
    python_host: str
    csharp_host: str

    def service_url(self, name: str) -> str:
        return {"go": self.go, "python": self.python, "csharp": self.csharp}[name]

    def service_host(self, name: str) -> str:
        return {
            "go": self.go_host,
            "python": self.python_host,
            "csharp": self.csharp_host,
        }[name]


def endpoints_for(env: Environment) -> Endpoints:
    """Resolve the URL/host layout for a given environment.

    docker: each service exposed on its own port; OPA on 8181 directly.
    k8s:    everything behind the Istio gateway on :8080 with Host
            header routing; OPA reached via port-forward on :8181.
    """
    if env == "k8s":
        gateway = "http://localhost:8080"
        return Endpoints(
            keycloak="http://localhost:8180",
            opa="http://localhost:8181",
            go=gateway,
            python=gateway,
            csharp=gateway,
            go_host="go-service.local",
            python_host="python-service.local",
            csharp_host="csharp-service.local",
        )
    return Endpoints(
        keycloak="http://localhost:8180",
        opa="http://localhost:8181",
        go="http://localhost:9001",
        python="http://localhost:9002",
        csharp="http://localhost:9003",
        go_host="",
        python_host="",
        csharp_host="",
    )


# ---------------------------------------------------------------------------
# Keycloak / JWT
# ---------------------------------------------------------------------------


def get_token(
    keycloak_url: str,
    username: str,
    password: str,
    realm: str = "demo",
    client_id: str = "demo-client",
    timeout: float = 5.0,
) -> str:
    """Request an access token from Keycloak via the password grant."""
    url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"
    resp = requests.post(
        url,
        data={
            "grant_type": "password",
            "client_id": client_id,
            "username": username,
            "password": password,
        },
        timeout=timeout,
    )
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token:
        raise RuntimeError(f"Keycloak returned no access_token for {username!r}")
    return token


def decode_jwt(token: str) -> dict:
    """Decode the payload section of a JWT. No signature check — this is
    test-side introspection, not authn."""
    parts = token.split(".")
    if len(parts) < 2:
        raise ValueError("token does not look like a JWT")
    payload_b64 = parts[1]
    # Pad to a multiple of 4 for base64
    payload_b64 += "=" * (-len(payload_b64) % 4)
    return json.loads(base64.urlsafe_b64decode(payload_b64))


def get_user_id(token: str) -> str:
    """Extract the JWT's `sub` claim — the user ID Keycloak issued."""
    payload = decode_jwt(token)
    sub = payload.get("sub")
    if not sub:
        raise RuntimeError("JWT has no `sub` claim")
    return sub


# ---------------------------------------------------------------------------
# OPA policy-set detection
# ---------------------------------------------------------------------------

PolicySet = Literal["use-one", "use-three", "use-seven", "none"]


def detect_policy_set(opa_url: str, timeout: float = 3.0) -> PolicySet:
    """Inspect which policy modules are loaded in OPA.

    Mirrors common.sh's bash heuristic:
      - rbac + rebac + time_based  → use-three
      - rbac + rebac + many others → use-seven
      - rbac only                  → use-one
      - nothing                    → none
    """
    try:
        resp = requests.get(f"{opa_url}/v1/policies", timeout=timeout)
        resp.raise_for_status()
    except requests.RequestException:
        return "none"

    ids = {p["id"] for p in resp.json().get("result", [])}
    if not ids:
        return "none"
    # The advanced bundle ships geofencing, ip_allowlist, mfa, rate_limit
    # alongside rbac/rebac/time_based — count modules to disambiguate.
    advanced_markers = {"geofencing", "ip_allowlist", "mfa", "rate_limit"}
    if ids & advanced_markers:
        return "use-seven"
    if {"rbac", "rebac", "time_based"} <= ids:
        return "use-three"
    return "use-one"


# ---------------------------------------------------------------------------
# OPA direct query (for test-opa-policy)
# ---------------------------------------------------------------------------


def opa_decide(opa_url: str, token: str, path: str, method: str = "GET") -> bool:
    jwt_payload = decode_jwt(token)
    body = {
        "input": {
            "attributes": {
                "request": {
                    "http": {
                        "path": path,
                        "method": method,
                        # Compose policies parse the JWT from this header
                        "headers": {"authorization": f"Bearer {token}"},
                    }
                },
                # k8s policies read it from here
                "metadataContext": {
                    "filterMetadata": {
                        "envoy.filters.http.jwt_authn": {"jwt_payload": jwt_payload}
                    }
                },
            }
        }
    }
    resp = requests.post(f"{opa_url}/v1/data/envoy/authz/allow", json=body, timeout=3.0)
    resp.raise_for_status()
    result = resp.json().get("result")
    if isinstance(result, dict):
        return bool(result.get("allowed", False))
    return bool(result)