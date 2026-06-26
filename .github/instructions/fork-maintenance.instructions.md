---
description: "Use when syncing this fork with upstream main, comparing fork divergence, keeping the deployment wrapper aligned with the fork's own GHCR image (ghcr.io/jzkk720/hermes-agent:latest), preserving data/.env credentials and Postgres state, or smoke-testing container updates."
name: "Fork Maintenance"
applyTo:
  - "docker-compose.yml"
  - "docker-compose.upstream.yml"
  - "docker-compose.windows.yml"
  - "INSTALL.md"
  - "docker/*.sh"
  - "docker/*.yaml"
  - ".github/workflows/docker-publish.yml"
  - ".github/workflows/fork-ghcr-publish.yml"
---

# Fork Maintenance

This fork's runtime image source is **the fork's own GHCR image** (`ghcr.io/jzkk720/hermes-agent:latest`), NOT the upstream Docker Hub image. The fork publishes its own image from [fork-ghcr-publish.yml](../workflows/fork-ghcr-publish.yml) on every push to `origin/main`, baking in `gateway/platforms/weixin_qr_session.py`, the WeChat web-onboarding endpoints, the `dashboard.basic_auth` provider, and the `scripts/fix_dashboard_auth.py` recovery path. The upstream `docker-publish.yml` is gated on `github.repository == 'NousResearch/hermes-agent'` and does not fire on this fork.

## Start From Current State

- Verify remotes before planning merges. The usual layout in this fork is `origin` for the personal fork and `upstream` for `NousResearch/hermes-agent`, but always confirm with `git remote -v`. A `fork` remote pointing at `https://github.com/JZKK720/hermes-agent.git` is the canonical source for syncing this fork.
- Read [docker-compose.yml](../../docker-compose.yml), [docker-compose.upstream.yml](../../docker-compose.upstream.yml), [docker-compose.windows.yml](../../docker-compose.windows.yml), [INSTALL.md](../../INSTALL.md), [docker/hermes-config.yaml](../../docker/hermes-config.yaml), [docker/hermes-env.example](../../docker/hermes-env.example), [fork-ghcr-publish.yml](../workflows/fork-ghcr-publish.yml), and [docker-publish.yml](../workflows/docker-publish.yml) before proposing Docker changes. Read [docker/entrypoint.sh](../../docker/entrypoint.sh) when startup behavior or image-entrypoint drift is part of the task.
- The upstream container reference is [website/docs/user-guide/docker.md](../../website/docs/user-guide/docker.md).

## Safety Rules

- Preserve local runtime state: never overwrite, regenerate, or delete `data/.env`, `data/config.yaml`, `data/SOUL.md`, `data/memories/`, `data/sessions/`, `data/weixin/accounts/`, or the `postgres_data` volume unless the user explicitly asks.
- Avoid destructive reset commands like `docker compose down -v` or deleting `data/` during sync or image-migration work.
- Do not push fork-specific deployment changes to `upstream`. Merge or rebase locally, then push only to `origin` unless the user explicitly wants an upstream contribution.
- Treat bind-mounted files as part of the deployment contract. By default [docker/hermes-config.yaml](../../docker/hermes-config.yaml) stays mounted, so the fork's GHCR image can still be partially shaped by fork-local config (including the `dashboard.basic_auth` block — username `admin`, password `hermes`). If a task reintroduces [docker/entrypoint.sh](../../docker/entrypoint.sh) or another overlay, call out that additional pinning risk explicitly.

## Image Source and Refresh

- The compose files default to `image: ${HERMES_FORK_IMAGE:-ghcr.io/jzkk720/hermes-agent:latest}`. `HERMES_FORK_IMAGE` is the user-facing override.
- For routine updates in this fork, prefer `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans`; do not switch to `--build` or local-fork image tags unless the user is explicitly testing image contents.
- To fall back to the upstream Docker Hub image (no fork features baked in) for one-off debugging:
  ```bash
  HERMES_FORK_IMAGE=docker.io/nousresearch/hermes-agent:latest \
    docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
  ```
- Treat [docker-compose.upstream.yml](../../docker-compose.upstream.yml) as the preferred pulled-image refresh lane for this fork when the goal is to stay on the fork's GHCR image while keeping fork-local mounts and state.
- Re-check whether the default [docker/hermes-config.yaml](../../docker/hermes-config.yaml) mount and any optional overlays are still necessary; they preserve the fork wrapper but can also block future upstream behavior changes.

## Dashboard basic_auth

- Upstream 0.17+ refuses to bind the dashboard to `0.0.0.0` without an auth provider; `--insecure` is now a no-op.
- The fork ships `dashboard.basic_auth` (username `admin`, password `hermes`, scrypt hash baked into [docker/hermes-config.yaml](../../docker/hermes-config.yaml)) so the standard `docker compose up -d` "just works". The host port stays bound to `127.0.0.1:9119`; only the container-internal bind is `0.0.0.0` (Docker port forwarding requires it).
- If YAML escaping mangles the hash on first boot and locks the user out, the recovery path is [scripts/fix_dashboard_auth.py](../../scripts/fix_dashboard_auth.py):
  ```bash
  docker cp scripts/fix_dashboard_auth.py hermes-web:/tmp/fix.py
  docker exec -u root hermes-web python3 /tmp/fix.py
  docker compose -f docker-compose.upstream.yml restart hermes-web
  ```
  The script must run as root because `data/config.yaml` is owned by `hermes`. Changing the default credentials means updating both `docker/hermes-config.yaml` (the template) and `scripts/fix_dashboard_auth.py` (the constant) together.

## Merge and Divergence Checks

- Inspect divergence with `git fetch fork --prune`, `git fetch upstream --prune`, `git fetch origin --prune`, and `git rev-list --left-right --count origin/main...fork/main` before discussing merge strategy.
- If the fork carries local-only deployment commits, keep them on `origin/main` or a dedicated branch. Do not merge `fork/main` into the fork unless the user explicitly asks for that sync path.
- If the user wants to review upstream without integrating it yet, compare commits and diffs without rewriting remotes or force-pushing.
- `fork-ghcr-publish.yml` is what publishes the fork's image. If `origin/main` is pushed but the GHCR image is stale, check this workflow's run history before debugging the compose files.

## Smoke Test Expectations

- After editing compose or deployment docs, validate with `docker compose config`.
- For fork GHCR image stacks, use `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans`.
- Check `docker compose ps`, the dashboard health endpoint `http://127.0.0.1:9119/api/status` (prompts for `admin/hermes`), the gateway health endpoint `http://127.0.0.1:8789/health`, and the agent API `http://127.0.0.1:8789/v1/models` when available. Or run [scripts/smoke_test_local.sh](../../scripts/smoke_test_local.sh) for the full four-level sequence.
- Report any step that would change credentials, rebuild volumes, or replace mounted config before doing it.