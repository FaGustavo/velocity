# ============================================================
#  Velocity · Preferências persistentes
#  Arquivo: %ProgramData%\Velocity\settings.json
# ============================================================

function Get-VSettings {
    $file = Join-Path $global:VelocityDataDir 'settings.json'
    $data = @{}
    if (Test-Path $file) {
        try { foreach ($p in (ConvertFrom-Json ([IO.File]::ReadAllText($file))).PSObject.Properties) { $data[$p.Name] = $p.Value } } catch { }
    }
    return $data
}

function Set-VSetting([string]$Name, $Value) {
    $data = Get-VSettings
    $data[$Name] = $Value
    if (-not (Test-Path $global:VelocityDataDir)) { [void](New-Item -ItemType Directory -Force -Path $global:VelocityDataDir) }
    [IO.File]::WriteAllText((Join-Path $global:VelocityDataDir 'settings.json'), (ConvertTo-Json -InputObject $data), (New-Object Text.UTF8Encoding $false))
}
