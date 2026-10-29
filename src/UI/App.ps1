# ============================================================
#  Velocity · Camada de interface (WPF), estilo Apple
#  Toda operação que altera o sistema roda num runspace separado
#  para a janela nunca congelar.
# ============================================================

$script:States       = @{}
$script:Owned        = @{}
$script:CurrentPage  = 'dashboard'
$script:LastPage     = $null
$script:NavButtons   = @{}
$script:DialogAction = $null
$script:PendingIds   = @()
$script:StartupItems = @()
$script:XmlNs        = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'

# ------------------------------------------------------------
#  Paleta (cores de sistema da Apple, modo claro e escuro)
# ------------------------------------------------------------
$script:Palettes = @{
    dark = @{
        Bg = '1C1C1E'; Sidebar = '252527'; Group = '2C2C2E'; GroupBorder = '38383B'; Hover = '17FFFFFF'
        Fill = '3A3A3C'; Separator = '3A3A3D'; Elevated = '303033'; Control = '414145'; ControlBorder = '505055'
        Text = 'F5F5F7'; Secondary = '98989F'; Tertiary = '6E6E73'
        Accent = '0A84FF'; AccentPressed = '0A6AD6'; Green = '30D158'; Orange = 'FF9F0A'; Red = 'FF453A'; RedPressed = 'D93A31'
        Teal = '64D2FF'; Indigo = '5E5CE6'; Purple = 'BF5AF2'; Pink = 'FF375F'; Gray = '8E8E93'
        SwitchOff = '48484C'; Scrim = '80000000'; WarnText = 'FFC266'
    }
    light = @{
        Bg = 'F5F5F7'; Sidebar = 'EAEAEC'; Group = 'FFFFFF'; GroupBorder = 'E2E2E6'; Hover = '10000000'
        Fill = 'E8E8ED'; Separator = 'E5E5EA'; Elevated = 'FFFFFF'; Control = 'FFFFFF'; ControlBorder = 'D1D1D6'
        Text = '1D1D1F'; Secondary = '6E6E73'; Tertiary = 'AEAEB2'
        Accent = '007AFF'; AccentPressed = '0062CC'; Green = '34C759'; Orange = 'FF9500'; Red = 'FF3B30'; RedPressed = 'D70015'
        Teal = '5AC8FA'; Indigo = '5856D6'; Purple = 'AF52DE'; Pink = 'FF2D55'; Gray = '8E8E93'
        SwitchOff = 'E2E2E7'; Scrim = '40000000'; WarnText = '9A5B00'
    }
}

# Segue o tema do Windows. Dá para forçar com "Theme": "light"/"dark" em settings.json
# (ou com a variável de ambiente VELOCITY_THEME, útil para testar).
function Get-VThemeMode {
    $mode = [string]$env:VELOCITY_THEME
    if ($mode -notin 'light', 'dark') { $mode = [string](Get-VSettings)['Theme'] }
    if ($mode -notin 'light', 'dark') {
        $v = Get-VRegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
        $mode = $(if ($v.Exists -and [int]$v.Value -eq 1) { 'light' } else { 'dark' })
    }
    return $mode
}

$script:ThemeMode = Get-VThemeMode
$script:Palette   = $script:Palettes[$script:ThemeMode]

function Get-VColor([string]$Name, [string]$Alpha) {
    $hex = $script:Palette[$Name]
    if (-not $hex) { throw "A cor '$Name' não existe na paleta." }
    $hex = $hex.Substring($hex.Length - 6)
    if ($Alpha) { return "#$Alpha$hex" }
    return '#' + $script:Palette[$Name]
}

# Troca os marcadores de cor do tema (nome entre sinais de porcentagem) pelas cores reais
function Expand-VTheme([string]$Xaml) {
    [regex]::Replace($Xaml, '%(\w+)(?:@([0-9A-Fa-f]{2}))?%', {
        param($m)
        Get-VColor $m.Groups[1].Value $(if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '' })
    })
}

# Cor de cada seção (como os ícones coloridos dos Ajustes do macOS)
$script:Tints = @{
    dashboard = 'Accent'; perf = 'Orange'; games = 'Purple'; network = 'Green'; services = 'Gray'
    visual = 'Pink'; deep = 'Red'; startup = 'Indigo'; tools = 'Teal'
}
function Get-VTint([string]$Key) {
    $name = $script:Tints[$Key]
    if (-not $name) { $name = 'Accent' }
    Get-VColor $name
}

# ------------------------------------------------------------
#  Utilitários de XAML
# ------------------------------------------------------------
function ConvertTo-XamlText([string]$Text) {
    if (-not $Text) { return '' }
    $s = [System.Security.SecurityElement]::Escape($Text)
    # Um texto que começa com "{" seria lido como extensão de marcação ({Binding}...) e quebraria a página
    if ($s.StartsWith('{')) { $s = '{}' + $s }
    return $s
}
function New-XamlElement([string]$Xaml) { [Windows.Markup.XamlReader]::Parse($Xaml) }
function Read-UiFile([string]$Name) { [IO.File]::ReadAllText((Join-Path $global:VelocityRoot "UI\$Name")) }

function New-TileXaml([string]$Icon, [string]$Color, [int]$Size = 26, [double]$FontSize = 13) {
    $radius = [math]::Round($Size * 0.24)
    "<Border Width=""$Size"" Height=""$Size"" CornerRadius=""$radius"" Background=""$Color"" VerticalAlignment=""Center"" HorizontalAlignment=""Left"">" +
    "<TextBlock Text=""&#x$Icon;"" FontFamily=""{StaticResource IconFont}"" FontSize=""$FontSize"" Foreground=""White"" HorizontalAlignment=""Center"" VerticalAlignment=""Center""/></Border>"
}

function New-Separator([int]$Inset = 16) {
    New-XamlElement "<Border $script:XmlNs Height=""1"" Background=""{StaticResource SeparatorBrush}"" Margin=""$Inset,0,0,0""/>"
}

# Preenche um grupo com linhas separadas por filetes recuados
function Set-GroupRows($Panel, [object[]]$Rows, [int]$Inset = 16) {
    $Panel.Children.Clear()
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($i -gt 0 -and $Inset -ge 0) { [void]$Panel.Children.Add((New-Separator $Inset)) }
        [void]$Panel.Children.Add($Rows[$i])
    }
}

# ------------------------------------------------------------
#  Aplicação e janela
# ------------------------------------------------------------
$script:App = New-Object System.Windows.Application
$script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$script:App.Resources.MergedDictionaries.Add((New-XamlElement (Expand-VTheme (Read-UiFile 'Theme.xaml'))))

$windowXaml    = Expand-VTheme (Read-UiFile 'MainWindow.xaml')
$script:Window = New-XamlElement $windowXaml
$script:UI     = @{}
foreach ($m in [regex]::Matches($windowXaml, 'x:Name="(\w+)"')) {
    $script:UI[$m.Groups[1].Value] = $script:Window.FindName($m.Groups[1].Value)
}

# ------------------------------------------------------------
#  Movimento
#  Curva exponencial de saída ≈ mola criticamente amortecida: começa
#  rápido e assenta sem quicar. Toda animação parte do valor atual da
#  tela, então pode ser interrompida e invertida a qualquer momento.
#  Com "Mostrar animações" desligado no Windows, só há esmaecimentos curtos.
# ------------------------------------------------------------
$script:Motion = [System.Windows.SystemParameters]::ClientAreaAnimation
$script:Ease = New-Object System.Windows.Media.Animation.ExponentialEase
$script:Ease.EasingMode = 'EaseOut'
$script:Ease.Exponent = 6
$script:Ease.Freeze()

$script:OpacityProp = [System.Windows.UIElement]::OpacityProperty
$script:ScaleXProp  = [System.Windows.Media.ScaleTransform]::ScaleXProperty
$script:ScaleYProp  = [System.Windows.Media.ScaleTransform]::ScaleYProperty

function Start-VAnim {
    param($Target, [System.Windows.DependencyProperty]$Property, [double]$To, [int]$Ms = 320, $From = $null, [scriptblock]$OnDone)
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $To
    if ($null -ne $From) { $a.From = [double]$From }
    $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    $a.EasingFunction = $script:Ease
    if ($OnDone) { $a.Add_Completed($OnDone) }
    $Target.BeginAnimation($Property, $a)
}

function Set-VScale($Transform, [double]$To, [int]$Ms) {
    Start-VAnim $Transform $script:ScaleXProp $To $Ms
    Start-VAnim $Transform $script:ScaleYProp $To $Ms
}

# Sem animações: os cartões já começam no tamanho final
if (-not $script:Motion) {
    foreach ($card in 'BusyCard', 'DialogCard') { $script:UI[$card].RenderTransform = New-Object System.Windows.Media.ScaleTransform 1, 1 }
}

# --- Fundo desfocado atrás de diálogos ("escurecer para focar")
function Set-VBackdrop([bool]$On) {
    $root = $script:UI.ContentRoot
    $radius = [System.Windows.Media.Effects.BlurEffect]::RadiusProperty
    if ($On) {
        if (-not ($root.Effect -is [System.Windows.Media.Effects.BlurEffect])) {
            $blur = New-Object System.Windows.Media.Effects.BlurEffect
            $blur.Radius = 0
            $blur.RenderingBias = 'Performance'
            $root.Effect = $blur
        }
        if ($script:Motion) { Start-VAnim $root.Effect $radius 10 300 }
        else { $root.Effect.BeginAnimation($radius, $null); $root.Effect.Radius = 10 }
    } elseif ($root.Effect) {
        if ($script:Motion) {
            Start-VAnim $root.Effect $radius 0 200 -OnDone { if (-not (Test-VOverlayOpen)) { $script:UI.ContentRoot.Effect = $null } }
        } else { $root.Effect = $null }
    }
}

# --- Sobreposições (processando / diálogo)
$script:OverlayCards   = @{ BusyOverlay = 'BusyCard'; DialogOverlay = 'DialogCard' }
$script:OverlayGen     = @{ BusyOverlay = 0; DialogOverlay = 0 }
$script:OverlayClosing = @{}

function Test-VOverlayOpen([string]$Except) {
    foreach ($n in $script:OverlayCards.Keys) {
        if ($n -eq $Except) { continue }
        if ($script:UI[$n].Visibility -eq 'Visible' -and -not $script:OverlayClosing.ContainsKey($n)) { return $true }
    }
    return $false
}

function Open-VOverlay([string]$Name) {
    $script:OverlayGen[$Name]++
    $script:OverlayClosing.Remove($Name)
    $overlay = $script:UI[$Name]
    $card = $script:UI[$script:OverlayCards[$Name]]
    $overlay.Visibility = 'Visible'
    if ($script:Motion) {
        Start-VAnim $overlay $script:OpacityProp 1 220
        Set-VScale $card.RenderTransform 1 420
    } else {
        Start-VAnim $overlay $script:OpacityProp 1 120
    }
    Set-VBackdrop $true
}

function Close-VOverlay([string]$Name) {
    $overlay = $script:UI[$Name]
    if ($overlay.Visibility -ne 'Visible' -or $script:OverlayClosing.ContainsKey($Name)) { return }
    $script:OverlayClosing[$Name] = $script:OverlayGen[$Name]
    if ($script:Motion) { Set-VScale $script:UI[$script:OverlayCards[$Name]].RenderTransform 0.97 180 }
    Start-VAnim $overlay $script:OpacityProp 0 $(if ($script:Motion) { 170 } else { 100 }) -OnDone { Complete-VOverlayClose }
    if (-not (Test-VOverlayOpen -Except $Name)) { Set-VBackdrop $false }
}

function Complete-VOverlayClose {
    foreach ($n in @($script:OverlayClosing.Keys)) {
        # Se a sobreposição foi reaberta no meio do fechamento, ela fica aberta
        if ($script:OverlayClosing[$n] -ne $script:OverlayGen[$n]) { continue }
        $script:UI[$n].Visibility = 'Collapsed'
        if ($script:Motion) {
            $t = $script:UI[$script:OverlayCards[$n]].RenderTransform
            $t.BeginAnimation($script:ScaleXProp, $null); $t.BeginAnimation($script:ScaleYProp, $null)   # volta a 0.94 para a próxima abertura
        }
        $script:OverlayClosing.Remove($n)
    }
}

# --- Indicador de atividade: só gira enquanto está visível
function Start-VSpinner {
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    for ($i = 0; $i -lt 8; $i++) {
        [void]$anim.KeyFrames.Add([System.Windows.Media.Animation.DiscreteDoubleKeyFrame]::new([double]($i * 45), [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($i * 100))))
    }
    $anim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(800))
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $script:UI.SpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $anim)
}
function Stop-VSpinner { $script:UI.SpinnerRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null) }

# ------------------------------------------------------------
#  Execução em segundo plano
# ------------------------------------------------------------
$script:Worker = {
    param($Root, $Operation, $Arguments)
    . (Join-Path $Root 'Core\Loader.ps1') -Root $Root

    function Out-TweakResult([hashtable]$Result) {
        $Result.Applied = Get-VTweakState -Id $Result.Id
        $Result.Owned   = @(Get-VOwnedTweakIds) -contains $Result.Id
        $Result.Name    = $global:VelocityTweaks[$Result.Id].Name
        [pscustomobject]$Result
    }

    switch ($Operation) {
        'apply' {
            if ($Arguments.RestorePoint) { [pscustomobject]((New-VRestorePoint) + @{ Id = 'restore' }) }
            foreach ($id in $Arguments.Ids) { Out-TweakResult (Invoke-VTweak -Id $id) }
        }
        'revert'  { foreach ($id in $Arguments.Ids) { Out-TweakResult (Undo-VTweak -Id $id) } }
        'action'  { [pscustomobject](Invoke-VAction -Id $Arguments.Id) }
        'sysinfo' { Get-VSystemInfo }
        'states'  {
            $owned = @(try { Get-VOwnedTweakIds } catch { })
            foreach ($id in $global:VelocityTweaks.Keys) { [pscustomobject]@{ Id = $id; Applied = (Get-VTweakState -Id $id); Owned = ($owned -contains $id) } }
        }
    }
}

function Invoke-Background {
    param([string]$Operation, [hashtable]$Arguments = @{}, [scriptblock]$OnComplete, $Context)
    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:Worker.ToString()).AddArgument($global:VelocityRoot).AddArgument($Operation).AddArgument($Arguments)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Tag = @{ PS = $ps; Handle = $ps.BeginInvoke(); OnComplete = $OnComplete; Context = $Context }
    $timer.Add_Tick({
        param($sender, $e)
        $job = $sender.Tag
        if (-not $job.Handle.IsCompleted) { return }
        $sender.Stop()
        $results = @()
        try {
            $results = @($job.PS.EndInvoke($job.Handle))
            foreach ($err in $job.PS.Streams.Error) { Write-VLog "Worker: $err" 'ERROR' }
        } catch {
            Write-VLog "Worker falhou: $($_.Exception.Message)" 'ERROR'
            $results = @([pscustomobject]@{ Id = ''; Name = 'Erro interno'; Success = $false; Message = $_.Exception.Message })
        } finally { $job.PS.Dispose() }
        if ($job.OnComplete) { & $job.OnComplete $results $job.Context }
    })
    $timer.Start()
}

# ------------------------------------------------------------
#  Status, carregamento e diálogos
# ------------------------------------------------------------
function Set-Status([string]$Text, [string]$Kind = 'info') {
    $brush = switch ($Kind) { 'ok' { 'OkBrush' } 'warn' { 'WarnBrush' } 'error' { 'DangerBrush' } default { 'AccentBrush' } }
    $script:UI.StatusDot.Fill = $script:Window.FindResource($brush)
    $script:UI.StatusText.Text = $Text
}

function Show-Busy([string]$Text) {
    $script:UI.BusyText.Text = $Text
    Open-VOverlay 'BusyOverlay'
    Start-VSpinner
}

function Hide-Busy {
    Close-VOverlay 'BusyOverlay'
    Stop-VSpinner
}

# Tom do diálogo: info (ícone do app), ok (verde), warn (laranja), danger (vermelho)
function Show-Dialog {
    param([string]$Title, [string]$Message, [string]$OkText = 'OK', [string]$CancelText = 'Cancelar',
          [scriptblock]$OnOk, [switch]$Info, [switch]$Danger, [string]$Tone)
    if (-not $Tone) { $Tone = $(if ($Danger) { 'danger' } else { 'info' }) }
    $icon, $tile = switch ($Tone) {
        'ok'     { 'E73E', (Get-VColor 'Green') }
        'warn'   { 'E7BA', (Get-VColor 'Orange') }
        'danger' { 'E7BA', (Get-VColor 'Red') }
        default  { 'E945', $null }
    }
    $script:UI.DialogIcon.Text = [string][char][Convert]::ToInt32($icon, 16)
    if ($tile) { $script:UI.DialogIconTile.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($tile)) }
    else { $script:UI.DialogIconTile.Background = $script:Window.FindResource('AppIconBrush') }

    $script:UI.DialogTitle.Text = $Title
    $script:UI.DialogText.Text = $Message
    # Mensagens curtas centralizadas, como um alerta do macOS; listas longas alinhadas à esquerda
    $script:UI.DialogText.TextAlignment = $(if ($Message.Length -le 160 -and $Message -notmatch "`n") { 'Center' } else { 'Left' })
    $script:UI.DialogOk.Content = $OkText
    $script:UI.DialogCancel.Content = $CancelText
    $script:UI.DialogCancel.Visibility = $(if ($Info) { 'Collapsed' } else { 'Visible' })
    $script:UI.DialogOk.Margin = $(if ($Info) { [System.Windows.Thickness]::new(0) } else { [System.Windows.Thickness]::new(5, 0, 0, 0) })
    $script:UI.DialogOk.Style = $script:Window.FindResource($(if ($Danger) { 'DangerButton' } else { 'PrimaryButton' }))
    $script:DialogAction = $OnOk
    Open-VOverlay 'DialogOverlay'
}

# ------------------------------------------------------------
#  Estado das otimizações
# ------------------------------------------------------------
function Get-CategoryTweaks([string]$CategoryId) {
    @($global:VelocityTweaks.Values | Where-Object { $_.Category -eq $CategoryId })
}

function Get-TweakIds([scriptblock]$Filter) {
    @($global:VelocityTweaks.Values | Where-Object $Filter | ForEach-Object { $_.Id })
}

function Test-Ready {
    if ($script:StatesLoaded) { return $true }
    Set-Status 'Aguarde: o Velocity ainda está analisando o sistema...' 'warn'
    return $false
}

function Update-AllStates {
    Set-Status 'Analisando o estado atual do sistema...'
    Invoke-Background -Operation 'states' -OnComplete {
        param($results, $ctx)
        foreach ($r in $results) {
            if (-not $r.Id) { continue }
            $script:States[[string]$r.Id] = [bool]$r.Applied
            $script:Owned[[string]$r.Id] = [bool]$r.Owned
        }
        $script:StatesLoaded = $true
        Show-Page $script:CurrentPage
        Set-Status 'Pronto. Escolha uma categoria ou use "Otimizar".' 'ok'
    }
}

function Register-Result($Result) {
    $id = [string]$Result.Id
    if ($id -and $global:VelocityTweaks.Contains($id)) {
        $script:States[$id] = [bool]$Result.Applied
        $script:Owned[$id] = [bool]$Result.Owned
        if ($Result.Success -and $global:VelocityTweaks[$id].RequiresReboot) { $script:UI.RebootPill.Visibility = 'Visible' }
    }
}

function Start-TweakBatch {
    param([string]$Operation, [string[]]$Ids, [string]$BusyText, [bool]$RestorePoint = $false)
    Show-Busy $BusyText
    Set-Status $BusyText
    Invoke-Background -Operation $Operation -Arguments @{ Ids = $Ids; RestorePoint = $RestorePoint } -OnComplete {
        param($results, $ctx)
        Hide-Busy
        $ok = 0; $failed = @(); $notes = @()
        foreach ($r in $results) {
            if ($r.Id -eq 'restore') { $notes += $r.Message; continue }
            Register-Result $r
            if ($r.Success) { $ok++ } else { $failed += "• $($r.Message)" }
        }
        Show-Page $script:CurrentPage
        Update-SystemInfo

        $total = @($results | Where-Object { $_.Id -ne 'restore' }).Count
        $msg = "$ok de $total alterações concluídas com sucesso."
        if ($notes) { $msg = ($notes -join "`n") + "`n`n" + $msg }
        if ($failed) { $msg += "`n`nCom problemas:`n" + ($failed -join "`n") }
        if ($script:UI.RebootPill.Visibility -eq 'Visible') { $msg += "`n`nAlgumas alterações só terão efeito completo depois de reiniciar o PC." }
        Show-Dialog -Title $(if ($failed) { 'Concluído com avisos' } else { 'Tudo pronto' }) -Message $msg -Info -Tone $(if ($failed) { 'warn' } else { 'ok' })
        Set-Status "Operação concluída: $ok com sucesso, $($failed.Count) com problemas." $(if ($failed) { 'warn' } else { 'ok' })
    }
}

# ------------------------------------------------------------
#  Navegação
# ------------------------------------------------------------
function Add-NavHeader([string]$Text) {
    [void]$script:UI.NavPanel.Children.Add((New-XamlElement "<TextBlock $script:XmlNs Text=""$(ConvertTo-XamlText $Text)"" FontSize=""11"" FontWeight=""SemiBold"" Foreground=""{StaticResource TertiaryBrush}"" Margin=""9,18,0,5""/>"))
}

function Add-NavItem([string]$Key, [string]$Label, [string]$Icon) {
    $rb = New-XamlElement @"
<RadioButton $script:XmlNs Style="{StaticResource NavButton}" GroupName="Nav" Tag="$Key">
  <StackPanel Orientation="Horizontal">
    $(New-TileXaml $Icon (Get-VTint $Key) 22 11)
    <TextBlock Text="$(ConvertTo-XamlText $Label)" FontSize="13" Margin="9,0,0,0" VerticalAlignment="Center"/>
  </StackPanel>
</RadioButton>
"@
    $rb.Add_Checked({ param($s, $e) Show-Page ([string]$s.Tag) })
    $script:NavButtons[$Key] = $rb
    [void]$script:UI.NavPanel.Children.Add($rb)
}

function Select-Nav([string]$Key) { $script:NavButtons[$Key].IsChecked = $true }

function Show-Page([string]$Key) {
    $animate = $Key -ne $script:LastPage
    $script:CurrentPage = $Key
    $script:LastPage = $Key
    foreach ($p in 'PageDashboard', 'PageTweaks', 'PageStartup', 'PageTools') { $script:UI[$p].Visibility = 'Collapsed' }
    switch ($Key) {
        'dashboard' { Update-Dashboard; $page = $script:UI.PageDashboard }
        'startup'   { Show-StartupItems; $page = $script:UI.PageStartup }
        'tools'     { $page = $script:UI.PageTools }
        default     { Show-Category $Key; $page = $script:UI.PageTweaks }
    }
    $page.Visibility = 'Visible'
    if (-not $animate) { return }   # atualizar a mesma página não deve piscar
    if ($script:Motion) {
        # A página entra subindo levemente, já no rumo do conteúdo
        $page.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0, 12)
        Start-VAnim $page.RenderTransform ([System.Windows.Media.TranslateTransform]::YProperty) 0 420
        Start-VAnim $page $script:OpacityProp 1 260 -From 0
    } else {
        Start-VAnim $page $script:OpacityProp 1 140 -From 0
    }
}

# ------------------------------------------------------------
#  Painel
# ------------------------------------------------------------

# Desenha o anel (estilo Atividade) para um valor de 0 a 100
function Update-Ring([double]$Value) {
    $c = 68.0; $r = 61.0
    $path = $script:UI.RingArc
    if ($Value -le 0.05) { $path.Data = $null; return }
    if ($Value -ge 99.95) { $path.Data = [System.Windows.Media.EllipseGeometry]::new([System.Windows.Point]::new($c, $c), $r, $r); return }
    $angle = $Value / 100.0 * 2 * [math]::PI
    $end = [System.Windows.Point]::new($c + $r * [math]::Sin($angle), $c - $r * [math]::Cos($angle))
    $figure = New-Object System.Windows.Media.PathFigure
    $figure.StartPoint = [System.Windows.Point]::new($c, $c - $r)
    $figure.IsClosed = $false
    [void]$figure.Segments.Add([System.Windows.Media.ArcSegment]::new($end, [System.Windows.Size]::new($r, $r), 0.0, [bool]($Value -gt 50), [System.Windows.Media.SweepDirection]::Clockwise, $true))
    $geometry = New-Object System.Windows.Media.PathGeometry
    [void]$geometry.Figures.Add($figure)
    $path.Data = $geometry
}

$script:UI.ScoreBar.Add_ValueChanged({ Update-Ring $script:UI.ScoreBar.Value })

function Update-Dashboard {
    $all   = @($global:VelocityTweaks.Values)
    $rec   = @($all | Where-Object { $_.Recommended })
    $recOn = @($rec | Where-Object { $script:States[$_.Id] }).Count
    $allOn = @($all | Where-Object { $script:States[$_.Id] }).Count
    $pct   = 0
    if ($rec.Count) { $pct = [int][math]::Round($recOn * 100 / $rec.Count) }

    if (-not $script:StatesLoaded) {
        $script:UI.ScoreText.Text = '—'
        $script:UI.ScoreLabel.Text = 'Analisando...'
        $script:UI.ScoreDetail.Text = 'Verificando o estado atual do seu Windows.'
        $pct = 0
    } else {
        $label, $color = switch ($pct) {
            { $_ -ge 100 } { 'Otimizado', 'Green'; break }
            { $_ -ge 60 }  { 'Bom', 'Accent'; break }
            { $_ -ge 25 }  { 'Pode melhorar', 'Orange'; break }
            default        { 'Não otimizado', 'Red' }
        }
        $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString((Get-VColor $color)))
        $script:UI.ScoreText.Text = "$pct%"
        $script:UI.ScoreLabel.Text = $label
        $script:UI.ScoreLabel.Foreground = $brush
        $script:UI.RingArc.Stroke = $brush
        $script:UI.ScoreDetail.Text = "$recOn de $($rec.Count) otimizações recomendadas ativas · $allOn de $($all.Count) no total."
    }

    # O anel cresce a partir de onde está agora (pode ser interrompido por outra atualização)
    if ($script:Motion) { Start-VAnim $script:UI.ScoreBar ([System.Windows.Controls.ProgressBar]::ValueProperty) $pct 900 }
    else {
        $script:UI.ScoreBar.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $null)
        $script:UI.ScoreBar.Value = $pct
        Update-Ring $pct
    }

    $rows = foreach ($cat in $global:VelocityCategories.Values) {
        $list = Get-CategoryTweaks $cat.Id
        $on = @($list | Where-Object { $script:States[$_.Id] }).Count
        $p = 0
        if ($list.Count) { $p = [int]($on * 100 / $list.Count) }
        $row = New-XamlElement @"
<Border $script:XmlNs Style="{StaticResource ClickRow}" Tag="$($cat.Id)">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="40"/><ColumnDefinition Width="*"/><ColumnDefinition Width="130"/><ColumnDefinition Width="54"/><ColumnDefinition Width="16"/>
    </Grid.ColumnDefinitions>
    $(New-TileXaml $cat.Icon (Get-VTint $cat.Id) 28 14)
    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="2,0,20,0">
      <TextBlock Text="$(ConvertTo-XamlText $cat.Name)" FontSize="13.5" FontWeight="SemiBold"/>
      <TextBlock Text="$(ConvertTo-XamlText $cat.Description)" Foreground="{StaticResource SecondaryBrush}" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>
    </StackPanel>
    <ProgressBar Grid.Column="2" Style="{StaticResource ScoreBar}" Foreground="$(Get-VTint $cat.Id)" Maximum="100" Value="$p" VerticalAlignment="Center"/>
    <TextBlock Grid.Column="3" Text="$on/$($list.Count)" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{StaticResource SecondaryBrush}"/>
    <TextBlock Grid.Column="4" Text="&#xE76C;" FontFamily="{StaticResource IconFont}" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{StaticResource TertiaryBrush}"/>
  </Grid>
</Border>
"@
        $row.Add_MouseLeftButtonUp({ param($s, $e) Select-Nav ([string]$s.Tag) })
        $row
    }
    Set-GroupRows $script:UI.CategorySummary @($rows) -1
}

function Update-SystemInfo {
    Invoke-Background -Operation 'sysinfo' -OnComplete {
        param($results, $ctx)
        $info = @($results)[0]
        if (-not $info -or -not $info.Cpu) { return }
        $script:UI.StatCpu.Text    = $info.Cpu;   $script:UI.StatCpu.ToolTip = $info.Cpu
        $script:UI.StatCpuSub.Text = $info.CpuDetail
        $script:UI.StatGpu.Text    = $info.Gpu;   $script:UI.StatGpu.ToolTip = $info.Gpu
        $script:UI.StatGpuSub.Text = $info.GpuDetail; $script:UI.StatGpuSub.ToolTip = $info.GpuDetail
        $script:UI.StatRam.Text    = $info.Ram
        $script:UI.StatRamSub.Text = $info.RamDetail
        $script:UI.StatOs.Text     = $info.Os
        $script:UI.StatOsSub.Text  = $info.OsDetail
        $script:UI.StatPower.Text  = $info.Power
        $script:UI.StatBackup.Text = "$($info.BackupCount) valores"
    }
}

# ------------------------------------------------------------
#  Página de categoria
# ------------------------------------------------------------
function New-Badge([string]$Text, [string]$ColorName) {
    $hex = (Get-VColor $ColorName).Substring(1)
    $hex = $hex.Substring($hex.Length - 6)
    "<Border Background=""#24$hex"" CornerRadius=""4"" Padding=""6,1"" Margin=""0,0,6,0""><TextBlock Text=""$(ConvertTo-XamlText $Text)"" FontSize=""11"" FontWeight=""SemiBold"" Foreground=""#$hex""/></Border>"
}

$script:OnTweakToggle = {
    param($sender, $e)
    $tweak = $global:VelocityTweaks[[string]$sender.Tag]
    if ($sender.IsChecked -and $tweak.Risk -eq 'Alto') {
        # Risco alto: só aplica após confirmação explícita
        $sender.IsChecked = $false
        $script:PendingToggle = $sender
        Show-Dialog -Title "Ativar '$($tweak.Name)'?" -OkText 'Ativar' -Danger -Message (
            "Esta é uma otimização de risco alto.`n`n$($tweak.Description)`n`n" +
            'O valor original fica salvo e você pode reverter desligando o botão. Recomendamos criar um ponto de restauração antes (em Ferramentas).') -OnOk {
            $script:PendingToggle.IsChecked = $true
            Invoke-TweakToggle $script:PendingToggle
        }
        return
    }
    Invoke-TweakToggle $sender
}

function Invoke-TweakToggle($Toggle) {
    $id   = [string]$Toggle.Tag
    $want = [bool]$Toggle.IsChecked
    $Toggle.IsEnabled = $false
    Set-Status ('{0}: {1}...' -f $(if ($want) { 'Aplicando' } else { 'Revertendo' }), $global:VelocityTweaks[$id].Name)
    Invoke-Background -Operation $(if ($want) { 'apply' } else { 'revert' }) -Arguments @{ Ids = @($id) } -Context $Toggle -OnComplete {
        param($results, $toggle)
        foreach ($r in $results) {
            Register-Result $r
            Set-Status $r.Message $(if ($r.Success) { 'ok' } else { 'error' })
            if ($r.Id -eq 'perf.powerplan') { Update-SystemInfo }
        }
        $toggle.IsChecked = [bool]$script:States[[string]$toggle.Tag]
        $toggle.IsEnabled = $true
        Update-CategoryHeader
    }
}

function New-TweakRow([hashtable]$Tweak) {
    $badges = ''
    if ($Tweak.Recommended)       { $badges += New-Badge 'Recomendado' 'Accent' }
    if ($Tweak.Risk -eq 'Médio')  { $badges += New-Badge 'Risco médio' 'Orange' }
    if ($Tweak.Risk -eq 'Alto')   { $badges += New-Badge 'Risco alto' 'Red' }
    if ($Tweak.RequiresReboot)    { $badges += New-Badge 'Requer reinício' 'Gray' }
    $badgePanel = $(if ($badges) { "<WrapPanel Margin=""0,8,0,0"">$badges</WrapPanel>" } else { '' })
    $checked = [string][bool]$script:States[$Tweak.Id]
    $row = New-XamlElement @"
<Grid $script:XmlNs Margin="18,14,18,14">
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel Margin="0,0,28,0">
    <TextBlock Text="$(ConvertTo-XamlText $Tweak.Name)" FontSize="13.5" FontWeight="SemiBold"/>
    <TextBlock Text="$(ConvertTo-XamlText $Tweak.Description)" Foreground="{StaticResource SecondaryBrush}" FontSize="12.5" TextWrapping="Wrap" Margin="0,3,0,0" LineHeight="18"/>
    $badgePanel
  </StackPanel>
  <CheckBox Grid.Column="1" Style="{StaticResource ToggleSwitch}" VerticalAlignment="Center" IsChecked="$checked" IsEnabled="$([string][bool]$script:StatesLoaded)" Tag="$(ConvertTo-XamlText $Tweak.Id)"/>
</Grid>
"@
    $row.Children[1].Add_Click($script:OnTweakToggle)
    return $row
}

function Show-Category([string]$CategoryId) {
    $cat = $global:VelocityCategories[$CategoryId]
    $script:UI.CatTitle.Text = $cat.Name
    $script:UI.CatDesc.Text = $cat.Description
    $script:UI.CatWarning.Visibility = $(if ($cat.Warning) { 'Visible' } else { 'Collapsed' })
    $script:UI.CatWarningText.Text = [string]$cat.Warning
    $hasRecommended = @(Get-CategoryTweaks $CategoryId | Where-Object { $_.Recommended }).Count -gt 0
    $script:UI.BtnCatApply.Visibility = $(if ($hasRecommended) { 'Visible' } else { 'Collapsed' })
    $rows = foreach ($t in Get-CategoryTweaks $CategoryId) { New-TweakRow $t }
    Set-GroupRows $script:UI.TweakList @($rows) 18
    Update-CategoryHeader
}

function Update-CategoryHeader {
    if (-not $global:VelocityCategories.Contains($script:CurrentPage)) { return }
    $list = Get-CategoryTweaks $script:CurrentPage
    $on = @($list | Where-Object { $script:States[$_.Id] }).Count
    $script:UI.CatCount.Text = "$on de $($list.Count) ativas"
}

# ------------------------------------------------------------
#  Página de inicialização
# ------------------------------------------------------------
$script:OnStartupToggle = {
    param($sender, $e)
    $item = $script:StartupItems[[int]$sender.Tag]
    $want = [bool]$sender.IsChecked
    try {
        Set-VStartupItem -Item $item -Enabled $want
        $item.Enabled = $want
        Set-Status ("'{0}' {1} na inicialização." -f $item.Display, $(if ($want) { 'ativado' } else { 'desativado' })) 'ok'
    } catch {
        $sender.IsChecked = -not $want
        Set-Status "Falha ao alterar '$($item.Display)': $($_.Exception.Message)" 'error'
    }
    Update-StartupCount
}

function Update-StartupCount {
    $on = @($script:StartupItems | Where-Object { $_.Enabled }).Count
    $script:UI.StartupCount.Text = "$on de $($script:StartupItems.Count) ativos"
}

# Cor estável por nome, para o monograma de cada programa
$script:MonogramColors = 'Accent', 'Green', 'Orange', 'Purple', 'Pink', 'Teal', 'Indigo', 'Red'
function Get-VMonogramColor([string]$Name) {
    $sum = 0
    foreach ($ch in $Name.ToCharArray()) { $sum = ($sum * 31 + [int]$ch) % 9973 }
    Get-VColor $script:MonogramColors[$sum % $script:MonogramColors.Count]
}

function Show-StartupItems {
    $script:StartupItems = @(Get-VStartupItems | Sort-Object Display)
    if ($script:StartupItems.Count -eq 0) {
        Set-GroupRows $script:UI.StartupList @((New-XamlElement "<TextBlock $script:XmlNs Text=""Nenhum programa de inicialização encontrado."" Foreground=""{StaticResource SecondaryBrush}"" Margin=""18,16""/>"))
        Update-StartupCount
        return
    }
    $rows = for ($i = 0; $i -lt $script:StartupItems.Count; $i++) {
        $it = $script:StartupItems[$i]
        $display = ([string]$it.Display).Trim()
        $letter = $(if ($display) { ConvertTo-XamlText $display.Substring(0, 1).ToUpper() } else { '?' })
        $row = New-XamlElement @"
<Grid $script:XmlNs Margin="18,11,18,11">
  <Grid.ColumnDefinitions><ColumnDefinition Width="42"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <Border Width="28" Height="28" CornerRadius="7" Background="$(Get-VMonogramColor $it.Display)" HorizontalAlignment="Left" VerticalAlignment="Center">
    <TextBlock Text="$letter" FontSize="13" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
  <StackPanel Grid.Column="1" Margin="0,0,24,0" VerticalAlignment="Center">
    <StackPanel Orientation="Horizontal">
      <TextBlock Text="$(ConvertTo-XamlText $it.Display)" FontSize="13.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
      <TextBlock Text="$(ConvertTo-XamlText $it.Scope)" FontSize="11.5" Foreground="{StaticResource TertiaryBrush}" Margin="8,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock Text="$(ConvertTo-XamlText $it.Command)" ToolTip="$(ConvertTo-XamlText $it.Command)" Foreground="{StaticResource SecondaryBrush}" FontFamily="Cascadia Mono, Consolas" FontSize="11" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
  </StackPanel>
  <CheckBox Grid.Column="2" Style="{StaticResource ToggleSwitch}" VerticalAlignment="Center" IsChecked="$([string][bool]$it.Enabled)" Tag="$i"/>
</Grid>
"@
        $row.Children[2].Add_Click($script:OnStartupToggle)
        $row
    }
    Set-GroupRows $script:UI.StartupList @($rows) 60
    Update-StartupCount
}

# ------------------------------------------------------------
#  Página de ferramentas
# ------------------------------------------------------------
$script:OnActionClick = {
    param($sender, $e)
    $action = $global:VelocityActions[[string]$sender.Tag]
    if ($action.Confirm) {
        $script:PendingAction = $action
        Show-Dialog -Title "$($action.Name)?" -Message $action.Confirm -OkText $action.ButtonText -Danger -OnOk { Start-Action $script:PendingAction }
        return
    }
    Start-Action $action
}

function Start-Action([hashtable]$Action) {
    $action = $Action
    Show-Busy "$($action.Name)..."
    Set-Status "$($action.Name)..."
    Invoke-Background -Operation 'action' -Arguments @{ Id = $action.Id } -OnComplete {
        param($results, $ctx)
        Hide-Busy
        $r = @($results)[0]
        if (-not $r) { return }
        Show-Dialog -Title $r.Name -Message $r.Message -Info -Tone $(if ($r.Success) { 'ok' } else { 'warn' })
        Set-Status "$($r.Name): $(($r.Message -split "`n")[0])" $(if ($r.Success) { 'ok' } else { 'error' })
        Update-SystemInfo
    }
}

$script:ToolColors = 'Teal', 'Purple', 'Red', 'Orange', 'Accent', 'Green', 'Indigo', 'Pink'
function Show-Tools {
    $i = 0
    $rows = foreach ($a in $global:VelocityActions.Values) {
        $color = Get-VColor $script:ToolColors[$i % $script:ToolColors.Count]; $i++
        $row = New-XamlElement @"
<Grid $script:XmlNs Margin="18,13,18,13">
  <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  $(New-TileXaml $a.Icon $color 30 15)
  <StackPanel Grid.Column="1" Margin="0,0,24,0" VerticalAlignment="Center">
    <TextBlock Text="$(ConvertTo-XamlText $a.Name)" FontSize="13.5" FontWeight="SemiBold"/>
    <TextBlock Text="$(ConvertTo-XamlText $a.Description)" Foreground="{StaticResource SecondaryBrush}" FontSize="12.5" TextWrapping="Wrap" Margin="0,3,0,0" LineHeight="18"/>
  </StackPanel>
  <Button Grid.Column="2" Style="{StaticResource SecondaryButton}" Content="$(ConvertTo-XamlText $a.ButtonText)" Tag="$($a.Id)" MinWidth="88" Padding="14,5" VerticalAlignment="Center"/>
</Grid>
"@
        $row.Children[2].Add_Click($script:OnActionClick)
        $row
    }
    Set-GroupRows $script:UI.ToolsList @($rows) 62
}

# ------------------------------------------------------------
#  Eventos
# ------------------------------------------------------------
$script:UI.BtnMin.Add_Click({ $script:Window.WindowState = 'Minimized' })
$script:UI.BtnMaxRestore.Add_Click({
    $script:Window.WindowState = $(if ($script:Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
})
$script:UI.BtnClose.Add_Click({ $script:Window.Close() })
$script:Window.Add_StateChanged({
    $max = $script:Window.WindowState -eq 'Maximized'
    $script:UI.RootGrid.Margin = $(if ($max) { 7 } else { 0 })
    $script:UI.MaxGlyph.Text = [string][char]$(if ($max) { 0xE73F } else { 0xE740 })
    $script:UI.BtnMaxRestore.ToolTip = $(if ($max) { 'Restaurar' } else { 'Maximizar' })
})

# Cantos arredondados da janela no Windows 11 (no Windows 10 não faz nada)
$script:Window.Add_SourceInitialized({
    try {
        if (-not ('Velocity.Dwm' -as [type])) {
            Add-Type -Namespace Velocity -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);'
        }
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:Window).Handle
        $round = 2
        [void][Velocity.Dwm]::DwmSetWindowAttribute($hwnd, 33, [ref]$round, 4)   # DWMWA_WINDOW_CORNER_PREFERENCE = arredondado
    } catch { }
})

$script:UI.DialogOk.Add_Click({
    if ($script:UI.DialogOverlay.Visibility -ne 'Visible') { return }
    Close-VOverlay 'DialogOverlay'
    $action = $script:DialogAction
    $script:DialogAction = $null
    if ($action) { & $action }
})
$script:UI.DialogCancel.Add_Click({
    if ($script:UI.DialogOverlay.Visibility -ne 'Visible') { return }
    Close-VOverlay 'DialogOverlay'
    $script:DialogAction = $null
})

$script:UI.BtnOptimize.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { $_.Recommended -and -not $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        Show-Dialog -Title 'Tudo otimizado' -Message 'Todas as otimizações recomendadas já estão ativas.' -Info -Tone 'ok'
        return
    }
    Show-Dialog -Title 'Aplicar otimizações recomendadas?' -OkText 'Otimizar' -Message (
        "Serão aplicadas $($script:PendingIds.Count) otimizações de baixo risco, escolhidas para dar mais desempenho em jogos sem efeitos colaterais relevantes.`n`n" +
        'Os valores originais ficam guardados e tudo pode ser revertido depois, item a item ou de uma vez.') -OnOk {
        Start-TweakBatch -Operation 'apply' -Ids $script:PendingIds -BusyText 'Aplicando otimizações recomendadas...' -RestorePoint ([bool]$script:UI.ChkRestore.IsChecked)
    }
})

$script:UI.BtnMaxMode.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { -not $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        Show-Dialog -Title 'Modo máximo ativo' -Message 'Todas as otimizações já estão aplicadas.' -Info -Tone 'ok'
        return
    }
    $risky = @($global:VelocityTweaks.Values | Where-Object { $_.Risk -ne 'Baixo' -and -not $script:States[$_.Id] } | ForEach-Object { "• $($_.Name) (risco $($_.Risk.ToLower()))" })
    $msg = "Aplica TODAS as $($script:PendingIds.Count) otimizações pendentes, inclusive as avançadas, que reduzem proteções de segurança (VBS, mitigações de CPU, exclusões do Defender) e alteram boot e drivers:`n`n" + ($risky -join "`n") +
           "`n`nRevise-as antes nas categorias se não tiver certeza. Um ponto de restauração é fortemente recomendado. Tudo pode ser revertido."
    Show-Dialog -Title 'Ativar o modo máximo?' -Message $msg -OkText 'Aplicar tudo' -Danger -OnOk {
        Start-TweakBatch -Operation 'apply' -Ids $script:PendingIds -BusyText 'Aplicando modo máximo...' -RestorePoint ([bool]$script:UI.ChkRestore.IsChecked)
    }
})

# Só reverte o que o Velocity aplicou: o que já estava assim no seu Windows fica como está
$script:NothingOwnedMessage = 'As otimizações que aparecem ligadas já estavam assim no seu Windows antes do Velocity, então não há nada do Velocity para desfazer. Se quiser mudar alguma, desligue o botão dela na categoria.'

$script:UI.BtnRevertAll.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { $script:States[$_.Id] -and $script:Owned[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        $applied = @(Get-TweakIds { $script:States[$_.Id] }).Count
        Show-Dialog -Title 'Nada para reverter' -Info -Message $(if ($applied) { $script:NothingOwnedMessage } else { 'Nenhuma otimização está ativa no momento.' })
        return
    }
    Show-Dialog -Title 'Reverter tudo?' -OkText 'Reverter' -Danger -Message (
        "$($script:PendingIds.Count) otimizações aplicadas pelo Velocity voltarão aos valores originais do seu Windows.") -OnOk {
        Start-TweakBatch -Operation 'revert' -Ids $script:PendingIds -BusyText 'Revertendo alterações...'
    }
})

$script:UI.BtnCatApply.Add_Click({
    if (-not (Test-Ready)) { return }
    $cat = $script:CurrentPage
    $ids = Get-TweakIds { $_.Category -eq $cat -and $_.Recommended -and -not $script:States[$_.Id] }
    if ($ids.Count -eq 0) { Set-Status 'Todas as otimizações recomendadas desta categoria já estão ativas.' 'ok'; return }
    Start-TweakBatch -Operation 'apply' -Ids $ids -BusyText 'Aplicando otimizações recomendadas...'
})

$script:UI.BtnCatRevert.Add_Click({
    if (-not (Test-Ready)) { return }
    $cat = $script:CurrentPage
    $script:PendingIds = Get-TweakIds { $_.Category -eq $cat -and $script:States[$_.Id] -and $script:Owned[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        $applied = @(Get-TweakIds { $_.Category -eq $cat -and $script:States[$_.Id] }).Count
        if ($applied) { Show-Dialog -Title 'Nada para reverter' -Info -Message $script:NothingOwnedMessage }
        else { Set-Status 'Nenhuma otimização ativa nesta categoria.' 'info' }
        return
    }
    Show-Dialog -Title 'Reverter categoria?' -OkText 'Reverter' -Danger -Message (
        "$($script:PendingIds.Count) otimizações de '$($global:VelocityCategories[$cat].Name)' voltarão aos valores originais.") -OnOk {
        Start-TweakBatch -Operation 'revert' -Ids $script:PendingIds -BusyText 'Revertendo categoria...'
    }
})

$script:UI.BtnStartupRefresh.Add_Click({ Show-StartupItems; Set-Status 'Lista de inicialização atualizada.' 'ok' })
$script:UI.BtnOpenLogs.Add_Click({ Start-Process explorer.exe $global:VelocityDataDir })

$script:App.Add_DispatcherUnhandledException({
    param($sender, $e)
    Write-VLog "Erro na interface: $($e.Exception)" 'ERROR'
    Hide-Busy
    Set-Status "Erro inesperado: $($e.Exception.Message)" 'error'
    $e.Handled = $true
})

# ------------------------------------------------------------
#  Inicialização
# ------------------------------------------------------------
$script:StatesLoaded = $false

# --- Ícone da janela
$iconPath = Join-Path $global:VelocityRoot 'assets\velocity.ico'
if (Test-Path $iconPath) {
    try { $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath) } catch { }
}

# --- Termo de consentimento (exibido até ser aceito; nova versão do termo = nova exibição)
$script:ConsentVersion = 2
$script:ConsentRows = @{ ConsentList = @(); ConsentSafety = @() }
function Add-ConsentLine([string]$Panel, [string]$Icon, [string]$ColorName, [string]$Text) {
    $script:ConsentRows[$Panel] += New-XamlElement @"
<DockPanel $script:XmlNs Margin="16,11">
  $(New-TileXaml $Icon (Get-VColor $ColorName) 24 12)
  <TextBlock Text="$(ConvertTo-XamlText $Text)" TextWrapping="Wrap" LineHeight="18" FontSize="13" Margin="12,0,0,0" VerticalAlignment="Center"/>
</DockPanel>
"@
}
Add-ConsentLine 'ConsentList' 'E713' 'Accent' 'Alterar o registro do sistema, do kernel e do agendador de CPU'
Add-ConsentLine 'ConsentList' 'E7E8' 'Accent' 'Modificar a configuração de boot (BCD) e criar planos de energia com ajustes ocultos'
Add-ConsentLine 'ConsentList' 'E9F5' 'Accent' 'Desativar serviços, tarefas agendadas, telemetria e apps em segundo plano'
Add-ConsentLine 'ConsentList' 'E968' 'Accent' 'Reconfigurar o driver da placa de rede e o modo de interrupção da placa de vídeo'
Add-ConsentLine 'ConsentList' 'EA18' 'Orange' 'Reduzir proteções de segurança quando você escolher: Isolamento de Núcleo (VBS), mitigações Spectre/Meltdown e exclusões do Defender'
Add-ConsentLine 'ConsentList' 'E74D' 'Orange' 'Remover apps pré-instalados do Windows (sob confirmação)'
Add-ConsentLine 'ConsentSafety' 'E73E' 'Green' 'O valor original de cada configuração é salvo antes de qualquer alteração'
Add-ConsentLine 'ConsentSafety' 'E73E' 'Green' 'Tudo pode ser revertido: item a item, por categoria ou de uma vez'
Add-ConsentLine 'ConsentSafety' 'E73E' 'Green' 'Ponto de restauração do Windows antes de otimizar (opção marcada por padrão)'
Add-ConsentLine 'ConsentSafety' 'E73E' 'Green' 'Itens de risco alto exigem confirmação individual, e cada ação fica registrada em log'
Set-GroupRows $script:UI.ConsentList $script:ConsentRows.ConsentList 52
Set-GroupRows $script:UI.ConsentSafety $script:ConsentRows.ConsentSafety 52

$settings = Get-VSettings
if ([int]$settings['ConsentVersion'] -lt $script:ConsentVersion) { $script:UI.ConsentOverlay.Visibility = 'Visible' }
$script:UI.ChkConsent.Add_Click({ $script:UI.BtnConsentAccept.IsEnabled = [bool]$script:UI.ChkConsent.IsChecked })
$script:UI.BtnConsentExit.Add_Click({ $script:Window.Close() })
$script:UI.BtnConsentAccept.Add_Click({
    Set-VSetting 'ConsentVersion' $script:ConsentVersion
    Write-VLog "Termo de consentimento v$script:ConsentVersion aceito."
    $overlay = $script:UI.ConsentOverlay
    if ($script:Motion) { Start-VAnim $overlay $script:OpacityProp 0 260 -OnDone { $script:UI.ConsentOverlay.Visibility = 'Collapsed' } }
    else { $overlay.Visibility = 'Collapsed' }
})

Add-NavHeader 'Geral'
Add-NavItem 'dashboard' 'Painel' 'E80F'
Add-NavHeader 'Otimizações'
foreach ($cat in $global:VelocityCategories.Values) { Add-NavItem $cat.Id $cat.Name $cat.Icon }
Add-NavHeader 'Sistema'
Add-NavItem 'startup' 'Inicialização' 'E7E8'
Add-NavItem 'tools' 'Ferramentas' 'E90F'
Show-Tools

$script:UI.VersionText.Text = "v$global:VelocityVersion"
Select-Nav 'dashboard'
$script:Window.Add_Loaded({ Update-AllStates; Update-SystemInfo })

Write-VLog "Velocity $global:VelocityVersion iniciado."
[void]$script:App.Run($script:Window)
