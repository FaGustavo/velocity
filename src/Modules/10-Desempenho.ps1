# ============================================================
#  Módulo · Desempenho (CPU, energia, agendador)
# ============================================================

Register-VCategory @{
    Id = 'perf'; Name = 'Desempenho'; Icon = 'EC4A'
    Description = 'Energia, agendamento de CPU e prioridade para o jogo em primeiro plano.'
}

Register-VTweak @{
    Id = 'perf.powerplan'; Category = 'perf'; Recommended = $true
    Name = 'Plano de energia Desempenho Máximo'
    Description = 'Cria um plano "Desempenho Máximo" (Ultimate Performance) ajustado: CPU sempre em 100% de estado mínimo, sem estacionamento de núcleos, sem suspensão seletiva de USB e sem economia de energia do PCIe (ASPM). Em notebooks aumenta consumo e temperatura.'
    Test = {
        $target = Get-VBackupEntry 'perf.powerplan|target'
        [bool]$target -and ((Get-VActivePowerScheme) -eq $target)
    }
    Apply = {
        Set-VBackupEntry 'perf.powerplan|previous' (Get-VActivePowerScheme)
        $target = Get-VBackupEntry 'perf.powerplan|target'
        if (-not $target -or (powercfg /list | Out-String) -notmatch $target) {
            $target = Get-VGuid (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-String)
            if (-not $target) { $target = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }   # Alto desempenho (fallback)
            Set-VBackupEntry 'perf.powerplan|target' $target -Overwrite
        }
        if ($target -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') {
            # Configurações ocultas — aplicadas só no plano criado pelo Velocity (apagado ao reverter)
            $settings = @(
                @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0),    # USB: suspensão seletiva
                @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0),    # PCIe: ASPM desligado
                @('54533251-82be-4824-96c1-47b60b740d00', '893dee8e-2bef-41e0-89c6-b55d0929964c', 100),  # CPU: estado mínimo 100%
                @('54533251-82be-4824-96c1-47b60b740d00', '0cc5b647-c1df-4637-891a-dec35c318583', 100),  # CPU: núcleos mínimos sem parking
                @('0012ee47-9041-4b5d-9b77-535fba8b1442', '6738e2c4-e8a5-4a42-b16a-e040e769756e', 0)     # Disco: nunca desligar
            )
            foreach ($s in $settings) { powercfg /setacvalueindex $target $s[0] $s[1] $s[2] | Out-Null }
        }
        powercfg /setactive $target | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Este PC não permite ativar o plano Desempenho Máximo/Alto desempenho.' }
    }
    Revert = {
        $previous = Get-VBackupEntry 'perf.powerplan|previous'
        if (-not $previous) { $previous = '381b4222-f694-41f0-9685-ff5bb260df2e' }   # Equilibrado
        powercfg /setactive $previous | Out-Null
        $target = Get-VBackupEntry 'perf.powerplan|target'
        if ($target -and $target -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') { powercfg /delete $target | Out-Null }
        Remove-VBackupEntry 'perf.powerplan|previous'
        Remove-VBackupEntry 'perf.powerplan|target'
    }
}

Register-VTweak @{
    Id = 'perf.powerthrottling'; Category = 'perf'; Recommended = $true; RequiresReboot = $true
    Name = 'Desativar Power Throttling'
    Description = 'Impede que o Windows reduza a frequência da CPU para processos em segundo plano (launchers, Discord, overlays), evitando quedas de desempenho.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; Name = 'PowerThrottlingOff'; Value = 1; Default = $null }
    )
}

Register-VTweak @{
    Id = 'perf.priority'; Category = 'perf'; Recommended = $true
    Name = 'Priorizar o programa em primeiro plano'
    Description = 'Ajusta o agendador (Win32PrioritySeparation = 0x26) para dar fatias de tempo maiores e mais curtas ao aplicativo ativo, o jogo.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Value = 0x26; Default = 2 }
    )
}

Register-VTweak @{
    Id = 'perf.mmcss'; Category = 'perf'; Recommended = $true
    Name = 'Prioridade multimídia para jogos (MMCSS)'
    Description = 'Reduz a CPU reservada para tarefas de fundo e eleva a prioridade de CPU/GPU/E-S do perfil "Games" do Multimedia Class Scheduler.'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Value = 10; Default = 20 }
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Value = 8; Default = 8 }
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Value = 6; Default = 2 }
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Value = 'High'; Type = 'String'; Default = 'Medium' }
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Value = 'High'; Type = 'String'; Default = 'Normal' }
    )
}

Register-VTweak @{
    Id = 'perf.hibernate'; Category = 'perf'; Risk = 'Médio'
    Name = 'Desativar hibernação'
    Description = 'Remove o arquivo hiberfil.sys (libera GBs no disco do sistema). Também desativa a Inicialização Rápida, o que torna cada desligamento um boot "limpo".'
    Test   = { $v = Get-VRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'; $v.Exists -and $v.Value -eq 0 }
    Apply  = { powercfg /hibernate off | Out-Null }
    Revert = { powercfg /hibernate on | Out-Null }
}

Register-VTweak @{
    Id = 'perf.timer'; Category = 'perf'; Risk = 'Médio'; RequiresReboot = $true; MinBuild = 22000
    Name = 'Resolução de timer global'
    Description = 'No Windows 11, faz a resolução de timer pedida por um jogo valer para o sistema todo (comportamento antigo). Pode deixar o frametime mais estável; aumenta um pouco o consumo de energia.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'GlobalTimerResolutionRequests'; Value = 1; Default = $null }
    )
}

Register-VTweak @{
    Id = 'perf.ntfs'; Category = 'perf'; Recommended = $true; RequiresReboot = $true
    Name = 'Reduzir escrita extra do sistema de arquivos'
    Description = 'Para de gravar o "último acesso" em cada arquivo lido e de gerar nomes curtos 8.3. Menos E/S de disco ao carregar jogos com milhares de arquivos.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisableLastAccessUpdate'; Value = 0x80000001; Default = 0x80000002 }
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'NtfsDisable8dot3NameCreation'; Value = 1; Default = 2 }
    )
}
