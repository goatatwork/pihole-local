#!/usr/bin/env bash
# Probe UDP/53 from the host and restart the container if it stops answering.
#
# Rationale: Docker Desktop bridges UDP through a userspace proxy. That proxy
# was observed once, during development, to stop forwarding while Pi-hole
# itself stayed healthy (TCP/53 and the admin UI kept working, container-
# internal resolution kept working). It could not be reproduced deliberately —
# gravity runs, container recreates and FTL restarts all left it intact — so
# treat it as rare, not routine. Sleep/wake and network changes are the most
# likely real-world triggers. A container restart clears it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ok() { dig +short +timeout=2 +tries=1 @127.0.0.1 example.com >/dev/null 2>&1; }

# Two strikes, so a single slow response does not cause a restart.
if ok; then exit 0; fi
sleep 3
if ok; then exit 0; fi

logger -t pihole-watchdog "UDP/53 not answering; restarting pihole container"
echo "$(date '+%F %T') UDP/53 down — restarting container" >> "$REPO_ROOT/.watchdog.log"
docker compose restart >/dev/null 2>&1 || true

sleep 5
if ok; then
  echo "$(date '+%F %T') recovered" >> "$REPO_ROOT/.watchdog.log"
else
  echo "$(date '+%F %T') STILL DOWN after restart" >> "$REPO_ROOT/.watchdog.log"
fi
