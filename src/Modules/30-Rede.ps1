# ============================================================
#  Módulo · Rede (latência)
# ============================================================

Register-VCategory @{
    Id = 'network'; Name = 'Rede'; Icon = 'E968'
    Description = 'Menor latência e sem limitação de pacotes durante as partidas.'
}

Register-VTweak @{
    Id = 'net.throttling'; Category = 'network'; Recommended = $true
    Name = 'Remover limitação de rede multimídia'
    Description = 'O Windows limita o processamento de pacotes de rede enquanto há áudio/vídeo tocando. Remover o limite evita picos de ping com música ou Discord abertos.'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Value = 0xFFFFFFFF; Default = 10 }
    )
}

Register-VTweak @{
    Id = 'net.delivery'; Category = 'network'; Recommended = $true
    Name = 'Desativar compartilhamento P2P de atualizações'
    Description = 'Impede que o Windows use sua conexão de upload para enviar atualizações a outros PCs na internet (Otimização de Entrega). Atualizações continuam chegando normalmente.'
    Registry = @(
        @{ Path = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Value = 0; Default = $null }
    )
}

# Gera as entradas para cada interface de rede com IP configurado
$nagleEntries = @()
$interfacesRoot = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
$interfacesKey = Get-VRegKey $interfacesRoot
if ($interfacesKey) {
    foreach ($guid in $interfacesKey.GetSubKeyNames()) {
        $sub = $interfacesKey.OpenSubKey($guid)
        if (-not $sub) { continue }
        $dhcp   = [string]$sub.GetValue('DhcpIPAddress')
        $static = (@($sub.GetValue('IPAddress')) | Where-Object { $_ -and $_ -ne '0.0.0.0' }) -join ''
        $sub.Close()
        if (($dhcp -and $dhcp -ne '0.0.0.0') -or $static) {
            $nagleEntries += @{ Path = "$interfacesRoot\$guid"; Name = 'TcpAckFrequency'; Value = 1; Default = $null }
            $nagleEntries += @{ Path = "$interfacesRoot\$guid"; Name = 'TCPNoDelay'; Value = 1; Default = $null }
        }
    }
    $interfacesKey.Close()
}

Register-VTweak @{
    Id = 'net.nagle'; Category = 'network'; Recommended = $true
    Name = 'Desativar algoritmo de Nagle'
    Description = 'Envia pacotes TCP imediatamente em vez de agrupá-los. Reduz a latência em jogos que usam TCP (MMOs, alguns MOBAs). Aplicado em todas as interfaces de rede ativas.'
    Registry = $nagleEntries
}
