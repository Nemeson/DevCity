# =====================================================================
# DevCity Module: Snapshot
# Transaktionaler Snapshot vor Setup-Start. Rollback bei kritischen Fehlern.
# NFR 3C: Snapshot vorab, Restore bei Fehler.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

New-Variable -Name DEVCITY_BACKUP_DIR -Value (Join-Path $PSScriptRoot '..\backups') -Option Constant -ErrorAction SilentlyContinue

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

function Resolve-DevClientPath {
    param([string]$PathTemplate)
    $platform = Get-DevCityPlatform
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { '~' }
    $result = $PathTemplate
    if ($env:APPDATA) { $result = $result.Replace('%APPDATA%', $env:APPDATA) }
    if ($env:USERPROFILE) { $result = $result.Replace('%USERPROFILE%', $env:USERPROFILE) }
    $result = $result.Replace('~', $home)
    $result = $result.Replace('$HOME', $home)
    if ($platform -eq 'windows') {
        $result = $result.Replace('/', '\')
    }
    return $result
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function New-DevCitySnapshot {
    <#
    .SYNOPSIS
        Erzeugt einen Snapshot der relevanten Config-Dateien vor dem Setup.
        ZIP-Archiv unter backups/snapshot-YYYYMMDD-HHMMSS.zip.
    .PARAMETER IncludeMcpConfigs
        Switch: Auch MCP-Client-Configs (opencode.json, claude_desktop_config.json, ...)
        mit sichern. Default: ja.
    .PARAMETER IncludeMemory
        Switch: Auch lokales Memory sichern. Default: nein (kann groß sein).
    .PARAMETER IncludeSecrets
        Switch: Auch Secret-Metadata sichern (NICHT die Secret-Werte!).
        Default: nein.
    .OUTPUTS
        Pfad zur Snapshot-Datei (string).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [switch]$IncludeMcpConfigs = $true,
        [switch]$IncludeMemory,
        [switch]$IncludeSecrets
    )

    $platform = Get-DevCityPlatform

    # 1. Backup-Verzeichnis sicherstellen
    if (-not (Test-Path $DEVCITY_BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $DEVCITY_BACKUP_DIR -Force | Out-Null
    }

    # 2. Temporäres Verzeichnis anlegen
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $tempDir = Join-Path $env:TEMP "devcity-snapshot-$timestamp"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # 3. Relevante Dateien hineinkopieren
        
        # config/*.json
        $configSrc = Join-Path $PSScriptRoot '..\config'
        $configDest = Join-Path $tempDir 'config'
        New-Item -ItemType Directory -Path $configDest -Force | Out-Null
        if (Test-Path $configSrc) {
            Copy-Item -Path "$configSrc\*.json" -Destination $configDest -Force
        }

        # templates/*.tpl
        $templatesSrc = Join-Path $PSScriptRoot '..\templates'
        $templatesDest = Join-Path $tempDir 'templates'
        New-Item -ItemType Directory -Path $templatesDest -Force | Out-Null
        if (Test-Path $templatesSrc) {
            Copy-Item -Path "$templatesSrc\*.tpl" -Destination $templatesDest -Force
        }

        # .env (wenn vorhanden und IncludeSecrets)
        $envFile = Join-Path $PSScriptRoot '..\.env'
        if ($IncludeSecrets -and (Test-Path $envFile)) {
            Copy-Item -Path $envFile -Destination $tempDir -Force
        }

        # memory/devcity-memory.json (Memory-Config, nicht Memory-Inhalt)
        $memorySrc = Join-Path $PSScriptRoot '..\memory'
        $memoryDest = Join-Path $tempDir 'memory'
        New-Item -ItemType Directory -Path $memoryDest -Force | Out-Null
        $memConfig = Join-Path $memorySrc 'devcity-memory.json'
        if (Test-Path $memConfig) {
            Copy-Item -Path $memConfig -Destination $memoryDest -Force
        }

        # MCP-Client-Configs NUR wenn -IncludeMcpConfigs
        if ($IncludeMcpConfigs) {
            $mcpDest = Join-Path $tempDir 'mcp-configs'
            New-Item -ItemType Directory -Path $mcpDest -Force | Out-Null
            $clientsConfigPath = Join-Path $PSScriptRoot '..\config\clients.json'
            if (Test-Path $clientsConfigPath) {
                $clientsConfig = Get-Content $clientsConfigPath -Raw | ConvertFrom-Json
                foreach ($client in $clientsConfig.clients) {
                    $pathTemplate = $client.configPath.$platform
                    if ($pathTemplate) {
                        $clientPath = Resolve-DevClientPath -PathTemplate $pathTemplate
                        if (Test-Path $clientPath) {
                            $ext = [System.IO.Path]::GetExtension($clientPath)
                            $destPath = Join-Path $mcpDest "$($client.id)$ext"
                            Copy-Item -Path $clientPath -Destination $destPath -Force
                        }
                    }
                }
            }
        }

        # 4. Memory-Inhalt kopieren (nur bei -IncludeMemory)
        if ($IncludeMemory -and (Test-Path $memorySrc)) {
            $memoryFilesDest = Join-Path $memoryDest 'files'
            New-Item -ItemType Directory -Path $memoryFilesDest -Force | Out-Null
            Get-ChildItem -Path $memorySrc -File -Recurse | Where-Object { $_.Name -ne 'devcity-memory.json' } | ForEach-Object {
                $relPath = $_.FullName.Substring($memorySrc.Length + 1)
                $destFile = Join-Path $memoryFilesDest $relPath
                $destFileDir = Split-Path $destFile -Parent
                if (-not (Test-Path $destFileDir)) {
                    New-Item -ItemType Directory -Path $destFileDir -Force | Out-Null
                }
                Copy-Item -Path $_.FullName -Destination $destFile -Force
            }
        }

        # Metadata-Datei im Temp-Dir erstellen
        $meta = [PSCustomObject]@{
            CreatedAt        = (Get-Date).ToString('o')
            IncludeMcp       = [bool]$IncludeMcpConfigs
            IncludeMemory    = [bool]$IncludeMemory
            IncludeSecrets   = [bool]$IncludeSecrets
        }
        $metaJson = $meta | ConvertTo-Json
        [System.IO.File]::WriteAllText((Join-Path $tempDir 'snapshot-meta.json'), $metaJson, [System.Text.Encoding]::UTF8)

        # 5. ZIP-Archiv erstellen
        $zipPath = Join-Path $DEVCITY_BACKUP_DIR "snapshot-$timestamp.zip"
        if ($PSCmdlet.ShouldProcess($zipPath, "Erzeuge Snapshot")) {
            Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        }

        # 7. Audit-Log
        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            $logMeta = @{ IncludeMcp = $IncludeMcpConfigs; IncludeMemory = $IncludeMemory; IncludeSecrets = $IncludeSecrets }
            Write-DevCityAuditLog -Action 'Create-Snapshot' -Detail "Path=$zipPath" -Metadata $logMeta -Level Info
        }

        # 8. Pfad zurückgeben
        return (Resolve-Path $zipPath).Path
    } finally {
        # 6. Temp-Verzeichnis löschen
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

function Get-DevCitySnapshot {
    <#
    .SYNOPSIS
        Liefert Metadaten eines Snapshots (ohne Inhalt zu entpacken).
    .PARAMETER Path
        Pfad zur ZIP-Datei.
    .OUTPUTS
        PSCustomObject: CreatedAt, SizeBytes, FileCount, IncludeMcp, IncludeMemory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "Snapshot-Datei nicht gefunden: $Path"
        return $null
    }

    $resolvedPath = (Resolve-Path $Path).Path

    Add-Type -AssemblyName System.IO.Compression
    $stream = [System.IO.File]::OpenRead($resolvedPath)
    $archive = [System.IO.Compression.ZipArchive]::new($stream)
    
    $metaEntry = $archive.Entries | Where-Object { $_.FullName -eq 'snapshot-meta.json' }
    
    $createdAt = $null
    $includeMcp = $false
    $includeMemory = $false
    $includeSecrets = $false
    
    if ($metaEntry) {
        $reader = [System.IO.StreamReader]::new($metaEntry.Open())
        $metaJson = $reader.ReadToEnd()
        $reader.Close()
        
        $meta = $metaJson | ConvertFrom-Json
        $createdAt = $meta.CreatedAt
        $includeMcp = $meta.IncludeMcp
        $includeMemory = $meta.IncludeMemory
        $includeSecrets = $meta.IncludeSecrets
    }
    
    $fileCount = $archive.Entries.Count
    $archive.Dispose()
    $stream.Dispose()

    $fileInfo = Get-Item $resolvedPath

    return [PSCustomObject]@{
        Path           = $resolvedPath
        CreatedAt      = $createdAt
        SizeBytes      = $fileInfo.Length
        FileCount      = $fileCount
        IncludeMcp     = $includeMcp
        IncludeMemory  = $includeMemory
        IncludeSecrets = $includeSecrets
    }
}

function Get-DevCitySnapshots {
    <#
    .SYNOPSIS
        Listet alle verfügbaren Snapshots auf (neueste zuerst).
    .OUTPUTS
        Array von PSCustomObject (Path, CreatedAt, SizeBytes)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param()

    if (-not (Test-Path $DEVCITY_BACKUP_DIR)) {
        return @()
    }

    $files = Get-ChildItem -Path $DEVCITY_BACKUP_DIR -Filter 'snapshot-*.zip' | Sort-Object LastWriteTime -Descending
    $results = @()
    foreach ($file in $files) {
        try {
            $snap = Get-DevCitySnapshot -Path $file.FullName
            if ($snap) {
                $results += $snap
            }
        } catch {
            # Ungültige ZIP-Dateien überspringen
        }
    }
    return $results
}

function Restore-DevCitySnapshot {
    <#
    .SYNOPSIS
        Stellt einen Snapshot wieder her.
        Überschreibt aktuelle Configs mit der gesicherten Version.
    .PARAMETER Path
        Pfad zur ZIP-Datei.
    .PARAMETER Force
        Switch: Keine Bestätigung einholen.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )

    if (-not (Test-Path $Path)) {
        Write-Error "Snapshot nicht gefunden: $Path"
        return
    }

    # 1. Snapshot prüfen
    $snap = Get-DevCitySnapshot -Path $Path
    if (-not $snap) {
        Write-Error "Ungültiger Snapshot: $Path"
        return
    }

    # 2. Bestätigung einholen (außer -Force)
    if (-not $Force) {
        Write-Warning "Wiederherstellen des Snapshots vom $($snap.CreatedAt) überschreibt aktuelle Konfigurationen!"
        $response = Read-Host "Möchtest Du fortfahren? (j/N)"
        if ($response -notmatch '^[jJyY]') {
            Write-Information "Restore abgebrochen." -InformationAction Continue
            return
        }
    }

    # 3. Vor Restore: neuen Pre-Restore-Snapshot erzeugen (Safety-Net)
    Write-Information "Erzeuge Sicherheits-Snapshot vor dem Restore..." -InformationAction Continue
    $safetySnapshot = New-DevCitySnapshot -IncludeMcpConfigs:$snap.IncludeMcp -IncludeMemory:$snap.IncludeMemory -IncludeSecrets:$snap.IncludeSecrets
    Write-Information "Sicherheits-Snapshot erzeugt unter: $safetySnapshot" -InformationAction Continue

    # 4. ZIP entpacken nach Temp-Verzeichnis
    $tempDir = Join-Path $env:TEMP "devcity-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        if ($PSCmdlet.ShouldProcess($Path, "Wiederherstellen aus Snapshot")) {
            Expand-Archive -Path $snap.Path -DestinationPath $tempDir -Force
            
            # 5. Dateien an ihre Ursprungsorte zurückkopieren
            
            # Restore config/*.json
            $configDest = Join-Path $PSScriptRoot '..\config'
            if (Test-Path (Join-Path $tempDir 'config')) {
                Copy-Item -Path "$tempDir\config\*.json" -Destination $configDest -Force
            }

            # Restore templates/*.tpl
            $templatesDest = Join-Path $PSScriptRoot '..\templates'
            if (Test-Path (Join-Path $tempDir 'templates')) {
                Copy-Item -Path "$tempDir\templates\*.tpl" -Destination $templatesDest -Force
            }

            # Restore .env (falls im Snapshot vorhanden)
            $envSrc = Join-Path $tempDir '.env'
            $envDest = Join-Path $PSScriptRoot '..'
            if (Test-Path $envSrc) {
                Copy-Item -Path $envSrc -Destination $envDest -Force
            } elseif ($snap.IncludeSecrets) {
                $curEnv = Join-Path $envDest '.env'
                if (Test-Path $curEnv) { Remove-Item $curEnv -Force }
            }

            # Restore memory/devcity-memory.json
            $memoryDest = Join-Path $PSScriptRoot '..\memory'
            if (-not (Test-Path $memoryDest)) {
                New-Item -ItemType Directory -Path $memoryDest -Force | Out-Null
            }
            $memConfigSrc = Join-Path $tempDir 'memory\devcity-memory.json'
            if (Test-Path $memConfigSrc) {
                Copy-Item -Path $memConfigSrc -Destination $memoryDest -Force
            }

            # Restore MCP-Client-Configs
            if ($snap.IncludeMcp -and (Test-Path (Join-Path $tempDir 'mcp-configs'))) {
                $platform = Get-DevCityPlatform
                $clientsConfigPath = Join-Path $PSScriptRoot '..\config\clients.json'
                if (Test-Path $clientsConfigPath) {
                    $clientsConfig = Get-Content $clientsConfigPath -Raw | ConvertFrom-Json
                    foreach ($client in $clientsConfig.clients) {
                        $ext = '.json'
                        $srcFile = Join-Path $tempDir "mcp-configs\$($client.id)$ext"
                        if (Test-Path $srcFile) {
                            $pathTemplate = $client.configPath.$platform
                            if ($pathTemplate) {
                                $clientPath = Resolve-DevClientPath -PathTemplate $pathTemplate
                                $clientDir = Split-Path $clientPath -Parent
                                if (-not (Test-Path $clientDir)) {
                                    New-Item -ItemType Directory -Path $clientDir -Force | Out-Null
                                }
                                Copy-Item -Path $srcFile -Destination $clientPath -Force
                            }
                        }
                    }
                }
            }

            # Restore Memory files
            if ($snap.IncludeMemory -and (Test-Path (Join-Path $tempDir 'memory\files'))) {
                $memoryFilesSrc = Join-Path $tempDir 'memory\files'
                Get-ChildItem -Path $memoryFilesSrc -File -Recurse | ForEach-Object {
                    $relPath = $_.FullName.Substring($memoryFilesSrc.Length + 1)
                    $destFile = Join-Path $memoryDest $relPath
                    $destFileDir = Split-Path $destFile -Parent
                    if (-not (Test-Path $destFileDir)) {
                        New-Item -ItemType Directory -Path $destFileDir -Force | Out-Null
                    }
                    Copy-Item -Path $_.FullName -Destination $destFile -Force
                }
            }

            Write-Information "Restore erfolgreich abgeschlossen." -InformationAction Continue

            # 6. Audit-Log
            if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
                Write-DevCityAuditLog -Action 'Restore-Snapshot' -Detail "Path=$($snap.Path)" -Level Warning
            }

            # 7. Empfehlung: DevCity neu starten
            Write-Information "Empfehlung: Bitte starte Deine MCP-Clients neu." -InformationAction Continue
        }
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

function Remove-DevCitySnapshot {
    <#
    .SYNOPSIS
        Löscht einen Snapshot.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force
    )

    if (-not (Test-Path $Path)) {
        Write-Error "Snapshot nicht gefunden: $Path"
        return
    }

    $resolvedPath = (Resolve-Path $Path).Path

    if ($Force -or $PSCmdlet.ShouldProcess($resolvedPath, "Lösche Snapshot")) {
        Remove-Item $resolvedPath -Force
        Write-Information "Snapshot gelöscht: $resolvedPath" -InformationAction Continue
        
        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Remove-Snapshot' -Detail "Path=$resolvedPath" -Level Info
        }
    }
}

Export-ModuleMember -Function *