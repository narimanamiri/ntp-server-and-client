# ntp-server-and-client

Bash setup scripts for deploying a **chrony**-based NTP server and clients on
Debian/Ubuntu systems.

## Scripts
- **`ntp-server-setup.sh`** — interactive server setup: installs chrony, lets
  you pick a timezone, choose manual (offline authoritative) or internet-synced
  mode, opens UDP/123, and starts the service.
- **`ntp-client-setup.sh`** — interactive client setup: installs chrony, picks a
  timezone, validates and configures the NTP server IP, and forces an initial
  step-sync.
- **`ntp-server-non-interactive.sh`** / **`ntp-client-non-interactive.sh`** —
  unattended variants for scripted provisioning.

All scripts use `set -euo pipefail`, require root, and back up `chrony.conf`
before changing it.

## Requirements
- A Debian/Ubuntu host with `apt-get` and `systemd`.
- Run as root (or via `sudo`).

## Usage
```bash
sudo ./ntp-server-setup.sh        # on the server
sudo ./ntp-client-setup.sh        # on each client
```
