#!/usr/bin/env bash
# Restore DNS to whatever it was before dns-on.sh (usually DHCP).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STATE_DIR="$REPO_ROOT/.dns-state"

while IFS= read -r svc; do
  [ -z "$svc" ] && continue
  f="$STATE_DIR/$(echo "$svc" | tr ' /' '__').prev"
  if [ -f "$f" ] && ! grep -qi "There aren't any DNS Servers set" "$f"; then
    # shellcheck disable=SC2046
    sudo networksetup -setdnsservers "$svc" $(cat "$f")
    c_ok "$svc restored to $(tr '\n' ' ' < "$f")"
  else
    sudo networksetup -setdnsservers "$svc" Empty
    c_ok "$svc reverted to DHCP-provided DNS"
  fi
done < <(active_services)

flush_dns
c_ok "System DNS restored."
