"""
Pytest configuration shared by all test modules.

Adds a --env command-line option (docker | k8s) and exposes session-scoped
fixtures for endpoints, tokens, user IDs, and the detected policy set.
"""

from __future__ import annotations

import pytest

from helpers import (
    Endpoints,
    PolicySet,
    detect_policy_set,
    endpoints_for,
    get_token,
    get_user_id,
)

# ---------------------------------------------------------------------------
# CLI option
# ---------------------------------------------------------------------------


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--env",
        action="store",
        default="docker",
        choices=["docker", "k8s"],
        help="Target environment: docker (compose, default) or k8s (kind).",
    )


# ---------------------------------------------------------------------------
# Markers
# ---------------------------------------------------------------------------


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "policy_set(*sets): only run when OPA has one of the named policy "
        "sets loaded (use-one, use-three, use-seven).",
    )


def pytest_collection_modifyitems(
    config: pytest.Config, items: list[pytest.Item]
) -> None:
    """Implement the policy_set(...) marker: skip tests whose required
    set isn't currently loaded in OPA."""
    env = config.getoption("--env")
    eps = endpoints_for(env)
    detected = detect_policy_set(eps.opa)
    for item in items:
        marker = item.get_closest_marker("policy_set")
        if marker is None:
            continue
        if detected not in marker.args:
            item.add_marker(
                pytest.mark.skip(
                    reason=f"requires policy set {marker.args!r}, "
                    f"OPA currently has {detected!r}"
                )
            )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def env(pytestconfig: pytest.Config) -> str:
    return pytestconfig.getoption("--env")


@pytest.fixture(scope="session")
def endpoints(env: str) -> Endpoints:
    return endpoints_for(env)  # type: ignore[arg-type]


@pytest.fixture(scope="session")
def policy_set(endpoints: Endpoints) -> PolicySet:
    detected = detect_policy_set(endpoints.opa)
    if detected == "none":
        pytest.exit(
            "No OPA policies loaded — run `make compose-use-one` or "
            "`make k8s-use-one` first.",
            returncode=2,
        )
    return detected


@pytest.fixture(scope="session")
def alice_token(endpoints: Endpoints) -> str:
    return get_token(endpoints.keycloak, "alice", "password")


@pytest.fixture(scope="session")
def bob_token(endpoints: Endpoints) -> str:
    return get_token(endpoints.keycloak, "bob", "password")


@pytest.fixture(scope="session")
def alice_id(alice_token: str) -> str:
    return get_user_id(alice_token)


@pytest.fixture(scope="session")
def bob_id(bob_token: str) -> str:
    return get_user_id(bob_token)
