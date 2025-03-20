#!/usr/bin/env bash

# Copyright (c) 2025 Dein Name
# License: MIT
# Automatisierte Bereitstellung eines ERPNext 15 LXC-Containers auf Proxmox

source functions.sh  # Hilfsfunktionen einbinden

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Benutzer-Eingabe mit Dialog
install_package dialog

INPUT=$(dialog --stdout --backtitle "ERPNext LXC Installer" --title "Container Einstellungen" \
    --form "Bitte die Werte eingeben" 15 60 9 \
    "Container ID:" 1 1 "" 1 20 10 0 \
    "LXC-Name:" 2 1 "" 2 20 20 0 \
    "Hostname:" 3 1 "" 3 20 20 0 \
    "Statische IP (z.B. 192.168.1.100/24):" 4 1 "" 4 20 20 0 \
    "Gateway (z.B. 192.168.1.1):" 5 1 "" 5 20 20 0 \
    "Speichergröße (z.B. 10G):" 6 1 "10G" 6 20 10 0 \
    "RAM (MB):" 7 1 "2048" 7 20 10 0 \
    "CPU-Kerne:" 8 1 "2" 8 20 5 0 \
    "MariaDB Root-Passwort:" 9 1 "" 9 20 20 0)

if [ $? -ne 0 ]; then
    echo "Abgebrochen!"
    exit 1
fi

IFS=$'\n' read -r CTID LXC_NAME HOSTNAME IP GATEWAY DISK_SIZE RAM CPUS DB_ROOT_PASS <<< "$INPUT"

# Eingabe prüfen
validate_ip $IP || { echo "Ungültige IP-Adresse!"; exit 1; }
validate_ip $GATEWAY || { echo "Ungültiges Gateway!"; exit 1; }
validate_number $CTID || { echo "Ungültige Container-ID!"; exit 1; }
validate_number $RAM || { echo "Ungültiger RAM-Wert!"; exit 1; }
validate_number $CPUS || { echo "Ungültige CPU-Anzahl!"; exit 1; }

# SSH-Optionen abfragen
SSH_OPTION=$(dialog --stdout --backtitle "ERPNext LXC Installer" --title "SSH-Zugriff" \
    --menu "Wie soll SSH konfiguriert werden?" 10 50 3 \
    1 "Passwort-Authentifizierung" \
    2 "SSH-Schlüssel eingeben" \
    3 "Kein SSH-Zugang")

if [ "$SSH_OPTION" == "2" ]; then
    SSH_KEY=$(dialog --stdout --backtitle "ERPNext LXC Installer" --title "SSH-Key" \
        --inputbox "Gib deinen öffentlichen SSH-Schlüssel ein:" 8 60)
    if [ -z "$SSH_KEY" ]; then
        echo "Fehler: Kein SSH-Schlüssel eingegeben!"
        exit 1
    fi
fi

# Template-Check & Download
TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
STORAGE="local-lvm"
if ! pveam list | grep -q "$TEMPLATE"; then
    msg_info "Debian-Template nicht gefunden. Lade herunter..."
    pveam download $STORAGE $TEMPLATE
    msg_ok "Debian-Template heruntergeladen."
fi

msg_info "Erstelle LXC Container..."
pct create $CTID $STORAGE:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --net0 name=eth0,bridge=vmbr0,ip=$IP,gw=$GATEWAY \
    --cores $CPUS \
    --memory $RAM \
    --rootfs $STORAGE:$DISK_SIZE \
    --features nesting=1 \
    --unprivileged 1 \
    --password "changeme"

# SSH-Einstellungen setzen
if [ "$SSH_OPTION" == "1" ]; then
    pct exec $CTID -- sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
elif [ "$SSH_OPTION" == "2" ]; then
    pct exec $CTID -- mkdir -p /root/.ssh
    pct exec $CTID -- bash -c "echo '$SSH_KEY' > /root/.ssh/authorized_keys"
    pct exec $CTID -- chmod 600 /root/.ssh/authorized_keys
fi
msg_ok "Container erstellt und SSH konfiguriert."

motd_ssh
