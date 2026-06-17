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
| `ntp-server-setup-multi.sh` | **Cross-distro** non-interactive server setup (Debian/Ubuntu **and** RHEL/CentOS/Fedora/Rocky/Alma). Auto-detects package manager, service name, config path and firewall tool. Supports `--dry-run` (prints the `chrony.conf` it would write, applies nothing). |
| `ntp-status.sh` | Readable status table: stratum, last offset, RMS offset, root dispersion and the selected upstream source, each graded against a threshold. Runs without root. |
| `ntp-syncnow.sh` | One-shot force resync (`chronyc burst` + `makestep`). Steps the clock immediately. Requires root. |
| `ntp-uninstall.sh` | Cleanly reverts the setup: stops/disables chrony, restores the most recent config backup, re-enables `systemd-timesyncd`. Optional `--purge` and `--dry-run`. Requires root. |
| `ntp-verify.sh` | Health check for any chrony host. Prints tracking/sources and exits `0` if synchronized, `1` if not, `2` if `chronyc` is missing. Runs without root. |

All scripts use `set -euo pipefail`, require root (except `ntp-verify.sh`,
`ntp-status.sh` and dry-runs), and back up an existing chrony config before
overwriting it.

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

## Cross-distro server setup (Debian/Ubuntu + RHEL family)

`ntp-server-setup-multi.sh` is a non-interactive server installer that works on
both the Debian/Ubuntu and the RHEL/CentOS/Fedora/Rocky/Alma families. It
auto-detects, from `/etc/os-release` and the available tooling:

| | Debian / Ubuntu | RHEL / CentOS / Fedora |
| --- | --- | --- |
| Package manager | `apt-get` | `dnf` (or `yum`) |
| Service name | `chrony` | `chronyd` |
| Config path | `/etc/chrony/chrony.conf` | `/etc/chrony.conf` |
| Firewall | `ufw` | `firewalld` |

Online server (sync from a pool, serve to a subnet), set the timezone too:

```bash
sudo ./ntp-server-setup-multi.sh \
  --mode online \
  --pool pool.ntp.org \
  --allow 192.168.1.0/24 \
  --timezone Europe/Berlin
```

Offline/manual authoritative server (stratum 10, fixed clock):

```bash
sudo ./ntp-server-setup-multi.sh --mode manual --time '2026-06-17 12:00:00'
```

**Dry run** — preview the exact `chrony.conf` and the planned actions without
installing, writing, or starting anything (does not require root):

```bash
./ntp-server-setup-multi.sh --dry-run --mode online --allow 10.0.0.0/8
```

Options: `-m/--mode`, `-t/--time`, `-p/--pool`, `-a/--allow`, `-z/--timezone`,
`-n/--dry-run`, `-h/--help`. Exit codes: `0` success/dry-run, `1` action failed
or unsupported distro, `2` bad arguments, `3` not root (real run only).

## Status table

`ntp-status.sh` parses `chronyc tracking` and `chronyc sources` into a compact,
graded table. It needs no root:

```bash
./ntp-status.sh
```

```
======================  NTP STATUS  ======================
Reference ID:      C0A8010A (ntp.example.lan)
Selected source:   192.168.1.10
...
METRIC         VALUE                THRESHOLD    GRADE
------------------------------------------------------------
Stratum        3                    <= 10        OK
Last offset    +0.000023456 s       <= 0.1 s     OK
RMS offset     0.000034567 s        -            -
Root disp.     0.000045678 s        <= 0.05 s    OK
------------------------------------------------------------
Result: OK
```

Tune the thresholds:

```bash
./ntp-status.sh -o 0.05 -j 0.02 -s 5    # offset / jitter / stratum limits
```

Exit codes: `0` synced and within thresholds, `1` synced but a metric exceeded
its threshold (WARN), `2` `chronyc` missing, `3` not synchronized.

## Force an immediate resync

`ntp-syncnow.sh` requests a measurement burst from all sources and then steps
the clock with `chronyc makestep`. Useful right after configuring a client or
after a large drift. Requires root (talks to the chronyd command socket):

```bash
sudo ./ntp-syncnow.sh          # default 8s burst window
sudo ./ntp-syncnow.sh -w 12    # wait 12s for samples before stepping
```

Exit codes: `0` step requested, `1` chronyd not running / step failed,
`2` `chronyc` missing, `3` not root.

## Uninstall / revert

`ntp-uninstall.sh` undoes what the setup scripts did. By default it stops and
disables chrony, restores the most recent `chrony.conf.bak.*` backup, and
re-enables `systemd-timesyncd` so the host still tracks time. It auto-detects
the Debian vs RHEL service name and config path.

```bash
sudo ./ntp-uninstall.sh                 # restore backup, keep chrony installed
sudo ./ntp-uninstall.sh --purge -y      # also remove the chrony package, no prompt
sudo ./ntp-uninstall.sh --dry-run       # show what would happen, change nothing
sudo ./ntp-uninstall.sh --remove-config # if no backup exists, delete the config
```

Options: `-n/--dry-run`, `-p/--purge`, `--remove-config`, `-y/--yes`,
`-h/--help`. Exit codes: `0` success/dry-run, `1` action failed, `3` not root.
