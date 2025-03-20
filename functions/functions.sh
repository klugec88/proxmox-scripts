### functions.sh (im Ordner /functions)

#!/usr/bin/env bash

# Farben für die Ausgabe
green="\e[32m"
red="\e[31m"
reset="\e[0m"

msg_info() {
    echo -e "${green}[INFO] $1${reset}"
}

msg_error() {
    echo -e "${red}[ERROR] $1${reset}" >&2
}

catch_errors() {
    trap 'msg_error "Ein Fehler ist aufgetreten!"; exit 1' ERR
}

network_check() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        msg_error "Keine Internetverbindung! Prüfe deine Netzwerkeinstellungen."
        exit 1
    fi
}

update_os() {
    msg_info "Aktualisiere das System..."
    apt update && apt upgrade -y
    msg_info "Systemaktualisierung abgeschlossen."
}

motd_ssh() {
    echo "Willkommen auf Ihrem ERPNext-Server!" > /etc/motd
}

customize() {
    msg_info "Passe System an..."
    # Hier können weitere Anpassungen folgen
    msg_info "Systemanpassung abgeschlossen."
}
