# =====================================================================
# DevCity Module: Memory
# Verwaltet Projekt-Memory — lokal oder zentral (Jenkins/Atlassian-Server).
# Transportwege: SSH/SCP, Git-Remote, SMB, HTTP-API (via Setup-Menue waehlbar).
# Optimierung 5: Memory-Transport-Auto-Detection
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

if (-not (Test-Path Variable:DEVCITY_MEMORY_LOCAL_PATH)) {
    New-Variable -Name DEVCITY_MEMORY_LOCAL_PATH -Value (Join-Path $PSScriptRoot '..\memory') -Option Constant -ErrorAction SilentlyContinue
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

function Get-DevCityMemoryConfigPath {
    return Join-Path $DEVCITY_MEMORY_LOCAL_PATH 'devcity-memory.json'
}

# ---------------------------------------------------------------------
# Auto-Detection (Optimierung 5)
# ---------------------------------------------------------------------

function Get-DevCityMemoryTransport {
    <#
    .SYNOPSIS
        Optimierung 5: Erraet den besten Transportweg aus der Remote-URL.
    .OUTPUTS
        String: 'ssh-scp' | 'git-remote' | 'smb' | 'http-api' | $null
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RemoteUrl
    )

    if (-not $RemoteUrl) { return $null }

    # Git-Remote: endet auf .git oder beginnt mit git@
    if ($RemoteUrl -match '^git@' -or $RemoteUrl -match '\.git$') {
        return 'git-remote'
    }

    # SMB: beginnt mit \\ (UNC-Pfad)
    if ($RemoteUrl -match '^\\\\') {
        return 'smb'
    }

    # HTTP-API: beginnt mit http(s)://
    if ($RemoteUrl -match '^https?://') {
        return 'http-api'
    }

    # SSH/SCP: beginnt mit user@host: oder enthaelt ssh-Indikatoren
    if ($RemoteUrl -match '^\w+@[\w\.-]+:' -or $RemoteUrl -match '^ssh://') {
        return 'ssh-scp'
    }

    # Fallback: ssh-scp (häufigster Fall fuer Jenkins/Atlassian-Server)
    return 'ssh-scp'
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function New-DevCityMemory {
    <#
    .SYNOPSIS
        Legt ein neues Projekt-Memory an — lokal oder zentral.
    .PARAMETER Mode
        'lokal' (Default) oder 'zentral'. Wenn nicht angegeben, wird gepromptet.
    .PARAMETER Transport
        Nur bei Mode='zentral': 'ssh-scp' | 'git-remote' | 'smb' | 'http-api'.
    .PARAMETER RemoteUrl
        Nur bei Mode='zentral': Ziel-URL/Host/Pfad.
    .PARAMETER NonInteractive
        Switch: Keine Prompts — alle Parameter muessen als Argumente kommen.
    .OUTPUTS
        $true bei Erfolg, $false bei Fehler.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [ValidateSet('lokal', 'zentral')][string]$Mode,
        [ValidateSet('ssh-scp', 'git-remote', 'smb', 'http-api')][string]$Transport,
        [string]$RemoteUrl,
        [switch]$NonInteractive
    )

    # Mode prompten, falls nicht angegeben
    if (-not $Mode) {
        if ($NonInteractive) {
            $Mode = 'lokal'
            Write-Information "[Memory] NonInteractive-Mode: verwende Default 'lokal'." -InformationAction Continue
        } else {
            Write-Information "" -InformationAction Continue
            Write-Information "Projekt-Memory anlegen:" -InformationAction Continue
            Write-Information "  [1] lokal (Default) — DevCity/memory/ (nicht im Git-Repo)" -InformationAction Continue
            Write-Information "  [2] zentral         — Jenkins/Atlassian-Server via SSH/Git/SMB/HTTP" -InformationAction Continue
            $response = Read-Host "Modus (1/2, Default: 1)"
            $Mode = if ($response -eq '2') { 'zentral' } else { 'lokal' }
        }
    }

    # Lokales Memory-Verzeichnis sicherstellen
    if (-not (Test-Path $DEVCITY_MEMORY_LOCAL_PATH)) {
        New-Item -ItemType Directory -Path $DEVCITY_MEMORY_LOCAL_PATH -Force | Out-Null
    }

    # Config bauen
    $config = [ordered]@{
        version    = '1.0.0'
        mode       = $Mode
        localPath  = (Resolve-Path $DEVCITY_MEMORY_LOCAL_PATH).Path
        transport  = $null
        remoteUrl  = $null
        lastSync   = $null
        createdAt  = (Get-Date).ToString('o')
    }

    if ($Mode -eq 'zentral') {
        # RemoteUrl prompten
        if (-not $RemoteUrl -and -not $NonInteractive) {
            Write-Information "" -InformationAction Continue
            Write-Information "Zentraler Memory-Server:" -InformationAction Continue
            Write-Information "  Beispiele:" -InformationAction Continue
            Write-Information "    SSH : user@host:/srv/devcity-memory" -InformationAction Continue
            Write-Information "    Git : git@github.com:org/devcity-memory.git" -InformationAction Continue
            Write-Information "    SMB : \\\\server\\devcity-memory" -InformationAction Continue
            Write-Information "    HTTP: https://jenkins.example.com/api/memory" -InformationAction Continue
            $RemoteUrl = Read-Host "Remote-URL"
        }

        if (-not $RemoteUrl) {
            Write-Warning "[Memory] Keine Remote-URL angegeben — falle auf 'lokal' zurueck."
            $config.mode = 'lokal'
        } else {
            # Transport erraten (Optimierung 5), falls nicht angegeben
            if (-not $Transport) {
                $Transport = Get-DevCityMemoryTransport -RemoteUrl $RemoteUrl
                Write-Information "[Memory] Auto-Detection: Transportweg = $Transport" -InformationAction Continue
            }

            $config.transport = $Transport
            $config.remoteUrl = $RemoteUrl
        }
    }

    # Config schreiben
    $configPath = Get-DevCityMemoryConfigPath
    $json = $config | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Audit-Log
    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        $meta = @{ Mode = $config.mode; Transport = $config.transport }
        Write-DevCityAuditLog -Action 'New-Memory' -Detail "Mode=$($config.mode), Transport=$($config.transport)" -Metadata $meta -Level Info
    }

    Write-Information "[Memory] OK: Memory angelegt (Mode=$($config.mode))." -InformationAction Continue
    Write-Information "[Memory] Config: $configPath" -InformationAction Continue

    # Bei zentral: ersten Sync durchfuehren
    if ($config.mode -eq 'zentral') {
        Write-Information "[Memory] Erster Sync (zentral) ..." -InformationAction Continue
        Sync-DevCityMemory -Direction 'push' | Out-Null
    }

    return $true
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

    $configPath = Get-DevCityMemoryConfigPath
    if (-not (Test-Path $configPath)) {
        return $null
    }

    $raw = Get-Content $configPath -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Sync-DevCityMemory {
    <#
    .SYNOPSIS
        Synchronisiert das Memory mit dem zentralen Server (nur bei Mode='zentral').
        Bei Mode='lokal': No-Op.
    .PARAMETER Direction
        'push' (lokal -> zentral) oder 'pull' (zentral -> lokal) oder 'both' (Default).
    .OUTPUTS
        $true bei Erfolg, $false bei Fehler.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [ValidateSet('push', 'pull', 'both')][string]$Direction = 'both'
    )

    $config = Get-DevCityMemoryConfig
    if (-not $config) {
        Write-Warning "[Memory] Keine Memory-Config gefunden. Bitte zuerst New-DevCityMemory aufrufen."
        return $false
    }

    if ($config.mode -eq 'lokal') {
        Write-Information "[Memory] Lokales Memory — kein Sync noetig." -InformationAction Continue
        return $true
    }

    $transport = $config.transport
    $remoteUrl = $config.remoteUrl
    $localPath = $config.localPath

    Write-Information "[Memory] Sync ($Direction) via $transport ..." -InformationAction Continue

    try {
        switch ($transport) {
            'ssh-scp' {
                if ($Direction -in @('push', 'both')) {
                    # scp -r localPath/* remoteUrl
                    $cmd = "scp -r `"$localPath\*`" `"$remoteUrl`""
                    Write-Verbose "[Memory] $cmd"
                    Invoke-Expression $cmd
                    if ($LASTEXITCODE -ne 0) { throw "scp push fehlgeschlagen (Exit $LASTEXITCODE)" }
                }
                if ($Direction -in @('pull', 'both')) {
                    $cmd = "scp -r `"$remoteUrl/*`" `"$localPath`""
                    Write-Verbose "[Memory] $cmd"
                    Invoke-Expression $cmd
                    if ($LASTEXITCODE -ne 0) { throw "scp pull fehlgeschlagen (Exit $LASTEXITCODE)" }
                }
            }

            'git-remote' {
                Push-Location $localPath
                try {
                    if (-not (Test-Path (Join-Path $localPath '.git'))) {
                        git init -b main 2>&1 | Out-Null
                        git remote add origin $remoteUrl 2>&1 | Out-Null
                    }
                    if ($Direction -in @('push', 'both')) {
                        git add -A 2>&1 | Out-Null
                        git commit -m "DevCity memory sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
                        git push origin main 2>&1 | Out-Null
                    }
                    if ($Direction -in @('pull', 'both')) {
                        git pull origin main 2>&1 | Out-Null
                    }
                } finally {
                    Pop-Location
                }
            }

            'smb' {
                if ($Direction -in @('push', 'both')) {
                    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                        robocopy $localPath $remoteUrl /MIR /R:2 /W:5 | Out-Null
                    } else {
                        Write-Warning "[Memory] SMB-Sync auf Unix nicht implementiert — bitte manuell via mount."
                        return $false
                    }
                }
                if ($Direction -in @('pull', 'both')) {
                    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                        robocopy $remoteUrl $localPath /MIR /R:2 /W:5 | Out-Null
                    } else {
                        Write-Warning "[Memory] SMB-Sync auf Unix nicht implementiert — bitte manuell via mount."
                        return $false
                    }
                }
            }

            'http-api' {
                if ($Direction -in @('push', 'both')) {
                    $files = Get-ChildItem -Path $localPath -File -Recurse
                    foreach ($f in $files) {
                        $relPath = $f.FullName -replace [regex]::Escape($localPath + '\'), ''
                        $url = "$remoteUrl/$relPath" -replace '\\', '/'
                        Invoke-RestMethod -Uri $url -Method Put -InFile $f.FullName -ErrorAction Stop | Out-Null
                    }
                }
                if ($Direction -in @('pull', 'both')) {
                    Write-Warning "[Memory] HTTP-Pull nicht implementiert — bitte manuell."
                }
            }

            default {
                Write-Error "[Memory] Unbekannter Transportweg: $transport"
                return $false
            }
        }

        # LastSync aktualisieren
        $config.lastSync = (Get-Date).ToString('o')
        $configPath = Get-DevCityMemoryConfigPath
        $json = $config | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))

        Write-Information "[Memory] OK: Sync abgeschlossen." -InformationAction Continue

        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Sync-Memory' -Detail "Direction=$Direction, Transport=$transport" -Level Info
        }

        return $true
    } catch {
        Write-Error "[Memory] Sync fehlgeschlagen: $_"

        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Sync-Memory' -Detail "Direction=$Direction, Error=$($_.Exception.Message)" -Level Error
        }

        return $false
    }
}

function Remove-DevCityMemory {
    <#
    .SYNOPSIS
        Loescht das lokale Memory und entfernt die Config.
        ACHTUNG: Nur fuer Reset. Backup vorher via Snapshot-Modul.
    .OUTPUTS
        $true bei Erfolg.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [switch]$Force
    )

    if (-not $Force) {
        $response = Read-Host "Wirklich Memory loeschen? (j/N)"
        if ($response -notmatch '^[jJyY]') {
            Write-Information "[Memory] Abgebrochen." -InformationAction Continue
            return $false
        }
    }

    $configPath = Get-DevCityMemoryConfigPath
    if (Test-Path $configPath) { Remove-Item $configPath -Force }

    # Inhalt loeschen, aber README.md und .gitkeep behalten
    $protected = @('README.md', '.gitkeep', 'devcity-memory.json')
    Get-ChildItem -Path $DEVCITY_MEMORY_LOCAL_PATH -Recurse -File |
        Where-Object { $_.Name -notin $protected } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'Remove-Memory' -Detail "LocalPath=$DEVCITY_MEMORY_LOCAL_PATH" -Level Warning
    }

    Write-Information "[Memory] OK: Memory-Inhalte geloescht (README/.gitkeep behalten)." -InformationAction Continue
    return $true
}

Export-ModuleMember -Function *