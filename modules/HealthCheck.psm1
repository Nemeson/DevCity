# =====================================================================
# DevCity Module: HealthCheck
# Health-Check NUR fuer Remote-Server (Jenkins + Atlassian).
# Lokale Tools werden NICHT geprueft (Frage 6: B, nur Remoteserver).
# Optimierung 8: Retry mit Exponential-Backoff (3x: 1s, 2s, 4s)
# Optimierung 9: Health-Check-Report als Markdown
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

# ---------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------

function Get-DevCityPlatform {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { return 'windows' }
    if ($IsMacOS) { return 'macos' }
    if ($IsLinux) {
        if (Test-Path '/etc/debian_version') { return 'linux-apt' }
        if (Test-Path '/etc/redhat-release') { return 'linux-dnf' }
        return 'linux-apt'
    }
    return 'unknown'
}

function Invoke-DevCityHttpRequest {
    <#
    .SYNOPSIS
        HTTP-Request mit Retry + Exponential-Backoff (Optimierung 8).
        3 Versuche mit 1s, 2s, 4s Wartezeit.
    .OUTPUTS
        PSCustomObject: StatusCode, Ok, ResponseTimeMs, Error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [hashtable]$Headers,
        [int]$TimeoutSec = 10,
        [int]$MaxRetries = 3
    )

    $backoffSeconds = @(1, 2, 4)
    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $response = Invoke-RestMethod -Uri $Url -Method Get -Headers $Headers -TimeoutSec $TimeoutSec -ErrorAction Stop
            $stopwatch.Stop()

            return [PSCustomObject]@{
                StatusCode      = 200
                Ok              = $true
                ResponseTimeMs  = $stopwatch.ElapsedMilliseconds
                Error           = $null
                Attempt         = $attempt
                Response        = $response
            }
        } catch {
            $stopwatch.Stop()
            $statusCode = 0
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Bei HTTP-Status-Code (nicht Transient): kein Retry
            if ($statusCode -ge 400 -and $statusCode -lt 500) {
                return [PSCustomObject]@{
                    StatusCode      = $statusCode
                    Ok              = $false
                    ResponseTimeMs  = $stopwatch.ElapsedMilliseconds
                    Error           = $_.Exception.Message
                    Attempt         = $attempt
                    Response        = $null
                }
            }

            # Transienter Fehler (Netzwerk, 5xx, Timeout): Retry mit Backoff
            if ($attempt -lt $MaxRetries) {
                $waitSec = $backoffSeconds[$attempt - 1]
                Write-Verbose "[HealthCheck] Versuch $attempt fehlgeschlagen, warte ${waitSec}s ..."
                Start-Sleep -Seconds $waitSec
            } else {
                # Letzter Versuch — Fehler zurueckgeben
                return [PSCustomObject]@{
                    StatusCode      = $statusCode
                    Ok              = $false
                    ResponseTimeMs  = $stopwatch.ElapsedMilliseconds
                    Error           = $_.Exception.Message
                    Attempt         = $attempt
                    Response        = $null
                }
            }
        }
    }
}

function Resolve-DevCityHealthCheckSecret {
    <#
    .SYNOPSIS
        Loest {{secret:name}}-Platzhalter in Endpoints/Headers auf.
        Nutzt Secrets-Modul falls verfuegbar, sonst bleibt Platzhalter stehen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Text)

    if ($Text -match '\{\{secret:(.+?)\}\}') {
        $secretName = $matches[1]
        if (Get-Command Get-DevCitySecret -ErrorAction SilentlyContinue) {
            $val = Get-DevCitySecret -Name $secretName
            if ($val) {
                return $Text -replace "\{\{secret:$secretName\}\}", $val
            }
        }
    }
    return $Text
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function Invoke-DevCityHealthCheck {
    <#
    .SYNOPSIS
        Pingt die zentralen Remote-Server (Jenkins, Atlassian) an, um
        Erreichbarkeit und Credentials zu verifizieren.
    .PARAMETER Tools
        Array von Tool-IDs, die geprueft werden sollen.
        Default: alle Tools mit healthCheck=true in tools.json (Jenkins + Atlassian).
    .PARAMETER TimeoutSec
        Timeout pro Request in Sekunden. Default: 10.
    .OUTPUTS
        Array von PSCustomObject:
          ToolId, Endpoint, StatusCode, Ok, Error, ResponseTimeMs, Attempt
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [array]$Tools,
        [int]$TimeoutSec = 10,
        [string]$ConfigPath = "$PSScriptRoot\..\config\tools.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "[HealthCheck] Tools-Konfiguration nicht gefunden: $ConfigPath"
        return @()
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $toolsToCheck = $config.tools | Where-Object { $_.healthCheck -eq $true }

    if ($Tools -and $Tools.Count -gt 0) {
        $toolsToCheck = $toolsToCheck | Where-Object { $_.id -in $Tools }
    }

    if ($toolsToCheck.Count -eq 0) {
        Write-Information "[HealthCheck] Keine Tools mit healthCheck=true gefunden." -InformationAction Continue
        return @()
    }

    $results = @()

    foreach ($tool in $toolsToCheck) {
        Write-Information "[HealthCheck] Pruefe $($tool.id) ..." -InformationAction Continue

        # Endpoint + Headers mit Secret-Platzhaltern aufloesen
        $endpoint = Resolve-DevCityHealthCheckSecret -Text $tool.healthCheckEndpoint
        $headers = @{}
        if ($tool.healthCheckHeaders) {
            foreach ($prop in $tool.healthCheckHeaders.PSObject.Properties) {
                $headers[$prop.Name] = Resolve-DevCityHealthCheckSecret -Text $prop.Value
            }
        }

        # Pruefen, ob noch Platzhalter uebrig sind (Secrets nicht erfasst)
        $hasPlaceholder = $false
        if ($endpoint -match '\{\{secret:') { $hasPlaceholder = $true }
        foreach ($h in $headers.Values) {
            if ($h -match '\{\{secret:') { $hasPlaceholder = $true }
        }

        if ($hasPlaceholder) {
            Write-Warning "[HealthCheck] $($tool.id): Secrets nicht erfasst — Ueberspringe Health-Check."
            $results += [PSCustomObject]@{
                ToolId         = $tool.id
                Endpoint       = ($endpoint -replace '\{\{secret:.+?\}\}', '[SECRET]')
                StatusCode     = 0
                Ok             = $false
                Error          = 'Secrets not configured (run Phase 5 first)'
                ResponseTimeMs = 0
                Attempt        = 0
            }
            continue
        }

        # HTTP-Request mit Retry
        $result = Invoke-DevCityHttpRequest -Url $endpoint -Headers $headers -TimeoutSec $TimeoutSec

        $results += [PSCustomObject]@{
            ToolId         = $tool.id
            Endpoint       = $endpoint
            StatusCode     = $result.StatusCode
            Ok             = $result.Ok
            Error          = $result.Error
            ResponseTimeMs = $result.ResponseTimeMs
            Attempt        = $result.Attempt
        }

        # Audit-Log (Endpoint ohne Secrets —已经是 resolved, aber wir loggen nur ToolId)
        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            $level = if ($result.Ok) { 'Info' } else { 'Error' }
            $meta = @{ StatusCode = $result.StatusCode; ResponseTimeMs = $result.ResponseTimeMs; Attempts = $result.Attempt }
            Write-DevCityAuditLog -Action 'HealthCheck' -Detail "ToolId=$($tool.id), Ok=$($result.Ok)" -Metadata $meta -Level $level
        }
    }

    return $results
}

function Test-DevCityJenkinsHealth {
    <#
    .SYNOPSIS
        Spezifischer Health-Check fuer Jenkins.
        Ruft {{JENKINS_URL}}/api/json?tree=mode auf.
    .OUTPUTS
        PSCustomObject: Url, StatusCode, Ok, ResponseTimeMs, Error, Version
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$TimeoutSec = 10
    )

    $results = Invoke-DevCityHealthCheck -Tools @('jenkins-mcp-plugin') -TimeoutSec $TimeoutSec
    if ($results.Count -eq 0) { return $null }
    return $results[0]
}

function Test-DevCityAtlassianHealth {
    <#
    .SYNOPSIS
        Spezifischer Health-Check fuer Atlassian.
        Ruft {{ATLASSIAN_URL}}/rest/api/3/myself auf.
    .OUTPUTS
        PSCustomObject: Url, StatusCode, Ok, ResponseTimeMs, Error, AccountId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$TimeoutSec = 10
    )

    $results = Invoke-DevCityHealthCheck -Tools @('atlassian-mcp-server') -TimeoutSec $TimeoutSec
    if ($results.Count -eq 0) { return $null }
    return $results[0]
}

function Format-DevCityHealthCheckReport {
    <#
    .SYNOPSIS
        Formatiert Health-Check-Ergebnisse als lesbaren Report fuer die Konsole.
    .PARAMETER Results
        Array von Health-Check-Ergebnissen (von Invoke-DevCityHealthCheck).
    .OUTPUTS
        String: Formatted report (mehrere Zeilen).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][array]$Results
    )

    $lines = @()
    $lines += '================================================='
    $lines += '   DevCity Health-Check Report'
    $lines += '================================================='
    $lines += ''

    foreach ($r in $Results) {
        $status = if ($r.Ok) { 'OK' } else { 'FAIL' }
        $time = if ($r.ResponseTimeMs -gt 0) { "$($r.ResponseTimeMs)ms" } else { '-' }
        $endpoint = $r.Endpoint
        if ($endpoint.Length -gt 50) { $endpoint = $endpoint.Substring(0, 47) + '...' }

        $lines += ("  [{0}] {1,-20} {2,-50} {3}" -f $status, $r.ToolId, $endpoint, $time)
        if ($r.Error) {
            $lines += "         Error: $($r.Error)"
        }
        if ($r.Attempt -gt 1) {
            $lines += "         (nach $($r.Attempt) Versuchen)"
        }
    }

    $lines += ''
    $okCount = ($Results | Where-Object { $_.Ok }).Count
    $failCount = ($Results | Where-Object { -not $_.Ok }).Count
    $lines += "  Zusammenfassung: $okCount OK, $failCount FAIL"
    $lines += '================================================='

    return $lines -join "`n"
}

function Write-DevCityHealthCheckMarkdown {
    <#
    .SYNOPSIS
        Optimierung 9: Schreibt Health-Check-Report als Markdown-Datei.
        Pfad: logs/health-check-YYYYMMDD.md
        Kann in GitHub Issues gepastet werden.
    .PARAMETER Results
        Array von Health-Check-Ergebnissen.
    .OUTPUTS
        Pfad zur Markdown-Datei.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][array]$Results
    )

    if (-not (Test-Path $DEVCITY_LOG_DIR)) {
        New-Item -ItemType Directory -Path $DEVCITY_LOG_DIR -Force | Out-Null
    }

    $dateStamp = (Get-Date).ToString('yyyy-MM-dd-HHmmss')
    $mdFile = Join-Path $DEVCITY_LOG_DIR "health-check-$dateStamp.md"

    $lines = @()
    $lines += "# DevCity Health-Check Report"
    $lines += ""
    $lines += "**Datum:** $(Get-Date -Format 'o')"
    $lines += "**Plattform:** $(Get-DevCityPlatform)"
    $lines += ""
    $lines += "## Ergebnisse"
    $lines += ""
    $lines += "| Tool | Endpoint | Status | Response Time | Versuche | Fehler |"
    $lines += "|---|---|---|---|---|---|"

    foreach ($r in $Results) {
        $status = if ($r.Ok) { 'OK' } else { 'FAIL' }
        $endpoint = $r.Endpoint -replace '\{\{secret:.+?\}\}', '[SECRET]'
        $error = if ($r.Error) { $r.Error } else { '-' }
        $lines += "| $($r.ToolId) | $endpoint | $status | $($r.ResponseTimeMs)ms | $($r.Attempt) | $error |"
    }

    $lines += ""
    $okCount = ($Results | Where-Object { $_.Ok }).Count
    $failCount = ($Results | Where-Object { -not $_.Ok }).Count
    $lines += "## Zusammenfassung"
    $lines += ""
    $lines += "- OK: $okCount"
    $lines += "- FAIL: $failCount"
    $lines += ""

    [System.IO.File]::WriteAllText($mdFile, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))

    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'HealthCheck-Markdown' -Detail "File=$mdFile" -Level Info
    }

    return $mdFile
}

Export-ModuleMember -Function *