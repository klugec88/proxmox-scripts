#!/usr/bin/env bash

# Copyright (c) 2025 Christopher Kluge
# License: MIT
# Beschreibung: Automatisierte Bereitstellung und Aktualisierung eines ERPNext 15 LXC-Containers auf Proxmox

source /functions/functions.sh
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Menü zur Eingabe der Variablen
whiptail --title "ERPNext LXC Installation" --msgbox "Willkommen zur Installation von ERPNext 15 als LXC-Container auf Proxmox." 10 60

CTID=$(whiptail --inputbox "Geben Sie die Container ID (CTID) ein:" 10 60 111 3>&1 1>&2 2>&3)
LXC_NAME=$(whiptail --inputbox "Geben Sie den LXC-Namen ein:" 10 60 "erpnext" 3>&1 1>&2 2>&3)
HOSTNAME=$(whiptail --inputbox "Geben Sie den Hostnamen ein:" 10 60 "erpnext.local" 3>&1 1>&2 2>&3)
IP=$(whiptail --inputbox "Geben Sie die statische IP (z. B. 192.168.1.100/24) ein:" 10 60 3>&1 1>&2 2>&3)
GATEWAY=$(whiptail --inputbox "Geben Sie das Gateway ein (z. B. 192.168.1.1):" 10 60 3>&1 1>&2 2>&3)
DISK_SIZE=$(whiptail --inputbox "Geben Sie die Speichergröße (z. B. 10G) ein:" 10 60 3>&1 1>&2 2>&3)
RAM=$(whiptail --inputbox "Geben Sie den Arbeitsspeicher in MB ein:" 10 60 2048 3>&1 1>&2 2>&3)
CPUS=$(whiptail --inputbox "Geben Sie die Anzahl der CPU-Kerne ein:" 10 60 2 3>&1 1>&2 2>&3)
ROOT_PASS=$(whiptail --passwordbox "Geben Sie das Root-Passwort für den Container ein:" 10 60 3>&1 1>&2 2>&3)

# MariaDB Konfiguration
DB_NAME=$(whiptail --inputbox "Geben Sie den Namen für die MariaDB-Datenbank ein:" 10 60 "erpnext" 3>&1 1>&2 2>&3)
DB_USER=$(whiptail --inputbox "Geben Sie den Datenbankbenutzer ein:" 10 60 "erpuser" 3>&1 1>&2 2>&3)
DB_PASS=$(whiptail --passwordbox "Geben Sie das Passwort für den Datenbankbenutzer ein:" 10 60 3>&1 1>&2 2>&3)
DB_ROOT_PASS=$(whiptail --passwordbox "Geben Sie das MariaDB Root-Passwort ein:" 10 60 3>&1 1>&2 2>&3)

# ERPNext Konfiguration
ERP_USER=$(whiptail --inputbox "Geben Sie den ERPNext-Benutzernamen ein (z. B. erpadmin):" 10 60 "erpadmin" 3>&1 1>&2 2>&3)
ERP_SITE=$(whiptail --inputbox "Geben Sie den Namen für die ERPNext-Site ein (z. B. erp.meinefirma.local):" 10 60 "erpnext.local" 3>&1 1>&2 2>&3)

# SSH Konfiguration
SSH_MODE=$(whiptail --title "SSH Konfiguration" --radiolist "Wie soll SSH konfiguriert werden?" 15 60 3 
"Passwort" "Login per Passwort" ON 
"Schlüssel" "Login per SSH-Schlüssel" OFF 3>&1 1>&2 2>&3)

TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
STORAGE="local-lvm"

# Prüfen, ob das Debian-Template vorhanden ist, falls nicht herunterladen
if ! pveam list | grep -q "$TEMPLATE"; then
    msg_info "Debian Template nicht gefunden, lade herunter..."
    pveam download $STORAGE $TEMPLATE
    msg_ok "Debian Template heruntergeladen."
fi

# Container erstellen
msg_info "Erstelle LXC Container..."
pct create $CTID $STORAGE:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --net0 name=eth0,bridge=vmbr0,ip=$IP,gw=$GATEWAY \
    --cores $CPUS \
    --memory $RAM \
    --rootfs $STORAGE:$DISK_SIZE \
    --features nesting=1 \
    --unprivileged 1 \
    --password "$ROOT_PASS"
msg_ok "LXC Container erstellt"

msg_info "Starte den Container..."
pct start $CTID
sleep 5
msg_ok "Container gestartet"

# SSH konfigurieren
if [ "$SSH_MODE" == "Schlüssel" ]; then
    pct exec $CTID -- mkdir -p /root/.ssh
    whiptail --msgbox "Bitte legen Sie den SSH-Schlüssel unter /root/.ssh/authorized_keys ab." 10 60
else
    msg_info "SSH-Zugang per Passwort aktiviert."
fi

motd_ssh
customize

msg_ok "Setup abgeschlossen! Der ERPNext-Container läuft unter $IP."
