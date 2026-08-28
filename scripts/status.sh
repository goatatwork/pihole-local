#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
docker compose ps
echo
docker exec pihole pihole -v 2>/dev/null || true
echo
printf 'System resolver: '; scutil --dns | awk '/nameserver\[0\]/{print $3; exit}'
