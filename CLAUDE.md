# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Pi-hole running under Docker Desktop on macOS (Apple Silicon), serving DNS to
the Mac itself and nothing else. See [INTENT.md](INTENT.md) for the original
goal and [README.md](README.md) for user-facing docs.

There is no build and no test suite. The repo is a compose file plus bash
scripts; `scripts/verify.sh` is the closest thing to a test — run it after any
change to `docker-compose.yml`.

## Commands

```bash
./scripts/setup.sh              # bootstrap (idempotent)
./scripts/watchdog.sh           # one-shot UDP/53 probe + restart-if-dead
./scripts/verify.sh             # end-to-end checks, mutates nothing — use as the test
./scripts/status.sh             # container state, version, active system resolver
./scripts/update.sh             # update Pi-hole image + blocklists
./scripts/dns-on.sh             # point macOS at Pi-hole (sudo)
./scripts/dns-off.sh            # restore previous/DHCP DNS (sudo)
./scripts/fix-docker-network.sh # disable the Docker Desktop options that break port 53
```

`bash -n scripts/*.sh` to syntax-check.

## The two constraints that shape everything here

Docker containers on macOS run inside Docker Desktop's Linux VM, and published
ports are bridged by a userspace proxy. This is why the naive
`docker run -p 53:53/udp` approach in the `goatatwork/pihole` repo failed, and
it explains both non-obvious settings in `docker-compose.yml`:

1. **`FTLCONF_dns_listeningMode: all` is load-bearing.** Pi-hole defaults to
   answering only "local" queries. Every query through the Docker proxy appears
   to originate from the VM gateway, fails that check, and is refused — with no
   useful error. Removing this line silently breaks all resolution.
2. **The `127.0.0.1:`-prefixed port bindings are a safety pairing with #1.**
   `listeningMode: all` plus an all-interfaces bind would be an open resolver on
   the LAN. Never widen these bindings without removing `listeningMode: all`.

The proxy also rewrites source addresses, so per-client stats and per-client
groups cannot work. That is accepted, not a bug to fix — serving the LAN is
explicitly out of scope (README explains the alternative).

### Docker Desktop options that silently break port 53

Two toggles under **Settings → Resources → Network** move Docker Desktop off
the default userspace (gvisor) path and onto a `vmnet` interface:

- **Use kernel networking for UDP** (`kernelForUDP`)
- **Enable host networking** (`hostNetworkingEnabled`)

Either one creates a `bridge100`/`vmenet0` interface. macOS reacts by starting
its Internet-Sharing stack, which **binds `mDNSResponder` to `*:53`** — so the
container can no longer publish `127.0.0.1:53` and `docker compose up` fails
with:

```text
ports are not available: exposing port UDP 127.0.0.1:53 -> 127.0.0.1:0: port is already allocated
```

Signature to recognise it: that error, `sudo lsof -iUDP:53` shows
`mDNSResponder` on `*:53`, and `ifconfig` shows a `bridge100` **that comes back
after every Docker restart and even after a reboot** — an ordinary port
conflict does neither. Someone enabling `kernelForUDP` to "make UDP more
reliable" is the likely origin; the working reference machine has both off.

Handled in code: `lib.sh:check_docker_net_mode` detects it, `setup.sh` refuses
to run until it's clear, `verify.sh` flags it, and `scripts/fix-docker-network.sh`
turns both off via Docker Desktop's backend socket
(`~/Library/Containers/com.docker.docker/Data/backend.sock`) and restarts
Docker. The settings themselves can't be edited from a file over SSH (TCC
protects the `group.com.docker` container) — only the GUI or that socket.

**On the UDP proxy's reliability.** It was stress-tested (gravity incl. forced
re-download, repeated `--force-recreate`, `restartdns`, >512 B DNSSEC
responses) and held every time. One unreproducible transient was seen where
UDP/53 stopped forwarding while TCP/53, the admin UI and container-internal
resolution all still worked; `docker compose restart` cleared it. That is what
`scripts/watchdog.sh` exists for. Do not escalate this into a rewrite without
first reproducing a failure — the signature to look for is **TCP works, UDP
does not**. Gravity is not the trigger (it completes in ~0.5 s and causes no
outage window).

## Working on this

- **`etc-pihole/` is the live Pi-hole state** (config, gravity DB, query
  history), bind-mounted and gitignored. It survives `docker compose up
  --force-recreate`; `rm -rf` it and you lose settings and history.
- **`.env` is gitignored and holds the generated admin password.** `.env.example`
  is the tracked template — add new variables to both, with a default in
  `docker-compose.yml` (`${VAR:-default}`).
- **Pi-hole v6** merged dnsmasq config into `pihole.toml`; there is no
  `/etc/dnsmasq.d` volume and `FTLCONF_*` env vars are the configuration
  surface. Guidance written for v5 will not apply.
- **Do not run `pihole -up` in the container** — updating means pulling a new
  image (`scripts/update.sh`).
- `scripts/dns-on.sh` refuses to run unless Pi-hole is already answering, and
  saves the prior resolver to `.dns-state/` first. Keep that guard: without it a
  failed setup leaves the Mac with no DNS and no easy way to look up the fix.

## Environment notes

- macOS 26 (Tahoe), arm64. Images must be `linux/arm64`.
- `limactl` is **not** installed, despite INTENT.md saying it is. A Lima-based
  approach (VM with its own host-reachable IP) is the fallback if the Docker
  proxy ever proves inadequate; it would need `brew install lima` first.
