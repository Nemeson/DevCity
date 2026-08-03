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
        return 'linux-apt'
    }

    return 'unknown'
}

function Compare-DevCityVersion {
    <#
    .SYNOPSIS
        Vergleicht zwei Version-Strings (semver-like). $true wenn $actual >= $minimum.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Actual,
        [string]$Minimum
    )

    if (-not $Actual -or -not $Minimum) { return $false }
    try {
        # Normalisiere: nur Ziffern und Punkte behalten
        $actualClean = ($Actual -replace '[^0-9.]', '').TrimEnd('.')
        $minClean    = ($Minimum -replace '[^0-9.]', '').TrimEnd('.')

        # Auf gleiche Segment-Anzahl auffuellen (z.B. "24" -> "24.0.0" fuer Vergleich mit "20.0.0")
        $actualSegs = $actualClean -split '\.'
        $minSegs    = $minClean -split '\.'
        $maxLen = [Math]::Max($actualSegs.Count, $minSegs.Count)
        while ($actualSegs.Count -lt $maxLen) { $actualSegs += '0' }
        while ($minSegs.Count -lt $maxLen) { $minSegs += '0' }

        $actualVer = [version]($actualSegs -join '.')
        $minVer    = [version]($minSegs -join '.')
        return $actualVer -ge $minVer
    } catch {
        return $false
    }
}

function Get-DevCityInstalledVersion {
    <#
    .SYNOPSIS
        Führt checkCommand aus und parst die Versionsnummer.
    .OUTPUTS
        String mit Versionsnummer, oder $null wenn nicht gefunden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$CheckCommand,
        [string]$ParseRegex,
        [string]$ParseFunction
    )

    try {
        # Doppeltes 2>&1 vermeiden: falls checkCommand schon 2>&1 enthaelt, entfernen
        $cleanCmd = $CheckCommand -replace '\s+2>&1\s*$', ''
        $output = Invoke-Expression "$cleanCmd 2>&1" -ErrorAction Stop
        $output = $output -join "`n"

        if ($ParseFunction -eq 'extract-major') {
            if ($output -match '(?:version\s+)?"?(\d+)(?:\.\d+)*"?\s') {
                return $matches[1]
            }
        }

        if ($ParseRegex) {
            if ($output -match $ParseRegex) {
                return $matches[1]
            }
        }

        if ($output -match '(\d+(?:\.\d+)+)') {
            return $matches[1]
        }
    } catch {
        # Command nicht gefunden
    }

    return $null
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Prüft alle Prerequisites aus config/prerequisites.json.
    .OUTPUTS
        Array von PSCustomObject: Id, Name, Installed, Version, MinVersion, Ok, Missing
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\prerequisites.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Error "Prerequisites-Konfiguration nicht gefunden: $ConfigPath"
        return @()
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $results = @()

    foreach ($prereq in $config.prerequisites) {
        $installedVersion = Get-DevCityInstalledVersion -CheckCommand $prereq.checkCommand -ParseRegex $prereq.parseRegex -ParseFunction $prereq.parseFunction
        $isInstalled = -not [string]::IsNullOrWhiteSpace($installedVersion)
        $meetsMin = if ($isInstalled) { Compare-DevCityVersion -Actual $installedVersion -Minimum $prereq.minVersion } else { $false }

        $results += [PSCustomObject]@{
            Id          = $prereq.id
            Name        = $prereq.name
            Installed   = $isInstalled
            Version     = $installedVersion
            MinVersion  = $prereq.minVersion
            Ok          = $meetsMin
            Missing     = -not $meetsMin
            RequiredBy  = ($prereq.requiredBy -join ', ')
            Description = $prereq.description
            CheckCommand = $prereq.checkCommand
            ParseRegex  = $prereq.parseRegex
            ParseFunction = $prereq.parseFunction
        }
    }

    return $results
}

function Install-Prerequisite {
    <#
    .SYNOPSIS
        Installiert ein einzelnes Prerequisite per Winget/Brew/Apt/Scoop.
    .PARAMETER Id
        Prerequisite-ID aus prerequisites.json (z.B. 'java', 'node')
    .PARAMETER AutoInstall
        Switch: Wenn gesetzt, keine Bestätigung fragen.
    .OUTPUTS
        $true bei Erfolg, $false bei Abbruch/Fehler.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$AutoInstall,
        [string]$ConfigPath = "$PSScriptRoot\..\config\prerequisites.json"
    )

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $prereq = $config.prerequisites | Where-Object { $_.id -eq $Id }

    if (-not $prereq) {
        Write-Error "Prerequisite nicht gefunden: $Id"
        return $false
    }

    $platform = Get-DevCityPlatform
    $installCmd = $prereq.installCommands.$platform

    if (-not $installCmd) {
        Write-Warning "Kein Installationsbefehl für Plattform '$platform' definiert ($Id)."
        Write-Warning "Bitte manuell installieren: $($prereq.name) >= $($prereq.minVersion)"
        return $false
    }

    if (-not $AutoInstall) {
        Write-Information "" -InformationAction Continue
        Write-Warning "$($prereq.name) fehlt oder ist veraltet (mindestens $($prereq.minVersion))."
        Write-Information "Installationsbefehl für $platform :" -InformationAction Continue
        Write-Information "  $installCmd" -InformationAction Continue
        Write-Information "" -InformationAction Continue

        $response = Read-Host "Auto-installieren? (j/N)"
        if ($response -notmatch '^[jJyY]') {
            Write-Information "Übersprungen. Bitte manuell installieren." -InformationAction Continue
            return $false
        }
    }

    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'Install-Prerequisite' -Detail "Id=$Id, Platform=$platform" -Level Info
    }

    Write-Information "Installiere $($prereq.name) ..." -InformationAction Continue

    try {
        if ($platform -eq 'windows') {
            $args = ($installCmd -replace '^winget\s+', '') -split '\s+(?=(?:[^"]*"[^"]*")*[^"]*$)'
            $result = Start-Process -FilePath 'winget' -ArgumentList $args -Wait -PassThru -NoNewWindow 2>&1
            if ($result.ExitCode -ne 0) {
                Write-Warning "Winget-Exit-Code: $($result.ExitCode)"
                Write-Warning "Falls Admin-Rechte nötig sind, führe setup.ps1 als Administrator aus."
                return $false
            }
        } else {
            Invoke-Expression $installCmd
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Installationsbefehl fehlgeschlagen (Exit $LASTEXITCODE)"
                return $false
            }
        }

        Write-Information "OK: $($prereq.name) installiert." -InformationAction Continue

        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Install-Prerequisite' -Detail "Id=$Id, Status=Success" -Level Info
        }

        return $true
    } catch {
        Write-Error "Installation fehlgeschlagen: $_"

        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Install-Prerequisite' -Detail "Id=$Id, Status=Failed, Error=$($_.Exception.Message)" -Level Error
        }

        return $false
    }
}

function Invoke-PrerequisiteCheck {
    <#
    .SYNOPSIS
        Haupt-Entry-Point für das Setup-Skript.
        Prüft alle Prerequisites, bietet Auto-Install an, bricht bei kritischen Fehlern ab.
    .PARAMETER AutoInstall
        Switch: Wenn gesetzt, alle fehlenden Prerequisites ohne Prompt installieren.
    .PARAMETER SkipOptional
        Switch: Überspringt optionale Prerequisites (z.B. Maven wenn Docker da ist).
    .OUTPUTS
        $true wenn alle Prerequisites erfüllt sind, $false wenn nicht.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$AutoInstall,
        [switch]$SkipOptional
    )

    Write-Information "[Prerequisites] Pruefe Java/Node/Python/Git/Maven/Docker ..." -InformationAction Continue

    $results = Test-Prerequisites

    if ($results.Count -eq 0) {
        Write-Warning "Keine Prerequisites konfiguriert."
        return $true
    }

    # Tabelle ausgeben
    Write-Information "" -InformationAction Continue
    Write-Information ("{0,-10} {1,-20} {2,-12} {3,-10} {4,-10}" -f 'Id', 'Name', 'Installed', 'Min', 'Status') -InformationAction Continue
    Write-Information ("{0,-10} {1,-20} {2,-12} {3,-10} {4,-10}" -f '--', '----', '---------', '---', '------') -InformationAction Continue

    foreach ($r in $results) {
        $status = if ($r.Ok) { 'OK' } elseif ($r.Installed) { 'OLD' } else { 'MISS' }
        $version = if ($r.Version) { $r.Version } else { '-' }
        Write-Information ("{0,-10} {1,-20} {2,-12} {3,-10} {4}" -f $r.Id, $r.Name, $version, $r.MinVersion, $status) -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    $missing = $results | Where-Object { -not $_.Ok }

    if ($missing.Count -eq 0) {
        Write-Information "OK: Alle Prerequisites erfuellt." -InformationAction Continue
        return $true
    }

    Write-Warning "$($missing.Count) Prerequisite(s) fehlen oder sind veraltet."

    foreach ($m in $missing) {
        if ($SkipOptional -and $m.Id -eq 'maven') {
            $dockerOk = ($results | Where-Object { $_.Id -eq 'docker' }).Ok
            if ($dockerOk) {
                Write-Information "Ueberspringe Maven (Docker vorhanden, Atlassian-MCP via Docker)." -InformationAction Continue
                continue
            }
        }

        $success = Install-Prerequisite -Id $m.Id -AutoInstall:$AutoInstall

        if (-not $success) {
            Write-Error "Prerequisite '$($m.Id)' konnte nicht installiert werden. Setup kann nicht fortgesetzt werden."
            return $false
        }

        $newVersion = Get-DevCityInstalledVersion -CheckCommand $m.CheckCommand -ParseRegex $m.ParseRegex -ParseFunction $m.ParseFunction 2>$null
        if ($newVersion -and (Compare-DevCityVersion -Actual $newVersion -Minimum $m.MinVersion)) {
            Write-Information "OK: $($m.Name) jetzt installiert: $newVersion" -InformationAction Continue
        } else {
            Write-Warning "$($m.Name) nach Installation noch nicht gefunden. Bitte Shell neu starten (PATH-Refresh)."
            return $false
        }
    }

    return $true
}

Export-ModuleMember -Function *