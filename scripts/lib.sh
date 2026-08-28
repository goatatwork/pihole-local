# Shared helpers. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# .env values are needed by the scripts, not just by compose. Parse it safely
# (values may contain ';', which the shell would treat as a command separator).
load_env() {
  [ -f "$REPO_ROOT/.env" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue ;; esac
    v="${v%\"}"; v="${v#\"}"
    export "$k=$v"
  done < "$REPO_ROOT/.env"
}

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }
c_info() { printf '\033[36m→\033[0m %s\n' "$*"; }
die()    { c_err "$*"; exit 1; }

# Network services that are enabled (no leading '*') and thus worth touching.
active_services() {
  networksetup -listallnetworkservices \
    | tail -n +2 \
    | grep -v '^\*'
}

require_docker() {
  command -v docker >/dev/null || die "docker not found. Install Docker Desktop."
  docker info >/dev/null 2>&1 || die "Docker daemon not running. Start Docker Desktop, then retry."
}

flush_dns() {
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder 2>/dev/null || true
}

# Docker Desktop not starting at login is the classic footgun for this setup:
# after a reboot Pi-hole never comes back, and a Mac pointed at 127.0.0.1 for
# DNS then has no resolver at all — including for looking up how to fix it.
docker_autostart_state() {
  local f="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
  [ -f "$f" ] || { echo unknown; return; }
  python3 -c "import json,sys; print('on' if json.load(open(sys.argv[1])).get('AutoStart') else 'off')" "$f" 2>/dev/null || echo unknown
}
