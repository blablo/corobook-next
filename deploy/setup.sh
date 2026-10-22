#!/usr/bin/env bash
#
# Interactive Corobook production setup.
#
# Asks the handful of questions the deploy needs, writes deploy/.env.prod, then
# brings up the Corobook app stack (web + postgres + worker). The shared Caddy
# edge is separate infra and must already be running (external `edge` network).
# Re-runnable: existing values are offered as defaults and you can skip the bring-up.
#
# Usual entry point is the Makefile:  make -C deploy setup
# (or run this directly:  bash deploy/setup.sh)

set -euo pipefail

# ── resolve paths relative to this script, so it works from any CWD ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_PROD="$DEPLOY_DIR/.env.prod"
MASTER_KEY_FILE="$REPO_ROOT/config/master.key"

# ── colors (fall back to plain if not a tty) ──
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# read an existing KEY=value from an env file (first match), empty if absent
read_env() { # file key
  [ -f "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" | head -n1
}

# prompt with a default; echoes the chosen value
ask() { # prompt default
  local prompt="$1" default="${2:-}" reply
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply
    printf '%s' "${reply:-$default}"
  else
    read -r -p "$prompt: " reply
    printf '%s' "$reply"
  fi
}

# prompt for a secret (no echo); keeps existing value on empty input
ask_secret() { # prompt had_existing
  local prompt="$1" had="$2" reply
  if [ "$had" = "yes" ]; then
    read -r -s -p "$prompt [keep existing]: " reply; echo
  else
    read -r -s -p "$prompt: " reply; echo
  fi
  printf '%s' "$reply"
}

confirm() { # prompt default(Y/n)
  local prompt="$1" default="${2:-Y}" reply
  read -r -p "$prompt [$([ "$default" = Y ] && echo 'Y/n' || echo 'y/N')]: " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ── docker compose shim (v2 plugin or legacy v1) ──
if docker compose version >/dev/null 2>&1; then
  DC() { docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  DC() { docker-compose "$@"; }
else
  DC() { die "docker compose not found — install Docker + the Compose plugin."; }
fi

hdr "Corobook production setup"
say  "${DIM}Writes deploy/.env.prod, then brings up the Corobook app stack.${RESET}"
say  "${DIM}The shared Caddy edge (external 'edge' network) must already be running.${RESET}"
command -v docker >/dev/null 2>&1 || die "docker not found on PATH."

# ─────────────────────────────── questions ───────────────────────────────
hdr "1) Hostname"
DEF_HOST="$(read_env "$ENV_PROD" APP_HOST)"; DEF_HOST="${DEF_HOST:-corobook.duckdns.org}"
APP_HOST="$(ask "Public hostname Corobook is served at (no scheme)" "$DEF_HOST")"
[ -n "$APP_HOST" ] || die "A hostname is required."
say "${DIM}Its A record must point at this server; church subdomains will be <church>.$APP_HOST${RESET}"

hdr "2) Rails master key"
DEF_MK="$(read_env "$ENV_PROD" RAILS_MASTER_KEY)"
MK_HAD="no"; [ -n "$DEF_MK" ] && MK_HAD="yes"
if [ -z "$DEF_MK" ] && [ -f "$MASTER_KEY_FILE" ]; then
  if confirm "Found config/master.key — use it?" Y; then
    DEF_MK="$(tr -d '[:space:]' < "$MASTER_KEY_FILE")"; MK_HAD="yes"
    ok "Using config/master.key"
  fi
fi
RAILS_MASTER_KEY="$(ask_secret "RAILS_MASTER_KEY (hidden)" "$MK_HAD")"
RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-$DEF_MK}"
[ -n "$RAILS_MASTER_KEY" ] || die "RAILS_MASTER_KEY is required (contents of config/master.key)."

hdr "3) Database password"
DEF_PW="$(read_env "$ENV_PROD" COROBOOK_NEXT_DATABASE_PASSWORD)"
PW_HAD="no"; [ -n "$DEF_PW" ] && PW_HAD="yes"
if [ -z "$DEF_PW" ] && confirm "Generate a strong Postgres password automatically?" Y; then
  DEF_PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
  PW_HAD="yes"; ok "Generated a 32-char password."
fi
DB_PW="$(ask_secret "COROBOOK_NEXT_DATABASE_PASSWORD (hidden)" "$PW_HAD")"
DB_PW="${DB_PW:-$DEF_PW}"
[ -n "$DB_PW" ] || die "A database password is required."

hdr "4) Mail (optional on production)"
say "${DIM}If the domain isn't verified with your mail provider, confirmation emails won't deliver —${RESET}"
say "${DIM}the on-screen fallback link still works. See docs/mail-setup.md.${RESET}"
DEF_MD="$(read_env "$ENV_PROD" MAIL_DOMAIN)"; DEF_MD="${DEF_MD:-example.com}"
MAIL_DOMAIN="$(ask "Mail domain" "$DEF_MD")"
DEF_MF="$(read_env "$ENV_PROD" MAIL_FROM)"; DEF_MF="${DEF_MF:-Corobook <no-reply@$MAIL_DOMAIN>}"
MAIL_FROM="$(ask "Mail 'from' address" "$DEF_MF")"

# ─────────────────────────────── write env file ───────────────────────────────
hdr "Writing env file"

umask 077   # secrets → owner-only

cat > "$ENV_PROD" <<EOF
# Corobook production env — generated by deploy/setup.sh. Gitignored (holds secrets).
APP_HOST=$APP_HOST
RAILS_MASTER_KEY=$RAILS_MASTER_KEY
COROBOOK_NEXT_DATABASE_PASSWORD=$DB_PW
MAIL_DOMAIN=$MAIL_DOMAIN
MAIL_FROM=$MAIL_FROM
EOF
ok "Wrote ${ENV_PROD#$REPO_ROOT/}"

umask 022

# ─────────────────────────────── bring up ───────────────────────────────
if ! confirm "Bring Corobook up now (docker compose up)?" Y; then
  hdr "Setup complete — not started."
  say "Start later with:"
  say "  ${BOLD}make -C deploy up${RESET}"
  exit 0
fi

if ! docker network inspect edge >/dev/null 2>&1; then
  die "The external 'edge' network is missing. Start the shared Caddy edge (separate infra) first, then re-run."
fi

hdr "Building + starting Corobook"
( cd "$DEPLOY_DIR" && DC --env-file .env.prod -f docker-compose.prod.yml up -d --build )
ok "Corobook up (postgres + web + worker)."

hdr "Done"
say "Corobook should be reachable at ${BOLD}https://$APP_HOST${RESET} once the shared Caddy edge"
say "routes it and its DNS points at this server."
say ""
say "Check app health:   ${DIM}curl -I https://$APP_HOST/up${RESET}"
say "Follow app logs:    ${DIM}make -C deploy logs${RESET}"
say "Routing (add this app to the shared Caddy) is configured in the edge infra, not here."
