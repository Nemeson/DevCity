#!/usr/bin/env bash
# =====================================================================
# DevCity — Bash-Wrapper für setup.ps1
# Ruft setup.ps1 via pwsh auf (falls vorhanden), sonst nativ (TODO).
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_PS1="${SCRIPT_DIR}/setup.ps1"

# ---------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------

log() { echo "[devcity] $*" >&2; }
die() { echo "[devcity] FEHLER: $*" >&2; exit 1; }

# ---------------------------------------------------------------------
# Check: pwsh vorhanden?
# ---------------------------------------------------------------------

if command -v pwsh >/dev/null 2>&1; then
    log "PowerShell Core gefunden: $(pwsh --version)"
    log "Starte setup.ps1 ..."
    exec pwsh -NoProfile -File "${SETUP_PS1}" "$@"
else
    log "PowerShell Core (pwsh) NICHT gefunden."
    log ""
    log "Optionen:"
    log "  1) PowerShell Core installieren:"
    log "       macOS:  brew install powershell/tap/powershell"
    log "       Ubuntu:  sudo apt-get install -y powershell"
    log "       Fedora:  sudo dnf install -y powershell"
    log "       Arch:    yay -S powershell-bin"
    log ""
    log "  2) Setup manuell mit Bash-Äquivalenten ausführen (TODO: setup.sh nativ)"
    log ""
    log "DevCity benötigt PowerShell 7+ für das Setup-Skript."
    log "Bitte installiere pwsh und starte ./setup.sh erneut."
    exit 1
fi

# ---------------------------------------------------------------------
# Native Bash-Variante (Stub, TODO)
# ---------------------------------------------------------------------
# Falls PowerShell Core nicht installierbar ist, wird eine native
# Bash-Implementierung der Module benötigt. Das ist ein größerer Aufwand
# und ist nicht Teil des v1.0-Scopes.
#
# TODO: Native Bash-Implementierung der Module in modules/*.sh
#       - modules/Audit.sh
#       - modules/Snapshot.sh
#       - modules/Secrets.sh
#       - modules/Prerequisites.sh
#       - modules/Tools.sh
#       - modules/Memory.sh
#       - modules/MCPConfig.sh
#       - modules/HealthCheck.sh
#
# Bis dahin ist PowerShell Core Pflicht.