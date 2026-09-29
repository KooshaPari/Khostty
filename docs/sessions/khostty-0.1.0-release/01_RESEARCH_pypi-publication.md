# PyPI Publication Research

**Date:** 2026-09-29
**Status:** Blocked on one operator action (API token) — everything else verified.

## Correction to the original plan

The plan of record said to upload artifacts "through the web UI" after opening
`https://pypi.org/account/login/?next=/manage/project/create/`.

**That path no longer exists.** Two independent findings:

1. Every `manage/project/create/` variant returns `404`, anonymously and while
   authenticated:
   - `/manage/project/create/` → 404
   - `/manage/project/create/?form=create` → 404
   - `/manage/projects/create/` → 404
   - `/manage/project/new/` → 404
   - `/manage/projects/` → 303 to login (this is the real entry point)
2. PyPI's own help page, "Why can't I manually upload files to PyPI, through the
   browser interface?":

   > In a previous version of PyPI, it was possible for maintainers to upload
   > releases to PyPI using a form in the web browser. This feature was
   > deprecated with the new version of PyPI – we instead recommend that you use
   > twine to upload your project to PyPI.

So the project-creation step is unnecessary anyway: **PyPI creates the project
implicitly on the first successful upload**, provided the name is free. It is
(`GET /pypi/khostty-vt/json` → `404`).

## Why not Trusted Publishing

Trusted Publishing (OIDC) is the modern path and needs **no token at all**, but
it requires GitHub Actions to be enabled in the repository — and Actions are
disabled on this fork (push-triggered runs do not fire; documented in
`docs/CI.md`).

Enabling Actions is operator-only and is a separate open item. The token path
does not depend on it, so the token path is the correct unblock now. Trusted
Publishing can be configured afterward as the durable follow-up.

## Verified preconditions

| Check | Result |
|---|---|
| `GET /pypi/khostty-vt/json` | `404` — name free, unpublished |
| `twine check` (wheel) | PASSED |
| `twine check` (sdist) | PASSED |
| twine version | 7.0.0 (installed via `uv tool install twine`) |
| Python pkg changes since tag | none — `git log v0.1.0..HEAD -- khostty-python/` is empty |
| wheel contents | 26 entries, `khostty_vt/` package + dist-info |

## Operator action required

1. Create a project-scoped API token at
   `https://pypi.org/manage/account/#api-tokens`
   - Project name: `khostty-vt`
   - Scope: `khostty-vt` only (not the whole account)
2. Provide it via a keyring entry or env var. **Never paste the token into chat,
   into a shell history, or into any committed file.**

Recommended (no plaintext on disk):

```bash
read -rs PYPI_TOKEN && export PYPI_TOKEN
~/.local/bin/twine upload --repository pypi \
  khostty-python/dist/khostty_vt-0.1.0.tar.gz \
  khostty-python/dist/khostty_vt-0.1.0-py3-none-any.whl
unset PYPI_TOKEN
```

Credentials are consumed by twine only and are never read, logged, or stored by
the agent.

## Follow-ups

- Enable GitHub Actions in the fork, then configure Trusted Publishing so no
  token has to be minted manually for future releases.
- Add a `publish-pypi.yml` workflow gated on tags.
