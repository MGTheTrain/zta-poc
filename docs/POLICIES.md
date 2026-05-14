# Policy Sets

Two policy sets ship with the PoC, plus an `advanced` set with extra
illustrative examples. Switch between them with `make compose-use-one`
/ `make compose-use-three` (or the `k8s-use-*` equivalents).

## `use-one` — RBAC only

Pure role-based access control with proper HTTP status codes.

- Admin: full access
- User: `GET` only, no `/admin/*`
- Anonymous: `401`
- Authenticated but insufficient permissions: `403`

Source: [`policies/opa/rbac/`](../policies/opa/rbac/) (compose) ·
[`policies/opa-k8s/rbac/`](../policies/opa-k8s/rbac/) (k8s)

## `use-three` — RBAC + ReBAC + Time

Adds resource ownership and business-hours enforcement on top of `use-one`.

- All RBAC rules apply
- Users can only access `/users/{their-sub}/*`
- Business hours: Mon–Fri 09:00–17:00 UTC
- Admins bypass ReBAC and time restrictions

Source: [`policies/opa/rbac-rebac-time/`](../policies/opa/rbac-rebac-time/) ·
[`policies/opa-k8s/rbac-rebac-time/`](../policies/opa-k8s/rbac-rebac-time/)

## `advanced` — illustrative ABAC

Compose-only. IP allowlists, MFA, geofencing, rate limits. Not all rules
are runnable without additional setup (Keycloak claim mappers, external
data sources). See [ABAC-EXAMPLES.md](ABAC-EXAMPLES.md) for the runnable
variants.

Source: [`policies/opa/advanced/`](../policies/opa/advanced/)

## Authorization matrix

Assumes `use-three` loaded; rows marked *(RBAC only)* differ under `use-one`.

| Endpoint                            | Admin    | User                | Anonymous |
|-------------------------------------|----------|---------------------|-----------|
| `GET /`                             | ✅ 200   | ✅ 200              | ❌ 401    |
| `GET /health`                       | ✅ 200   | ✅ 200              | ✅ 200    |
| `GET /api/data`                     | ✅ 200   | ✅ 200              | ❌ 401    |
| `POST /api/data`                    | ✅ 200   | ❌ 403              | ❌ 401    |
| `GET /admin/users`                  | ✅ 200   | ❌ 403              | ❌ 401    |
| `GET /users/{bob-sub}/profile`      | ✅ 200   | ✅ 200 *(own)*      | ❌ 401    |
| `GET /users/{alice-sub}/profile`    | ✅ 200   | ❌ 403 *(not own)*  | ❌ 401    |

Under `use-one` the last two rows behave like any other path: user can
`GET`, so both profile reads return `200`.

## Switching sets

The two paths use different mechanisms — both end up with the named set
loaded in OPA.

| Path    | Mechanism                                                                  |
|---------|----------------------------------------------------------------------------|
| compose | `OPA_POLICY_SET` env var → bind-mount swap → container restart (~1 s)      |
| k8s     | `scripts/load-opa-policies.sh` → port-forward → `PUT /v1/policies/<id>`    |

The pytest suite auto-detects which set is currently loaded
([`tests/helpers.py::detect_policy_set`](../tests/helpers.py)) and skips
tests that require a set other than the active one. So running
`make compose-test` after `compose-use-one` runs only RBAC tests; after
`compose-use-three` it also runs the ReBAC tests.
