---
name: docker-compose-smoke-test
description: "Bring up Hermes locally with Docker Compose, seed data/.env from docker/hermes-env.example, inspect logs, and smoke test the fork's deployment wrapper around the published GHCR image (ghcr.io/jzkk720/hermes-agent). Use when asked to install without local builds, validate docker compose, debug container startup, or check local stack health."
argument-hint: "[service or issue to verify]"
user-invocable: true
---

# Docker Compose Smoke Test

Use this skill for local stack validation after install changes, deployment-wrapper changes, or fork sync work. The runtime image source is the **fork's own GHCR image** (`ghcr.io/jzkk720/hermes-agent:latest`), built and published by [`.github/workflows/fork-ghcr-publish.yml`](../../../.github/workflows/fork-ghcr-publish.yml) on every push to `origin/main`. It bakes in the WeChat QR onboarding endpoints, the `dashboard.basic_auth` provider, and the `scripts/fix_dashboard_auth.py` recovery path — no local build required.

## Read First

- [docker-compose.yml](../../../docker-compose.yml)
- [docker-compose.upstream.yml](../../../docker-compose.upstream.yml)
- [docker-compose.windows.yml](../../../docker-compose.windows.yml)
- [INSTALL.md](../../../INSTALL.md)
- [docker/hermes-env.example](../../../docker/hermes-env.example)
- [docker/hermes-config.yaml](../../../docker/hermes-config.yaml)
- [docker/entrypoint.sh](../../../docker/entrypoint.sh) when startup behavior or entrypoint drift is relevant
- [.github/workflows/fork-ghcr-publish.yml](../../../.github/workflows/fork-ghcr-publish.yml)

## When to Use

- Install or refresh Hermes from `ghcr.io/jzkk720/hermes-agent:latest` without rebuilding locally.
- Confirm that `hermes-web`, `hermes-gateway`, and `postgres` start correctly.
- Debug a failed local bring-up.
- Verify that the stack is usable before pushing a fork update.
- Keep the existing local env file, config mounts, and host ports while refreshing the fork's GHCR image.

## Procedure

### 1. Check prerequisites and environment

- On Windows, prefer WSL2-oriented workflows because the main README does not treat native Windows as the supported runtime path.
- Confirm Docker Engine and Docker Compose are available before changing files or starting containers.
- Treat `data/.env`, `data/config.yaml`, `data/weixin/accounts/`, and the `postgres_data` volume as local runtime state, not committed source.
- Preserve the host-port contract from the compose files: `9119`, `8789`, `8644`, and `5433` should stay unchanged unless the user explicitly asks for different ports.

### 2. Seed the local env file if needed

Use the repo-documented layout:

```bash
mkdir -p data
cp docker/hermes-env.example data/.env
```

If `data/.env` already exists, inspect it before replacing it.

### 3. Choose the compose path before starting containers

Default to the documented fork deployment wrapper:

```bash
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

This pulls the latest `ghcr.io/jzkk720/hermes-agent:latest` (override via `HERMES_FORK_IMAGE` if you want a specific tag or want the upstream Docker Hub image for one-off debugging). It keeps the same `./data` mount, `data/.env`, generated `data/config.yaml`, host ports, and fork-local `docker/hermes-config.yaml` surface.

Use the local-build stack only when fork code, the Dockerfile, or other in-repo image contents are under test:

```bash
docker compose up -d --build
```

### 4. Start the stack

Use the command that matches the chosen compose path.

This should start:

- `hermes-web` on `:9119` — dashboard behind basic_auth (`admin / hermes` by default).
- `hermes-gateway` running the gateway with the `weixin` (WeChat personal) platform enabled — no host port, outbound long-poll only.
- `postgres` on host port `5433`.

### 5. Check status and logs

Use targeted inspection before escalating:

```bash
docker compose -f docker-compose.upstream.yml ps
docker compose -f docker-compose.upstream.yml logs --tail=100 hermes-web
docker compose -f docker-compose.upstream.yml logs --tail=100 hermes-gateway
docker compose -f docker-compose.upstream.yml logs --tail=100 postgres
```

If the pull-only stack is active, add `-f docker-compose.upstream.yml` consistently to the same commands.

Focus on:

- healthcheck failures;
- config bootstrap problems or entrypoint drift when startup behavior is under discussion;
- missing env vars or permission errors;
- port binding conflicts;
- dashboard 401/403 (basic_auth gate failure) — run [scripts/fix_dashboard_auth.py](../../../scripts/fix_dashboard_auth.py) if the YAML-escaped hash got mangled on first boot;
- WeChat gateway stuck on first poll — verify `data/weixin/accounts/` exists and contains a JSON credential file. If empty, run the wizard (the `setup` subcommand opens a menu — select `Weixin / WeChat`, item 13):
  ```bash
  docker compose -f docker-compose.upstream.yml run --rm hermes-gateway \
      hermes gateway setup
  ```

### 6. Smoke test the running stack

For the full automated sequence, run:

```bash
bash scripts/smoke_test_local.sh
```

That script covers all four levels below. Validate these expectations:

- `docker compose ps` shows all three containers `(healthy)`.
- Dashboard: `curl -fsS -u admin:hermes http://127.0.0.1:9119/api/status` returns a healthy status. The unauthenticated probe should return `401`.
- Gateway: `http://127.0.0.1:8789/health` returns 200.
- WeChat: `docker compose -f docker-compose.upstream.yml logs --tail=200 hermes-gateway | grep "Connected"` shows a `[weixin] Connected account=...` line.

`docker exec -it hermes-web hermes` is the documented interactive smoke test when an interactive shell is appropriate.

#### 6a. WeChat channel smoke test (no HTTP port to probe)

The weixin adapter uses outbound long-poll to Tencent iLink — there is no host port to `curl`. Use this four-level sequence instead, cheapest first.

**Level 1 — Container healthcheck (5s).** The compose healthcheck probes `http://127.0.0.1:8789/health`. If `healthy`, the gateway has booted past the WeChat startup gate.

```bash
docker compose -f docker-compose.upstream.yml ps
# hermes-gateway state should be "healthy" (or "Up" if healthcheck is still pending)
```

If state is `Up` but not `healthy`, the gateway has not finished bootstrapping yet — check the logs.

**Level 2 — Adapter connected log (10-30s).** The weixin adapter logs a specific line when its long-poll loop is up. This is the canonical "channel is alive" signal.

```bash
docker compose -f docker-compose.upstream.yml logs --tail=200 hermes-gateway 2>&1 \
    | grep -E "Connected|Disconnected"
```

Success looks like:

```
hermes-gateway  | [weixin] Connected account=<id> base=https://ilinkai.weixin.qq.com
```

That line is emitted at [gateway/platforms/weixin.py:1297](gateway/platforms/weixin.py#L1297). No `Disconnected` line should follow.

Failure modes:

- `getUpdates failed ret=-14 errcode=-14 errmsg=session expired` — iLink session expired; re-run the wizard.
- `getUpdates failed ret=-2 errmsg=unknown error` — stale-session signal (same as `-14`); re-run the wizard.
- `Session expired; pausing for 10 minutes` — same root cause; wizard re-run required.
- `Connected` then `Disconnected` — token lock conflict (another profile is using the same bot). Stop the other profile, restart.

**Level 3 — Gateway status CLI (instant).** Reports running gateway PIDs and platform state. Useful when logs are ambiguous.

```bash
docker compose -f docker-compose.upstream.yml exec hermes-gateway hermes gateway status
```

**Level 4 — End-to-end inbound (the real proof).** This is the only test that proves the channel actually delivers messages.

```bash
# 1. Tail the gateway log
docker compose -f docker-compose.upstream.yml logs -f hermes-gateway 2>&1 \
    | grep -E "inbound|Connected|Disconnected"

# 2. From your phone, send "ping" to the WeChat account you scanned with

# 3. Expected within ~2 seconds:
#    [weixin] inbound from=<sender_id> type=direct media=0

# 4. Confirm a session file was created:
docker compose -f docker-compose.upstream.yml exec hermes-web ls -la /opt/data/sessions/ | tail -5
# Look for a new .json file with recent mtime
```

The `inbound from=` line is emitted at [gateway/platforms/weixin.py:1466](gateway/platforms/weixin.py#L1466).

**One-shot script (all four levels in one command):**

```bash
docker compose -f docker-compose.upstream.yml ps && \
echo "--- adapter connected? ---" && \
docker compose -f docker-compose.upstream.yml logs --tail=200 hermes-gateway 2>&1 \
    | grep -E "Connected|Disconnected" | tail -3 && \
echo "--- gateway status ---" && \
docker compose -f docker-compose.upstream.yml exec hermes-gateway hermes gateway status && \
echo "--- recent sessions (send a test message from WeChat first) ---" && \
docker compose -f docker-compose.upstream.yml exec hermes-web ls -la /opt/data/sessions/ | tail -3
```

**Common failure → fix table:**

| Symptom | Likely cause | Fix |
|---|---|---|
| Container `Exit 1` immediately | Config bootstrap or basic_auth misconfig | Check `docker compose logs hermes-web`; if hash looks wrong, run `scripts/fix_dashboard_auth.py` |
| Dashboard returns `401` even with `admin/hermes` | YAML-escaped hash got mangled on first boot | `docker exec -u root hermes-web python3 /tmp/fix.py` then restart |
| Container `Up` but not `healthy` | Wizard hasn't run yet | Run the QR wizard |
| `Connected` then `Disconnected` | Token lock conflict (another profile using same bot) | Stop other profile, restart |
| `getUpdates failed ret=-14` | iLink session expired | Re-run wizard |
| `getUpdates failed ret=-2 errmsg=unknown error` | Stale session signal | Re-run wizard |
| `Connected` but no `inbound` after sending message | WeChat side didn't deliver (iLink bot not in your contacts) | Add the bot as a contact in WeChat first |
| `inbound` appears but no session file | Agent crashed mid-processing | Check `docker compose logs hermes-gateway` for stack traces |
| `ghcr.io/jzkk720/hermes-agent:latest` pull times out | GHCR connectivity or auth | `docker login ghcr.io && docker pull ghcr.io/jzkk720/hermes-agent:latest` |

### 7. Shut down safely when needed

Non-destructive stop:

```bash
docker compose -f docker-compose.upstream.yml down
```

Destructive reset:

```bash
docker compose -f docker-compose.upstream.yml down -v
```

Do not use the destructive reset unless the user clearly wants volumes and persisted state removed.

## Guardrails

- Prefer repo-documented commands from [INSTALL.md](../../../INSTALL.md) over improvised alternatives.
- Do not overwrite an existing `data/.env` without checking whether it contains local secrets.
- Default to [docker-compose.upstream.yml](../../../docker-compose.upstream.yml) for routine no-build install or runtime validation of this fork's wrapper path against the fork's GHCR image.
- Keep the same local env mounts and ports when moving between wrapper validation and raw-upstream comparison; do not introduce alternate host ports unless the user explicitly asks for them.
- If the stack fails because Ollama or another external dependency is unavailable, report that as an environment blocker rather than guessing at code changes.
- The fork's GHCR image publishes on every push to `origin/main`. If you find the local fork checkout out of sync with the published image, pull from origin first; do not edit code locally and then run `docker compose up -d --build`.

## Expected Output Shape

1. what was started or skipped;
2. container status summary;
3. health/log findings by service;
4. next action or blocker.
