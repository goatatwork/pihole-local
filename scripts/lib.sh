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

# --- Docker Desktop live settings ------------------------------------------
# The GUI settings live in a TCC-protected container and can't be read over
# SSH, but Docker Desktop's backend socket serves them to any local process.
_docker_backend_sock() {
  local s="$HOME/Library/Containers/com.docker.docker/Data/backend.sock"
  [ -S "$s" ] && printf '%s' "$s"
}

# _docker_setting <python-expr on `d`>  -> the value, or "" / nonzero on failure
_docker_setting() {
  local sock; sock=$(_docker_backend_sock) || return 1
  curl -s --max-time 5 --unix-socket "$sock" http://localhost/app/settings 2>/dev/null \
    | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
v = ($1)
if isinstance(v, dict): v = v.get('value')
print('' if v is None else v)
" 2>/dev/null
}

# docker_net_setting <key>  ->  true | false | unknown
docker_net_setting() {
  local v; v=$(_docker_setting "d.get('vm',{}).get('network',{}).get('$1')") || { echo unknown; return; }
  case "$v" in True) echo true ;; False) echo false ;; *) echo unknown ;; esac
}

# A Docker-created vmnet bridge — the interface that ends up owning port 53.
_vmnet_bridge_present() {
  ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -qE '^(bridge100|vmenet[0-9]+)$'
}

# "Use kernel networking for UDP" and "Enable host networking" (Settings >
# Resources > Network) both push Docker Desktop onto a vmnet interface. That
# makes macOS bind mDNSResponder to *:53, so the container can never publish
# 127.0.0.1:53 — `docker compose up` fails with "port is already allocated"
# and a bridge100 that returns after every Docker restart. Returns 1 (and
# explains) when the host is in that state.
check_docker_net_mode() {
  local bad=0 kudp host
  kudp=$(docker_net_setting kernelForUDP)
  host=$(docker_net_setting hostNetworkingEnabled)
  [ "$kudp" = true ] && { c_err 'Docker Desktop: "Use kernel networking for UDP" is ON'; bad=1; }
  [ "$host" = true ] && { c_err 'Docker Desktop: "Enable host networking" is ON'; bad=1; }
  if [ "$bad" = 0 ] && _vmnet_bridge_present \
     && lsof -nP -iUDP:53 2>/dev/null | grep -q mDNSResponder; then
    c_err 'vmnet bridge + mDNSResponder on *:53 found — Docker will not get port 53'
    bad=1
  fi
  [ "$bad" = 0 ] && return 0
  cat >&2 <<'MSG'
  This forces Docker onto a vmnet interface; macOS then binds mDNSResponder to
  *:53 and the container can never publish 127.0.0.1:53. A reboot does not help.
  Fix:  ./scripts/fix-docker-network.sh    (turns both off, restarts Docker)
  or:   Docker Desktop > Settings > Resources > Network — turn both off.
MSG
  return 1
}

flush_dns() {
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder 2>/dev/null || true
}

# Docker Desktop not starting at login is the classic footgun for this setup:
# after a reboot Pi-hole never comes back, and a Mac pointed at 127.0.0.1 for
# DNS then has no resolver at all — including for looking up how to fix it.
docker_autostart_state() {
  local v; v=$(_docker_setting "d.get('desktop',{}).get('autoStart')")
  case "$v" in True) echo on; return ;; False) echo off; return ;; esac
  # Fall back to the settings file (readable from a normal user session).
  local f="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
  [ -f "$f" ] || { echo unknown; return; }
  python3 -c "import json,sys; print('on' if json.load(open(sys.argv[1])).get('AutoStart') else 'off')" "$f" 2>/dev/null || echo unknown
}
