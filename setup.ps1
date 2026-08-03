#Requires -Version 7.0
# =====================================================================
# DevCity - Interaktives Setup-Skript
# Agent-Driven-Development-Umgebung: 7 Tools, MCP, Memory, Multi-Client
# =====================================================================
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [switch]$AutoInstall,
    [switch]$NonInteractive,
    [string[]]$OnlyModule,
    [string]$Rollback,
    [switch]$ListSnapshots,
    [switch]$SkipHealthCheck,
    [switch]$SkipSnapshot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# UTF-8 Console-Encoding sicherstellen (fixt Umlaut-Darstellung auf Windows)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

$script:DEVCITY_ROOT = (Resolve-Path $PSScriptRoot).Path
$script:DEVCITY_MODULES = Join-Path $script:DEVCITY_ROOT 'modules'
$script:DEVCITY_CONFIG = Join-Path $script:DEVCITY_ROOT 'config'
$script:DEVCITY_LOGS = Join-Path $script:DEVCITY_ROOT 'logs'
$script:DEVCITY_BACKUPS = Join-Path $script:DEVCITY_ROOT 'backups'

# ---------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------

function Show-DevCityBanner {
    Write-Information '=================================================' -InformationAction Continue
    Write-Information '   DevCity — Agent-Driven-Development Setup v1.0' -InformationAction Continue
    Write-Information '=================================================' -InformationAction Continue
    Write-Information ''
    Write-Information "  Root: $script:DEVCITY_ROOT" -InformationAction Continue
    Write-Information "  OS  : $(Get-DevCityPlatform)" -InformationAction Continue
    Write-Information ''
}

# ---------------------------------------------------------------------
# Module importieren
# ---------------------------------------------------------------------

function Import-DevCityModules {
    $modules = @(
        'Audit.psm1', 'Snapshot.psm1', 'Secrets.psm1', 'Prerequisites.psm1',
        'Tools.psm1', 'Memory.psm1', 'MCPConfig.psm1', 'HealthCheck.psm1'
    )

    foreach ($mod in $modules) {
        $path = Join-Path $script:DEVCITY_MODULES $mod
        if (Test-Path $path) {
            try {
                Import-Module $path -Force -ErrorAction Stop
                Write-Verbose "Modul geladen: $mod"
            } catch {
                Write-Error "Modul konnte nicht geladen werden: $mod — $_"
                throw
            }
        } else {
            Write-Error "Modul-Datei fehlt: $path"
            throw "Missing module: $path"
        }
    }
}

# Plattform-Erkennung wird aus Prerequisites.psm1 exportiert, aber wir
# brauchen sie frueher fuer den Banner. Lokale Definition als Fallback.
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

# ---------------------------------------------------------------------
# Setup-Phasen (Stubs, rufen Modul-Funktionen auf)
# ---------------------------------------------------------------------

function Invoke-Phase1Snapshot {
    Write-Information '[1/8] Erzeuge Pre-Setup-Snapshot ...' -InformationAction Continue
    if ($SkipSnapshot) {
        Write-Information '     uebersprungen (-SkipSnapshot)' -InformationAction Continue
        return $null
    }
    if ($DryRun) {
        Write-Information '     Dry-Run: wuerde Snapshot erzeugen.' -InformationAction Continue
        return $null
    }
    # TODO: $snapshotPath = New-DevCitySnapshot -IncludeMcpConfigs -ErrorAction Continue
    # Write-Information "     Snapshot: $snapshotPath" -InformationAction Continue
    return $null
}

function Invoke-Phase2Prerequisites {
    Write-Information '[2/8] Pruefe Prerequisites (Java/Node/Python/Git/Maven/Docker) ...' -InformationAction Continue
    if ($DryRun) {
        $results = Test-Prerequisites
        Write-Information '     Dry-Run: Prerequisites-Status:' -InformationAction Continue
        foreach ($r in $results) {
            $status = if ($r.Ok) { 'OK' } elseif ($r.Installed) { 'OLD' } else { 'MISS' }
            $version = if ($r.Version) { $r.Version } else { '-' }
            Write-Information ("       {0,-10} {1,-20} v{2,-10} (min v{3}) {4}" -f $r.Id, $r.Name, $version, $r.MinVersion, $status) -InformationAction Continue
        }
        return $true
    }
    return Invoke-PrerequisiteCheck -AutoInstall:$AutoInstall -ErrorAction Continue
}

function Invoke-Phase3ToolInstall {
    Write-Information '[3/8] Installiere 7 obligatorische Tools ...' -InformationAction Continue
    if ($DryRun) {
        $status = Get-DevCityToolStatus
        Write-Information '     Dry-Run: Tool-Status (Cache):' -InformationAction Continue
        foreach ($toolId in $status.Keys) {
            $isInstalled = $status[$toolId]
            $mark = if ($isInstalled) { 'OK' } else { 'MISSING' }
            Write-Information ("       {0,-25} {1}" -f $toolId, $mark) -InformationAction Continue
        }
        return $true
    }
    return Install-AllDevCityTools -Force:$Force -Parallel:$true -ErrorAction Continue
}

function Invoke-Phase4Memory {
    Write-Information '[4/8] Konfiguriere Projekt-Memory (lokal/zentral) ...' -InformationAction Continue
    if ($DryRun) {
        $existing = Get-DevCityMemoryConfig
        if ($existing) {
            Write-Information "     Dry-Run: bestehende Memory-Config:" -InformationAction Continue
            Write-Information "       Mode     : $($existing.mode)" -InformationAction Continue
            Write-Information "       Transport: $($existing.transport)" -InformationAction Continue
            Write-Information "       LocalPath: $($existing.localPath)" -InformationAction Continue
            Write-Information "       LastSync : $($existing.lastSync)" -InformationAction Continue
        } else {
            Write-Information "     Dry-Run: wuerde Memory-Setup prompten (Default: lokal)." -InformationAction Continue
        }
        return $true
    }
    return New-DevCityMemory -NonInteractive:$NonInteractive -ErrorAction Continue
}

function Invoke-Phase5Secrets {
    Write-Information '[5/8] Frage Secrets ab (Jenkins/Atlassian/Git-Remote) ...' -InformationAction Continue
    if ($DryRun) {
        Write-Information '     Dry-Run: wuerde Secrets interaktiv abfragen.' -InformationAction Continue
        return
    }
    # TODO: Invoke-DevCitySecretPrompt -Name 'jenkins_url' -Prompt 'Jenkins Base-URL'
    # TODO: Invoke-DevCitySecretPrompt -Name 'jenkins_user' -Prompt 'Jenkins User'
    # TODO: Invoke-DevCitySecretPrompt -Name 'jenkins_token' -Prompt 'Jenkins API-Token'
    # TODO: Invoke-DevCitySecretPrompt -Name 'atlassian_url' -Prompt 'Atlassian Base-URL (Jira/Confluence)'
    # TODO: Invoke-DevCitySecretPrompt -Name 'atlassian_token' -Prompt 'Atlassian API-Token'
}

function Invoke-Phase6McpConfig {
    Write-Information '[6/8] Schreibe MCP-Client-Konfiguration (Multi-Select) ...' -InformationAction Continue
    if ($DryRun) {
        $clientIds = Select-DevCityMcpClients -NonInteractive:$NonInteractive
        Write-Information "     Dry-Run: wuerde MCP-Config schreiben fuer:" -InformationAction Continue
        foreach ($id in $clientIds) {
            Write-Information "       - $id" -InformationAction Continue
        }
        Write-Information "     (Force=$Force — bestehende Eintraege werden $(if ($Force) { 'ueberschrieben' } else { 'erhalten' }))" -InformationAction Continue
        return $true
    }
    $clientIds = Select-DevCityMcpClients -NonInteractive:$NonInteractive
    $results = Write-DevCityMcpConfig -ClientIds $clientIds -Force:$Force
    foreach ($r in $results) {
        if ($r.Error) {
            Write-Warning "     FEHLER ($($r.ClientId)): $($r.Error)" -ErrorAction Continue
        } else {
            $addedCount = if ($r.Added) { $r.Added.Count } else { 0 }
            $conflictCount = if ($r.Conflicts) { $r.Conflicts.Count } else { 0 }
            Write-Information "     OK ($($r.ClientId)): $addedCount Server hinzugefuegt, $conflictCount Konflikte" -InformationAction Continue
        }
    }
    return $true
}

function Invoke-Phase7HealthCheck {
    Write-Information '[7/8] Health-Check fuer Remote-Server (Jenkins + Atlassian) ...' -InformationAction Continue
    if ($SkipHealthCheck) {
        Write-Information '     uebersprungen (-SkipHealthCheck)' -InformationAction Continue
        return
    }
    if ($DryRun) {
        Write-Information '     Dry-Run: wuerde Remote-Server pingen.' -InformationAction Continue
        return
    }
    # TODO: $results = Invoke-DevCityHealthCheck -ErrorAction Continue
    # TODO: Format-DevCityHealthCheckReport -Results $results | Write-Information
}

function Invoke-Phase8Summary {
    Write-Information '[8/8] Zusammenfassung' -InformationAction Continue
    Write-Information '' -InformationAction Continue
    Write-Information '   DevCity-Setup abgeschlossen.' -InformationAction Continue
    Write-Information "   Audit-Logs: $script:DEVCITY_LOGS" -InformationAction Continue
    Write-Information "   Snapshots : $script:DEVCITY_BACKUPS" -InformationAction Continue
    Write-Information '' -InformationAction Continue
    Write-Information '   Naechste Schritte:' -InformationAction Continue
    Write-Information '     1. Client neu starten (OpenCode/Copilot CLI/Claude Desktop)' -InformationAction Continue
    Write-Information '     2. Memory-Pfad pruefen: ./memory/' -InformationAction Continue
    Write-Information '     3. Secrets rotieren nach 90 Tagen (Reminder folgt)' -InformationAction Continue
    Write-Information '' -InformationAction Continue
}

# ---------------------------------------------------------------------
# Rollback-Modus
# ---------------------------------------------------------------------

function Invoke-DevCityRollback {
    param([string]$SnapshotPath)
    Write-Information "Rollback auf Snapshot: $SnapshotPath" -InformationAction Continue
    if (-not (Test-Path $SnapshotPath)) {
        Write-Error "Snapshot-Datei nicht gefunden: $SnapshotPath"
        return
    }
    # TODO: Restore-DevCitySnapshot -Path $SnapshotPath -Force
}

function Show-DevCitySnapshots {
    Write-Information 'Verfuegbare Snapshots (neueste zuerst):' -InformationAction Continue
    # TODO: $snapshots = Get-DevCitySnapshots
    # TODO: foreach ($s in $snapshots) { Write-Information "  $($s.CreatedAt)  $($_.Path)" -InformationAction Continue }
    Write-Information '  (noch keine Snapshots — Stub)' -InformationAction Continue
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

function Main {
    Show-DevCityBanner

    if ($ListSnapshots) {
        Show-DevCitySnapshots
        return
    }

    if ($Rollback) {
        Invoke-DevCityRollback -SnapshotPath $Rollback
        return
    }

    Import-DevCityModules

    # Phasen sequenziell ausfuehren, bei -OnlyModule nur die angegebenen
    $phases = @{
        1 = 'Invoke-Phase1Snapshot'
        2 = 'Invoke-Phase2Prerequisites'
        3 = 'Invoke-Phase3ToolInstall'
        4 = 'Invoke-Phase4Memory'
        5 = 'Invoke-Phase5Secrets'
        6 = 'Invoke-Phase6McpConfig'
        7 = 'Invoke-Phase7HealthCheck'
        8 = 'Invoke-Phase8Summary'
    }

    foreach ($num in ($phases.Keys | Sort-Object)) {
        if ($OnlyModule -and ([string]$num -notin $OnlyModule)) { continue }
        & $phases[$num]
    }
}

# ---------------------------------------------------------------------
# Ausfuehren
# ---------------------------------------------------------------------

try {
    Main
} catch {
    Write-Error "DevCity-Setup fehlgeschlagen: $_"
    Write-Information '' -InformationAction Continue
    Write-Information 'Rollback verfuegbar via:' -InformationAction Continue
    Write-Information "  .\setup.ps1 -ListSnapshots" -InformationAction Continue
    Write-Information "  .\setup.ps1 -Rollback backups\<snapshot>.zip" -InformationAction Continue
    exit 1
}

Write-Information 'DevCity Setup-Skript beendet.' -InformationAction Continue