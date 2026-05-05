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
        TZ_CHOSEN="$choice"
        return 0
      fi
      echo "Invalid choice."
    done
  done
}

ensure_service_started() {
  if systemctl list-unit-files | grep -q '^chrony\.service'; then
    systemctl enable --now chrony
  elif systemctl list-unit-files | grep -q '^chronyd\.service'; then
    systemctl enable --now chronyd
  else
    echo "chrony service not found."
    exit 1
  fi
}

main() {
  require_root

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y chrony

  systemctl disable --now systemd-timesyncd 2>/dev/null || true

  choose_timezone

  local default_cidr
  default_cidr="$(ip -4 route | awk '/proto kernel/ {print $1; exit}')"
  [[ -z "${default_cidr:-}" ]] && default_cidr="0.0.0.0/0"

  echo
  read -rp "Allowed client subnet/CIDR [${default_cidr}]: " ALLOW_CIDR
  ALLOW_CIDR="${ALLOW_CIDR:-$default_cidr}"

  local conf="/etc/chrony/chrony.conf"
  local backup="${conf}.bak.$(date +%F_%H%M%S)"
  cp "$conf" "$backup"

  sed -i -E '/^[[:space:]]*allow[[:space:]]+/d' "$conf"
  if ! grep -qE '^[[:space:]]*rtcsync([[:space:]]|$)' "$conf"; then
    echo "rtcsync" >> "$conf"
  fi
  if ! grep -qE '^[[:space:]]*makestep[[:space:]]+' "$conf"; then
    echo "makestep 1.0 3" >> "$conf"
  fi

  {
    echo
    echo "# Added by setup-ntp-server.sh"
    echo "allow $ALLOW_CIDR"
  } >> "$conf"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow 123/udp >/dev/null 2>&1 || true
  fi

  ensure_service_started
  systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true

  echo
  echo "Server setup complete."
  echo "Timezone: $(timedatectl show -p Timezone --value)"
  echo "Allowed clients: $ALLOW_CIDR"
  echo
  chronyc tracking || true
  chronyc sources -v || true
}

main "$@"