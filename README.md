# ntp-server-and-client

Bash setup scripts for deploying a **chrony**-based NTP server and clients on
Debian/Ubuntu systems. There are interactive variants (prompt for timezone,
mode and server IP) and non-interactive variants (take arguments, for scripted
provisioning), plus a small health-check script.

## Scripts

| Script | Purpose |
| --- | --- |
| `ntp-server-setup.sh` | Interactive server setup. Installs chrony, lets you pick a timezone, and choose **manual** (offline authoritative) or **internet-synced + local fallback** mode. Opens UDP/123 (via `ufw`, if present) and starts the service. |
| `ntp-client-setup.sh` | Interactive client setup. Installs chrony, picks a timezone, validates the NTP server IPv4 address, configures it as the time source, and forces an initial step-sync. |
| `ntp-server-non-interactive.sh` | Unattended **manual/offline** server. Takes a manual time as its single argument, sets timezone `Asia/Tehran`, and serves time at stratum 10. |
| `ntp-client-non-interactive.sh` | Unattended client. Takes the NTP server IPv4 address as its single argument and sets timezone `Asia/Tehran`. |
| `ntp-verify.sh` | Health check for any chrony host. Prints tracking/sources and exits `0` if synchronized, `1` if not, `2` if `chronyc` is missing. Runs without root. |

All scripts use `set -euo pipefail`, require root (except `ntp-verify.sh`), and
back up an existing `/etc/chrony/chrony.conf` before overwriting it.

> Note: the non-interactive scripts hardcode the `Asia/Tehran` timezone. Edit
> the `configure_timezone` function if you need a different zone.

## Requirements

- A Debian/Ubuntu host with `apt-get`, `systemd` and `timedatectl`.
- Root privileges (run the setup scripts via `sudo`). `ufw` is optional; the
  firewall rule is added only if `ufw` is installed.
- Internet access on the host to install the `chrony` package.

## Server setup

Interactive:

```bash
sudo ./ntp-server-setup.sh
```

You will be prompted for a timezone and a mode:

1. **Manual time** — offline authoritative server. You enter the current time
   (`YYYY-MM-DD HH:MM:SS`); the server serves that clock at stratum 10.
2. **Internet sync + fallback** (recommended) — syncs from `pool.ntp.org` and
   falls back to its own clock (`local stratum 10 orphan`) only if the pool is
   unreachable.

Non-interactive (manual/offline only):

```bash
sudo ./ntp-server-non-interactive.sh '2026-06-17 12:00:00'
```

## Client setup

Interactive (prompts for the server IP):

```bash
sudo ./ntp-client-setup.sh
```

Non-interactive (server IP as argument):

```bash
sudo ./ntp-client-non-interactive.sh 192.168.1.10
```

Both client scripts validate that the server address is a well-formed IPv4
address before writing the config, then restart chrony and force an initial
`chronyc makestep`.

## Verify / health check

Run on either the server or a client to confirm synchronization:

```bash
./ntp-verify.sh
```

Exit codes:

- `0` — synchronized (chrony reports `Leap status : Normal`)
- `1` — not synchronized yet
- `2` — `chronyc` not found (chrony not installed)
