# Proxmox Scripts

Dieses Repository enthält Skripte zur Automatisierung von LXC- und VM-Deployments auf Proxmox.

## 📂 Ordnerstruktur

- `ct/` → Skripte für die Bereitstellung von LXC-Containern
- `vm/` → Skripte für die Erstellung von VMs
- `functions/` → Allgemeine Hilfsfunktionen für die Skripte
- `docs/` → Dokumentation zur Installation und Nutzung

## 📌 Installation

Klonen des Repositories:
```bash
git clone https://github.com/DEIN-GITHUB-NAME/proxmox-scripts.git
```

## 🚀 Nutzung

Beispiel für die Bereitstellung eines ERPNext 15 Containers:
```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/DEIN-GITHUB-NAME/proxmox-scripts/main/ct/erpnext15.sh)"
```

## 📖 Dokumentation

Für detaillierte Anleitungen siehe den Ordner [`docs/`](docs/).

## ⚖️ Lizenz

Dieses Projekt steht unter der MIT-Lizenz.
