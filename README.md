# pihole-local

Pi-hole running on macOS (Apple Silicon), acting as the DNS resolver for the Mac itself.

## Requirements

- macOS on Apple Silicon (developed on macOS 26 "Tahoe", M5)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) — running
- Admin rights (changing the system resolver needs `sudo`)

## Quick start

```bash
git clone <this repo> && cd pihole-local
./scripts/setup.sh      # pulls image, starts Pi-hole, builds blocklists, verifies
./scripts/dns-on.sh     # points macOS at it (sudo)
```

`setup.sh` prints the generated admin password and the UI URL
(`http://127.0.0.1:8089/admin/`). To back out at any time:

```bash
./scripts/dns-off.sh    # restore previous/DHCP DNS
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/setup.sh` | Bootstrap: `.env`, image pull, start, initial gravity build, verify. Re-runnable. |
| `scripts/dns-on.sh` | Point every active network service at `127.0.0.1`. Saves the prior setting. |
| `scripts/dns-off.sh` | Restore the saved setting (or fall back to DHCP). |
| `scripts/update.sh` | Update Pi-hole itself **and** its blocklists. |
| `scripts/verify.sh` | End-to-end checks; touches nothing. |
| `scripts/status.sh` | Container state, Pi-hole version, active system resolver. |
| `scripts/watchdog.sh` | Probe UDP/53; restart the container if it stops answering. |
| `scripts/watchdog-install.sh` | Opt-in: run the watchdog every 2 min via launchd. `--uninstall` to remove. |

## Configuration

`setup.sh` writes `.env` from `.env.example` (gitignored, `chmod 600`):

| Variable | Default | Notes |
| --- | --- | --- |
| `PIHOLE_PASSWORD` | random 20 chars | Admin UI password. |
| `PIHOLE_TAG` | `latest` | Pin to a release (e.g. `2025.08.0`) for reproducibility. |
| `WEB_PORT` | `8089` | Host port for the admin UI. |
| `TZ` | detected | Affects log/graph timestamps. |
| `UPSTREAMS` | `1.1.1.1;9.9.9.9` | Semicolon-separated. |

**Local hostnames.** Public upstreams cannot resolve names your router serves
(`*.lan`, printers, NAS). Either set `UPSTREAMS` to your router
(`192.168.2.1`) or add a conditional forward in the admin UI under
*Settings → DNS → Conditional forwarding*.

## Updating Pi-hole

```bash
./scripts/update.sh
```

This pulls the newest image, recreates the container, runs `pihole -g` to
refresh blocklists, prunes the superseded image, and re-verifies. Your
configuration and query history live in `./etc-pihole/`, which survives the
recreate.

Do **not** run `pihole -up` inside the container — on container images that
command is a no-op by design; the image *is* the unit of update.

Pi-hole also refreshes gravity on its own weekly. `update.sh` is for pulling a
new Pi-hole version and for forcing a blocklist refresh on demand.

## How this works, and why it looks like this

The obvious approach — `docker run` with `-p 53:53/udp` and pointing the Mac at
the container — is the one that fails, and it is worth understanding why before
changing anything here.

On macOS, Docker containers do not run on the Mac. They run inside a Linux VM
that Docker Desktop manages, and every published port is bridged by a userspace
proxy. Two consequences drive this design:

1. **Source addresses are destroyed.** Every DNS query arriving at Pi-hole
   appears to come from the VM's gateway, not from the real client. Per-client
   statistics and per-client group assignment cannot work through that proxy.
   Since only this Mac is a client, that costs nothing here — but it is why
   this repo does not try to serve the LAN.
2. **Pi-hole's default listening mode rejects it.** Pi-hole defaults to
   answering only "local" queries. Traffic emerging from the Docker gateway
   trips that check, and queries are refused with no obvious error. Hence
   `FTLCONF_dns_listeningMode: all` in the compose file — paired with a
   `127.0.0.1`-only host binding so "all" never means "the whole network".

### Why not serve the LAN

Serving other devices would mean binding `0.0.0.0:53` on the Mac. Combined with
`listeningMode: all` that is an open resolver on your network, with no
usable per-client attribution to show for it. If you want Pi-hole for the whole
house, run it on a device that has a real network interface — a Raspberry Pi, a
NAS, or a Linux VM with bridged networking — not behind Docker Desktop's NAT.

### Bootstrap dependency

`dns-on.sh` sets `127.0.0.1` as the only resolver, so **DNS depends on Docker
Desktop being up**. `restart: unless-stopped` brings Pi-hole back with Docker —
but only if Docker itself starts.

> **Check this before you reboot.** Docker Desktop's *Settings → General →
> "Start Docker Desktop when you sign in"* is **off by default**. With it off,
> a reboot leaves you with no Pi-hole and — if `127.0.0.1` is your only
> resolver — no DNS at all. `scripts/verify.sh` warns when this is disabled.

If you would rather trade a little ad-blocking for resilience:

```bash
FALLBACK=1 ./scripts/dns-on.sh   # adds 1.1.1.1 as a secondary
```

macOS will then still resolve when Pi-hole is down — but it may also reach past
Pi-hole when Pi-hole is merely slow, so some queries go unfiltered.

## Reliability of the UDP path

DNS is almost entirely UDP, and on macOS every published UDP port is bridged by
a Docker Desktop userspace proxy. That proxy is the weak link in this design, so
it was tested deliberately:

| Stressor | UDP/53 after |
| --- | --- |
| `pihole -g` (blocklist rebuild, incl. forced re-download) | works |
| `docker compose up -d --force-recreate` × 3 | works |
| `pihole restartdns` (FTL restart only) | works |
| Large DNSSEC response (`org DNSKEY`, >512 B) | works, untruncated |

It held up in all of them. One transient failure *was* observed during
development — UDP/53 stopped forwarding while Pi-hole stayed healthy, with
TCP/53, the admin UI and container-internal resolution all still working — but
it could not be reproduced, and a `docker compose restart` cleared it
immediately. Sleep/wake and network changes are the likeliest triggers.

If you would rather not think about it:

```bash
./scripts/watchdog-install.sh     # probes every 2 min, restarts if UDP is dead
```

The tell-tale symptom is **TCP works, UDP does not**:

```bash
dig +short @127.0.0.1 example.com          # times out
dig +short +tcp @127.0.0.1 example.com     # answers
docker compose restart                      # fixes it
```

## Troubleshooting

**No DNS at all / "server not found" everywhere.** Almost certainly Pi-hole is
not running while `127.0.0.1` is the only resolver. Recover without needing DNS:

```bash
cd /path/to/pihole-local && ./scripts/dns-off.sh
```

If the repo is out of reach, do it by hand:

```bash
sudo networksetup -setdnsservers Wi-Fi Empty
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

**`bind: address already in use` on port 53.** Something else holds the port:

```bash
sudo lsof -nP -iUDP:53 -iTCP:53
```

Common culprits: another Pi-hole/dnsmasq container, `mDNSResponder` in an
unusual configuration, or a VPN client's resolver.

**Queries work with `dig @127.0.0.1` but the browser is unfiltered.** The
system resolver has not picked up the change, or the browser is using
DNS-over-HTTPS and bypassing the OS entirely. Disable "Secure DNS" in
Chrome/Firefox/Safari settings.

**Nothing is blocked.** The blocklist is empty until gravity runs:
`./scripts/update.sh`.

## Uninstall

```bash
./scripts/dns-off.sh
docker compose down
rm -rf etc-pihole .dns-state
```
