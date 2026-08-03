# =====================================================================
# DevCity Module: MCPConfig
# Schreibt MCP-Server-Einträge in mehrere Client-Configs (Multi-Select).
# OpenCode (Default), Copilot CLI, Claude Desktop, Codex, Gemini, Antigravity.
# Idempotent: User-Einträge werden nicht überschrieben.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Hauptfunktionen (Stubs)
# ---------------------------------------------------------------------

function Get-DevCityMcpClients {
    <#
    .SYNOPSIS
        Liest config/clients.json und gibt die Liste der verfügbaren Clients zurück.
    .OUTPUTS
        Array von PSCustomObject (Id, Name, ConfigPath, Default)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\clients.json"
    )

    # TODO: Implement
    return @()
}

function Select-DevCityMcpClients {
    <#
    .SYNOPSIS
        Interaktiver Multi-Select-Prompt für die Client-Auswahl.
        Default: OpenCode + Copilot CLI.
    .PARAMETER NonInteractive
        Switch: Gibt die Defaults zurück ohne Prompt.
    .OUTPUTS
        Array von gewählten Client-IDs (z.B. @('opencode', 'copilot-cli'))
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [switch]$NonInteractive
    )

    # TODO: Implement
    # 1. Get-DevCityMcpClients aufrufen
    # 2. Wenn -NonInteractive: Default-IDs zurückgeben
    # 3. Sonst: Multi-Select-Prompt (via $Host.UI.PromptForChoice oder .NET-Console)
    return @('opencode', 'copilot-cli')
}

function Write-DevCityMcpConfig {
    <#
    .SYNOPSIS
        Schreibt die MCP-Server-Konfiguration in die gewählten Client-Configs.
        Idempotent: bestehende User-Einträge werden nicht überschrieben.
    .PARAMETER ClientIds
        Array von Client-IDs, in die geschrieben werden soll.
    .PARAMETER ToolIds
        Array von Tool-IDs, deren MCP-Server eingetragen werden sollen.
        Default: alle Tools, die einen mcp-Block in tools.json haben.
    .PARAMETER Force
        Switch: Überschreibt bestehende MCP-Server-Einträge mit gleicher ID.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][array]$ClientIds,
        [array]$ToolIds,
        [switch]$Force
    )

    # TODO: Implement
    # 1. tools.json laden, Tools mit mcp-Block filtern
    # 2. pro ClientId:
    #    a. Config-Pfad plattformabhängig ermitteln
    #    b. Bestehende Config lesen (oder leeres Objekt)
    #    c. Backup via Snapshot-Modul
    #    d. mcpServers-Block mergen (deep-merge, User-Einträge erhalten)
    #    e. Config schreiben (UTF-8, BOM-less)
    # 3. Audit-Log pro Client
    # 4. Konfliktwarnung bei -Force und bestehendem Eintrag
    return
}

function Remove-DevCityMcpConfig {
    <#
    .SYNOPSIS
        Entfernt DevCity-MCP-Server-Einträge aus Client-Configs.
        Nützlich für Clean-Uninstall.
    .PARAMETER ClientIds
        Array von Client-IDs, aus denen entfernt werden soll.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][array]$ClientIds
    )

    # TODO: Implement
    return
}

Export-ModuleMember -Function *