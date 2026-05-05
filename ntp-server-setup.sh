#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run this script as root or with sudo."
    exit 1
  fi
}

choose_timezone() {
  local query=""
  local -a zones=()
  local choice=""

  while true; do
    echo
    read -rp "Enter a timezone search term (e.g. Europe, Asia, Berlin): " query
    mapfile -t zones < <(timedatectl list-timezones | grep -i -- "${query:-.}" || true)

    if ((${#zones[@]} == 0)); then
      echo "No matching timezones found."
      continue
    fi

    echo
    select choice in "${zones[@]}"; do
      if [[ -n "${choice:-}" ]]; then
        timedatectl set-timezone "$choice"
        echo "Timezone set to: $choice"
        return 0
      fi
      echo "Invalid choice."
    done
  done
}

ensure_service_started() {
  echo "Starting chrony service..."

  systemctl daemon-reload

  systemctl enable chrony
  systemctl restart chrony

  if ! systemctl is-active --quiet chrony; then
    echo "❌ chrony failed to start"
    systemctl status chrony --no-pager
    exit 1
  fi

  echo "✅ chrony is running"
}

main() {
  require_root

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y chrony

  # Disable default time sync
  systemctl disable --now systemd-timesyncd 2>/dev/null || true

  choose_timezone

  # Backup config
  local conf="/etc/chrony/chrony.conf"
  local backup="${conf}.bak.$(date +%F_%H%M%S)"
  cp "$conf" "$backup"

  # Remove old allow rules
  sed -i -E '/^[[:space:]]*allow[[:space:]]+/d' "$conf"

  # Ensure required options
  grep -q "^rtcsync" "$conf" || echo "rtcsync" >> "$conf"
  grep -q "^makestep" "$conf" || echo "makestep 1.0 3" >> "$conf"

  # 🔥 Allow ALL IPs
  echo "" >> "$conf"
  echo "# Allow all clients (public NTP server)" >> "$conf"
  echo "allow 0.0.0.0/0" >> "$conf"

  # Open firewall
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 123/udp >/dev/null 2>&1 || true
  fi

  ensure_service_started
  systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true

  echo
  echo "✅ NTP Server is now PUBLIC"
  echo "Timezone: $(timedatectl show -p Timezone --value)"
  echo "Allowed: ALL IPs (0.0.0.0/0)"
  echo

  chronyc tracking || true
  chronyc sources -v || true
}

main "$@"