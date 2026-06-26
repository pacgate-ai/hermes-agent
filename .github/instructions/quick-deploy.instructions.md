---
description: "Use when the user asks to install, deploy, or spin up the Hermes stack on a new machine from the fork. Provides the canonical one-liner and post-install WeChat onboarding steps so the local agent can execute the deployment without manual lookup."
name: "Quick Deploy from Fork"
applyTo:
  - "docker/deploy.sh"
  - "docker-compose.upstream.yml"
  - "INSTALL.md"
  - "scripts/smoke_test_local.sh"
---

# Quick Deploy from Fork

This fork's canonical deployment path is the fork's own GHCR image
(`ghcr.io/jzkk720/hermes-agent:latest`) wrapped by fork-owned compose files.
The image is built and published by [`.github/workflows/fork-ghcr-publish.yml`](../../.github/workflows/fork-ghcr-publish.yml) on every push to `origin/main` and bakes in the WeChat web QR onboarding, the dashboard `basic_auth` provider, and the `scripts/fix_dashboard_auth.py` recovery path. Do **not** use `docker compose up -d --build` for routine installs — that builds from local source and is only for testing fork code changes.

## One-liner (fresh machine)

```bash
curl -fsSL https://raw.githubusercontent.com/JZKK720/hermes-agent/main/docker/deploy.sh | bash
```

Prerequisites on the target machine:
- Docker + Docker Compose v2
- Ollama running on host port 11434 with a model pulled:
  ```bash
  ollama pull gemma4:e4b-it-q8_0
  ```

## What the deploy script does

1. Clones `JZKK720/hermes-agent` (skipped if already cloned)
2. Creates `data/` and seeds `data/.env` from `docker/hermes-env.example`
3. Runs `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans`

## Post-install: dashboard login + connect WeChat

The dashboard now requires basic_auth (upstream 0.17+ refuses non-loopback binds without an auth provider).

1. Open `http://localhost:9119` in a browser → log in with **`admin` / `hermes`** (default baked into `docker/hermes-config.yaml`).
2. To change the password, generate a new scrypt hash on the host:
   ```bash
   docker exec hermes-web python3 -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-new-password'))"
   ```
   paste it into `data/config.yaml` under `dashboard.basic_auth.password_hash`, then `docker compose -f docker-compose.upstream.yml restart hermes-web`.
3. Channels page → **WeChat** card → click **"Set up with QR"** → scan the QR with the WeChat phone app → confirm. Credentials are saved automatically; the gateway restarts. No terminal, CLI, or TTY required — the web QR onboarding flow handles everything.

If YAML escaping on first boot mangles the hash and locks you out, run:
```bash
docker cp scripts/fix_dashboard_auth.py hermes-web:/tmp/fix.py
docker exec -u root hermes-web python3 /tmp/fix.py
docker compose -f docker-compose.upstream.yml restart hermes-web
```

## Routine updates (existing machine)

```bash
cd hermes-agent
git pull origin main
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

This preserves `data/.env`, `data/config.yaml`, sessions, memories, and the PostgreSQL volume while refreshing the fork's GHCR image.

To fall back to the upstream Docker Hub image (no fork features):
```bash
HERMES_FORK_IMAGE=docker.io/nousresearch/hermes-agent:latest \
  docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

## Services after deploy

| Service | URL / Port | Notes |
|---------|-----------|-------|
| Hermes Web UI | `http://localhost:9119` | Login: `admin / hermes` |
| WeChat gateway | outbound only | Long-poll to Tencent iLink, no host port |
| API server | `http://localhost:8789` | OpenAI-compatible |
| Webhook | `http://localhost:8644` | When `platforms.webhook.enabled: true` |
| PostgreSQL | `localhost:5433` | Internal database |

## Smoke test

```bash
docker compose ps
bash scripts/smoke_test_local.sh
curl -fsS -u admin:hermes http://127.0.0.1:9119/api/status
```

All three containers should show `(healthy)`. The smoke script runs four levels: container healthcheck → dashboard basic_auth → gateway `/health` → WeChat iLink `Connected` log line.
