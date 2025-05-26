#!/usr/bin/env bash

# Proxmox LXC Updater (Universal)
# Autor: Dein Name
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
declare -a custom_updates=()

function set_locale() {
  container=$1
  pct exec "$container" -- bash -c "sed -i -e 's/# de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen && locale-gen de_DE.UTF-8" 2>/dev/null || true
  pct exec "$container" -- bash -c "update-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8" 2>/dev/null || true
  pct exec "$container" -- bash -c "export LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8"
}

function update_custom_apps() {
  container=$1
  name=$(pct exec "$container" hostname 2>/dev/null || echo "Unbekannt")
  
  # Traefik Update
  if pct exec "$container" -- bash -c "[ -f /usr/local/bin/traefik ]"; then
    echo "[Info] Traefik gefunden in $container ($name), versuche Update..."
    traefik_version=$(pct exec "$container" -- bash -c "/usr/local/bin/traefik version 2>/dev/null | head -n 1 | awk '{print \$3}'" || echo "")
    if [ -n "$traefik_version" ]; then
      latest_version=$(pct exec "$container" -- bash -c "curl -s https://api.github.com/repos/traefik/traefik/releases/latest | grep 'tag_name' | cut -d '\"' -f 4 | tr -d 'v'")
      
      if [ "$traefik_version" != "$latest_version" ]; then
        echo "[Info] Aktualisiere Traefik von $traefik_version auf $latest_version"
        pct exec "$container" -- bash -c "curl -fsSL -o /tmp/traefik_linux-amd64.tar.gz https://github.com/traefik/traefik/releases/download/v${latest_version}/traefik_v${latest_version}_linux-amd64.tar.gz"
        pct exec "$container" -- bash -c "tar -xzf /tmp/traefik_linux-amd64.tar.gz -C /usr/local/bin/ traefik && rm /tmp/traefik_linux-amd64.tar.gz"
        new_version=$(pct exec "$container" -- bash -c "/usr/local/bin/traefik version 2>/dev/null | head -n 1 | awk '{print \$3}'")
        custom_updates+=("$container ($name): Traefik von $traefik_version auf $new_version aktualisiert")
        pct exec "$container" -- bash -c "systemctl restart traefik.service || true"
      else
        echo "[Info] Traefik ist bereits auf der neuesten Version ($traefik_version)"
      fi
    fi
  fi

  # Hier können weitere benutzerdefinierte Updates hinzugefügt werden
}

function update_container() {
  container=$1
  name=$(pct exec "$container" hostname 2>/dev/null || echo "Unbekannt")
  os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  echo -e "\n[Info] Aktualisiere Container: $container ($name, OS: $os)\n"
  set_locale "$container"

  export_env="env LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8"

  updates_before=0
  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "devuan" ]]; then
    updates_before=$(pct exec "$container" -- $export_env bash -c "apt-get -s dist-upgrade | grep -c '^Inst ' || true")
  fi

  case "$os" in
    alpine) pct exec "$container" -- ash -c "$export_env apk update && $export_env apk upgrade" ;;
    archlinux) pct exec "$container" -- bash -c "$export_env pacman -Syyu --noconfirm" ;;
    fedora | rocky | centos | alma) pct exec "$container" -- bash -c "$export_env dnf -y update && $export_env dnf -y upgrade" ;;
    ubuntu | debian | devuan) 
      pct exec "$container" -- bash -c "$export_env apt-get update && $export_env apt-get -yq dist-upgrade"

      autoremove_needed=$(pct exec "$container" -- $export_env bash -c "apt-get -s autoremove | grep -E '^Remv ' || echo ''")
      if [[ -n "$autoremove_needed" ]]; then
        echo "[Info] Führe 'apt autoremove' auf $container aus..."
        pct exec "$container" -- $export_env bash -c "apt-get -yq autoremove"
        autoremove_containers+=("$container ($name)")
      fi
      ;;
    opensuse) pct exec "$container" -- bash -c "$export_env zypper ref && $export_env zypper --non-interactive dup" ;;
    *) echo "[Warnung] OS $os wird nicht unterstützt oder nicht erkannt." ; return ;;
  esac

  updates_after=0
  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "devuan" ]]; then
    updates_after=$(pct exec "$container" -- $export_env bash -c "apt-get -s dist-upgrade | grep -c '^Inst ' || true")
  fi

  if [[ "$updates_before" -gt "0" && "$updates_after" -eq "0" ]]; then
    updated_containers+=("$container ($name)")
  else
    unchanged_containers+=("$container ($name)")
  fi

  # Benutzerdefinierte Updates durchführen
  update_custom_apps "$container"

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
if [ "${#custom_updates[@]}" -gt 0 ]; then
  echo -e "\n[Benutzerdefinierte Updates]:"
  printf '%s\n' "${custom_updates[@]}"
fi
