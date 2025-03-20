#!/usr/bin/env bash

# Copyright (c) 2025 Dein Name
# License: MIT
# Beschreibung: Automatisierte Bereitstellung und Aktualisierung eines ERPNext 15 LXC-Containers auf Proxmox

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Prüfen, ob das Skript innerhalb des Containers läuft oder ob ein neuer Container erstellt werden soll
if [[ $(hostname) == "erpnext" ]]; then
    msg_info "Aktualisiere ERPNext 15 in virtueller Umgebung..."
    source ~/frappe-bench-venv/bin/activate
    cd ~/frappe-bench
    bench update --reset
    msg_ok "ERPNext 15 erfolgreich aktualisiert"
    exit 0
fi

# Benutzerdefinierte Variablen abfragen
echo -n "Geben Sie die Container ID (CTID) ein: "
read CTID
echo -n "Geben Sie den LXC-Namen ein: "
read LXC_NAME
echo -n "Geben Sie den Hostnamen ein: "
read HOSTNAME
echo -n "Geben Sie die statische IP (z. B. 192.168.1.100/24) ein: "
read IP
echo -n "Geben Sie das Gateway ein (z. B. 192.168.1.1): "
read GATEWAY
echo -n "Geben Sie die Speichergröße (z. B. 10G) ein: "
read DISK_SIZE
echo -n "Geben Sie den Arbeitsspeicher in MB ein (z. B. 2048): "
read RAM
echo -n "Geben Sie die Anzahl der CPU-Kerne ein (z. B. 2): "
read CPUS
echo -n "Geben Sie den Namen für die MariaDB-Datenbank ein: "
read DB_NAME
echo -n "Geben Sie den Datenbankbenutzer ein: "
read DB_USER
echo -n "Geben Sie das Passwort für den Datenbankbenutzer ein: "
read -s DB_PASS
echo
echo -n "Geben Sie das MariaDB Root-Passwort ein: "
read -s DB_ROOT_PASS
echo
echo -n "Geben Sie den ERPNext-Benutzernamen ein (z. B. erpadmin): "
read ERP_USER
echo -n "Geben Sie den Namen für die ERPNext-Site ein (z. B. erp.meinefirma.local): "
read ERP_SITE

TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
STORAGE="local-lvm"

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
msg_ok "LXC Container erstellt"

msg_info "Starte den Container..."
pct start $CTID
sleep 5
msg_ok "Container gestartet"

msg_info "Führe Updates im Container aus..."
pct exec $CTID -- apt update && apt upgrade -y
msg_ok "Updates abgeschlossen"

msg_info "Installiere ERPNext-Abhängigkeiten..."
pct exec $CTID -- apt install -y \
    mariadb-server \
    redis \
    curl \
    python3-venv \
    python3-pip \
    python3-dev \
    libmysqlclient-dev \
    software-properties-common \
    nginx \
    supervisor
msg_ok "ERPNext-Abhängigkeiten installiert"

msg_info "Konfiguriere MariaDB..."
pct exec $CTID -- mysql -uroot -e "
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
    CREATE DATABASE $DB_NAME;
    CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES;
"
msg_ok "MariaDB wurde konfiguriert"

msg_info "Installiere ERPNext 15 in virtueller Umgebung..."
pct exec $CTID -- bash -c "
    useradd -m -s /bin/bash $ERP_USER
    echo '$ERP_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
    su - $ERP_USER -c 'python3 -m venv ~/frappe-bench-venv'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && pip install -U pip'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && git clone -b version-15 https://github.com/frappe/bench.git --depth 1'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && pip install -e bench'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && bench init --frappe-branch version-15 frappe-bench'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && cd frappe-bench && bench new-site $ERP_SITE --mariadb-root-password=$DB_ROOT_PASS --admin-password=$DB_PASS'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && cd frappe-bench && bench get-app erpnext --branch version-15'
    su - $ERP_USER -c 'source ~/frappe-bench-venv/bin/activate && cd frappe-bench && bench install-app erpnext'
"
msg_ok "ERPNext 15 erfolgreich in virtueller Umgebung installiert"

motd_ssh
customize

msg_info "Bereinige System..."
pct exec $CTID -- apt-get -y autoremove
pct exec $CTID -- apt-get -y autoclean
msg_ok "Bereinigung abgeschlossen"

echo "Setup abgeschlossen! Der ERPNext-Container läuft unter $IP mit dem Namen $LXC_NAME"
echo "MariaDB:"
echo " - Datenbankname: $DB_NAME"
echo " - Benutzer: $DB_USER"
echo " - Passwort: (aus Sicherheitsgründen nicht angezeigt)"
echo "ERPNext:"
echo " - Benutzername: $ERP_USER"
echo " - Website: $ERP_SITE"
