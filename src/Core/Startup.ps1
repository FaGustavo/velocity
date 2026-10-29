# ============================================================
#  Velocity · Programas de inicialização
#  Usa as mesmas chaves StartupApproved do Gerenciador de Tarefas,
#  então nada é apagado: os itens são apenas ativados/desativados.
# ============================================================

function Get-VStartupSources {
    $cu = 'HKCU\Software\Microsoft\Windows\CurrentVersion'
    $lm = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion'
    @(
        @{ Kind = 'Registry'; Path = "$cu\Run"; Approved = "$cu\Explorer\StartupApproved\Run"; Scope = 'Usuário atual' }
        @{ Kind = 'Registry'; Path = "$lm\Run"; Approved = "$lm\Explorer\StartupApproved\Run"; Scope = 'Todos os usuários' }
        @{ Kind = 'Registry'; Path = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "$lm\Explorer\StartupApproved\Run32"; Scope = 'Todos os usuários (32 bits)' }
        @{ Kind = 'Folder'; Path = [Environment]::GetFolderPath('Startup'); Approved = "$cu\Explorer\StartupApproved\StartupFolder"; Scope = 'Pasta Inicializar' }
        @{ Kind = 'Folder'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "$lm\Explorer\StartupApproved\StartupFolder"; Scope = 'Pasta Inicializar (todos)' }
    )
}

function Get-VStartupItems {
    foreach ($src in Get-VStartupSources) {
        $items = @()
        if ($src.Kind -eq 'Registry') {
            $key = Get-VRegKey $src.Path
            if (-not $key) { continue }
            foreach ($n in $key.GetValueNames()) {
                if ($n) { $items += @{ Name = $n; Display = $n; Command = [string]$key.GetValue($n) } }
            }
            $key.Close()
        } elseif ($src.Path -and (Test-Path -LiteralPath $src.Path)) {
            foreach ($f in Get-ChildItem -LiteralPath $src.Path -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
                $items += @{ Name = $f.Name; Display = [IO.Path]::GetFileNameWithoutExtension($f.Name); Command = $f.FullName }
            }
        }
        foreach ($it in $items) {
            $a = Get-VRegValue $src.Approved $it.Name
            $enabled = $true
            if ($a.Exists -and $a.Kind -eq 'Binary' -and @($a.Value).Count -gt 0) { $enabled = (([byte[]]$a.Value)[0] -band 1) -eq 0 }
            [pscustomobject]@{
                Name     = $it.Name
                Display  = $it.Display
                Command  = $it.Command
                Scope    = $src.Scope
                Approved = $src.Approved
                Enabled  = $enabled
            }
        }
    }
}

function Set-VStartupItem($Item, [bool]$Enabled) {
    $bytes = New-Object byte[] 12
    if ($Enabled) { $bytes[0] = 2 }
    else {
        $bytes[0] = 3
        [Array]::Copy([BitConverter]::GetBytes([DateTime]::Now.ToFileTime()), 0, $bytes, 4, 8)
    }
    Set-VRegValue $Item.Approved $Item.Name $bytes 'Binary'
    Write-VLog ("Inicialização '{0}' {1}." -f $Item.Display, $(if ($Enabled) { 'ativada' } else { 'desativada' }))
}
