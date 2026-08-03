# =====================================================================
# DevCity Module: Audit
# Audit-Log fuer Setup-Aktionen. NIE Secret-Werte loggen.
# NFR 2B: Jede Secret-Speicherung wird geloggt (ohne Wert).
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

if (-not (Test-Path Variable:DEVCITY_LOG_DIR)) {
    New-Variable -Name DEVCITY_LOG_DIR -Value (Join-Path $PSScriptRoot '..\logs') -Option Constant -ErrorAction SilentlyContinue
}

# Secret-Patterns fuer Test-DevCitySecretInLog
$script:DEVCITY_SECRET_PATTERNS = @(
    'Bearer\s+[A-Za-z0-9._-]{20,}',
    'token\s*=\s*[A-Za-z0-9]{16,}',
    '[A-Za-z0-9+/]{40,}={0,2}',
    '(?i)password\s*=\s*\S+',
    '(?i)secret\s*=\s*\S+',
    '(?i)api[_-]?key\s*=\s*\S+',
    'AKIA[0-9A-Z]{16}',
    'ghp_[A-Za-z0-9]{36}',
    'gho_[A-Za-z0-9]{36}',
    'github_pat_[A-Za-z0-9_]{82}',
    'xox[baprs]-[A-Za-z0-9-]{10,}',
    '-----BEGIN [A-Z ]+PRIVATE KEY-----'
)

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function Write-DevCityAuditLog {
    <#
    .SYNOPSIS
        Schreibt einen Audit-Log-Eintrag. NFR: Secret-Werte werden NIEMALS geloggt.
    .PARAMETER Action
        Aktion, die geloggt wird (z.B. 'Install-Tool', 'Save-Secret', 'HealthCheck').
    .PARAMETER Detail
        Freitext-Detail. SECRET-WERTE SIND HIER VERBOTEN.
    .PARAMETER Level
        'Info' (Default), 'Warning', 'Error'.
    .PARAMETER Metadata
        Optional: Hashtable mit zusaetzlichem Kontext (keine Secrets!).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Detail,
        [ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info',
        [hashtable]$Metadata
    )

    # Log-Verzeichnis sicherstellen
    if (-not (Test-Path $DEVCITY_LOG_DIR)) {
        New-Item -ItemType Directory -Path $DEVCITY_LOG_DIR -Force | Out-Null
    }

    # Sanity-Check: keine Secrets im Detail oder Metadata
    if ($Detail -and (Test-DevCitySecretInLog -Text $Detail)) {
        Write-Warning "[Audit] Secret-Muster im Detail erkannt — wird NICHT geloggt."
        $Detail = '[REDACTED: Secret-Muster erkannt]'
    }
    if ($Metadata) {
        $metaJson = $Metadata | ConvertTo-Json -Compress -Depth 3
        if (Test-DevCitySecretInLog -Text $metaJson) {
            Write-Warning "[Audit] Secret-Muster in Metadata erkannt — wird NICHT geloggt."
            $Metadata = @{ redacted = $true }
        }
    }

    # Log-Dateiname: pro Tag eine Datei
    $dateStamp = (Get-Date).ToString('yyyy-MM-dd')
    $logFile = Join-Path $DEVCITY_LOG_DIR "setup-audit-$dateStamp.log"

    # Eintrag formatieren
    $timestamp = (Get-Date).ToString('o')  # ISO 8601
    $metaString = if ($Metadata) { ' | ' + ($Metadata | ConvertTo-Json -Compress -Depth 3) } else { '' }
    $line = "[$timestamp] [$Level] [$Action] $Detail$metaString"

    # Schreiben (UTF-8 ohne BOM, Append)
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Get-DevCityAuditLog {
    <#
    .SYNOPSIS
        Liest Audit-Log-Eintraege gefiltert nach Kriterien.
    .PARAMETER Since
        Nur Eintraege ab diesem Datum (Default: 7 Tage zurueck).
    .PARAMETER Level
        Nur Eintraege dieses Levels.
    .PARAMETER Action
        Nur Eintraege dieser Aktion.
    .OUTPUTS
        Array von PSCustomObject (Timestamp, Level, Action, Detail, Metadata)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [datetime]$Since = (Get-Date).AddDays(-7),
        [string]$Level,
        [string]$Action
    )

    if (-not (Test-Path $DEVCITY_LOG_DIR)) { return @() }

    $logFiles = Get-ChildItem -Path $DEVCITY_LOG_DIR -Filter 'setup-audit-*.log' |
        Where-Object { $_.LastWriteTime -ge $Since.Date }

    $results = @()
    foreach ($file in $logFiles) {
        $lines = Get-Content -Path $file.FullName -Encoding utf8
        foreach ($line in $lines) {
            # Parse: [ISO8601] [Level] [Action] Detail | Metadata
            if ($line -match '^\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+(.*)$') {
                $ts = [datetime]$matches[1]
                $lvl = $matches[2]
                $act = $matches[3]
                $rest = $matches[4]

                if ($ts -lt $Since) { continue }
                if ($Level -and $lvl -ne $Level) { continue }
                if ($Action -and $act -ne $Action) { continue }

                # Detail und Metadata trennen
                $detail = $rest
                $meta = $null
                if ($rest -match '^(.*?)\s\|\s(\{.*\})$') {
                    $detail = $matches[1]
                    try { $meta = $matches[2] | ConvertFrom-Json } catch { }
                }

                $results += [PSCustomObject]@{
                    Timestamp = $ts
                    Level     = $lvl
                    Action    = $act
                    Detail    = $detail
                    Metadata  = $meta
                    File      = $file.Name
                }
            }
        }
    }

    return $results
}

function Clear-DevCityAuditLog {
    <#
    .SYNOPSIS
        Loescht Audit-Logs aelter als N Tage. Default: 90 Tage behalten.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$KeepDays = 90
    )

    if (-not (Test-Path $DEVCITY_LOG_DIR)) { return }

    $cutoff = (Get-Date).AddDays(-$KeepDays)
    $oldFiles = Get-ChildItem -Path $DEVCITY_LOG_DIR -Filter 'setup-audit-*.log' |
        Where-Object { $_.LastWriteTime -lt $cutoff }

    foreach ($file in $oldFiles) {
        if ($PSCmdlet.ShouldProcess($file.Name, "Loesche altes Audit-Log (> $KeepDays Tage)")) {
            Remove-Item -Path $file.FullName -Force
            Write-Verbose "Geloescht: $($file.Name)"
        }
    }
}

function Test-DevCitySecretInLog {
    <#
    .SYNOPSIS
        Sanity-Check: Prueft, ob ein String Secret-Muster enthaelt,
        die versehentlich ins Audit-Log geraten koennten.
        Wird von Write-DevCityAuditLog intern genutzt.
    .OUTPUTS
        $true wenn Secret-Muster erkannt wird (dann: NICHT loggen!).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Text
    )

    foreach ($pattern in $script:DEVCITY_SECRET_PATTERNS) {
        if ($Text -match $pattern) { return $true }
    }

    return $false
}

Export-ModuleMember -Function *