# ============================================================
#  Velocity · Backup persistente dos valores originais
#  Arquivo: %ProgramData%\Velocity\backup.json
#  Um mutex protege a leitura/escrita entre threads de trabalho.
#  A gravação é atômica (arquivo temporário + troca), então uma
#  queda de energia no meio não corrompe o backup.
# ============================================================

function Get-VBackupFile { Join-Path $global:VelocityDataDir 'backup.json' }

function Use-VBackupLock([scriptblock]$Body) {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\VelocityBackup')
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne(10000) }
        catch [System.Threading.AbandonedMutexException] { $owned = $true }   # outro processo morreu segurando a trava
        if (-not $owned) { throw 'O arquivo de backup está ocupado por outra operação. Tente novamente.' }
        & $Body
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function ConvertFrom-VBackupJson([string]$Raw) {
    $data = @{}
    if ($Raw -and $Raw.Trim()) {
        foreach ($p in (ConvertFrom-Json $Raw).PSObject.Properties) { $data[$p.Name] = $p.Value }
    }
    return $data
}

function Read-VBackup {
    $file = Get-VBackupFile
    if (-not (Test-Path -LiteralPath $file)) { return @{} }
    try {
        return ConvertFrom-VBackupJson ([IO.File]::ReadAllText($file))
    } catch {
        # Arquivo danificado: tenta a cópia anterior e guarda o danificado para análise
        $previous = "$file.bak"
        Write-VLog "backup.json ilegível ($($_.Exception.Message)). Tentando a cópia anterior." 'ERROR'
        try { Copy-Item -LiteralPath $file -Destination ("$file.corrompido-{0:yyyyMMdd-HHmmss}" -f (Get-Date)) -Force } catch { }
        if (Test-Path -LiteralPath $previous) {
            try { return ConvertFrom-VBackupJson ([IO.File]::ReadAllText($previous)) } catch { }
        }
        throw 'O arquivo de backup está danificado. Uma cópia foi guardada em %ProgramData%\Velocity.'
    }
}

function Write-VBackup([hashtable]$Data) {
    if (-not (Test-Path $global:VelocityDataDir)) { [void](New-Item -ItemType Directory -Force -Path $global:VelocityDataDir) }
    $file = Get-VBackupFile
    $temp = "$file.tmp"
    $json = ConvertTo-Json -InputObject $Data -Depth 8
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $file) { [IO.File]::Replace($temp, $file, "$file.bak") }
    else { [IO.File]::Move($temp, $file) }
}

function Get-VBackupEntry([string]$Key) {
    Use-VBackupLock { (Read-VBackup)[$Key] }
}

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

# Otimizações que o próprio Velocity aplicou (têm algo guardado no backup).
# "Reverter tudo" só mexe nelas: o que já estava assim antes do Velocity fica como está.
function Get-VOwnedTweakIds {
    $ids = @{}
    Use-VBackupLock {
        foreach ($k in (Read-VBackup).Keys) {
            if ($k -like '#applied|*') { $ids[$k.Substring(9)] = $true }
            elseif ($k -match '^([^|#]+)\|') { $ids[$Matches[1]] = $true }
        }
    }
    return @($ids.Keys)
}
