#!/usr/bin/env bash
# One-shot bootstrap. Safe to re-run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_docker

if [ ! -f .env ]; then
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
  tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
  sed -e "s/^PIHOLE_PASSWORD=.*/PIHOLE_PASSWORD=$pw/" \
      -e "s|^TZ=.*|TZ=${tz:-UTC}|" .env.example > .env
  chmod 600 .env
  c_ok "Generated .env with a random admin password"
else
  c_info ".env already exists — leaving it alone"
fi

mkdir -p etc-pihole

c_info "Pulling image and starting Pi-hole"
docker compose pull
docker compose up -d

c_info "Waiting for Pi-hole to answer queries"
for i in $(seq 1 60); do
  if dig +short +timeout=1 +tries=1 @127.0.0.1 example.com >/dev/null 2>&1; then
    c_ok "Answering after ${i}s"; break
  fi
  [ "$i" = "60" ] && die "Pi-hole never came up. Check: docker compose logs pihole"
  sleep 1
done

# A fresh install has no blocklists until gravity runs.
if [ ! -s etc-pihole/gravity.db ]; then
  c_info "Building initial blocklist (this takes a minute)"
  docker exec pihole pihole -g || c_warn "gravity build failed; run scripts/update.sh later"
fi

echo
"$REPO_ROOT/scripts/verify.sh" || true
echo
c_ok "Admin UI: http://127.0.0.1:$(grep -E '^WEB_PORT=' .env | cut -d= -f2)/admin/"
c_ok "Password: $(grep -E '^PIHOLE_PASSWORD=' .env | cut -d= -f2)"
echo
c_info "Pi-hole is running but macOS is NOT using it yet."
c_info "Run: scripts/dns-on.sh    (needs sudo; undo with scripts/dns-off.sh)"
