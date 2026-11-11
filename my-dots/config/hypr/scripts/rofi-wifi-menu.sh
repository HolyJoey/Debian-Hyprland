#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# Rofi WiFi menu - list nearby networks via NetworkManager and connect.

set -euo pipefail

ROFI_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config.rasi"
WIFI_DEV="$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')"

# --rescan: wait for a fresh scan (used by the Rescan action). Default opens
# straight from NetworkManager's cache so the menu appears instantly.
force_rescan=0
[[ "${1:-}" == "--rescan" ]] && force_rescan=1

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u low "WiFi" "$1"
  else
    printf '%s\n' "$1" >&2
  fi
}

if [[ -z "${WIFI_DEV}" ]]; then
  notify "No WiFi device found"
  exit 1
fi

# Close any existing rofi before launching
if pgrep -x "rofi" >/dev/null 2>&1; then
  pkill rofi
fi

menu() {
  rofi -dmenu -i -p "WiFi" -mesg "$1" -config "${ROFI_CONFIG}"
}

# Returns the 0-based index of the selection, so SSIDs are never recovered by
# parsing the display string (they may contain spaces, colons, trailing blanks).
menu_index() {
  rofi -dmenu -i -p "WiFi" -mesg "$1" -format i -config "${ROFI_CONFIG}"
}

signal_icon() {
  local s="$1"
  if   (( s >= 80 )); then printf '󰤨'
  elif (( s >= 60 )); then printf '󰤥'
  elif (( s >= 40 )); then printf '󰤢'
  elif (( s >= 20 )); then printf '󰤟'
  else                     printf '󰤯'
  fi
}

radio="$(nmcli -t radio wifi)"
if [[ "${radio}" == "disabled" ]]; then
  choice="$(printf '󰖩  Turn WiFi on\n󰅖  Cancel' | menu 'WiFi is currently disabled')"
  case "${choice}" in
    *"Turn WiFi on"*) nmcli radio wifi on && notify "WiFi enabled - rescanning..." ;;
  esac
  exit 0
fi

# ACTIVE:SIGNAL:SECURITY:SSID - SSID last so embedded colons survive.
# Read once and reuse: a plain `wifi list` blocks on a fresh scan (~2s each
# call), while --rescan no returns NetworkManager's cache in milliseconds.
scan_list() {
  nmcli -t -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list \
    ifname "${WIFI_DEV}" --rescan "$1" 2>/dev/null || true
}

if (( force_rescan )); then
  raw="$(scan_list yes)"
else
  raw="$(scan_list no)"
  if [[ -z "${raw//[[:space:]]/}" ]]; then
    # Empty cache (first open after boot/resume): fall back to a real scan.
    raw="$(scan_list yes)"
  else
    # Refresh in the background so the next open is up to date.
    setsid nmcli device wifi rescan ifname "${WIFI_DEV}" >/dev/null 2>&1 &
  fi
fi

active_ssid="$(printf '%s\n' "${raw}" \
  | awk -F: '$1=="yes"{sub(/^[^:]*:[^:]*:[^:]*:/, ""); gsub(/\\:/, ":"); print; exit}')"

# Dedupe by SSID keeping the strongest signal; skip hidden (empty) SSIDs.
networks="$(
  printf '%s\n' "${raw}" \
  | awk -F: '
      {
        active=$1; signal=$2; sec=$3
        ssid=$0
        sub(/^[^:]*:[^:]*:[^:]*:/, "", ssid)
        gsub(/\\:/, ":", ssid)
        if (ssid == "") next
        # An SSID stays marked active even when a stronger AP of the same
        # network is not the one we are associated with.
        if (active == "yes") act[ssid]="yes"
        if (!(ssid in best) || signal+0 > best[ssid]+0) {
          best[ssid]=signal; secu[ssid]=sec
          if (!(ssid in act)) act[ssid]=active
          if (!(ssid in seen)) { seen[ssid]=1; order[++n]=ssid }
        }
      }
      END { for (i=1;i<=n;i++) { s=order[i]; print act[s] "|" best[s] "|" secu[s] "|" s } }
    ' \
  | sort -t'|' -k2 -rn
)"

ssids=()
secs=()
entries=""
while IFS='|' read -r active signal sec ssid; do
  [[ -n "${ssid}" ]] || continue
  ssids+=("${ssid}")
  secs+=("${sec}")
  icon="$(signal_icon "${signal}")"
  lock=""
  [[ -n "${sec}" && "${sec}" != "--" ]] && lock="󰌾"
  mark="  "
  [[ "${active}" == "yes" ]] && mark="󰄬 "
  entries+="$(printf '%s%s  %-28s %3s%%  %s' "${mark}" "${icon}" "${ssid}" "${signal}" "${lock}")"$'\n'
done <<< "${networks}"

actions=$'󰑓  Rescan\n󰖪  Disconnect\n󰖩  Turn WiFi off\n󱂇  Manual (nmtui)'

if [[ -n "${active_ssid}" ]]; then
  msg="Connected to ${active_ssid}"
else
  msg='Select a network to connect'
fi

count="${#ssids[@]}"
index="$(printf '%s%s\n' "${entries}" "${actions}" | menu_index "${msg}")"
[[ "${index}" =~ ^[0-9]+$ ]] || exit 0

if (( index >= count )); then
  case "$(( index - count ))" in
    0) exec "$0" --rescan ;;
    1) nmcli device disconnect "${WIFI_DEV}" >/dev/null && notify "Disconnected"; exit 0 ;;
    2) nmcli radio wifi off && notify "WiFi disabled"; exit 0 ;;
    3) exec "${HOME}/.config/hypr/scripts/WaybarScripts.sh" --nmtui ;;
    *) exit 0 ;;
  esac
fi

ssid="${ssids[$index]}"
secured="${secs[$index]}"
[[ -n "${ssid}" ]] || exit 0

if [[ "${ssid}" == "${active_ssid}" ]]; then
  notify "Already connected to ${ssid}"
  exit 0
fi

# Known connection? Bring it up without prompting.
if nmcli -t -f NAME connection show | grep -Fxq "${ssid}"; then
  if nmcli connection up id "${ssid}" >/dev/null 2>&1; then
    notify "Connected to ${ssid}"
    exit 0
  fi
  notify "Saved profile for ${ssid} failed - asking for password"
fi

if [[ -n "${secured}" && "${secured}" != "--" ]]; then
  password="$(printf '' | rofi -dmenu -password -p "Password" \
    -mesg "Password for ${ssid}" -config "${ROFI_CONFIG}")"
  [[ -n "${password}" ]] || exit 0
  if nmcli device wifi connect "${ssid}" password "${password}" ifname "${WIFI_DEV}" >/dev/null 2>&1; then
    notify "Connected to ${ssid}"
  else
    notify "Failed to connect to ${ssid} - wrong password?"
    exit 1
  fi
else
  if nmcli device wifi connect "${ssid}" ifname "${WIFI_DEV}" >/dev/null 2>&1; then
    notify "Connected to ${ssid}"
  else
    notify "Failed to connect to ${ssid}"
    exit 1
  fi
fi
