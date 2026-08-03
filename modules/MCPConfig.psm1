# =====================================================================
# DevCity Module: MCPConfig
# Schreibt MCP-Server-Eintraege in mehrere Client-Configs (Multi-Select).
# OpenCode (Default), Copilot CLI, Claude Desktop, Codex, Gemini, Antigravity.
# Idempotent: User-Eintraege werden nicht ueberschrieben (Deep-Merge).
# Optimierung 4: Deep-Merge mit Konfliktwarnung
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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
    <#
    .SYNOPSIS
        Loest einen plattformabhaengigen Pfad aus clients.json auf.
        Ersetzt %APPDATA%, %USERPROFILE%, ~, etc.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$PathTemplate
    )

    $platform = Get-DevCityPlatform
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { '~' }

    $result = $PathTemplate
    if ($env:APPDATA) { $result = $result -replace '%APPDATA%', $env:APPDATA }
    if ($env:USERPROFILE) { $result = $result -replace '%USERPROFILE%', $env:USERPROFILE }
    $result = $result -replace '~', $home
    $result = $result -replace '\$HOME', $home

    # Windows: Forward-Slashes in Backslashes umwandeln
    if ($platform -eq 'windows') {
        $result = $result -replace '/', '\'
    }

    return $result
}

function Get-DevCityMcpClients {
    <#
    .SYNOPSIS
        Liest config/clients.json und gibt die Liste der verfuegbaren Clients zurueck.
    .OUTPUTS
        Array von PSCustomObject (Id, Name, ConfigPath, Default)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\clients.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Clients-Konfiguration nicht gefunden: $ConfigPath"
        return @()
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    return $config.clients
}

# ---------------------------------------------------------------------
# Merge-Logik (Optimierung 4: Deep-Merge mit Konfliktwarnung)
# ---------------------------------------------------------------------

function Merge-DevCityMcpServers {
    <#
    .SYNOPSIS
        Merged neue MCP-Server in eine bestehende mcpServers-Hashtable.
        Bestehende User-Eintraege werden NICHT ueberschrieben (ausser -Force).
        Konflikte werden als Warnung gemeldet.
    .PARAMETER Existing
        Bestehende mcpServers-Hashtable aus Client-Config.
    .PARAMETER NewServers
        Neue MCP-Server-Hashtable (DevCity-Eintraege).
    .PARAMETER Force
        Switch: Bestehende Eintraege gleichen Namens ueberschreiben.
    .OUTPUTS
        PSCustomObject: MergedServers (Hashtable), Conflicts (Array), Added (Array)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [hashtable]$Existing,
        [hashtable]$NewServers,
        [switch]$Force
    )

    if (-not $Existing) { $Existing = @{} }
    $merged = @{}
    $conflicts = @()
    $added = @()

    # Bestehende Eintraege uebernehmen
    foreach ($key in $Existing.Keys) {
        $merged[$key] = $Existing[$key]
    }

    # Neue Eintraege mergen
    foreach ($key in $NewServers.Keys) {
        if ($merged.ContainsKey($key)) {
            if ($Force) {
                $merged[$key] = $NewServers[$key]
                $conflicts += [PSCustomObject]@{ Server = $key; Action = 'Overwritten' }
            } else {
                $conflicts += [PSCustomObject]@{ Server = $key; Action = 'Preserved (use -Force to overwrite)' }
            }
        } else {
            $merged[$key] = $NewServers[$key]
            $added += $key
        }
    }

    return [PSCustomObject]@{
        MergedServers = $merged
        Conflicts     = $conflicts
        Added         = $added
    }
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function Select-DevCityMcpClients {
    <#
    .SYNOPSIS
        Interaktiver Multi-Select-Prompt fuer die Client-Auswahl.
        Default: OpenCode + Copilot CLI.
    .PARAMETER NonInteractive
        Switch: Gibt die Defaults zurueck ohne Prompt.
    .OUTPUTS
        Array von gewaehlten Client-IDs (z.B. @('opencode', 'copilot-cli'))
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [switch]$NonInteractive
    )

    $clients = Get-DevCityMcpClients

    if ($clients.Count -eq 0) {
        Write-Warning "Keine MCP-Clients konfiguriert."
        return @()
    }

    if ($NonInteractive) {
        return ($clients | Where-Object { $_.default } | Select-Object -ExpandProperty id)
    }

    Write-Information "" -InformationAction Continue
    Write-Information "Verfuegbare MCP-Clients:" -InformationAction Continue
    Write-Information "" -InformationAction Continue

    $i = 0
    foreach ($c in $clients) {
        $mark = if ($c.default) { '[x]' } else { '[ ]' }
        $num = '{0,2}.' -f ($i + 1)
        Write-Information "  $mark $num $($c.Name) — $($c.description)" -InformationAction Continue
        $i++
    }

    Write-Information "" -InformationAction Continue
    Write-Information "Welche Clients sollen MCP-Server bekommen?" -InformationAction Continue
    Write-Information "  - Kommaseparierte Nummern (z.B. '1,2,4')" -InformationAction Continue
    Write-Information "  - 'all' = alle" -InformationAction Continue
    Write-Information "  - 'default' = nur Defaults (Empfehlung)" -InformationAction Continue
    $response = Read-Host "Auswahl (Default: 'default')"

    if (-not $response -or $response -eq 'default') {
        return ($clients | Where-Object { $_.default } | Select-Object -ExpandProperty id)
    }

    if ($response -eq 'all') {
        return ($clients | Select-Object -ExpandProperty id)
    }

    # Parse nummerische Auswahl
    $selected = @()
    $nums = $response -split ',' | ForEach-Object { $_.Trim() }
    foreach ($n in $nums) {
        $idx = [int]$n - 1
        if ($idx -ge 0 -and $idx -lt $clients.Count) {
            $selected += $clients[$idx].id
        } else {
            Write-Warning "Ungueltige Nummer: $n — ignoriert."
        }
    }

    if ($selected.Count -eq 0) {
        Write-Warning "Keine gueltigen Clients gewaehlt — verwende Defaults."
        return ($clients | Where-Object { $_.default } | Select-Object -ExpandProperty id)
    }

    return $selected
}

function Write-DevCityMcpConfig {
    <#
    .SYNOPSIS
        Schreibt die MCP-Server-Konfiguration in die gewaehlten Client-Configs.
        Idempotent: bestehende User-Einträge werden nicht ueberschrieben.
    .PARAMETER ClientIds
        Array von Client-IDs, in die geschrieben werden soll.
    .PARAMETER ToolIds
        Array von Tool-IDs, deren MCP-Server eingetragen werden sollen.
        Default: alle Tools, die einen mcp-Block in tools.json haben.
    .PARAMETER Force
        Switch: Ueberschreibt bestehende MCP-Server-Eintraege mit gleicher ID.
    .PARAMETER SecretsResolver
        Optional: ScriptBlock, der {{secret:name}}-Platzhalter aufloest.
        Default: gibt Platzhalter zurueck (fuer Dry-Run).
    .OUTPUTS
        Array von PSCustomObject: ClientId, Path, Added, Conflicts, Error
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)][array]$ClientIds,
        [array]$ToolIds,
        [switch]$Force,
        [scriptblock]$SecretsResolver,
        [string]$ToolsConfigPath = "$PSScriptRoot\..\config\tools.json",
        [string]$ClientsConfigPath = "$PSScriptRoot\..\config\clients.json"
    )

    # Tools laden + filtern (nur Tools mit mcp-Block)
    $toolsConfig = Get-Content $ToolsConfigPath -Raw | ConvertFrom-Json
    $tools = $toolsConfig.tools | Where-Object { $_.mcp -ne $null }
    if ($ToolIds -and $ToolIds.Count -gt 0) {
        $tools = $tools | Where-Object { $_.id -in $ToolIds }
    }

    if ($tools.Count -eq 0) {
        Write-Warning "Keine Tools mit MCP-Server-Definition gefunden."
        return @()
    }

    # Neue MCP-Server-Hashtable bauen — Format pro Client transformieren
    $newServers = @{}
    foreach ($tool in $tools) {
        $serverName = $tool.mcp.serverName
        $serverDef = [ordered]@{
            type    = $tool.mcp.transport
            command = $tool.mcp.command
            args    = $tool.mcp.args
        }
        if ($tool.mcp.env -and $tool.mcp.env.PSObject.Properties.Count -gt 0) {
            $envResolved = @{}
            foreach ($prop in $tool.mcp.env.PSObject.Properties) {
                $val = $prop.Value
                # Platzhalter aufloesen
                if ($val -match '\{\{secret:(.+?)\}\}') {
                    if ($SecretsResolver) {
                        $val = & $SecretsResolver $matches[1]
                    }
                    # sonst: Platzhalter stehen lassen (Dry-Run)
                }
                if ($val -match '\{\{memory_store_path\}\}') {
                    $memPath = Join-Path $PSScriptRoot '..\memory'
                    $val = $val -replace '\{\{memory_store_path\}\}', ($memPath -replace '\\', '/')
                }
                if ($val -match '\{\{MCP_DIR\}\}') {
                    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                        $mcpDir = Join-Path $env:USERPROFILE '.mcp-servers' -replace '\\', '/'
                    } else {
                        $mcpDir = Join-Path $env:HOME '.mcp-servers'
                    }
                    $val = $val -replace '\{\{MCP_DIR\}\}', $mcpDir
                }
                $envResolved[$prop.Name] = $val
            }
            $serverDef.env = $envResolved
        }
        $newServers[$serverName] = $serverDef
    }

    # Clients laden
    $clientsConfig = Get-Content $ClientsConfigPath -Raw | ConvertFrom-Json
    $allClients = $clientsConfig.clients

    $results = @()

    foreach ($clientId in $ClientIds) {
        $client = $allClients | Where-Object { $_.id -eq $clientId }
        if (-not $client) {
            $results += [PSCustomObject]@{
                ClientId  = $clientId
                Path      = $null
                Added     = @()
                Conflicts = @()
                Error     = "Client nicht gefunden: $clientId"
            }
            continue
        }

        # Config-Pfad plattformabhaengig ermitteln
        $platform = Get-DevCityPlatform
        $pathTemplate = $client.configPath.$platform
        if (-not $pathTemplate) {
            $results += [PSCustomObject]@{
                ClientId  = $clientId
                Path      = $null
                Added     = @()
                Conflicts = @()
                Error     = "Kein Config-Pfad fuer Plattform '$platform' definiert"
            }
            continue
        }

        $configPath = Resolve-DevClientPath -PathTemplate $pathTemplate
        $configDir = Split-Path $configPath -Parent

        # Bestehende Config laden
        $existing = @{}
        $existingConfig = $null
        if (Test-Path $configPath) {
            try {
                $raw = Get-Content $configPath -Raw -Encoding UTF8
                if ($raw) { $existingConfig = $raw | ConvertFrom-Json -AsHashtable }
            } catch {
                Write-Warning "Bestehende Config konnte nicht geladen werden: $configPath — $_"
            }
            if ($existingConfig -and $existingConfig.ContainsKey($client.mcpServersKey)) {
                $existing = $existingConfig[$client.mcpServersKey]
            }
        }

        # Server-Definitionen fuer dieses Client-Format transformieren
        $clientFormat = if ($client.format) { $client.format } else { 'default' }
        $transformedServers = @{}
        foreach ($key in $newServers.Keys) {
            $srv = $newServers[$key]
            if ($clientFormat -eq 'opencode') {
                # OpenCode-Format: command als Array, type="local", enabled=true, env statt environment
                $cmdArray = @($srv.command) + @($srv.args | Where-Object { $_ })
                $transformed = [ordered]@{
                    type    = 'local'
                    command = $cmdArray
                    enabled = $true
                }
                if ($srv.env) { $transformed.env = $srv.env }
                $transformedServers[$key] = $transformed
            } else {
                # Default-Format (Claude Desktop, Copilot CLI etc.): type="stdio", command+args getrennt
                $transformed = [ordered]@{
                    type    = 'stdio'
                    command = $srv.command
                    args    = $srv.args
                }
                if ($srv.env) { $transformed.env = $srv.env }
                $transformedServers[$key] = $transformed
            }
        }

        # Merge
        $mergeResult = Merge-DevCityMcpServers -Existing $existing -NewServers $transformedServers -Force:$Force

        # Konfliktwarnungen ausgeben
        foreach ($c in $mergeResult.Conflicts) {
            Write-Warning "[MCPConfig] Konflikt ($clientId): $($c.Server) — $($c.Action)"
        }

        # Backup vor Write (NFR 3C + clients.json backupBeforeWrite)
        if ($client.backupBeforeWrite -and (Test-Path $configPath)) {
            $backupPath = "$configPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $configPath -Destination $backupPath -Force
            Write-Verbose "[MCPConfig] Backup: $backupPath"
        }

        # Config-Verzeichnis sicherstellen
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        # Neue Config zusammenbauen
        $newConfig = if ($existingConfig) { $existingConfig } else { @{} }
        $newConfig[$client.mcpServersKey] = $mergeResult.MergedServers

        # Schreiben (UTF-8 ohne BOM)
        $jsonOut = $newConfig | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($configPath, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))

        # Audit-Log
        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            $meta = @{ Client = $clientId; Added = ($mergeResult.Added -join ','); Conflicts = $mergeResult.Conflicts.Count }
            Write-DevCityAuditLog -Action 'Write-MCPConfig' -Detail "Client=$clientId, Path=$configPath" -Metadata $meta -Level Info
        }

        $results += [PSCustomObject]@{
            ClientId  = $clientId
            Path      = $configPath
            Added     = $mergeResult.Added
            Conflicts = $mergeResult.Conflicts
            Error     = $null
        }
    }

    return $results
}

function Remove-DevCityMcpConfig {
    <#
    .SYNOPSIS
        Entfernt DevCity-MCP-Server-Eintraege aus Client-Configs.
        Nuetzlich fuer Clean-Uninstall.
    .PARAMETER ClientIds
        Array von Client-IDs, aus denen entfernt werden soll.
    .PARAMETER ToolIds
        Array von Tool-IDs, deren MCP-Server entfernt werden sollen.
        Default: alle DevCity-Tools mit mcp-Block.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][array]$ClientIds,
        [array]$ToolIds,
        [string]$ToolsConfigPath = "$PSScriptRoot\..\config\tools.json",
        [string]$ClientsConfigPath = "$PSScriptRoot\..\config\clients.json"
    )

    $toolsConfig = Get-Content $ToolsConfigPath -Raw | ConvertFrom-Json
    $tools = $toolsConfig.tools | Where-Object { $_.mcp -ne $null }
    if ($ToolIds -and $ToolIds.Count -gt 0) {
        $tools = $tools | Where-Object { $_.id -in $ToolIds }
    }

    $serverNames = $tools | ForEach-Object { $_.mcp.serverName }
    $clientsConfig = Get-Content $ClientsConfigPath -Raw | ConvertFrom-Json
    $allClients = $clientsConfig.clients

    foreach ($clientId in $ClientIds) {
        $client = $allClients | Where-Object { $_.id -eq $clientId }
        if (-not $client) { continue }

        $platform = Get-DevCityPlatform
        $pathTemplate = $client.configPath.$platform
        if (-not $pathTemplate) { continue }

        $configPath = Resolve-DevClientPath -PathTemplate $pathTemplate

        if (-not (Test-Path $configPath)) { continue }

        $existingConfig = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        if (-not $existingConfig -or -not $existingConfig.ContainsKey($client.mcpServersKey)) { continue }

        $servers = $existingConfig[$client.mcpServersKey]
        foreach ($name in $serverNames) {
            if ($servers.ContainsKey($name)) {
                $servers.Remove($name)
                Write-Verbose "[MCPConfig] Entfernt: $name aus $clientId"
            }
        }
        $existingConfig[$client.mcpServersKey] = $servers

        $jsonOut = $existingConfig | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($configPath, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))

        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Remove-MCPConfig' -Detail "Client=$clientId" -Level Info
        }
    }
}

Export-ModuleMember -Function *