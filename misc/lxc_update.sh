#!/usr/bin/env bash

# Proxmox LXC Updater (Universal)
# Autor: klugec88
# Lizenz: MIT

function header_info {
  clear
  cat <<"EOF"
   __  __          __      __          __   _  ________
  / / / /___  ____/ /___ _/ /____     / /  | |/ / ____/
 / / / / __ \/ __  / __ `/ __/ _ \   / /   |   / /    
/ /_/ / /_/ / /_/ / /_/ / /_/  __/  / /___/   / /___  
\____/ .___/\__,_/\__,_/\__/\___/  /_____/_/|_\____/  
    /_/                                              
EOF
}

set -eEuo pipefail
header_info
echo "LXC Update Script startet..."

NODE=$(hostname)
EXCLUDE_MENU=()
MSG_MAX_LENGTH=0
while read -r TAG ITEM; do
  OFFSET=2
  ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
  EXCLUDE_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

excluded_containers=$(whiptail --backtitle "Proxmox LXC Updater" --title "Container auf $NODE" --checklist "\nContainer auswählen, die NICHT aktualisiert werden sollen:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${EXCLUDE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"') || exit

declare -a containers_needing_reboot=()
declare -a updated_containers=()
declare -a unchanged_containers=()
declare -a skipped_containers=()
declare -a autoremove_containers=()

# Standard-Deutsch-Umgebung
DE_LOCALE="de_DE.UTF-8"
EXPORT_ENV="env LANG=$DE_LOCALE LC_ALL=$DE_LOCALE LANGUAGE=de"

function set_locale() {
  container=$1
  # Sicherstellen, dass locale installiert und korrekt konfiguriert ist
  current_locale=$(pct exec "$container" -- bash -c "echo \$LANG" 2>/dev/null || echo "")
  if [[ -z "$current_locale" || "$current_locale" != "$DE_LOCALE" ]]; then
    echo "[Info] Setze Locale auf $DE_LOCALE im Container $container"
    pct exec "$container" -- bash -c "apt-get update && apt-get install -y locales"
    pct exec "$container" -- bash -c "sed -i '/$DE_LOCALE/s/^# //g' /etc/locale.gen && locale-gen"
    pct exec "$container" -- bash -c "update-locale LANG=$DE_LOCALE"
  fi
}

function update_container() {
  container=$1
  name=$(pct exec "$container" hostname 2>/dev/null || echo "Unbekannt")
  os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  echo -e "\n[Info] Aktualisiere Container: $container ($name, OS: $os)\n"
  set_locale "$container"

  updates_before=0
  updates_after=0

  case "$os" in
    alpine)
      pct exec "$container" -- sh -c "$EXPORT_ENV apk update && $EXPORT_ENV apk upgrade"
      ;;
    archlinux)
      pct exec "$container" -- bash -c "$EXPORT_ENV pacman -Syyu --noconfirm"
      ;;
    fedora | rocky | centos | alma)
      pct exec "$container" -- bash -c "$EXPORT_ENV dnf -y update && $EXPORT_ENV dnf -y upgrade"
      ;;
    ubuntu | debian | devuan)
      updates_before=$(pct exec "$container" -- $EXPORT_ENV bash -c "apt-get -s dist-upgrade | grep -c '^Inst ' || true")
      pct exec "$container" -- $EXPORT_ENV bash -c "apt-get update && apt-get -yq dist-upgrade"

      autoremove_needed=$(pct exec "$container" -- $EXPORT_ENV bash -c "apt-get -s autoremove | grep 'The following packages will be REMOVED' || echo ''")
      if [[ -n "$autoremove_needed" ]]; then
        echo "[Info] Führe 'apt autoremove' auf $container aus..."
        pct exec "$container" -- $EXPORT_ENV bash -c "apt-get -yq autoremove"
        autoremove_containers+=("$container ($name)")
      fi
      updates_after=$(pct exec "$container" -- $EXPORT_ENV bash -c "apt-get -s dist-upgrade | grep -c '^Inst ' || true")
      ;;
    opensuse)
      pct exec "$container" -- bash -c "$EXPORT_ENV zypper ref && $EXPORT_ENV zypper --non-interactive dup"
      ;;
    *)
      echo "[Warnung] OS $os wird nicht unterstützt oder nicht erkannt."
      return
      ;;
  esac

  if [[ "$updates_before" -gt 0 && "$updates_after" -eq 0 ]]; then
    updated_containers+=("$container ($name)")
  else
    unchanged_containers+=("$container ($name)")
  fi

  if pct exec "$container" -- [ -e "/var/run/reboot-required" ]; then
    containers_needing_reboot+=("$container ($name)")
  fi
}

for container in $(pct list | awk 'NR>1 {print $1}'); do
  if [[ " ${excluded_containers[@]} " =~ " $container " ]]; then
    echo "[Info] Überspringe Container $container"
    skipped_containers+=("$container")
    continue
  fi
  status=$(pct status $container | awk '{print $2}')
  if [[ "$status" == "stopped" ]]; then
    echo "[Info] Starte Container $container"
    pct start $container
    sleep 5
  fi
  update_container "$container"
done

header_info
echo -e "\n[Info] Update abgeschlossen!"
if [ "${#updated_containers[@]}" -gt 0 ]; then
  echo -e "\n[Erfolgreich aktualisierte Container]:"
  printf '%s\n' "${updated_containers[@]}"
fi
if [ "${#unchanged_containers[@]}" -gt 0 ]; then
  echo -e "\n[Keine Updates für folgende Container]:"
  printf '%s\n' "${unchanged_containers[@]}"
fi
if [ "${#skipped_containers[@]}" -gt 0 ]; then
  echo -e "\n[Übersprungene Container]:"
  printf '%s\n' "${skipped_containers[@]}"
fi
if [ "${#containers_needing_reboot[@]}" -gt 0 ]; then
  echo -e "\n[Hinweis] Die folgenden Container benötigen einen Neustart:"
  printf '%s\n' "${containers_needing_reboot[@]}"
fi
if [ "${#autoremove_containers[@]}" -gt 0 ]; then
  echo -e "\n[Autoremove durchgeführt in folgenden Containern]:"
  printf '%s\n' "${autoremove_containers[@]}"
fi
