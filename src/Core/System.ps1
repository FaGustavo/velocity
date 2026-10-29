# ============================================================
#  Velocity · Utilitários de sistema
# ============================================================

function Get-VGuid([string]$Text) {
    if ($Text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
}

function Get-VActivePowerScheme { Get-VGuid (powercfg /getactivescheme | Out-String) }

function Format-VSize([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Get-VFolderSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($sum) { return [int64]$sum }
    return [int64]0
}

# Esvazia uma pasta (ignora arquivos em uso) e retorna os bytes liberados
function Clear-VFolder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $before = Get-VFolderSize $Path
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    return [int64][math]::Max(0, $before - (Get-VFolderSize $Path))
}

# Mudanças no BCD podem disparar a tela de recuperação do BitLocker.
# Suspende a proteção só até o próximo boot (é reativada automaticamente).
function Suspend-VBitLockerOnce {
    try {
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ([string]$volume.ProtectionStatus -eq 'On') {
            Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null
            Write-VLog 'BitLocker suspenso até o próximo reinício (alteração de BCD).'
        }
    } catch { }
}

function Get-VBcdValue([string]$Name) {
    if ((bcdedit /enum '{current}' | Out-String) -match "(?m)^$Name\s+(\S+)") { return $Matches[1] }
}

function New-VRestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Remove o limite de 1 ponto a cada 24h
        Set-VRegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0 'DWord'
        Checkpoint-Computer -Description 'Velocity - antes das otimizacoes' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningAction SilentlyContinue
        Write-VLog 'Ponto de restauração criado.'
        return @{ Success = $true; Message = 'Ponto de restauração do sistema criado.' }
    } catch {
        Write-VLog "Ponto de restauração falhou: $($_.Exception.Message)" 'WARN'
        return @{ Success = $false; Message = "Não foi possível criar o ponto de restauração: $($_.Exception.Message)" }
    }
}

function Get-VSystemInfo {
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Indirect' })
    $mem  = @(Get-CimInstance Win32_PhysicalMemory)
    $os   = Get-CimInstance Win32_OperatingSystem
    $nt   = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $plan = 'Desconhecido'
    try { $plan = (Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerPlan -Filter 'IsActive=True' -ErrorAction Stop).ElementName } catch { }
    if (-not $plan -or $plan -eq 'Desconhecido') {
        if ((powercfg /getactivescheme | Out-String) -match '\(([^)]+)\)\s*$') { $plan = $Matches[1] }
    }

    $gpu = 'Não detectada'; $gpuDetail = ''
    if ($gpus.Count -gt 0) {
        $gpu = $gpus[0].Name
        $gpuDetail = "Driver $($gpus[0].DriverVersion)"
        if ($gpus.Count -gt 1) { $gpuDetail = 'Também: ' + (($gpus | Select-Object -Skip 1 | ForEach-Object { $_.Name }) -join ', ') }
    }

    $ramGb = [math]::Round((($mem | Measure-Object -Property Capacity -Sum).Sum) / 1GB)
    $speed = ($mem | Select-Object -First 1).ConfiguredClockSpeed
    $ramDetail = "$($mem.Count) módulo(s)"
    if ($speed) { $ramDetail = "$speed MT/s · $ramDetail" }

    [pscustomobject]@{
        Cpu         = $cpu.Name.Trim()
        CpuDetail   = "$($cpu.NumberOfCores) núcleos · $($cpu.NumberOfLogicalProcessors) threads"
        Gpu         = $gpu
        GpuDetail   = $gpuDetail
        Ram         = "$ramGb GB"
        RamDetail   = $ramDetail
        Os          = $os.Caption -replace '^Microsoft\s+', ''
        OsDetail    = "$((Get-VRegValue $nt 'DisplayVersion').Value) · build $((Get-VRegValue $nt 'CurrentBuild').Value).$((Get-VRegValue $nt 'UBR').Value)"
        Power       = $plan
        BackupCount = (Read-VBackup).Count
    }
}
