"""
End-to-end tests against the three demo services, going through their
Envoy sidecar (compose) or Istio gateway (k8s) so the JWT validation
and ext_authz call to OPA are exercised.

Mirrors the original test-internal-services.sh, but each old "for svc
in go python csharp" loop is now a parametrized test that produces a
separate pytest result per service.
"""
from __future__ import annotations

import pytest
import requests

from helpers import Endpoints

SERVICES = ("go", "python", "csharp")


# ---------------------------------------------------------------------------
# Small request helper. We keep it inline rather than as a fixture because
# tests want to pass different (token, path, method, expected) tuples.
# ---------------------------------------------------------------------------


def _call(
    endpoints: Endpoints,
    service: str,
    path: str,
    method: str = "GET",
    token: str | None = None,
) -> int:
    url = endpoints.service_url(service) + path
    headers: dict[str, str] = {}
    host = endpoints.service_host(service)
    if host:
        headers["Host"] = host
    if token:
        headers["Authorization"] = f"Bearer {token}"
    # allow_redirects=False so a 302 doesn't masquerade as a 200.
    resp = requests.request(method, url, headers=headers, allow_redirects=False, timeout=5)
    return resp.status_code


# ---------------------------------------------------------------------------
# Admin (alice) — full access across every endpoint
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("service", SERVICES)
@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/"),
        ("GET", "/api/data"),
        ("GET", "/admin/users"),
        ("POST", "/api/data"),
    ],
)
def test_admin_has_full_access(
    endpoints: Endpoints, alice_token: str, service: str, method: str, path: str
) -> None:
    status = _call(endpoints, service, path, method, alice_token)
    assert status == 200, f"admin alice was denied {method} {path} on {service}"


# ---------------------------------------------------------------------------
# User (bob) — RBAC limits: read-only, no /admin
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("service", SERVICES)
@pytest.mark.parametrize(
    ("method", "path", "expected"),
    [
        ("GET", "/", 200),
        ("GET", "/api/data", 200),
        ("POST", "/api/data", 403),
        ("GET", "/admin/users", 403),
    ],
)
def test_user_rbac(
    endpoints: Endpoints,
    bob_token: str,
    service: str,
    method: str,
    path: str,
    expected: int,
) -> None:
    status = _call(endpoints, service, path, method, bob_token)
    assert status == expected, (
        f"user bob: expected {expected} for {method} {path} on {service}, got {status}"
    )


# ---------------------------------------------------------------------------
# ReBAC — only meaningful with rbac-rebac-time loaded
# ---------------------------------------------------------------------------


@pytest.mark.policy_set("use-three")
@pytest.mark.parametrize("service", SERVICES)
def test_user_can_read_own_profile(
    endpoints: Endpoints, bob_token: str, bob_id: str, service: str
) -> None:
    status = _call(endpoints, service, f"/users/{bob_id}/profile", "GET", bob_token)
    assert status == 200, f"bob denied access to own profile on {service}"


@pytest.mark.policy_set("use-three")
@pytest.mark.parametrize("service", SERVICES)
def test_user_cannot_read_others_profile(
    endpoints: Endpoints, bob_token: str, alice_id: str, service: str
) -> None:
    status = _call(endpoints, service, f"/users/{alice_id}/profile", "GET", bob_token)
    assert status == 403, (
        f"bob was allowed to read alice's profile on {service} (status {status})"
    )


@pytest.mark.policy_set("use-three")
@pytest.mark.parametrize("service", SERVICES)
def test_admin_can_read_any_profile(
    endpoints: Endpoints, alice_token: str, bob_id: str, service: str
) -> None:
    status = _call(endpoints, service, f"/users/{bob_id}/profile", "GET", alice_token)
    assert status == 200, f"alice (admin) denied bob's profile on {service}"


# ---------------------------------------------------------------------------
# Anonymous — denial + /health passthrough
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("service", SERVICES)
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/", 401),
        ("/api/data", 401),
        ("/health", 200),
    ],
)
def test_anonymous(
    endpoints: Endpoints, service: str, path: str, expected: int
) -> None:
    status = _call(endpoints, service, path, "GET", token=None)
    assert status == expected, (
        f"anonymous {path} on {service}: expected {expected}, got {status}"
    )