# ============================================================
#  Módulo · Serviços e processos em segundo plano
# ============================================================

Register-VCategory @{
    Id = 'services'; Name = 'Serviços'; Icon = 'E713'
    Description = 'Menos processos em segundo plano disputando CPU, disco e rede com o jogo.'
}

Register-VTweak @{
    Id = 'svc.telemetry'; Category = 'services'; Recommended = $true
    Name = 'Desativar telemetria'
    Description = 'Para o serviço "Experiências do Usuário Conectado e Telemetria" (DiagTrack) e limita a coleta de dados de diagnóstico ao mínimo.'
    Services = @(
        @{ Name = 'DiagTrack'; Start = 4; Default = 2 }
        @{ Name = 'dmwappushservice'; Start = 4; Default = 3 }
    )
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'svc.unused'; Category = 'services'; Recommended = $true
    Name = 'Desativar serviços pouco usados'
    Description = 'Mapas offline (MapsBroker), modo demonstração de loja (RetailDemo), Fax e relatório de erros (WerSvc). Nenhum deles afeta jogos.'
    Services = @(
        @{ Name = 'MapsBroker'; Start = 4; Default = 2 }
        @{ Name = 'RetailDemo'; Start = 4; Default = 3 }
        @{ Name = 'Fax'; Start = 4; Default = 3 }
        @{ Name = 'WerSvc'; Start = 4; Default = 3 }
    )
}

Register-VTweak @{
    Id = 'svc.ads'; Category = 'services'; Recommended = $true
    Name = 'Desativar sugestões e apps patrocinados'
    Description = 'Impede que o Windows instale apps promocionais em silêncio e mostre dicas e anúncios no Iniciar e nas Configurações.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Value = 0; Default = 1 }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Default = 1 }
    )
}

$global:VelocityTelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Application Experience\PcaPatchDbTask'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    '\Microsoft\Windows\Maps\MapsUpdateTask'
)

function Get-VScheduledTask([string]$FullPath) {
    $i = $FullPath.LastIndexOf('\')
    Get-ScheduledTask -TaskPath $FullPath.Substring(0, $i + 1) -TaskName $FullPath.Substring($i + 1) -ErrorAction SilentlyContinue
}

Register-VTweak @{
    Id = 'svc.tasks'; Category = 'services'; Recommended = $true
    Name = 'Desativar tarefas agendadas de telemetria'
    Description = 'Desliga tarefas que rodam escondidas, escaneiam o disco e enviam dados (Compatibility Appraiser, CEIP, Feedback, Diagnóstico de disco). Algumas delas causam picos de CPU e disco no meio do jogo.'
    Test = {
        $blocked = @(Get-VBackupEntry 'svc.tasks|blocked')
        foreach ($path in $global:VelocityTelemetryTasks) {
            if ($blocked -contains $path) { continue }
            $task = Get-VScheduledTask $path
            if ($task -and [string]$task.State -ne 'Disabled') { return $false }
        }
        $true
    }
    Apply = {
        $changed = @(Get-VBackupEntry 'svc.tasks|enabled' | Where-Object { $_ })
        $blocked = @()
        foreach ($path in $global:VelocityTelemetryTasks) {
            $task = Get-VScheduledTask $path
            if (-not $task -or [string]$task.State -eq 'Disabled') { continue }
            try { $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null; $changed += $path }
            catch { $blocked += $path }
        }
        Set-VBackupEntry 'svc.tasks|enabled' @($changed | Select-Object -Unique) -Overwrite
        Set-VBackupEntry 'svc.tasks|blocked' $blocked -Overwrite
    }
    Revert = {
        $list = @(Get-VBackupEntry 'svc.tasks|enabled' | Where-Object { $_ })
        if ($list.Count -eq 0) { $list = $global:VelocityTelemetryTasks }
        foreach ($path in $list) {
            $task = Get-VScheduledTask $path
            if ($task) { $task | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null }
        }
        Remove-VBackupEntry 'svc.tasks|enabled'
        Remove-VBackupEntry 'svc.tasks|blocked'
    }
}

Register-VTweak @{
    Id = 'svc.ai'; Category = 'services'; Recommended = $true
    Name = 'Desativar Copilot, Recall e Widgets'
    Description = 'Desliga os recursos de IA e o painel de Widgets do Windows 11, que mantêm processos (WebView/Edge) abertos consumindo RAM e CPU o tempo todo.'
    Registry = @(
        @{ Path = 'HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Default = $null }
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Value = 1; Default = $null }
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Value = 1; Default = $null }
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'svc.edge'; Category = 'services'; Recommended = $true
    Name = 'Impedir o Edge de rodar em segundo plano'
    Description = 'Desliga o "Startup Boost" e a execução em segundo plano do Microsoft Edge, que deixam vários processos dele abertos mesmo com o navegador fechado. O Edge passa a exibir "gerenciado pela organização"; isso é normal.'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Value = 0; Default = $null }
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'svc.xbox'; Category = 'services'; Risk = 'Médio'
    Name = 'Desativar serviços do Xbox Live'
    Description = 'Somente se você NÃO usa Game Pass, app Xbox ou jogos da Microsoft Store com login Xbox (Forza, Halo, Minecraft Bedrock). Controles Xbox continuam funcionando.'
    Services = @(
        @{ Name = 'XblAuthManager'; Start = 4; Default = 3 }
        @{ Name = 'XblGameSave'; Start = 4; Default = 3 }
        @{ Name = 'XboxNetApiSvc'; Start = 4; Default = 3 }
    )
}

Register-VTweak @{
    Id = 'svc.backgroundapps'; Category = 'services'; Risk = 'Médio'
    Name = 'Bloquear apps da Store em segundo plano'
    Description = 'Apps da Microsoft Store deixam de rodar escondidos. Apps como WhatsApp ou Email da Store podem parar de mostrar notificações com eles fechados.'
    Registry = @(
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Value = 1; Default = $null }
        @{ Path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BackgroundAppGlobalToggle'; Value = 0; Default = $null }
    )
}

Register-VTweak @{
    Id = 'svc.sysmain'; Category = 'services'; Risk = 'Médio'
    Name = 'Desativar SysMain (Superfetch)'
    Description = 'Para o pré-carregamento de apps na RAM, que às vezes causa uso de disco a 100%. Em SSD rápido o ganho do SysMain é pequeno; em HDD os apps podem abrir mais devagar.'
    Services = @( @{ Name = 'SysMain'; Start = 4; Default = 2 } )
}

Register-VTweak @{
    Id = 'svc.spooler'; Category = 'services'; Risk = 'Médio'
    Name = 'Desativar spooler de impressão'
    Description = 'Desative apenas se você NÃO usa impressora (nem "Imprimir para PDF"). Libera memória e fecha uma superfície de ataque conhecida.'
    Services = @( @{ Name = 'Spooler'; Start = 4; Default = 2 } )
}

Register-VTweak @{
    Id = 'svc.search'; Category = 'services'; Risk = 'Alto'
    Name = 'Desativar indexação da Pesquisa do Windows'
    Description = 'Elimina a indexação contínua do disco. Em troca, a busca de arquivos no Iniciar, no Explorer e no Outlook fica bem mais lenta.'
    Services = @( @{ Name = 'WSearch'; Start = 4; Default = 2 } )
}
