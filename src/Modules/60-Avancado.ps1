# ============================================================
#  Módulo · Avançado (Deep)
#  Kernel, boot, drivers e segurança. Itens de risco alto pedem
#  confirmação individual na interface.
# ============================================================

Register-VCategory @{
    Id = 'deep'; Name = 'Avançado (Deep)'; Icon = 'E7BA'
    Description = 'Kernel, boot, interrupções de hardware, drivers de rede e recursos de segurança.'
    Warning = 'Estas otimizações mexem em camadas profundas do Windows: configuração de boot, drivers e proteções de segurança. São reversíveis, mas recomendamos criar um ponto de restauração antes e aplicar uma de cada vez, testando seus jogos entre as mudanças.'
}

# ---------------- Kernel e boot ------------------------------

Register-VTweak @{
    Id = 'deep.bcd'; Category = 'deep'; Risk = 'Médio'; RequiresReboot = $true
    Name = 'Desativar tick dinâmico do kernel (BCD)'
    Description = 'Configura o boot (bcdedit) para manter o timer do kernel em ritmo constante, em vez de "dormir" entre interrupções, e remove o HPET forçado, se houver. Reduz a latência de agendamento e deixa o frametime mais consistente. Aumenta um pouco o consumo em idle.'
    Test = {
        $v = Get-VBcdValue 'disabledynamictick'
        [bool]$v -and $v -notmatch '^(No|N.o)$'
    }
    Apply = {
        Suspend-VBitLockerOnce
        $platformClock = Get-VBcdValue 'useplatformclock'
        if ($platformClock) { Set-VBackupEntry 'deep.bcd|useplatformclock' $platformClock }
        bcdedit /set '{current}' disabledynamictick yes | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'bcdedit recusou a alteração (Secure Boot/política do sistema).' }
        if ($platformClock) { bcdedit /deletevalue '{current}' useplatformclock | Out-Null }
    }
    Revert = {
        Suspend-VBitLockerOnce
        bcdedit /deletevalue '{current}' disabledynamictick | Out-Null
        $platformClock = Get-VBackupEntry 'deep.bcd|useplatformclock'
        if ($platformClock -and $platformClock -notmatch '^(No|N.o)$') { bcdedit /set '{current}' useplatformclock yes | Out-Null }
        Remove-VBackupEntry 'deep.bcd|useplatformclock'
    }
}

Register-VTweak @{
    Id = 'deep.pagingexec'; Category = 'deep'; Risk = 'Médio'; RequiresReboot = $true
    Name = 'Manter o kernel sempre na RAM'
    Description = 'Impede que drivers e código do kernel sejam enviados para o arquivo de paginação (DisablePagingExecutive). Evita travadas quando o sistema volta a usar algo que estava no disco. Indicado para PCs com 16 GB ou mais.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'DisablePagingExecutive'; Value = 1; Default = 0 }
    )
}

Register-VTweak @{
    Id = 'deep.memcompress'; Category = 'deep'; Risk = 'Médio'; RequiresReboot = $true
    Name = 'Desativar compressão de memória'
    Description = 'O Windows comprime páginas de RAM usando CPU para "caber mais". Com 16 GB ou mais isso só gasta ciclos de CPU durante o jogo. Não use em PCs com 8 GB.'
    Test   = { try { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { $false } }
    Apply  = { Disable-MMAgent -MemoryCompression -ErrorAction Stop }
    Revert = { Enable-MMAgent -MemoryCompression -ErrorAction Stop }
}

# ---------------- Hardware -----------------------------------

Register-VTweak @{
    Id = 'deep.msi'; Category = 'deep'; Risk = 'Alto'; RequiresReboot = $true
    Name = 'Modo MSI para a placa de vídeo'
    Description = 'Troca as interrupções da GPU de "linha compartilhada" para Message Signaled Interrupts: menos latência de DPC e menos conflito com outros dispositivos. GPUs modernas suportam, mas se a tela ficar preta após reiniciar, use o Modo de Segurança e reverta (ou o ponto de restauração).'
    Registry = {
        Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\*' } | ForEach-Object {
            @{ Path = "HKLM\SYSTEM\CurrentControlSet\Enum\$($_.PNPDeviceID)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"; Name = 'MSISupported'; Value = 1 }
        }
    }
}

# Propriedades avançadas do driver de rede -> valor desejado
$global:VelocityNicTargets = @{
    '*InterruptModeration' = '0'    # moderação de interrupção (agrupa pacotes = latência)
    '*EEE'                 = '0'    # Energy Efficient Ethernet
    '*FlowControl'         = '0'
    '*LsoV2IPv4'           = '0'    # Large Send Offload
    '*LsoV2IPv6'           = '0'
    'EEELinkAdvertisement' = '0'    # Intel
    'AdvancedEEE'          = '0'    # Realtek
    'EnableGreenEthernet'  = '0'    # Realtek
    'GreenEthernet'        = '0'
    'PowerSavingMode'      = '0'
    'ULPMode'              = '0'    # Intel Ultra Low Power
}

function Get-VNicTweakProperties {
    foreach ($adapter in Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { [string]$_.Status -ne 'Disabled' }) {
        foreach ($p in Get-NetAdapterAdvancedProperty -Name $adapter.Name -AllProperties -ErrorAction SilentlyContinue) {
            $target = $global:VelocityNicTargets[[string]$p.RegistryKeyword]
            if ($null -eq $target) { continue }
            if ($p.ValidRegistryValues -and @($p.ValidRegistryValues) -notcontains $target) { continue }
            [pscustomobject]@{ Adapter = $adapter; Keyword = [string]$p.RegistryKeyword; Current = [string]@($p.RegistryValue)[0]; Target = $target }
        }
    }
}

Register-VTweak @{
    Id = 'deep.nic'; Category = 'deep'; Risk = 'Médio'
    Name = 'Driver de rede em modo baixa latência'
    Description = 'Desliga, direto no driver da placa de rede, a moderação de interrupções, Large Send Offload, Energy Efficient/Green Ethernet, controle de fluxo e a economia de energia do adaptador. Cada pacote é processado na hora. A conexão cai por alguns segundos ao aplicar.'
    Test = {
        $props = @(Get-VNicTweakProperties)
        $props.Count -gt 0 -and -not ($props | Where-Object { $_.Current -ne $_.Target })
    }
    Apply = {
        $touched = @{}
        foreach ($p in Get-VNicTweakProperties | Where-Object { $_.Current -ne $_.Target }) {
            Set-VBackupEntry "deep.nic|$($p.Adapter.InterfaceDescription)|$($p.Keyword)" $p.Current
            Set-NetAdapterAdvancedProperty -Name $p.Adapter.Name -RegistryKeyword $p.Keyword -RegistryValue $p.Target -NoRestart -ErrorAction Stop
            $touched[$p.Adapter.Name] = $true
        }
        foreach ($adapter in Get-NetAdapter -Physical -ErrorAction SilentlyContinue) {
            try {
                $pm = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
                if ([string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled') {
                    Set-VBackupEntry "deep.nic|$($adapter.InterfaceDescription)|#power" 'Enabled'
                    Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Disabled -NoRestart -ErrorAction Stop
                    $touched[$adapter.Name] = $true
                }
            } catch { }
        }
        foreach ($name in $touched.Keys) { Restart-NetAdapter -Name $name -ErrorAction SilentlyContinue }
    }
    Revert = {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        $touched = @{}
        foreach ($key in @((Read-VBackup).Keys | Where-Object { $_ -like 'deep.nic|*' })) {
            $null, $description, $keyword = $key -split '\|', 3
            $adapter = $adapters | Where-Object { $_.InterfaceDescription -eq $description } | Select-Object -First 1
            if ($adapter) {
                if ($keyword -eq '#power') { Set-NetAdapterPowerManagement -Name $adapter.Name -AllowComputerToTurnOffDevice Enabled -NoRestart -ErrorAction SilentlyContinue }
                else { Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -RegistryValue ([string](Get-VBackupEntry $key)) -NoRestart -ErrorAction SilentlyContinue }
                $touched[$adapter.Name] = $true
            }
            Remove-VBackupEntry $key
        }
        foreach ($name in $touched.Keys) { Restart-NetAdapter -Name $name -ErrorAction SilentlyContinue }
    }
}

# ---------------- Segurança x desempenho ---------------------

Register-VTweak @{
    Id = 'deep.vbs'; Category = 'deep'; Risk = 'Alto'; RequiresReboot = $true
    Name = 'Desativar Isolamento de Núcleo (VBS / HVCI)'
    Description = 'Desliga a virtualização de segurança e a Integridade de Memória. É a otimização com maior ganho real: costuma render 5–15% de FPS. Em troca, reduz a proteção do kernel contra malware. Alguns anti-cheats (ex.: FACEIT, Vanguard em certas configurações) exigem esse recurso ligado.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 }
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Value = 0 }
    )
}

Register-VTweak @{
    Id = 'deep.mitigations'; Category = 'deep'; Risk = 'Alto'; RequiresReboot = $true
    Name = 'Desativar mitigações Spectre/Meltdown'
    Description = 'Remove as correções de software contra vulnerabilidades de CPU (Spectre, Meltdown e similares). Em CPUs anteriores a 2019 o ganho em jogos e E/S pode ser grande; em CPUs recentes é pequeno. Deixa o PC vulnerável a ataques de canal lateral, como código malicioso lendo memória de outros processos.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverride'; Value = 3; Default = $null }
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'FeatureSettingsOverrideMask'; Value = 3; Default = $null }
    )
}

function Get-VGameFolders {
    $paths = New-Object System.Collections.Generic.List[string]
    $steam = [string](Get-VRegValue 'HKCU\Software\Valve\Steam' 'SteamPath').Value
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $paths.Add((Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common'))
            }
        }
    }
    $epic = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path $epic) {
        foreach ($f in Get-ChildItem $epic -Filter '*.item' -ErrorAction SilentlyContinue) {
            try { $paths.Add((ConvertFrom-Json ([IO.File]::ReadAllText($f.FullName))).InstallLocation) } catch { }
        }
    }
    foreach ($p in @("$env:SystemDrive\Riot Games", "$env:SystemDrive\XboxGames", "$env:ProgramFiles\EA Games",
                     "${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher\games", "$env:ProgramFiles\Epic Games")) { $paths.Add($p) }
    @($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        ForEach-Object { (Resolve-Path -LiteralPath $_).ProviderPath.TrimEnd('\') } | Sort-Object -Unique)
}

Register-VTweak @{
    Id = 'deep.defender'; Category = 'deep'; Risk = 'Médio'
    Name = 'Excluir pastas de jogos do Windows Defender'
    Description = 'Detecta suas bibliotecas Steam, Epic, Riot, EA, Ubisoft e Xbox e as exclui da verificação em tempo real. Reduz stutter ao carregar mapas e texturas. Arquivos dessas pastas deixam de ser escaneados; baixe jogos só de lojas oficiais.'
    Test = {
        try {
            $folders = Get-VGameFolders
            $excluded = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
            $folders.Count -gt 0 -and -not ($folders | Where-Object { $excluded -notcontains $_ })
        } catch { $false }
    }
    Apply = {
        $folders = Get-VGameFolders
        if ($folders.Count -eq 0) { throw 'Nenhuma pasta de jogos encontrada.' }
        $excluded = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
        $new = @($folders | Where-Object { $excluded -notcontains $_ })
        if ($new.Count -gt 0) {
            Add-MpPreference -ExclusionPath $new -ErrorAction Stop
            $previous = @(Get-VBackupEntry 'deep.defender|added' | Where-Object { $_ })
            Set-VBackupEntry 'deep.defender|added' @($previous + $new | Select-Object -Unique) -Overwrite
        }
    }
    Revert = {
        $added = @(Get-VBackupEntry 'deep.defender|added' | Where-Object { $_ })
        if ($added.Count -gt 0) { Remove-MpPreference -ExclusionPath $added -ErrorAction Stop }
        Remove-VBackupEntry 'deep.defender|added'
    }
}
