# ============================================================
#  Módulo · Jogos (GPU, Game Bar, entrada)
# ============================================================

Register-VCategory @{
    Id = 'games'; Name = 'Jogos e Gráficos'; Icon = 'E7FC'
    Description = 'Modo de Jogo, agendamento da GPU, gravação em segundo plano e entrada.'
}

Register-VTweak @{
    Id = 'games.gamemode'; Category = 'games'; Recommended = $true
    Name = 'Ativar Modo de Jogo'
    Description = 'Faz o Windows dar prioridade de recursos ao jogo e suspender atualizações e notificações enquanto você joga.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Default = $null }
        @{ Path = 'HKCU\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode'; Value = 1; Default = $null }
    )
}

Register-VTweak @{
    Id = 'games.hags'; Category = 'games'; Recommended = $true; RequiresReboot = $true
    Name = 'Agendamento de GPU acelerado por hardware'
    Description = 'A própria GPU gerencia sua memória de vídeo, reduzindo latência e uso de CPU. Necessário para o DLSS Frame Generation. Requer GPU e driver compatíveis.'
    Registry = @(
        @{ Path = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Value = 2; Default = 1 }
    )
}

Register-VTweak @{
    Id = 'games.gamedvr'; Category = 'games'; Recommended = $true
    Name = 'Desativar gravação em segundo plano (Game DVR)'
    Description = 'Desliga a captura contínua do Xbox Game Bar, que grava os últimos minutos de jogo e consome GPU e disco o tempo todo.'
    Registry = @(
        @{ Path = 'HKCU\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Value = 0; Default = $null }
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'games.windowed'; Category = 'games'; Recommended = $true; MinBuild = 22000
    Name = 'Otimizações para jogos em janela'
    Description = 'Recurso do Windows 11 que usa o modelo de apresentação flip em jogos DX10/11 em janela/sem borda: menor latência e suporte a VRR e Auto HDR.'
    Test = {
        $v = Get-VRegValue 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
        $v.Exists -and [string]$v.Value -match 'SwapEffectUpgradeEnable=1'
    }
    Apply = {
        $path = 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
        Save-VRegBackup 'games.windowed' $path 'DirectXUserGlobalSettings'
        $current = [string](Get-VRegValue $path 'DirectXUserGlobalSettings').Value
        $parts = @($current -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' }) + 'SwapEffectUpgradeEnable=1'
        Set-VRegValue $path 'DirectXUserGlobalSettings' (($parts | ForEach-Object { "$_;" }) -join '') 'String'
    }
    Revert = {
        $path = 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
        if (-not (Restore-VRegBackup 'games.windowed' $path 'DirectXUserGlobalSettings')) {
            $current = [string](Get-VRegValue $path 'DirectXUserGlobalSettings').Value
            $parts = @($current -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
            Set-VRegValue $path 'DirectXUserGlobalSettings' (($parts | ForEach-Object { "$_;" }) -join '') 'String'
        }
    }
}

Register-VTweak @{
    Id = 'games.mouse'; Category = 'games'; Recommended = $true; RequiresReboot = $true
    Name = 'Desativar aceleração do mouse'
    Description = 'Desliga o "Aumentar precisão do ponteiro" para que o movimento seja 1:1 com a mão. Essencial para mira consistente em FPS.'
    Registry = @(
        @{ Path = 'HKCU\Control Panel\Mouse'; Name = 'MouseSpeed'; Value = '0'; Type = 'String'; Default = '1' }
        @{ Path = 'HKCU\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = '0'; Type = 'String'; Default = '6' }
        @{ Path = 'HKCU\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = '0'; Type = 'String'; Default = '10' }
    )
}

Register-VTweak @{
    Id = 'games.stickykeys'; Category = 'games'; Recommended = $true
    Name = 'Desativar atalho das Teclas de Aderência'
    Description = 'Evita que apertar Shift 5 vezes no meio do jogo abra o aviso de Teclas de Aderência e tire o foco da partida.'
    Registry = @(
        @{ Path = 'HKCU\Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Value = '506'; Type = 'String'; Default = '510' }
    )
}

Register-VTweak @{
    Id = 'games.fso'; Category = 'games'; Risk = 'Médio'
    Name = 'Desativar otimizações de tela cheia'
    Description = 'Força tela cheia exclusiva de verdade. Pode reduzir input lag em jogos DX9/DX11 mais antigos; em jogos modernos as otimizações em janela costumam ser melhores.'
    Registry = @(
        @{ Path = 'HKCU\System\GameConfigStore'; Name = 'GameDVR_FSEBehaviorMode'; Value = 2; Default = 0 }
        @{ Path = 'HKCU\System\GameConfigStore'; Name = 'GameDVR_FSEBehavior'; Value = 2; Default = $null }
        @{ Path = 'HKCU\System\GameConfigStore'; Name = 'GameDVR_HonorUserFSEBehaviorMode'; Value = 1; Default = 0 }
        @{ Path = 'HKCU\System\GameConfigStore'; Name = 'GameDVR_DXGIHonorFSEWindowsCompatible'; Value = 1; Default = 0 }
    )
}

Register-VTweak @{
    Id = 'games.mpo'; Category = 'games'; Risk = 'Médio'; RequiresReboot = $true
    Name = 'Desativar Multiplane Overlay (MPO)'
    Description = 'Use apenas se tiver tela piscando, travadas ao alt-tab ou stutter com dois monitores (comum em GPUs NVIDIA). Sem esses sintomas, deixe desligado.'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayTestMode'; Value = 5; Default = $null }
    )
}
