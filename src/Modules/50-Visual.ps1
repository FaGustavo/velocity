# ============================================================
#  Módulo · Interface e efeitos visuais
# ============================================================

Register-VCategory @{
    Id = 'visual'; Name = 'Interface'; Icon = 'E790'
    Description = 'Menos animações e efeitos, com um Windows mais rápido de usar.'
}

Register-VTweak @{
    Id = 'vis.menudelay'; Category = 'visual'; Recommended = $true; RequiresReboot = $true
    Name = 'Menus instantâneos'
    Description = 'Remove o atraso de 400 ms antes de abrir submenus.'
    Registry = @(
        @{ Path = 'HKCU\Control Panel\Desktop'; Name = 'MenuShowDelay'; Value = '0'; Type = 'String'; Default = '400' }
    )
}

Register-VTweak @{
    Id = 'vis.startupdelay'; Category = 'visual'; Recommended = $true
    Name = 'Remover atraso dos apps de inicialização'
    Description = 'Por padrão, o Windows espera alguns segundos após o login antes de abrir os apps de inicialização. Isso remove a espera.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'vis.transparency'; Category = 'visual'
    Name = 'Desativar transparência'
    Description = 'Remove o efeito acrílico/vidro da barra de tarefas, do Iniciar e das janelas. Alivia um pouco a GPU integrada.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Value = 0; Default = 1 }
    )
}

Register-VTweak @{
    Id = 'vis.effects'; Category = 'visual'; RequiresReboot = $true
    Name = 'Efeitos visuais para desempenho'
    Description = 'Desliga animações de janelas, da barra de tarefas, sombras e o Aero Peek, mas mantém a suavização de fontes. O visual fica mais seco e a resposta mais imediata.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Value = 3; Default = 0 }
        @{ Path = 'HKCU\Control Panel\Desktop'; Name = 'UserPreferencesMask'; Value = '90 12 03 80 10 00 00 00'; Type = 'Binary'; Default = '9E 1E 07 80 12 00 00 00' }
        @{ Path = 'HKCU\Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Value = '0'; Type = 'String'; Default = '1' }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAnimations'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ListviewAlphaSelect'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\DWM'; Name = 'EnableAeroPeek'; Value = 0; Default = 1 }
    )
}
