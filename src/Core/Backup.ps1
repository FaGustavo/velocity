# ============================================================
#  Velocity · Backup persistente dos valores originais
#  Arquivo: %ProgramData%\Velocity\backup.json
#  Um mutex protege a leitura/escrita entre threads de trabalho.
# ============================================================

function Get-VBackupFile { Join-Path $global:VelocityDataDir 'backup.json' }

function Use-VBackupLock([scriptblock]$Body) {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\VelocityBackup')
    [void]$mutex.WaitOne(10000)
    try { & $Body } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}

function Read-VBackup {
    $file = Get-VBackupFile
    $data = @{}
    if (Test-Path $file) {
        $raw = [IO.File]::ReadAllText($file)
        if ($raw.Trim()) {
            foreach ($p in (ConvertFrom-Json $raw).PSObject.Properties) { $data[$p.Name] = $p.Value }
        }
    }
    return $data
}

function Write-VBackup([hashtable]$Data) {
    if (-not (Test-Path $global:VelocityDataDir)) { [void](New-Item -ItemType Directory -Force -Path $global:VelocityDataDir) }
    $json = ConvertTo-Json -InputObject $Data -Depth 8
    [IO.File]::WriteAllText((Get-VBackupFile), $json, (New-Object Text.UTF8Encoding $false))
}

function Get-VBackupEntry([string]$Key) { (Read-VBackup)[$Key] }

# Por padrão só grava se ainda não existir: preserva o valor ORIGINAL do Windows
function Set-VBackupEntry([string]$Key, $Value, [switch]$Overwrite) {
    Use-VBackupLock {
        $data = Read-VBackup
        if ($Overwrite -or -not $data.ContainsKey($Key)) {
            $data[$Key] = $Value
            Write-VBackup $data
        }
    }
}

function Remove-VBackupEntry([string]$Key) {
    Use-VBackupLock {
        $data = Read-VBackup
        if ($data.ContainsKey($Key)) {
            $data.Remove($Key)
            Write-VBackup $data
        }
    }
}

# --- Backup de valores de registro ---------------------------

function Save-VRegBackup([string]$TweakId, [string]$Path, [string]$Name) {
    $cur = Get-VRegValue $Path $Name
    $data = $cur.Value
    if ($cur.Kind -eq 'Binary') { $data = [Convert]::ToBase64String([byte[]]$cur.Value) }
    elseif ($cur.Kind -eq 'MultiString') { $data = @($cur.Value) }
    Set-VBackupEntry "$TweakId|$Path|$Name" @{ Exists = $cur.Exists; Kind = $cur.Kind; Data = $data }
}

# Retorna $true se havia backup e ele foi restaurado
function Restore-VRegBackup([string]$TweakId, [string]$Path, [string]$Name) {
    $key = "$TweakId|$Path|$Name"
    $b = Get-VBackupEntry $key
    if ($null -eq $b) { return $false }
    if ($b.Exists) {
        $value = $b.Data
        if ($b.Kind -eq 'Binary') { $value = [Convert]::FromBase64String($b.Data) }
        Set-VRegValue $Path $Name $value $b.Kind
    } else {
        Remove-VRegValue $Path $Name
    }
    Remove-VBackupEntry $key
    return $true
}
