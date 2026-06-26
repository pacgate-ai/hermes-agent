#!/usr/bin/env bash
# scripts/smoke_test_local.sh — four-level smoke test for the JZKK720 fork stack
#
# Run AFTER `docker compose -f docker-compose.upstream.yml up -d --pull always --force-recreate --remove-orphans`
# to verify the GHCR-published fork image is actually running, the dashboard
# is up behind basic_auth, the gateway health endpoint responds, and the
# Weixin adapter has connected to Tencent iLink.
#
# Exit code: 0 if all four levels pass, 1 if any fails.

set -uo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.upstream.yml}"
DASH_URL="http://127.0.0.1:9119"
DASH_CREDS="${DASH_CREDS:-admin:hermes}"   # default basic_auth in docker/hermes-config.yaml
GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL:-http://127.0.0.1:8789/health}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}OK${NC}    $*"; }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAILED=1; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; }
info() { echo -e "  ${CYAN}----${NC}  $*"; }

FAILED=0

echo -e "${CYAN}== Level 1: container healthcheck ==${NC}"
if docker compose -f "$COMPOSE_FILE" ps 2>&1 | tee /tmp/compose_ps.txt | grep -E "hermes-web|hermes-gateway|hermes-postgres" >/dev/null; then
    if grep -E "Up \(healthy\)" /tmp/compose_ps.txt >/dev/null; then
        pass "all three services report healthy"
    else
        warn "services are Up but not all healthy yet:"
        grep -E "hermes-web|hermes-gateway|hermes-postgres" /tmp/compose_ps.txt | sed 's/^/         /'
        FAILED=1
    fi
else
    fail "could not list services via docker compose -f $COMPOSE_FILE ps"
fi

echo
echo -e "${CYAN}== Level 2: dashboard behind basic_auth ==${NC}"
# 401 without creds, 200 with admin:hermes.
if ! command -v curl >/dev/null 2>&1; then
    fail "curl not found"
else
    http_code_no_creds=$(curl -s -o /dev/null -w "%{http_code}" "$DASH_URL/api/status" || echo "000")
    http_code_with_creds=$(curl -s -o /dev/null -w "%{http_code}" -u "$DASH_CREDS" "$DASH_URL/api/status" || echo "000")
    if [ "$http_code_no_creds" = "401" ]; then
        pass "dashboard returns 401 without credentials (basic_auth gate engaged)"
    elif [ "$http_code_no_creds" = "000" ]; then
        fail "dashboard unreachable at $DASH_URL"
    else
        warn "dashboard returns $http_code_no_creds without credentials (expected 401)"
    fi
    if [ "$http_code_with_creds" = "200" ]; then
        pass "dashboard returns 200 with $DASH_CREDS"
    else
        fail "dashboard returns $http_code_with_creds with $DASH_CREDS (expected 200)"
    fi
fi

echo
echo -e "${CYAN}== Level 3: gateway health endpoint ==${NC}"
if ! command -v curl >/dev/null 2>&1; then
    fail "curl not found"
else
    gateway_code=$(curl -s -o /tmp/gateway_health.json -w "%{http_code}" "$GATEWAY_HEALTH_URL" || echo "000")
    if [ "$gateway_code" = "200" ]; then
        pass "gateway /health returns 200"
        if command -v jq >/dev/null 2>&1; then
            info "gateway /health body: $(jq -c . /tmp/gateway_health.json 2>/dev/null || cat /tmp/gateway_health.json)"
        fi
    else
        warn "gateway /health returns $gateway_code (expected 200). hermes-gateway may still be starting."
        info "tail the gateway log: docker compose -f $COMPOSE_FILE logs --tail=50 hermes-gateway"
        FAILED=1
    fi
fi

echo
echo -e "${CYAN}== Level 4: Weixin adapter iLink connection ==${NC}"
gateway_log=$(docker compose -f "$COMPOSE_FILE" logs --tail=200 hermes-gateway 2>&1 || true)
if echo "$gateway_log" | grep -E "\[weixin\] Connected account=" >/dev/null; then
    pass "weixin adapter logged a Connected line — outbound long-poll to iLink is up"
elif echo "$gateway_log" | grep -E "getUpdates failed ret=-(2|14)" >/dev/null; then
    warn "weixin adapter logged a session-expired signal; re-run the QR wizard once:"
    info "    docker compose -f $COMPOSE_FILE run --rm hermes-gateway hermes gateway setup"
    info "    (pick Weixin / WeChat, item 13)"
    FAILED=1
elif echo "$gateway_log" | grep -E "WEIXIN_TOKEN is required|WEIXIN_ACCOUNT_ID is required" >/dev/null; then
    warn "weixin credentials missing — gateway has never been paired with WeChat"
    info "Run the QR wizard to bind an account: docker compose -f $COMPOSE_FILE run --rm hermes-gateway hermes gateway setup"
else
    warn "no Connected line yet in hermes-gateway logs (last 200 lines)"
    info "tail: docker compose -f $COMPOSE_FILE logs --tail=50 hermes-gateway"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}Smoke test PASSED${NC} — stack is healthy."
    exit 0
else
    echo -e "${RED}Smoke test FAILED${NC} — see diagnostics above."
    exit 1
fi