#!/usr/bin/env bash
# Prove the resolver actually works, end to end, without touching system DNS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_docker
load_env

fail=0

c_info "Docker Desktop networking mode"
net_mode_ok=1
if check_docker_net_mode; then
  c_ok "userspace path — no vmnet/port-53 conflict"
else
  net_mode_ok=0; fail=1
fi

c_info "Container state"
if [ "$(docker inspect -f '{{.State.Running}}' pihole 2>/dev/null)" = "true" ]; then
  c_ok "pihole running ($(docker inspect -f '{{.Config.Image}}' pihole))"
else
  c_err "pihole container is not running"; exit 1
fi

c_info "UDP/53 resolution via 127.0.0.1"
if out=$(dig +short +timeout=3 +tries=1 @127.0.0.1 example.com A 2>&1) && [ -n "$out" ]; then
  c_ok "UDP: example.com -> $(echo "$out" | head -1)"
else
  c_err "UDP query failed: $out"; fail=1
  [ "$net_mode_ok" = 0 ] && c_warn "  ^ likely the Docker Desktop networking mode flagged above — scripts/fix-docker-network.sh"
fi

c_info "TCP/53 resolution via 127.0.0.1"
if out=$(dig +short +tcp +timeout=3 +tries=1 @127.0.0.1 example.com A 2>&1) && [ -n "$out" ]; then
  c_ok "TCP: example.com -> $(echo "$out" | head -1)"
else
  c_err "TCP query failed: $out"; fail=1
fi

c_info "Blocking behaviour"
blocked=$(dig +short +timeout=3 @127.0.0.1 doubleclick.net A 2>/dev/null | head -1)
if [ -z "$blocked" ] || [ "$blocked" = "0.0.0.0" ]; then
  c_ok "doubleclick.net blocked (returned '${blocked:-NXDOMAIN/empty}')"
else
  c_warn "doubleclick.net -> $blocked (not blocked; gravity list may be empty — run scripts/update.sh)"
fi

c_info "Large response over UDP (Docker proxy truncation check)"
# DNSKEY for .org with DNSSEC is well over 512 bytes — this is the query that
# exposes a UDP proxy that cannot carry full-size DNS responses.
if dnskey=$(dig +timeout=4 +tries=1 +dnssec @127.0.0.1 org DNSKEY 2>/dev/null) \
   && grep -q 'status: NOERROR' <<<"$dnskey" \
   && grep -qE '^org\.[[:space:]]+[0-9]+[[:space:]]+IN[[:space:]]+DNSKEY' <<<"$dnskey"; then
  c_ok "large EDNS response ($(grep -c 'IN[[:space:]]*DNSKEY' <<<"$dnskey") records) survived the Docker UDP proxy"
else
  c_warn "large EDNS response failed or was truncated — see README troubleshooting"
fi

c_info "Web UI"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${WEB_PORT:-8089}/admin/" 2>/dev/null || echo 000)
[ "$code" = "200" ] || [ "$code" = "302" ] \
  && c_ok "admin UI reachable (HTTP $code) at http://127.0.0.1:${WEB_PORT:-8089}/admin/" \
  || { c_err "admin UI returned HTTP $code"; fail=1; }

c_info "Docker Desktop start-at-login"
case "$(docker_autostart_state)" in
  on)  c_ok "enabled — Pi-hole will return after a reboot" ;;
  off) c_warn "DISABLED. After a reboot Docker will not start, so Pi-hole will not
    answer. If system DNS points only at 127.0.0.1 you will have no DNS.
    Fix: Docker Desktop > Settings > General > 'Start Docker Desktop when you sign in'
    Or use: FALLBACK=1 ./scripts/dns-on.sh" ;;
  *)   c_warn "could not determine start-at-login setting" ;;
esac

c_info "System resolver currently in use"
scutil --dns | awk '/nameserver\[0\]/{print "    " $0; exit}'

exit $fail
