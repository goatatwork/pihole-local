#!/usr/bin/env bash
# Update Pi-hole itself (container image) and its blocklists.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_docker

before=$(docker inspect -f '{{.Image}}' pihole 2>/dev/null || echo none)

c_info "Pulling latest image"
docker compose pull

c_info "Recreating container"
docker compose up -d

after=$(docker inspect -f '{{.Image}}' pihole 2>/dev/null || echo none)
if [ "$before" = "$after" ]; then
  c_ok "Already on the latest image"
else
  c_ok "Image updated"
  c_info "Version now: $(docker exec pihole pihole -v 2>/dev/null | tr '\n' ' ')"
fi

c_info "Updating blocklists (gravity)"
docker exec pihole pihole -g

c_info "Removing superseded images"
docker image prune -f >/dev/null

echo
"$REPO_ROOT/scripts/verify.sh"
