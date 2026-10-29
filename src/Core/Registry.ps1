# ============================================================
#  Velocity · Acesso ao registro (sempre na visão 64 bits)
#  Caminhos no formato 'HKLM\SOFTWARE\...' ou 'HKCU\Software\...'
# ============================================================

function Get-VRegKey {
    param([string]$Path, [switch]$Writable, [switch]$Create)
    $hive, $sub = $Path -split '\\', 2
    $root = switch ($hive) {
        'HKLM'  { [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCU'  { [Microsoft.Win32.RegistryHive]::CurrentUser }
        default { throw "Hive não suportada: $hive" }
    }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($root, [Microsoft.Win32.RegistryView]::Registry64)
    if ($Create) { return $base.CreateSubKey($sub) }
    return $base.OpenSubKey($sub, [bool]$Writable)
}

function Test-VRegKey([string]$Path) {
    $key = Get-VRegKey $Path
    if ($key) { $key.Close(); return $true }
    return $false
}

function Get-VRegValue([string]$Path, [string]$Name) {
    $key = Get-VRegKey $Path
    if (-not $key) { return @{ Exists = $false; Kind = $null; Value = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) { return @{ Exists = $false; Kind = $null; Value = $null } }
        return @{
            Exists = $true
            Kind   = $key.GetValueKind($Name).ToString()
            Value  = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    } finally { $key.Close() }
}

function ConvertTo-VRegData($Value, [string]$Kind) {
    switch ($Kind) {
        'DWord' {
            $n = [int64]$Value
            if ($n -gt [int32]::MaxValue) { $n -= 4294967296 }
            return [int32]$n
        }
        'QWord' { return [int64]$Value }
        'Binary' {
            if ($Value -is [string]) {
                return , [byte[]]@(($Value -split '[\s,-]+' | Where-Object { $_ }) | ForEach-Object { [Convert]::ToByte($_, 16) })
            }
            return , [byte[]]@($Value)
        }
        'MultiString' { return , [string[]]@($Value) }
        default { return [string]$Value }
    }
}

# Representação textual estável, usada para comparar valor atual x desejado
function ConvertTo-VComparable($Value, [string]$Kind) {
    if ($null -eq $Value) { return '' }
    switch ($Kind) {
        'Binary'      { $bytes = ConvertTo-VRegData $Value 'Binary'; return [BitConverter]::ToString($bytes) }
        'DWord'       { return [string](ConvertTo-VRegData $Value 'DWord') }
        'QWord'       { return [string][int64]$Value }
        'MultiString' { return (@($Value) -join "`n") }
        default       { return [string]$Value }
    }
}

function Set-VRegValue([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord') {
    $key = Get-VRegKey $Path -Create
    try { $key.SetValue($Name, (ConvertTo-VRegData $Value $Kind), [Microsoft.Win32.RegistryValueKind]$Kind) }
    finally { $key.Close() }
}

function Remove-VRegValue([string]$Path, [string]$Name) {
    $key = Get-VRegKey $Path -Writable
    if ($key) {
        try { $key.DeleteValue($Name, $false) } finally { $key.Close() }
    }
}
