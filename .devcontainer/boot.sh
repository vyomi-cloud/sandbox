#!/usr/bin/env bash
# Vyomi Cloud Sandbox boot orchestrator (P0 MVP). See plan §3.1, §3.3, §3.8.
#
#   boot.sh up          → start the aws-core stack, register with the cost meter
#   boot.sh heartbeat    → (re)arm the running-time heartbeat + the TTL reaper
#
# All portal calls are fail-soft: metering must never block the sandbox.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="$HERE/docker-compose.sandbox.yml"

PORTAL="${VYOMI_LICENSE_BACKEND_URL:-https://vyomi.cloud}"
CODESPACE="${CODESPACE_NAME:-vyomi-sandbox-local}"
ORG="${GITHUB_REPOSITORY_OWNER:-}"
GH_USER="${GITHUB_USER:-}"
PROFILE="${VYOMI_PROFILE:-all-clouds}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-aws,gcp,azure}"; export COMPOSE_PROFILES
BILLING="${VYOMI_BILLING:-free_personal_quota}"
TTL="${VYOMI_SANDBOX_TTL:-8h}"
FWD_DOMAIN="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"

RUN_DIR="${HOME}/.vyomi-sandbox"
mkdir -p "$RUN_DIR"
HB_PID="$RUN_DIR/heartbeat.pid"
REAP_PID="$RUN_DIR/reaper.pid"

# Forwarded public URL — wins for GCP self-links; empty when run locally.
if [ -n "${CODESPACE_NAME:-}" ]; then
  export CLOUDLEARN_PUBLIC_URL="https://${CODESPACE_NAME}-9000.${FWD_DOMAIN}"
fi

log() { echo "[vyomi-sandbox] $*"; }

post() {  # post <path> <json>   (fail-soft)
  curl -fsS -m 10 -X POST "$PORTAL$1" -H 'Content-Type: application/json' -d "$2" >/dev/null 2>&1 || true
}

ttl_seconds() {  # 8h | 90m | 1d | 1w → seconds
  local t="$1" n unit
  n="${t%[hmdw]}"; unit="${t##*[0-9]}"
  case "$unit" in
    m) echo $(( n * 60 )) ;;
    h) echo $(( n * 3600 )) ;;
    d) echo $(( n * 86400 )) ;;
    w) echo $(( n * 604800 )) ;;
    *) echo $(( ${n:-8} * 3600 )) ;;
  esac
}

start_stack() {
  log "pulling + starting stack (profile=$PROFILE · clouds=$COMPOSE_PROFILES)…"
  docker compose -f "$COMPOSE" up -d
  log "waiting for the simulator (http://localhost:9000/healthz)…"
  for i in $(seq 1 60); do
    if curl -fsS -m 3 http://localhost:9000/healthz >/dev/null 2>&1; then
      log "simulator is up."
      if [ -n "${CLOUDLEARN_PUBLIC_URL:-}" ]; then
        log "console → ${CLOUDLEARN_PUBLIC_URL}"
      fi
      return 0
    fi
    sleep 3
  done
  log "WARNING: simulator did not report healthy in time (continuing)."
}

provision() {
  local ttl_s; ttl_s="$(ttl_seconds "$TTL")"
  log "registering sandbox with the cost meter (org=${ORG:-personal} billing=$BILLING profile=$PROFILE)…"
  post /api/sandbox/provision "$(cat <<JSON
{"codespace_id":"$CODESPACE","org":"$ORG","owner_email":"${GH_USER:+$GH_USER@users.noreply.github.com}","github_login":"$GH_USER","profile_id":"$PROFILE","compute_profile":"S","billing":"$BILLING","ttl_seconds":$ttl_s,"install_id":"$CODESPACE"}
JSON
)"
}

start_heartbeat() {
  # Idempotent: don't start a second loop.
  if [ -f "$HB_PID" ] && kill -0 "$(cat "$HB_PID")" 2>/dev/null; then
    log "heartbeat already running (pid $(cat "$HB_PID"))."; return 0
  fi
  log "arming running-time heartbeat (every 5 min)…"
  ( while true; do
      post /api/sandbox/heartbeat "{\"codespace_id\":\"$CODESPACE\"}"
      sleep 300
    done ) >/dev/null 2>&1 &
  echo $! > "$HB_PID"
  disown 2>/dev/null || true
}

arm_reaper() {
  # MVP-lite TTL: after VYOMI_SANDBOX_TTL, stop the stack + tell the meter.
  # (Hard org-level scheduled-Action reaper is a fast-follow; GitHub idle/
  # retention is the backstop.)
  if [ -f "$REAP_PID" ] && kill -0 "$(cat "$REAP_PID")" 2>/dev/null; then
    return 0
  fi
  local ttl_s; ttl_s="$(ttl_seconds "$TTL")"
  log "arming TTL reaper ($TTL = ${ttl_s}s)…"
  ( sleep "$ttl_s"
    post /api/sandbox/teardown "{\"codespace_id\":\"$CODESPACE\"}"
    docker compose -f "$COMPOSE" down 2>/dev/null || true
    echo "$(date -u +%FT%TZ) sandbox TTL reached ($TTL) — stack stopped." > "$RUN_DIR/EXPIRED"
  ) >/dev/null 2>&1 &
  echo $! > "$REAP_PID"
  disown 2>/dev/null || true
}

case "${1:-up}" in
  up)
    start_stack
    provision
    start_heartbeat
    arm_reaper
    log "ready. Open the forwarded port 9000 to reach the console."
    ;;
  heartbeat)
    start_heartbeat
    arm_reaper
    ;;
  *)
    echo "usage: boot.sh [up|heartbeat]" >&2; exit 2 ;;
esac
