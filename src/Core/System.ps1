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

# Apaga o conteúdo de uma pasta sem nunca entrar em junctions/links simbólicos.
# (No PowerShell 5.1, Remove-Item -Recurse segue junctions e apaga o DESTINO:
#  um link em C:\Windows\Temp apontando para outra pasta seria esvaziado como admin.)
function Remove-VFolderContent([string]$Path) {
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
        try {
            $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            if ($item.PSIsContainer) {
                if (-not $isLink) { Remove-VFolderContent $item.FullName }
                [IO.Directory]::Delete($item.FullName, $false)   # remove só o link ou a pasta já vazia
            } else {
                $item.Attributes = 'Normal'
                [IO.File]::Delete($item.FullName)
            }
        } catch { }   # em uso ou sem permissão: ignora
    }
}

# Esvazia uma pasta (ignora arquivos em uso) e retorna os bytes liberados
function Clear-VFolder([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $before = Get-VFolderSize $Path
    Remove-VFolderContent $Path
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
        # Remove o limite de 1 ponto a cada 24h só durante a criação e devolve o valor original depois
        $srKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $srName = 'SystemRestorePointCreationFrequency'
        $previous = Get-VRegValue $srKey $srName
        Set-VRegValue $srKey $srName 0 'DWord'
        try {
            Checkpoint-Computer -Description 'Velocity - antes das otimizacoes' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningAction SilentlyContinue
        } finally {
            if ($previous.Exists) { Set-VRegValue $srKey $srName $previous.Value $previous.Kind }
            else { Remove-VRegValue $srKey $srName }
        }
        Write-VLog 'Ponto de restauração criado.'
        return @{ Success = $true; Message = 'Ponto de restauração do sistema criado.' }
    } catch {
        Write-VLog "Ponto de restauração falhou: $($_.Exception.Message)" 'WARN'
        return @{ Success = $false; Message = "Não foi possível criar o ponto de restauração: $($_.Exception.Message)" }
    }
}

function Get-VSystemInfo {
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    # Placa dedicada primeiro: o WMI costuma listar a integrada (Intel HD/UHD) antes da NVIDIA/AMD
    $gpus = @(Get-CimInstance Win32_VideoController |
        Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Indirect' } |
        Sort-Object @{ Expression = { if ($_.Name -match 'NVIDIA|GeForce|Quadro|RTX|Radeon (RX|Pro)|Arc\b') { 0 } elseif ($_.Name -match 'Intel|UHD|Iris|Radeon\(TM\) Graphics|Vega \d+ Graphics') { 2 } else { 1 } } },
                     @{ Expression = { [int64]$_.AdapterRAM }; Descending = $true })
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
        if ($gpus.Count -gt 1) { $gpuDetail += ' · também: ' + (($gpus | Select-Object -Skip 1 | ForEach-Object { $_.Name }) -join ', ') }
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
        BackupCount = @((Read-VBackup).Keys | Where-Object { $_ -notlike '#*' }).Count
    }
}
