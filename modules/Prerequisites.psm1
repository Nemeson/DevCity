# =====================================================================
# DevCity Module: Prerequisites
# Prüft Java/Node/Python/Git/Maven/Docker und bietet Auto-Installation
# via Winget/Brew/Apt/Scoop an.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------

function Get-DevCityPlatform {
    <#
    .SYNOPSIS
        Erkennt das Betriebssystem und gibt einen normalisierten String zurück.
    .OUTPUTS
        String: 'windows' | 'macos' | 'linux-apt' | 'linux-dnf' | 'unknown'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'windows' }
    if ($IsMacOS) { return 'macos' }

    if ($IsLinux) {
        if (Test-Path '/etc/debian_version') { return 'linux-apt' }
        if (Test-Path '/etc/redhat-release') { return 'linux-dnf' }
        return 'linux-apt'  # Default
    }

    return 'unknown'
}

function Compare-DevCityVersion {
    <#
    .SYNOPSIS
        Vergleicht zwei Version Strings (semver-like). Gibt $true zurück,
        wenn $actual >= $minimum.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Actual,
        [string]$Minimum
    )

    if (-not $Actual -or -not $Minimum) { return $false }
    try {
        $actualVer = [version]($Actual -replace '[^0-9.]', '')
        $minVer = [version]($Minimum -replace '[^0-9.]', '')
        return $actualVer -ge $minVer
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------
# Hauptfunktionen (Stubs mit klarer Signatur)
# ---------------------------------------------------------------------

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Prüft alle Prerequisites aus config/prerequisites.json.
        Gibt ein Array mit Status-Objekten zurück.
    .OUTPUTS
        Array von PSCustomObject mit Properties:
          Id, Name, Installed, Version, MinVersion, Ok, Missing
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\prerequisites.json"
    )

    # TODO: Implement
    # 1. JSON laden
    # 2. pro Eintrag: checkCommand ausführen, Version parsen, vergleichen
    # 3. Status-Objekt zurückgeben
    return @()
}

function Install-Prerequisite {
    <#
    .SYNOPSIS
        Installiert ein einzelnes Prerequisite per Winget/Brew/Apt/Scoop.
    .PARAMETER Id
        Prerequisite-ID aus prerequisites.json (z.B. 'java', 'node')
    .PARAMETER AutoInstall
        Switch: Wenn gesetzt, keine Bestätigung fragen.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$AutoInstall
    )

    # TODO: Implement
    # 1. Plattform erkennen (Get-DevCityPlatform)
    # 2. Passenden Installationsbefehl aus prerequisites.json holen
    # 3. Bei -AutoInstall direkt ausführen, sonst Bestätigung einholen
    # 4. Audit-Log-Eintrag (via Audit-Modul)
    # 5. Rückgabe: $true bei Erfolg, $false bei Abbruch/Fehler
    return $false
}

function Invoke-PrerequisiteCheck {
    <#
    .SYNOPSIS
        Haupt-Entry-Point für das Setup-Skript.
        Prüft alle Prerequisites, bietet Auto-Install an, bricht bei kritischen
        Fehlern ab.
    .PARAMETER AutoInstall
        Switch: Wenn gesetzt, alle fehlenden Prerequisites ohne Prompt installieren.
    .PARAMETER SkipOptional
        Switch: Überspringt optionale Prerequisites (z.B. Maven wenn Docker da ist).
    #>
    [CmdletBinding()]
    param(
        [switch]$AutoInstall,
        [switch]$SkipOptional
    )

    # TODO: Implement
    # 1. Test-Prerequisites aufrufen
    # 2. Bei fehlenden: Install-Prerequisite mit AutoInstall aufrufen
    # 3. Wenn Installation fehlschlägt: klare Fehlermeldung + Abbruch
    # 4. Audit-Log
    return
}

Export-ModuleMember -Function *