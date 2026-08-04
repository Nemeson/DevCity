# =====================================================================
# DevCity Module: Secrets
# Hybrid-Credential-Store: Windows Credential Manager (DPAPI) / .env (Unix).
# NFR: Audit-Log jedes Secret-Zugriffs (ohne Secret-Werte).
# Optimierung 7: Rotation-Reminder beim Setup-Start
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------

if (-not (Test-Path Variable:DEVCITY_SECRET_PREFIX)) {
    New-Variable -Name DEVCITY_SECRET_PREFIX -Value 'DevCity:' -Option Constant -ErrorAction SilentlyContinue
}

if (-not (Test-Path Variable:DEVCITY_ENV_FILE)) {
    New-Variable -Name DEVCITY_ENV_FILE -Value (Join-Path $PSScriptRoot '..\.env') -Option Constant -ErrorAction SilentlyContinue
}

if (-not (Test-Path Variable:DEVCITY_SECRET_META_FILE)) {
    New-Variable -Name DEVCITY_SECRET_META_FILE -Value (Join-Path $PSScriptRoot '..\config\secret-metadata.json') -Option Constant -ErrorAction SilentlyContinue
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

function Get-DevCitySecretMeta {
    <#
    .SYNOPSIS
        Laedt die Secret-Metadaten (Creation-Dates fuer Rotation-Reminder).
    .OUTPUTS
        PSCustomObject oder $null
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (-not (Test-Path $DEVCITY_SECRET_META_FILE)) { return $null }
    try {
        return Get-Content $DEVCITY_SECRET_META_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { return $null }
}

function Set-DevCitySecretMeta {
    <#
    .SYNOPSIS
        Speichert die Secret-Metadaten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Meta
    )

    $dir = Split-Path $DEVCITY_SECRET_META_FILE -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $json = $Meta | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($DEVCITY_SECRET_META_FILE, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------------
# Windows Credential Manager (DPAPI)
# ---------------------------------------------------------------------

function Get-DevCitySecretWindows {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    $target = "$DEVCITY_SECRET_PREFIX$Name"

    # Versuche via cmdkey (eingebaut in Windows)
    try {
        $output = cmdkey /list:$target 2>&1
        if ($output -match 'Target:') {
            # Credential existiert — versuche es via Credential-Manager-Cmdlet
            # Fallback: PowerShell-eigene DPAPI-Verschluesselung in lokaler Datei
            $dpapiFile = Join-Path $PSScriptRoot "..\config\.secrets\$Name.xml"
            if (Test-Path $dpapiFile) {
                $cred = Import-Clixml -Path $dpapiFile
                return [System.Net.NetworkCredential]::new('', $cred.Password).Password
            }
        }
    } catch { }

    # Fallback: DPAPI-gesicherte Datei
    $dpapiFile = Join-Path $PSScriptRoot "..\config\.secrets\$Name.xml"
    if (Test-Path $dpapiFile) {
        try {
            $cred = Import-Clixml -Path $dpapiFile
            return [System.Net.NetworkCredential]::new('', $cred.Password).Password
        } catch { }
    }

    return $null
}

function Set-DevCitySecretWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $target = "$DEVCITY_SECRET_PREFIX$Name"

    # DPAPI-gesicherte Datei (PSCredential)
    $secretsDir = Join-Path $PSScriptRoot '..\config\.secrets'
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
        # Verstecke Attribute auf Windows
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            (Get-Item $secretsDir).Attributes = 'Hidden'
        }
    }

    $dpapiFile = Join-Path $secretsDir "$Name.xml"
    $secureStr = ConvertTo-SecureString $Value -AsPlainText -Force
    $cred = [PSCustomObject]@{
        Target  = $target
        Created = (Get-Date).ToString('o')
    }
    # PSCredential braucht Username/Password
    $psCred = [System.Management.Automation.PSCredential]::new('DevCity', $secureStr)
    $psCred | Export-Clixml -Path $dpapiFile -Force
}

function Remove-DevCitySecretWindows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $dpapiFile = Join-Path $PSScriptRoot "..\config\.secrets\$Name.xml"
    if (Test-Path $dpapiFile) { Remove-Item $dpapiFile -Force }
}

# ---------------------------------------------------------------------
# Unix .env-Datei
# ---------------------------------------------------------------------

function Get-DevCitySecretUnix {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-Path $DEVCITY_ENV_FILE)) { return $null }

    $lines = Get-Content $DEVCITY_ENV_FILE -Encoding UTF8
    foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Name))=(.+)$") {
            return $matches[1].Trim('"').Trim("'")
        }
    }
    return $null
}

function Set-DevCitySecretUnix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    # .env-Datei anlegen oder lesen
    $envDir = Split-Path $DEVCITY_ENV_FILE -Parent
    if (-not (Test-Path $envDir)) { New-Item -ItemType Directory -Path $envDir -Force | Out-Null }

    $lines = @()
    if (Test-Path $DEVCITY_ENV_FILE) {
        $lines = Get-Content $DEVCITY_ENV_FILE -Encoding UTF8
    }

    # Bestehenden Eintrag ersetzen oder neuen anhaengen
    $found = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Name))=") {
            $newLines += "$Name=`"$Value`""
            $found = $true
        } else {
            $newLines += $line
        }
    }
    if (-not $found) { $newLines += "$Name=`"$Value`"" }

    [System.IO.File]::WriteAllText($DEVCITY_ENV_FILE, ($newLines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))

    # chmod 600 auf Unix
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
        chmod 600 $DEVCITY_ENV_FILE 2>$null
    }
}

function Remove-DevCitySecretUnix {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-Path $DEVCITY_ENV_FILE)) { return }

    $lines = Get-Content $DEVCITY_ENV_FILE -Encoding UTF8
    $newLines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($Name))=" }
    [System.IO.File]::WriteAllText($DEVCITY_ENV_FILE, ($newLines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------------
# Hauptfunktionen
# ---------------------------------------------------------------------

function Get-DevCitySecret {
    <#
    .SYNOPSIS
        Liest ein Secret aus dem Credential-Store (Windows DPAPI) oder .env (Unix).
    .PARAMETER Name
        Secret-Name (z.B. 'atlassian_token', 'jenkins_url').
    .OUTPUTS
        String (oder $null wenn nicht gefunden).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $platform = Get-DevCityPlatform
    $value = if ($platform -eq 'windows') {
        Get-DevCitySecretWindows -Name $Name
    } else {
        Get-DevCitySecretUnix -Name $Name
    }

    # Audit-Log (ohne Wert!)
    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        $status = if ($value) { 'Found' } else { 'NotFound' }
        Write-DevCityAuditLog -Action 'Get-Secret' -Detail "Name=$Name, Status=$status" -Level Info
    }

    return $value
}

function Set-DevCitySecret {
    <#
    .SYNOPSIS
        Speichert ein Secret im Credential-Store (Windows DPAPI) oder .env (Unix).
    .PARAMETER Name
        Secret-Name (z.B. 'atlassian_token').
    .PARAMETER Value
        Secret-Wert. Wird NIE geloggt.
    .PARAMETER RotationDays
        Optional: Anzahl Tage bis zur Rotation. Default: 90 (NFR 2C).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [int]$RotationDays = 90
    )

    $platform = Get-DevCityPlatform
    if ($platform -eq 'windows') {
        Set-DevCitySecretWindows -Name $Name -Value $Value
    } else {
        Set-DevCitySecretUnix -Name $Name -Value $Value
    }

    # Metadaten aktualisieren (fuer Rotation-Reminder)
    $meta = Get-DevCitySecretMeta
    if (-not $meta) {
        $meta = [PSCustomObject]@{ secrets = [PSCustomObject]@{} }
    }
    if (-not $meta.secrets) {
        $meta | Add-Member -NotePropertyName secrets -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $meta.secrets | Add-Member -NotePropertyName $Name -NotePropertyValue ([PSCustomObject]@{
        createdAt      = (Get-Date).ToString('o')
        rotationDays   = $RotationDays
        lastChecked    = (Get-Date).ToString('o')
    }) -Force
    Set-DevCitySecretMeta -Meta $meta

    # Audit-Log (ohne Wert!)
    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'Set-Secret' -Detail "Name=$Name, Platform=$platform, RotationDays=$RotationDays" -Level Info
    }
}

function Remove-DevCitySecret {
    <#
    .SYNOPSIS
        Loescht ein Secret aus dem Credential-Store.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force
    )

    if (-not $Force) {
        $response = Read-Host "Wirklich Secret '$Name' loeschen? (j/N)"
        if ($response -notmatch '^[jJyY]') {
            Write-Information "[Secrets] Abgebrochen." -InformationAction Continue
            return
        }
    }

    $platform = Get-DevCityPlatform
    if ($platform -eq 'windows') {
        Remove-DevCitySecretWindows -Name $Name
    } else {
        Remove-DevCitySecretUnix -Name $Name
    }

    # Metadaten entfernen
    $meta = Get-DevCitySecretMeta
    if ($meta -and $meta.secrets) {
        $meta.secrets.PSObject.Properties.Remove($Name)
        Set-DevCitySecretMeta -Meta $meta
    }

    if (Get-Command Write-DevCityAuditLog -ErrorAction SilentlyContinue) {
        Write-DevCityAuditLog -Action 'Remove-Secret' -Detail "Name=$Name" -Level Warning
    }
}

function Test-DevCitySecretRotation {
    <#
    .SYNOPSIS
        Optimierung 7: Prueft alle Secrets auf Ablauf der Rotationsfrist (Default: 90 Tage).
        Gibt eine Liste von Secrets zurueck, die rotiert werden sollten.
    .OUTPUTS
        Array von PSCustomObject (Name, CreatedAt, AgeDays, NeedsRotation)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [int]$RotationDays = 90
    )

    $meta = Get-DevCitySecretMeta
    if (-not $meta -or -not $meta.secrets) { return @() }

    $results = @()
    $now = Get-Date

    foreach ($prop in $meta.secrets.PSObject.Properties) {
        $name = $prop.Name
        $info = $prop.Value
        $createdAt = [datetime]$info.createdAt
        $ageDays = ($now - $createdAt).Days
        $needsRotation = $ageDays -ge $RotationDays

        $results += [PSCustomObject]@{
            Name           = $name
            CreatedAt      = $info.createdAt
            AgeDays        = $ageDays
            RotationDays   = $info.rotationDays
            NeedsRotation  = $needsRotation
        }
    }

    return $results
}

function Invoke-DevCitySecretPrompt {
    <#
    .SYNOPSIS
        Interaktiver Prompt fuer ein Secret (Read-Host -AsSecureString).
        Wird direkt gespeichert, Wert wird nie im Klartext ausgegeben.
    .PARAMETER Name
        Secret-Name.
    .PARAMETER Prompt
        Anzeige-Text fuer den Prompt.
    .PARAMETER NonInteractive
        Switch: Ueberspringt den Prompt (keine Eingabe, kein Speichern).
    .OUTPUTS
        $true wenn Secret gespeichert wurde, $false bei Abbruch.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$NonInteractive
    )

    if ($NonInteractive) {
        Write-Information "[Secrets] NonInteractive: Secret '$Name' nicht erfasst ( Platzhalter bleibt bestehen)." -InformationAction Continue
        return $false
    }

    Write-Information "" -InformationAction Continue
    Write-Information $Prompt -InformationAction Continue
    $secureVal = Read-Host -AsSecureString "  Wert"

    if ($null -eq $secureVal -or $secureVal.Length -eq 0) {
        Write-Warning "[Secrets] Leerer Wert — Secret '$Name' nicht gespeichert."
        return $false
    }

    # SecureString zu PlainString (intern, wird nicht ausgegeben)
    $plainVal = [System.Net.NetworkCredential]::new('', $secureVal).Password
    Set-DevCitySecret -Name $Name -Value $plainVal
    # plainVal aus Memory werfen
    $plainVal = $null

    Write-Information "[Secrets] OK: Secret '$Name' gespeichert." -InformationAction Continue
    return $true
}

Export-ModuleMember -Function *