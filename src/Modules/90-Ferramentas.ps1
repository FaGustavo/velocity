# ============================================================
#  Módulo · Ferramentas (ações pontuais, sem estado)
# ============================================================

Register-VAction @{
    Id = 'clean.temp'; Name = 'Limpar arquivos temporários'; Icon = 'EA99'; ButtonText = 'Limpar'
    Description = 'Remove arquivos temporários do usuário e do Windows, além de despejos de falhas. Arquivos em uso são ignorados.'
    Run = {
        $freed = [int64]0
        foreach ($p in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:LOCALAPPDATA 'CrashDumps'))) { $freed += Clear-VFolder $p }
        "Espaço liberado: $(Format-VSize $freed)."
    }
}

Register-VAction @{
    Id = 'mem.standby'; Name = 'Liberar memória em espera (standby)'; Icon = 'E9F5'; ButtonText = 'Liberar'
    Description = 'Esvazia a lista de memória "standby" direto no kernel (a mesma técnica do ISLC). Ajuda contra stutter em jogos pesados quando a RAM está quase cheia. Rode antes de abrir o jogo.'
    Run = {
        if (-not ('Velocity.Memory' -as [type])) {
            Add-Type -Namespace Velocity -Name Memory -MemberDefinition @'
[DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool wasEnabled);
'@
        }
        $was = $false
        [void][Velocity.Memory]::RtlAdjustPrivilege(13, $true, $false, [ref]$was)   # SeProfileSingleProcessPrivilege
        $before = [int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
        $command = 4                                                                  # MemoryPurgeStandbyList
        $status = [Velocity.Memory]::NtSetSystemInformation(80, [ref]$command, 4)     # SystemMemoryListInformation
        if ($status -ne 0) { throw ('O kernel recusou a operação (NTSTATUS 0x{0:X8}).' -f $status) }
        $after = [int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
        "Memória livre: $(Format-VSize $before) → $(Format-VSize $after)."
    }
}

Register-VAction @{
    Id = 'apps.debloat'; Name = 'Remover apps pré-instalados'; Icon = 'E74D'; ButtonText = 'Remover'
    Description = 'Desinstala apps que vêm com o Windows e rodam tarefas em segundo plano: Notícias, Clima, Clipchamp, Solitaire, Teams pessoal, Dicas, Hub de Comentários, Mapas, To Do, Power Automate e outros. Todos podem ser reinstalados pela Microsoft Store.'
    Confirm = 'Os apps abaixo serão desinstalados da sua conta (se existirem). Isso NÃO é revertido pelo botão "Reverter"; reinstale pela Microsoft Store se precisar.' +
              "`n`nNotícias, Clima, Bing Search, Obter Ajuda, Dicas, Solitaire, Pessoas, Hub de Comentários, Mapas, To Do, Power Automate, Microsoft 365 (Office Hub), Clipchamp, Teams (pessoal), Cortana, Visualizador 3D, Portal de Realidade Mista, Skype."
    Run = {
        $apps = @(
            'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
            'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
            'Microsoft.Todos', 'Microsoft.PowerAutomateDesktop', 'Microsoft.MicrosoftOfficeHub', 'Clipchamp.Clipchamp', 'MSTeams',
            'MicrosoftTeams', 'Microsoft.549981C3F5F10', 'Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp'
        )
        $removed = @(); $failed = @()
        foreach ($name in $apps) {
            foreach ($pkg in @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)) {
                try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop; $removed += $name }
                catch { $failed += $name }
            }
        }
        if ($removed.Count -eq 0 -and $failed.Count -eq 0) { return 'Nenhum dos apps da lista estava instalado.' }
        $msg = "$($removed.Count) app(s) removido(s)."
        if ($removed) { $msg += "`n" + (($removed | Select-Object -Unique) -join ', ') }
        if ($failed) { $msg += "`n`nNão foi possível remover: " + (($failed | Select-Object -Unique) -join ', ') }
        $msg
    }
}

Register-VAction @{
    Id = 'clean.shaders'; Name = 'Limpar cache de shaders'; Icon = 'E7F4'; ButtonText = 'Limpar'
    Description = 'Apaga os caches de shaders do DirectX, NVIDIA, AMD e Intel. Útil após atualizar o driver ou quando um jogo apresenta stutter/artefatos. Na primeira abertura os jogos recompilam os shaders.'
    Run = {
        $paths = @(
            "$env:LOCALAPPDATA\D3DSCache"
            "$env:LOCALAPPDATA\NVIDIA\DXCache"
            "$env:LOCALAPPDATA\NVIDIA\GLCache"
            "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
            "$env:LOCALAPPDATA\AMD\DxCache"
            "$env:LOCALAPPDATA\AMD\DxcCache"
            "$env:LOCALAPPDATA\AMD\VkCache"
            "$env:LOCALAPPDATA\Intel\ShaderCache"
        )
        $freed = [int64]0
        foreach ($p in $paths) { $freed += Clear-VFolder $p }
        "Cache de shaders limpo. Espaço liberado: $(Format-VSize $freed)."
    }
}

Register-VAction @{
    Id = 'net.flushdns'; Name = 'Limpar cache DNS'; Icon = 'E774'; ButtonText = 'Executar'
    Description = 'Descarta resoluções DNS em cache. Ajuda quando um servidor de jogo mudou de IP ou a conexão está falhando.'
    Run = {
        Clear-DnsClientCache
        'Cache DNS limpo.'
    }
}

Register-VAction @{
    Id = 'drive.trim'; Name = 'Otimizar SSDs (TRIM)'; Icon = 'EDA2'; ButtonText = 'Otimizar'
    Description = 'Executa o TRIM em todas as unidades SSD fixas, mantendo a velocidade de escrita alta. Unidades HDD são ignoradas.'
    Run = {
        $volumes = Get-Volume | Where-Object { $_.DriveLetter -and [string]$_.DriveType -eq 'Fixed' -and "$($_.FileSystemType)$($_.FileSystem)" -match 'NTFS|ReFS' }
        $lines = foreach ($v in $volumes) {
            try { Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -ErrorAction Stop; "$($v.DriveLetter): TRIM concluído" }
            catch { "$($v.DriveLetter): ignorada (HDD ou não suportado)" }
        }
        if ($lines) { $lines -join "`n" } else { 'Nenhuma unidade compatível encontrada.' }
    }
}

Register-VAction @{
    Id = 'system.restore'; Name = 'Criar ponto de restauração'; Icon = 'E81C'; ButtonText = 'Criar'
    Description = 'Cria um ponto de restauração do Windows, uma rede de segurança extra além do backup automático do Velocity.'
    Run = {
        $r = New-VRestorePoint
        if (-not $r.Success) { throw $r.Message }
        $r.Message
    }
}

Register-VAction @{
    Id = 'system.graphics'; Name = 'Preferência de GPU por jogo'; Icon = 'E7FC'; ButtonText = 'Abrir'
    Description = 'Abre as configurações de Gráficos do Windows. Adicione seus jogos e escolha "Alto desempenho" para garantir que usem a GPU dedicada em notebooks.'
    Run = {
        Start-Process 'ms-settings:display-advancedgraphics'
        'Configurações de Gráficos abertas. Adicione o .exe do jogo e escolha "Alto desempenho".'
    }
}
