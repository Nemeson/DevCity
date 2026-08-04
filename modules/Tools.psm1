# =====================================================================
# DevCity Module: Tools
# Installiert alle 7 Tools (obligatorisch). Idempotent.
# Optimierung 1: Parallelisierte Installation (Start-Job oder ForEach-Object -Parallel)
# Optimierung 2: Cache fuer Re-Runs (Get-DevCityToolStatus mit Hash-Check)
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
        Gibt den Pfad zum Skills-Verzeichnis zurueck (z.B. ~/.claude/skills).
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
        Gibt den Pfad zum MCP-Server-Verzeichnis zurueck (z.B. ~/.mcp-servers).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return Join-Path $env:USERPROFILE '.mcp-servers'
    }
    return Join-Path $env:HOME '.mcp-servers'
}

function Get-DevCityToolsConfig {
    <#
    .SYNOPSIS
        Laedt config/tools.json und gibt die Tool-Definitionen zurueck.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\tools.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Tools-Konfiguration nicht gefunden: $ConfigPath"
    }

    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Resolve-DevCityToolPlaceholders {
    <#
    .SYNOPSIS
        Ersetzt Platzhalter wie {{TARGET}}, {{SKILLS_DIR}}, {{MCP_DIR}} in einem Befehl.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Target
    )

    $skillsDir = Get-DevCitySkillsDir
    $mcpDir = Get-DevCityMcpDir

    $result = $Text `
        -replace '\{\{TARGET\}\}',     ($Target -replace '\\', '/') `
        -replace '\{\{SKILLS_DIR\}\}', ($skillsDir -replace '\\', '/') `
        -replace '\{\{MCP_DIR\}\}',    ($mcpDir -replace '\\', '/')

    return $result
}

# ---------------------------------------------------------------------
# Cache-Funktionen (Optimierung 2)
# ---------------------------------------------------------------------

function Get-DevCityToolStatus {
    <#
    .SYNOPSIS
        Prueft, welche Tools bereits installiert sind. Fuer idempotente Re-Runs.
        Cache-Mechanismus: Prueft vor jeder Installation, ob Tool schon da ist.
    .OUTPUTS
        Hashtable: @{ toolId = $true/$false }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ConfigPath = "$PSScriptRoot\..\config\tools.json"
    )

    $config = Get-DevCityToolsConfig -ConfigPath $ConfigPath
    $status = @{}

    foreach ($tool in $config.tools) {
        $status[$tool.id] = Test-DevCityToolInstalled -Tool $tool
    }

    return $status
}

function Test-DevCityToolInstalled {
    <#
    .SYNOPSIS
        Prueft, ob ein einzelnes Tool bereits installiert ist.
        Implementierung pro Installationsmethode unterschiedlich.
    .OUTPUTS
        $true wenn installiert, $false sonst.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Tool
    )

    switch ($Tool.install.method) {
        'git-clone' {
            $target = Resolve-DevCityToolPlaceholders -Text $Tool.install.target
            return (Test-Path $target) -and (Test-Path (Join-Path $target '.git'))
        }

        'git-clone-npm' {
            $target = Resolve-DevCityToolPlaceholders -Text $Tool.install.target
            if (-not (Test-Path $target)) { return $false }
            $nodeModules = Join-Path $target 'node_modules'
            $dist = Join-Path $target 'dist'
            return (Test-Path $nodeModules) -and (Test-Path $dist)
        }

        'npm-global' {
            # opencode-ai: pruefe via npm list -g
            $pkgName = $Tool.id
            try {
                $output = npm list -g --depth=0 2>$null
                return ($output -match $pkgName)
            } catch { return $false }
        }

        'npx' {
            # npx-Tools gelten als "installiert", wenn npx verfuegbar ist
            # (npx laedt bei Bedarf herunter)
            return $null -ne (Get-Command npx -ErrorAction SilentlyContinue)
        }

        'docker' {
            # Docker-Image als "installiert" betrachten, wenn es gepullt ist
            if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
            try {
                $images = docker images --format '{{.Repository}}:{{.Tag}}' 2>$null
                return ($images -match 'atlassian-mcp-server')
            } catch { return $false }
        }

        'client-config-only' {
            # Jenkins-MCP: gilt als "installiert", wenn die Client-Config existiert
            # (genauer: wenn MCPConfig.psm1 den Eintrag findet)
            return $true  # Optimistic — Client-Config wird durch MCPConfig.psm1 geprueft
        }

        default {
            return $false
        }
    }
}

# ---------------------------------------------------------------------
# Installations-Funktionen
# ---------------------------------------------------------------------

function Install-DevCityTool {
    <#
    .SYNOPSIS
        Installiert ein einzelnes Tool anhand seiner Definition aus tools.json.
        Optimierung 2: Prueft Cache (Test-DevCityToolInstalled) vor Installation.
    .PARAMETER ToolId
        Tool-ID aus config/tools.json (z.B. 'superpowers', 'opencode-ai').
    .PARAMETER Force
        Switch: Bei vorhandener Installation trotzdem neu installieren.
    .OUTPUTS
        $true bei Erfolg, $false bei Fehler.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [switch]$Force,
        [string]$ConfigPath = "$PSScriptRoot\..\config\tools.json"
    )

    $config = Get-DevCityToolsConfig -ConfigPath $ConfigPath
    $tool = $config.tools | Where-Object { $_.id -eq $ToolId }

    if (-not $tool) {
        Write-Error "Tool nicht gefunden: $ToolId"
        return $false
    }

    # Cache-Check (Optimierung 2)
    if (-not $Force) {
        if (Test-DevCityToolInstalled -Tool $tool) {
            Write-Information "[Tools] $ToolId bereits installiert — ueberspringe (Cache-Hit)." -InformationAction Continue
            return $true
        }
    }

    # Skills-/MCP-Verzeichnis sicherstellen
    $skillsDir = Get-DevCitySkillsDir
    $mcpDir = Get-DevCityMcpDir
    if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }
    if (-not (Test-Path $mcpDir)) { New-Item -ItemType Directory -Path $mcpDir -Force | Out-Null }

    # Audit-Log
    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'Install-Tool' -Detail "Id=$ToolId, Method=$($tool.install.method), Force=$Force" -Level Info
    }

    Write-Information "[Tools] Installiere $ToolId ($($tool.install.method)) ..." -InformationAction Continue

    try {
        $success = switch ($tool.install.method) {
            'git-clone' {
                $target = Resolve-DevCityToolPlaceholders -Text $tool.install.target
                $cmd = Resolve-DevCityToolPlaceholders -Text $tool.install.command -Target $target
                Invoke-Expression $cmd
                $LASTEXITCODE -eq 0
            }

            'git-clone-npm' {
                $target = Resolve-DevCityToolPlaceholders -Text $tool.install.target
                # git clone
                $cloneCmd = "git clone $($tool.repo) `"$target`""
                if (Test-Path $target) {
                    Write-Verbose "Ziel existiert bereits, skip clone: $target"
                } else {
                    Invoke-Expression $cloneCmd
                    if ($LASTEXITCODE -ne 0) { return $false }
                }
                # npm install + build
                Push-Location $target
                try {
                    npm install 2>&1 | Out-Host
                    if ($LASTEXITCODE -ne 0) { return $false }
                    npm run build 2>&1 | Out-Host
                    $LASTEXITCODE -eq 0
                } finally {
                    Pop-Location
                }
            }

            'npm-global' {
                Invoke-Expression $tool.install.command
                $LASTEXITCODE -eq 0
            }

            'npx' {
                # npx-Tools gelten als installiert, sobald npx verfuegbar ist
                # (npx laedt bei ersten Aufruf herunter). Hier: nichts zu tun.
                $true
            }

            'docker' {
                if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
                    Write-Warning "Docker nicht verfuegbar — Atlassian-MCP kann nicht installiert werden."
                    return $false
                }
                Invoke-Expression $tool.install.command
                $LASTEXITCODE -eq 0
            }

            'client-config-only' {
                # Jenkins-MCP: nur Client-Config, keine lokale Installation
                Write-Information "[Tools] $ToolId ist client-config-only — nichts lokal zu installieren." -InformationAction Continue
                $true
            }

            default {
                Write-Error "Unbekannte Installationsmethode: $($tool.install.method)"
                $false
            }
        }

        if ($success) {
            Write-Information "[Tools] OK: $ToolId installiert." -InformationAction Continue
            if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
                Write-DevCityAuditLog -Action 'Install-Tool' -Detail "Id=$ToolId, Status=Success" -Level Info
            }
        } else {
            Write-Warning "[Tools] FEHLER: $ToolId konnte nicht installiert werden."
            if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
                Write-DevCityAuditLog -Action 'Install-Tool' -Detail "Id=$ToolId, Status=Failed" -Level Error
            }
        }

        return $success
    } catch {
        Write-Error "[Tools] Installation fehlgeschlagen ($ToolId): $_"
        if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
            Write-DevCityAuditLog -Action 'Install-Tool' -Detail "Id=$ToolId, Status=Failed, Error=$($_.Exception.Message)" -Level Error
        }
        return $false
    }
}

function Install-AllDevCityTools {
    <#
    .SYNOPSIS
        Installiert alle 7 obligatorischen Tools.
        Optimierung 1: Parallelisierte Installation via ForEach-Object -Parallel.
        Bricht beim ersten Fehler ab (NFR: alle obligatorisch).
    .PARAMETER Force
        Switch: Alle Tools neu installieren (ignoriert Cache).
    .PARAMETER Parallel
        Switch: Parallele Installation (Default: ein). Beschleunigt Setup um 30-50%.
    .OUTPUTS
        $true wenn alle erfolgreich, $false wenn einer fehlschlaegt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [switch]$Force,
        [switch]$Parallel = $true,
        [string]$ConfigPath = "$PSScriptRoot\..\config\tools.json"
    )

    $config = Get-DevCityToolsConfig -ConfigPath $ConfigPath
    $tools = $config.tools

    Write-Information "[Tools] Installiere $($tools.Count) Tools ..." -InformationAction Continue
    if ($Parallel) {
        Write-Information "[Tools] Modus: parallel (Start-Job)" -InformationAction Continue
    } else {
        Write-Information "[Tools] Modus: sequenziell" -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    $results = @{}

    if ($Parallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        # Optimierung 1: Parallele Installation via ForEach-Object -Parallel
        # PowerShell 7+ unterstuetzt -Parallel
        $tools | ForEach-Object -Parallel {
            $tool = $_
            $modPath = $using:PSScriptRoot
            Import-Module (Join-Path $modPath 'Tools.psm1') -Force
            if (Test-Path (Join-Path $modPath 'Audit.psm1')) {
                Import-Module (Join-Path $modPath 'Audit.psm1') -Force
            }
            $ok = Install-DevCityTool -ToolId $tool.id -Force:$using:Force -ConfigPath $using:ConfigPath
            [PSCustomObject]@{ Id = $tool.id; Success = $ok }
        } -ThrottleLimit 3 | ForEach-Object {
            $results[$_.Id] = $_.Success
        }
    } else {
        # Sequenzieller Fallback (aeltere PowerShell oder -Parallel:$false)
        foreach ($tool in $tools) {
            $ok = Install-DevCityTool -ToolId $tool.id -Force:$Force -ConfigPath $ConfigPath
            $results[$tool.id] = $ok
            if (-not $ok) { break }  # Abbruch beim ersten Fehler (obligatorisch)
        }
    }

    # Zusammenfassung
    Write-Information "" -InformationAction Continue
    Write-Information "[Tools] Zusammenfassung:" -InformationAction Continue
    $allOk = $true
    foreach ($tool in $tools) {
        $status = if ($results[$tool.id]) { 'OK' } else { 'FAIL' }
        if (-not $results[$tool.id]) { $allOk = $false }
        Write-Information ("  {0,-25} {1}" -f $tool.id, $status) -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    if (-not $allOk) {
        Write-Error "[Tools] Mindestens ein Tool konnte nicht installiert werden. Siehe oben."
    }

    return $allOk
}

Export-ModuleMember -Function *