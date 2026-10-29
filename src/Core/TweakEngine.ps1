# ============================================================
#  Velocity · Motor de otimizações
#
#  Uma otimização é declarada com Register-VTweak:
#    Id, Category, Name, Description
#    Risk            'Baixo' | 'Médio' | 'Alto'
#    Recommended     entra no "Otimizar (recomendado)"
#    RequiresReboot
#    Registry        @( @{ Path; Name; Value; Type='DWord'; Default } )
#                    Value $null = remover valor. Default = valor usado ao
#                    reverter quando não há backup ($null = remover).
#                    Também aceita um scriptblock que gera as entradas sob
#                    demanda (ex.: depende do hardware detectado).
#    Services        @( @{ Name; Start (2 auto/3 manual/4 desativado); Default } )
#    MinBuild        build mínima do Windows (ex.: 22000 = Windows 11);
#                    em sistemas mais antigos a otimização nem é exibida
#    Apply / Revert / Test   scriptblocks opcionais para lógica própria
# ============================================================

$global:VelocityWindowsBuild = [int](Get-VRegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'CurrentBuild').Value

$global:VelocityCategories = [ordered]@{}
$global:VelocityTweaks     = [ordered]@{}
$global:VelocityActions    = [ordered]@{}

function Register-VCategory([hashtable]$Definition) {
    $global:VelocityCategories[$Definition.Id] = $Definition
}

function Register-VAction([hashtable]$Definition) {
    $global:VelocityActions[$Definition.Id] = $Definition
}

function Register-VTweak([hashtable]$Definition) {
    if ($Definition.MinBuild -and $global:VelocityWindowsBuild -lt $Definition.MinBuild) { return }
    $t = @{ Risk = 'Baixo'; Recommended = $false; RequiresReboot = $false; Registry = @(); Services = @(); Apply = $null; Revert = $null; Test = $null }
    foreach ($k in $Definition.Keys) { $t[$k] = $Definition[$k] }

    $global:VelocityTweaks[$t.Id] = $t
}

# Resolve (uma vez) a lista final de entradas: registro + serviços
#  Retorna as entradas enumeradas (uma por vez). Não usar "return ," aqui:
#  em `foreach ($e in Get-VTweakEntries $t)` isso entregaria o array inteiro como um único item.
function Get-VTweakEntries([hashtable]$Tweak) {
    if ($Tweak.ContainsKey('Entries')) { return $Tweak.Entries }
    $entries = New-Object System.Collections.ArrayList
    $registry = $Tweak.Registry
    if ($registry -is [scriptblock]) {
        try { $registry = & $registry } catch { Write-VLog "Falha ao detectar entradas de '$($Tweak.Id)': $($_.Exception.Message)" 'WARN'; $registry = @() }
    }
    foreach ($e in @($registry)) { if ($e) { [void]$entries.Add($e) } }
    foreach ($s in @($Tweak.Services)) {
        if (-not $s) { continue }
        [void]$entries.Add(@{
            Path = "HKLM\SYSTEM\CurrentControlSet\Services\$($s.Name)"; Name = 'Start'; Type = 'DWord'
            Value = $s.Start; Default = $s.Default; SkipIfKeyMissing = $true; Service = $s.Name
        })
    }
    foreach ($e in $entries) { if (-not $e.Type) { $e.Type = 'DWord' } }
    $Tweak.Entries = $entries.ToArray()
    return $Tweak.Entries
}

function Test-VEntrySkipped([hashtable]$Entry) {
    $Entry.SkipIfKeyMissing -and -not (Test-VRegKey $Entry.Path)
}

function Get-VTweakState([string]$Id) {
    $t = $global:VelocityTweaks[$Id]
    if (-not $t) { return $false }
    try {
        $entries = @(Get-VTweakEntries $t)
        if ($entries.Count -eq 0 -and -not $t.Test) { return $false }
        foreach ($e in $entries) {
            if (Test-VEntrySkipped $e) { continue }
            $cur = Get-VRegValue $e.Path $e.Name
            if ($null -eq $e.Value) {
                if ($cur.Exists) { return $false }
                continue
            }
            if (-not $cur.Exists) { return $false }
            if ((ConvertTo-VComparable $cur.Value $cur.Kind) -ne (ConvertTo-VComparable $e.Value $e.Type)) { return $false }
        }
        if ($t.Test) { return [bool](& $t.Test) }
        return $true
    } catch {
        Write-VLog "Falha ao verificar '$Id': $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Invoke-VTweak([string]$Id) {
    $t = $global:VelocityTweaks[$Id]
    $errors = @()
    foreach ($e in Get-VTweakEntries $t) {
        try {
            if (Test-VEntrySkipped $e) { continue }
            Save-VRegBackup $Id $e.Path $e.Name
            if ($null -eq $e.Value) { Remove-VRegValue $e.Path $e.Name }
            else { Set-VRegValue $e.Path $e.Name $e.Value $e.Type }
            if ($e.Service -and $e.Value -eq 4) { Stop-Service -Name $e.Service -Force -ErrorAction SilentlyContinue }
        } catch { $errors += "$($e.Name): $($_.Exception.Message)" }
    }
    if ($t.Apply) {
        try { $null = & $t.Apply } catch { $errors += $_.Exception.Message }
    }
    try { Set-VBackupEntry "#applied|$Id" $true -Overwrite } catch { }
    New-VTweakResult $t 'aplicado' $errors
}

function Undo-VTweak([string]$Id) {
    $t = $global:VelocityTweaks[$Id]
    $errors = @()
    foreach ($e in Get-VTweakEntries $t) {
        try {
            if (Test-VEntrySkipped $e) { continue }
            $restored = Restore-VRegBackup $Id $e.Path $e.Name
            if (-not $restored -and $e.ContainsKey('Default')) {
                if ($null -eq $e.Default) { Remove-VRegValue $e.Path $e.Name }
                else { Set-VRegValue $e.Path $e.Name $e.Default $e.Type }
            }
            if ($e.Service -and (Get-VRegValue $e.Path 'Start').Value -eq 2) {
                Start-Service -Name $e.Service -ErrorAction SilentlyContinue
            }
        } catch { $errors += "$($e.Name): $($_.Exception.Message)" }
    }
    if ($t.Revert) {
        try { $null = & $t.Revert } catch { $errors += $_.Exception.Message }
    }
    if ($errors.Count -eq 0) { try { Remove-VBackupEntry "#applied|$Id" } catch { } }
    New-VTweakResult $t 'revertido' $errors
}

function New-VTweakResult([hashtable]$Tweak, [string]$Verb, [string[]]$Errors) {
    if ($Errors.Count -eq 0) {
        Write-VLog "'$($Tweak.Name)' $Verb."
        return @{ Id = $Tweak.Id; Success = $true; Message = "'$($Tweak.Name)' $Verb com sucesso." }
    }
    $detail = $Errors -join '; '
    Write-VLog "'$($Tweak.Name)' $Verb com erros: $detail" 'ERROR'
    return @{ Id = $Tweak.Id; Success = $false; Message = "'$($Tweak.Name)': $detail" }
}

function Invoke-VAction([string]$Id) {
    $a = $global:VelocityActions[$Id]
    try {
        $msg = (& $a.Run | Out-String).Trim()
        Write-VLog "Ação '$($a.Name)': $msg"
        return @{ Id = $Id; Name = $a.Name; Success = $true; Message = $msg }
    } catch {
        Write-VLog "Ação '$($a.Name)' falhou: $($_.Exception.Message)" 'ERROR'
        return @{ Id = $Id; Name = $a.Name; Success = $false; Message = $_.Exception.Message }
    }
}
