#!/usr/bin/env bash
# Point macOS at the local Pi-hole. Saves the previous setting first.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STATE_DIR="$REPO_ROOT/.dns-state"; mkdir -p "$STATE_DIR"

# Refuse to hijack the system resolver unless Pi-hole is actually answering.
if ! dig +short +timeout=3 +tries=1 @127.0.0.1 example.com >/dev/null 2>&1; then
  die "Pi-hole is not answering on 127.0.0.1:53. Run scripts/verify.sh first — refusing to break your DNS."
fi

# FALLBACK=1 keeps a public resolver as secondary so a stopped container can
# never leave the Mac with no DNS at all. It leaks some queries past Pi-hole
# when the primary is slow, so it is off by default.
servers=("127.0.0.1")
[ "${FALLBACK:-0}" = "1" ] && servers+=("1.1.1.1")

while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  networksetup -getdnsservers "$svc" > "$STATE_DIR/$(echo "$svc" | tr ' /' '__').prev" 2>/dev/null || true
  sudo networksetup -setdnsservers "$svc" "${servers[@]}"
  c_ok "$svc -> ${servers[*]}"
done < <(active_services)

flush_dns
c_ok "System DNS now points at Pi-hole. Undo with: scripts/dns-off.sh"
