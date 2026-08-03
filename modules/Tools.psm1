# =====================================================================
# DevCity Module: Tools
# Installiert alle 7 Tools (obligatorisch). Idempotent.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------

function Get-DevCitySkillsDir {
    <#
    .SYNOPSIS
        Gibt den Pfad zum Skills-Verzeichnis zurück (z.B. ~/.claude/skills).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return Join-Path $env:USERPROFILE '.claude\skills'
    }
    return Join-Path $env:HOME '.claude/skills'
}

function Get-DevCityMcpDir {
    <#
    .SYNOPSIS
        Gibt den Pfad zum MCP-Server-Verzeichnis zurück (z.B. ~/.mcp-servers).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return Join-Path $env:USERPROFILE '.mcp-servers'
    }
    return Join-Path $env:HOME '.mcp-servers'
}

# ---------------------------------------------------------------------
# Hauptfunktionen (Stubs)
# ---------------------------------------------------------------------

function Install-DevCityTool {
    <#
    .SYNOPSIS
        Installiert ein einzelnes Tool anhand seiner Definition aus tools.json.
    .PARAMETER ToolId
        Tool-ID aus config/tools.json (z.B. 'superpowers', 'opencode-ai').
    .PARAMETER Force
        Switch: Bei vorhandener Installation trotzdem neu installieren.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [switch]$Force
    )

    # TODO: Implement
    # 1. Tool-Definition aus config/tools.json laden
    # 2. Prerequisites prüfen (via Prerequisites-Modul)
    # 3. Install-Methode dispatchen (git-clone, npm-global, npx, docker, maven, client-config-only)
    # 4. Idempotenz: prüfen, ob Tool schon installiert ist; bei -Force neu
    # 5. Audit-Log
    # 6. Rückgabe: $true bei Erfolg, $false bei Fehler
    return $false
}

function Install-AllDevCityTools {
    <#
    .SYNOPSIS
        Installiert alle 7 obligatorischen Tools nacheinander.
        Bricht beim ersten Fehler ab (NFR: alle obligatorisch).
    .PARAMETER Force
        Switch: Alle Tools neu installieren.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force
    )

    # TODO: Implement
    # 1. tools.json laden, alle Einträge durchgehen
    # 2. pro Tool: Install-DevCityTool aufrufen
    # 3. bei Abbruch durch User: klarer Fehler + Abbruch
    # 4. Audit-Log pro Tool
    # 5. Zusammenfassung am Ende
    return
}

function Get-DevCityToolStatus {
    <#
    .SYNOPSIS
        Prüft, welche Tools bereits installiert sind. Für idempotente Re-Runs.
    .OUTPUTS
        Hashtable: @{ toolId = $true/$false }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # TODO: Implement
    return @{}
}

Export-ModuleMember -Function *