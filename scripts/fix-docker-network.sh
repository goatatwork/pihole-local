#!/usr/bin/env bash
# Turn off the two Docker Desktop options that stop the container from binding
# 127.0.0.1:53 on macOS — "Use kernel networking for UDP" (kernelForUDP) and
# "Enable host networking" (hostNetworkingEnabled) — then restart Docker
# Desktop. Idempotent. Pass -y to skip the confirmation prompt.
#
# These settings live in a TCC-protected container, so they can't be edited
# from a file over SSH; this talks to Docker Desktop's local backend socket
# instead (the same thing the GUI toggles write to).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

yes=0
[ "${1:-}" = "-y" ] && yes=1

sock=$(_docker_backend_sock) \
  || die "Docker Desktop backend socket not found — is Docker Desktop running?"

kudp=$(docker_net_setting kernelForUDP)
host=$(docker_net_setting hostNetworkingEnabled)

if [ "$kudp" != true ] && [ "$host" != true ]; then
  c_ok "Nothing to do (kernelForUDP=$kudp, hostNetworkingEnabled=$host)."
  _vmnet_bridge_present && c_warn "A vmnet bridge is still present — reboot to clear it."
  exit 0
fi

c_warn "Will disable  kernelForUDP=$kudp  hostNetworkingEnabled=$host  and restart Docker Desktop."
if [ "$yes" = 0 ]; then
  printf 'Proceed? [y/N] '
  read -r ans || ans=
  case "$ans" in y|Y) ;; *) die "Aborted." ;; esac
fi

curl -s -o /dev/null --fail -X POST --unix-socket "$sock" \
  -H 'Content-Type: application/json' \
  -d '{"vm":{"network":{"kernelForUDP":false,"hostNetworkingEnabled":false}}}' \
  http://localhost/app/settings \
  || die "Failed to update Docker Desktop settings via the backend socket."
c_ok "Settings updated."

c_info "Restarting Docker Desktop (~30s)…"
if ! docker desktop restart >/dev/null 2>&1; then
  osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
  sleep 5
  open -a Docker
fi

c_info "Waiting for the daemon…"
for i in $(seq 1 90); do
  docker info >/dev/null 2>&1 && { c_ok "Docker is back."; break; }
  [ "$i" = 90 ] && die "Docker did not come back up — start it manually and re-check."
  sleep 2
done

if _vmnet_bridge_present; then
  c_warn "vmnet bridge still present. Reboot once to clear it, then run scripts/verify.sh."
else
  c_ok "No vmnet bridge. Run: ./scripts/setup.sh"
fi
