# Hermes-Agent — Installation Guide

Deploy the JZKK720/hermes-agent fork with Ollama, PostgreSQL, and WeChat personal-account chat using Docker Compose.

## Prerequisites

| Requirement | Install |
|---|---|
| Docker + Docker Compose v2 | https://docs.docker.com/get-docker/ |
| Git | https://git-scm.com/ |
| Ollama | https://ollama.com/ |

### Pull the default model

```bash
ollama pull gemma4:e4b-it-q8_0
```

To use a different model, follow the [Change the model](#change-the-model) section after install.

---

## Quick Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/JZKK720/hermes-agent/main/docker/deploy.sh | bash
```

The script clones the repo, seeds `data/.env`, and recreates all services from the fork's GHCR-published `ghcr.io/jzkk720/hermes-agent:latest` image with the upstream-image compose file.

Routine updates on an existing machine stay pinned to the fork's GHCR image:

```bash
git pull origin main
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

To fall back to the upstream Docker Hub image, set `HERMES_FORK_IMAGE=docker.io/nousresearch/hermes-agent:latest` before running compose.

---

## Manual Install

### 1. Clone the fork

```bash
git clone https://github.com/JZKK720/hermes-agent.git
cd hermes-agent
```

### 2. Create the data directory and env file

```bash
mkdir -p data
cp docker/hermes-env.example data/.env
```

Edit `data/.env` if needed (see [Configuration](#configuration) below). For a plain Ollama setup no changes are required.

### 3. Start all services

```bash
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

This keeps the local `data/.env`, `data/config.yaml`, sessions, memories, and PostgreSQL data while pulling the fork's GHCR-published image. Use this pulled-image compose path for routine refreshes on this fork; do not switch the machine to a fork-owned build lane for normal updates.

---

## Services

| Service | URL | Description |
|---|---|---|
| Hermes Web UI | http://localhost:9119 | Chat interface — login **admin / hermes** on first boot |
| WeChat gateway | outbound only | `hermes-gateway` runs the gateway with `weixin` (WeChat personal) enabled. No host port — uses outbound long-poll to Tencent iLink. |
| PostgreSQL | localhost:5433 | Internal database (host port 5433) |

### Connect WeChat (one-shot)

The `hermes gateway setup` subcommand does **not** accept a platform argument — it opens an interactive menu. From the menu, pick `Weixin / WeChat` (item **13** in the default list).

```bash
docker compose -f docker-compose.upstream.yml run --rm hermes-gateway \
    hermes gateway setup
```

When prompted `Select [1-27] (27):`, type `13` and press Enter.

The wizard prints an ASCII QR code in the terminal. Scan it with the WeChat app on your phone (Settings → Plugins → search "iLink Bot" if not visible), confirm in WeChat, and the wizard saves credentials to `data/weixin/accounts/<account_id>.json` automatically.

Then bring the gateway up:

```bash
docker compose -f docker-compose.upstream.yml up -d hermes-gateway
```

You only need to run the wizard once per WeChat account. To re-bind a different account, repeat the command and the wizard will save a separate JSON file.

### Interactive CLI

```bash
docker exec -it hermes-web hermes
```

### Useful commands

```bash
docker compose -f docker-compose.upstream.yml logs -f                                                # stream logs from all services
docker compose -f docker-compose.upstream.yml logs -f hermes-web                                     # web UI logs only
docker compose -f docker-compose.upstream.yml logs -f hermes-gateway                                 # WeChat gateway logs only
docker compose -f docker-compose.upstream.yml down                                                   # stop all services
docker compose -f docker-compose.upstream.yml down -v                                                # stop + delete volumes (resets data!)
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans # start or refresh from the fork GHCR image
```

### Smoke test

```bash
docker compose ps
curl -fsS http://127.0.0.1:9119/api/status    # prompts for admin/hermes first; use -u admin:hermes for non-interactive probes
```

The web UI healthcheck on `:9119` is the primary smoke signal. The WeChat gateway has no public HTTP port — verify with `docker compose logs hermes-gateway` and look for a successful iLink `getupdates` long-poll connection.

For a full four-level smoke test (container healthcheck → adapter Connected log → gateway status CLI → end-to-end inbound), use the `docker-compose-smoke-test` skill.

---

## Configuration

### `data/.env` — secrets (never committed to git)

| Variable | Purpose | Required |
|---|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL container password (matches compose default `changeme`) | No — defaults to `changeme` |
| `TELEGRAM_BOT_TOKEN` | Telegram gateway | Optional |
| `DISCORD_BOT_TOKEN` | Discord gateway | Optional |
| `SLACK_BOT_TOKEN` / `SLACK_APP_TOKEN` | Slack gateway | Optional |
| `EXA_API_KEY` | AI-native web search | Optional |

WeChat personal accounts (`weixin`) do not use tokens — credentials are obtained via the QR wizard and saved to `data/weixin/accounts/`.

### `data/config.yaml` — runtime settings

Auto-created from `docker/hermes-config.yaml` on first start.  
Edit directly; no rebuild needed — takes effect on next container restart.

The `dashboard.basic_auth` block defines the dashboard login. Default credentials are `admin / hermes`. **Change the password** by generating a new hash:

```bash
docker exec hermes-web python3 -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-new-password'))"
```

Replace the `password_hash` line in `data/config.yaml`, then restart:

```bash
docker compose -f docker-compose.upstream.yml restart hermes-web
```

If YAML escaping mangles the hash on first boot and you get locked out, run the repair script (no rebuild needed):

```bash
docker cp scripts/fix_dashboard_auth.py hermes-web:/tmp/fix.py
docker exec -u root hermes-web python3 /tmp/fix.py   # the script must run as root to rewrite data/config.yaml
docker compose -f docker-compose.upstream.yml restart hermes-web
```

### Change the model

Edit `data/config.yaml`:

```yaml
model:
  default: "llama3.3:70b"        # any model pulled in Ollama
  context_length: 131072
```

Then restart the containers:

```bash
docker compose -f docker-compose.upstream.yml restart hermes-web hermes-gateway
```

---

## Keeping Up to Date

### Pull your own fork changes

```bash
git pull origin main
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

This is the normal update path for this fork. Keep regular refreshes pinned to the fork's GHCR image through the fork wrapper; do not treat `upstream/main` merges as part of the routine local update flow for this machine.

### Refresh containers from the fork's GHCR image

```bash
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

This updates the Hermes containers from the fork's GHCR-published image while keeping your local `data/.env`, `data/config.yaml`, sessions, and other persisted runtime data.

---

## Troubleshooting

### Web UI not reachable

```bash
docker compose ps              # check service state
docker compose logs hermes-web # read startup output
```

If the dashboard binds 0.0.0.0 inside the container (which is required for Docker port forwarding under upstream 0.17+), it MUST have an auth provider configured — the login challenge will fail otherwise. See [Configuration](#data-configyaml--runtime-settings) for changing the password or repairing a YAML-mangled hash.

### Model calls fail / "unknown provider"

Ensure Ollama is running on the host and the model is pulled:

```bash
ollama list
ollama pull gemma4:e4b-it-q8_0
```

Check `data/config.yaml` has `provider: "custom"` (not `"ollama"`).

### `hermes-web` and `hermes-gateway` drift to different image digests

Recreate both services together so the dashboard and gateway stay on the same fork image generation:

```bash
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

### Pull fails resolving `ghcr.io/jzkk720/hermes-agent:latest`

That reference is the fork's GHCR image source. The fork publishes its own image (with Weixin QR onboarding + dashboard auth) to GHCR via the `fork-ghcr-publish.yml` workflow. If Docker reports a timeout or `failed to do request: Head ...`, treat it as a GHCR connectivity or auth problem on the machine.

```bash
docker login ghcr.io
docker pull ghcr.io/jzkk720/hermes-agent:latest
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

To fall back to the upstream Docker Hub image (which does not include the fork's Weixin QR / dashboard auth fixes), set:

```bash
HERMES_FORK_IMAGE=docker.io/nousresearch/hermes-agent:latest docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

### `8644` does not respond

Webhook platform is no longer pre-published in this stack. To enable inbound webhooks, bind `:8644` in `docker-compose.yml` on the `hermes-gateway` service (already done by default) and set `platforms.webhook.enabled: true` in `data/config.yaml`.

### Reset everything (start fresh)

```bash
docker compose down -v   # removes named volumes (including postgres_data — all DB rows gone)
rm -rf data/             # removes persisted data (config, sessions, memories, weixin/accounts)
docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans
```

---

## Ports Reference

| Port (host) | Port (container) | Service |
|---|---|---|
| 9119 | 9119 | Hermes Web UI (basic_auth required) |
| 8789 | 8789 | API server (OpenAI-compatible) |
| 8644 | 8644 | Webhook (when enabled) |
| — | — | `hermes-gateway` (WeChat gateway, outbound only — no host port) |
| 5433 | 5432 | PostgreSQL |