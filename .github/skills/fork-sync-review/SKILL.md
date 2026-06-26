---
name: fork-sync-review
description: "Review fork divergence, sync origin/main with fork/main (JZKK720), keep this fork aligned as a deployment wrapper around the published fork GHCR image (ghcr.io/jzkk720/hermes-agent), preserve data/.env and Postgres state, and produce a smoke-test plan for deployment updates."
argument-hint: "Describe the fork sync, merge, or image migration question"
user-invocable: true
---

# Fork Sync Review

Use this skill when the task is to inspect how far this fork has drifted from upstream or from JZKK720's HEAD, decide whether deployment changes should stay fork-local, or keep the fork aligned as a deployment wrapper around the **fork's own GHCR image** (`ghcr.io/jzkk720/hermes-agent:latest`) without losing runtime state.

## Procedure

1. Inspect remotes and divergence with `git remote -v`, `git fetch fork --prune`, `git fetch upstream --prune`, `git fetch origin --prune`, and `git rev-list --left-right --count origin/main...fork/main` (and `...upstream/main` if you also want to measure upstream drift).
2. Review fork-only deployment files before changing the running stack: [docker-compose.yml](../../../docker-compose.yml), [docker-compose.upstream.yml](../../../docker-compose.upstream.yml), [docker-compose.windows.yml](../../../docker-compose.windows.yml), [INSTALL.md](../../../INSTALL.md), [docker/deploy.sh](../../../docker/deploy.sh), [docker/hermes-config.yaml](../../../docker/hermes-config.yaml), [docker/hermes-env.example](../../../docker/hermes-env.example), [.github/workflows/fork-ghcr-publish.yml](../../../.github/workflows/fork-ghcr-publish.yml), and [scripts/fix_dashboard_auth.py](../../../scripts/fix_dashboard_auth.py). Read [docker/entrypoint.sh](../../../docker/entrypoint.sh) when startup behavior or entrypoint drift is part of the question.
3. Check the currently running containers and images with `docker compose -f docker-compose.upstream.yml ps` and compare them to the documented fork image flow.
4. Preserve local state. Never delete `data/.env`, `data/config.yaml`, `data/memories/`, `data/sessions/`, `data/weixin/accounts/`, or the `postgres_data` volume unless the user explicitly asks.
5. Prefer `ghcr.io/jzkk720/hermes-agent:latest` for fork image pulls. Use `HERMES_FORK_IMAGE` for a specific tag or to pin to the upstream Docker Hub image for one-off debugging. Do not assume a local build path is part of the deployment — the GHCR workflow already publishes on every push to `origin/main`.
6. After any deployment edit, validate with `docker compose -f docker-compose.upstream.yml config`, then `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans`, followed by health checks on the dashboard (basic_auth `admin/hermes`), the gateway `/health` endpoint, the iLink `Connected` log line, and `scripts/smoke_test_local.sh` for the full four-level sequence.

## Output Expectations

- Report fork divergence as `ahead/behind` counts relative to both `fork/main` and `upstream/main`.
- Separate fork-only deployment customizations from upstream changes that can be adopted safely.
- Call out anything that would change credentials, mounted config, or persistent data before doing it.
- End with the concrete commands needed to smoke test the updated stack.
