# =====================================================================
# DevCity Module: Memory
# Verwaltet Projekt-Memory — lokal oder zentral (Jenkins/Atlassian-Server).
# Transportwege: SSH/SCP, Git-Remote, SMB, HTTP-API (via Setup-Menü wählbar).
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

New-Variable -Name DEVCITY_MEMORY_LOCAL_PATH -Value (Join-Path $PSScriptRoot '..\memory') -Option Constant -ErrorAction SilentlyContinue
New-Variable -Name DEVCITY_MEMORY_TRANSPORTS -Value @('ssh-scp', 'git-remote', 'smb', 'http-api') -Option Constant -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------
# Hauptfunktionen (Stubs)
# ---------------------------------------------------------------------

function New-DevCityMemory {
    <#
    .SYNOPSIS
        Legt ein neues Projekt-Memory an — lokal oder zentral.
        Interaktiver Prompt für Modus und Transportweg.
    .PARAMETER Mode
        'lokal' (Default) oder 'zentral'. Wenn nicht angegeben, wird gepromptet.
    .PARAMETER Transport
        Nur bei Mode='zentral': 'ssh-scp' | 'git-remote' | 'smb' | 'http-api'.
    .PARAMETER RemoteUrl
        Nur bei Mode='zentral': Ziel-URL/Host/Pfad.
    .PARAMETER NonInteractive
        Switch: Keine Prompts — alle Parameter müssen als Argumente kommen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('lokal', 'zentral')][string]$Mode,
        [ValidateSet('ssh-scp', 'git-remote', 'smb', 'http-api')][string]$Transport,
        [string]$RemoteUrl,
        [switch]$NonInteractive
    )

    # TODO: Implement
    # 1. Wenn -NonInteractive und $Mode leer: Abbruch
    # 2. Wenn $Mode leer: Prompt "lokal vs. zentral" (Default: lokal)
    # 3. Wenn Mode='zentral' und $Transport leer: Prompt Transportweg
    # 4. Wenn Mode='zentral': RemoteUrl abfragen (via Secrets-Modul, falls SSH-Host)
    # 5. Memory-Verzeichnis anlegen
    # 6. Config-Datei memory/devcity-memory.json schreiben
    # 7. Audit-Log
    # 8. Bei Mode='zentral': ersten Sync durchführen
    return
}

function Get-DevCityMemoryConfig {
    <#
    .SYNOPSIS
        Liest die aktuelle Memory-Konfiguration aus memory/devcity-memory.json.
    .OUTPUTS
        PSCustomObject: Mode, Transport, RemoteUrl, LastSync, etc.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # TODO: Implement
    return $null
}

function Sync-DevCityMemory {
    <#
    .SYNOPSIS
        Synchronisiert das Memory mit dem zentralen Server (nur bei Mode='zentral').
        Bei Mode='lokal': No-Op.
    .PARAMETER Direction
        'push' (lokal → zentral) oder 'pull' (zentral → lokal) oder 'both' (Default).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('push', 'pull', 'both')][string]$Direction = 'both'
    )

    # TODO: Implement
    # 1. Config laden (Get-DevCityMemoryConfig)
    # 2. Wenn Mode='lokal': Meldung "Lokales Memory, kein Sync nötig" + Return
    # 3. Transport dispatchen:
    #    - ssh-scp: scp/rsync Befehl
    #    - git-remote: git push/pull
    #    - smb: robocopy/Get-ChildItem -Path UNC
    #    - http-api: Invoke-RestMethod
    # 4. Audit-Log
    # 5. LastSync aktualisieren
    return
}

function Remove-DevCityMemory {
    <#
    .SYNOPSIS
        Löscht das lokale Memory und entfernt die Config.
        ACHTUNG: Nur für Reset. Backup vorher via Snapshot-Modul.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [switch]$Force
    )

    # TODO: Implement
    # 1. Snapshot via Snapshot-Modul
    # 2. Bestätigung einholen (außer -Force)
    # 3. Lokales Memory löschen
    # 4. Config löschen
    # 5. Audit-Log
    return
}

Export-ModuleMember -Function *