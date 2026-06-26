---
description: "Use when editing docker-compose.yml, INSTALL.md, docker deploy scripts, or deployment comments for the Ollama/WeChat stack. Keeps Docker docs aligned with the fork's GHCR image source, state-preserving update commands, and mounted local customizations."
name: "Docker Deployment Docs"
applyTo:
  - "docker-compose.yml"
  - "docker-compose.upstream.yml"
  - "docker-compose.windows.yml"
  - "INSTALL.md"
  - "docker/*.sh"
  - "docker/*.yaml"
  - ".github/workflows/fork-ghcr-publish.yml"
---

# Docker Deployment Docs

- Keep deployment comments and install docs aligned with the real compose behavior. The fork's image source is **the fork's own GHCR image** (`ghcr.io/jzkk720/hermes-agent:latest`), published by [fork-ghcr-publish.yml](../../.github/workflows/fork-ghcr-publish.yml). The docs should reference `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans` for routine refreshes, not `--build`.
- Do not describe the fork's image as Docker Hub-backed. The validated publish target in this repo is `ghcr.io/jzkk720/hermes-agent` (via `HERMES_FORK_IMAGE` env override; default falls back to the upstream `docker.io/nousresearch/hermes-agent:latest` for one-off debugging only).
- Preserve mention of fork-local overlays when they exist. In this repo, [docker/hermes-config.yaml](../../docker/hermes-config.yaml) stays bind-mounted in the default compose lane. It now ships a `dashboard.basic_auth` block (username `admin`, password `hermes`, scrypt hash) so the standard `docker compose up -d` "just works" under upstream 0.17+ auth gate. The host port stays bound to `127.0.0.1:9119`; only the container-internal bind is `0.0.0.0`.
- Treat [docker-compose.upstream.yml](../../docker-compose.upstream.yml) as the preferred pulled-image refresh lane for this fork's routine updates against the fork's GHCR image.
- If `8644` is documented, be explicit about whether the webhook platform is actually enabled by default or whether the port is only pre-published for later use.
- Treat `data/.env`, `data/config.yaml`, `data/weixin/accounts/`, and the PostgreSQL volume as persistent state in both docs and commands. Avoid suggesting `docker compose down -v` except for explicit reset instructions.
- When changing update instructions, include a smoke-test step that checks `docker compose ps`, the dashboard status endpoint (with `admin/hermes` credentials), the gateway `/health` endpoint, and `scripts/smoke_test_local.sh` for the full sequence.
- When the WeChat gateway credentials seem missing or expired, point users at [scripts/fix_dashboard_auth.py](../../scripts/fix_dashboard_auth.py) for the dashboard auth recovery and the QR wizard (`docker compose -f docker-compose.upstream.yml run --rm hermes-gateway hermes gateway setup`, then pick item 13) for WeChat.
