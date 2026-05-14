"""
Direct policy-decision tests against OPA's REST API.

These tests bypass Envoy/Istio entirely and ask OPA "would you allow
this?" by synthesizing the ext_authz input shape with the JWT already
decoded. Useful for isolating policy bugs from sidecar/networking
issues — if these pass but test_internal_services fails, the problem
is the data path, not the policy.

Mirrors test-opa-policy.sh.
"""
from __future__ import annotations

import pytest

from helpers import Endpoints, opa_decide


# ---------------------------------------------------------------------------
# RBAC — always runs, since every policy set has at least RBAC
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("user_fixture", "path", "method", "expected"),
    [
        ("alice_token", "/api/data",    "GET",  True),
        ("bob_token",   "/api/data",    "GET",  True),
        ("bob_token",   "/api/data",    "POST", False),
        ("bob_token",   "/admin/users", "GET",  False),
    ],
    ids=[
        "alice-admin-can-GET-api",
        "bob-user-can-GET-api",
        "bob-user-cannot-POST-api",
        "bob-user-cannot-GET-admin",
    ],
)
def test_rbac(
    endpoints: Endpoints,
    request: pytest.FixtureRequest,
    user_fixture: str,
    path: str,
    method: str,
    expected: bool,
) -> None:
    token = request.getfixturevalue(user_fixture)
    decision = opa_decide(endpoints.opa, token, path, method)
    assert decision is expected, (
        f"{user_fixture} {method} {path}: expected {expected}, got {decision}"
    )


# ---------------------------------------------------------------------------
# ReBAC — only with rbac-rebac-time loaded
# ---------------------------------------------------------------------------


@pytest.mark.policy_set("use-three")
def test_user_can_access_own_profile(
    endpoints: Endpoints, bob_token: str, bob_id: str
) -> None:
    assert opa_decide(endpoints.opa, bob_token, f"/users/{bob_id}/profile") is True


@pytest.mark.policy_set("use-three")
def test_user_cannot_access_others_profile(
    endpoints: Endpoints, bob_token: str, alice_id: str
) -> None:
    assert opa_decide(endpoints.opa, bob_token, f"/users/{alice_id}/profile") is False


@pytest.mark.policy_set("use-three")
def test_admin_can_access_any_profile(
    endpoints: Endpoints, alice_token: str, bob_id: str
) -> None:
    assert opa_decide(endpoints.opa, alice_token, f"/users/{bob_id}/profile") is True