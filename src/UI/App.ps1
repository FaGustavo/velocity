# ============================================================
#  Velocity · Camada de interface (WPF)
#  Toda operação que altera o sistema roda num runspace separado
#  para a janela nunca congelar.
# ============================================================

$script:States       = @{}
$script:CurrentPage  = 'dashboard'
$script:NavButtons   = @{}
$script:DialogAction = $null
$script:PendingIds   = @()
$script:StartupItems = @()
$script:XmlNs        = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"'
$script:RiskColors   = @{ 'Baixo' = '3DDC97'; 'Médio' = 'F5B13D'; 'Alto' = 'FF5C6C' }

function ConvertTo-XamlText([string]$Text) { [System.Security.SecurityElement]::Escape($Text) }
function New-XamlElement([string]$Xaml) { [Windows.Markup.XamlReader]::Parse($Xaml) }
function Read-UiFile([string]$Name) { [IO.File]::ReadAllText((Join-Path $global:VelocityRoot "UI\$Name")) }

# ------------------------------------------------------------
#  Aplicação e janela
# ------------------------------------------------------------
$script:App = New-Object System.Windows.Application
$script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
$script:App.Resources.MergedDictionaries.Add((New-XamlElement (Read-UiFile 'Theme.xaml')))

$windowXaml    = Read-UiFile 'MainWindow.xaml'
$script:Window = New-XamlElement $windowXaml
$script:UI     = @{}
foreach ($m in [regex]::Matches($windowXaml, 'x:Name="(\w+)"')) {
    $script:UI[$m.Groups[1].Value] = $script:Window.FindName($m.Groups[1].Value)
}

# ------------------------------------------------------------
#  Execução em segundo plano
# ------------------------------------------------------------
$script:Worker = {
    param($Root, $Operation, $Arguments)
    . (Join-Path $Root 'Core\Loader.ps1') -Root $Root

    function Out-TweakResult([hashtable]$Result) {
        $Result.Applied = Get-VTweakState -Id $Result.Id
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
        'states'  { foreach ($id in $global:VelocityTweaks.Keys) { [pscustomobject]@{ Id = $id; Applied = (Get-VTweakState -Id $id) } } }
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
    $script:UI.BusyOverlay.Visibility = 'Visible'
}

function Hide-Busy { $script:UI.BusyOverlay.Visibility = 'Collapsed' }

function Show-Dialog {
    param([string]$Title, [string]$Message, [string]$OkText = 'OK', [string]$CancelText = 'Cancelar',
          [scriptblock]$OnOk, [switch]$Info, [switch]$Danger)
    $script:UI.DialogTitle.Text = $Title
    $script:UI.DialogText.Text = $Message
    $script:UI.DialogOk.Content = $OkText
    $script:UI.DialogCancel.Content = $CancelText
    $script:UI.DialogCancel.Visibility = $(if ($Info) { 'Collapsed' } else { 'Visible' })
    $script:UI.DialogOk.Style = $script:Window.FindResource($(if ($Danger) { 'DangerButton' } else { 'PrimaryButton' }))
    $script:DialogAction = $OnOk
    $script:UI.DialogOverlay.Visibility = 'Visible'
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
        foreach ($r in $results) { if ($r.Id) { $script:States[[string]$r.Id] = [bool]$r.Applied } }
        $script:StatesLoaded = $true
        Show-Page $script:CurrentPage
        Set-Status 'Pronto. Escolha uma categoria ou use "Otimizar".' 'ok'
    }
}

function Register-Result($Result) {
    $id = [string]$Result.Id
    if ($id -and $global:VelocityTweaks.Contains($id)) {
        $script:States[$id] = [bool]$Result.Applied
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

        $msg = "$ok de $(@($results | Where-Object { $_.Id -ne 'restore' }).Count) alterações concluídas com sucesso."
        if ($notes) { $msg = ($notes -join "`n") + "`n`n" + $msg }
        if ($failed) { $msg += "`n`nCom problemas:`n" + ($failed -join "`n") }
        if ($script:UI.RebootPill.Visibility -eq 'Visible') { $msg += "`n`nAlgumas alterações só terão efeito completo após reiniciar o PC." }
        Show-Dialog -Title $(if ($failed) { 'Concluído com avisos' } else { 'Tudo pronto' }) -Message $msg -Info
        Set-Status "Operação concluída: $ok com sucesso, $($failed.Count) com problemas." $(if ($failed) { 'warn' } else { 'ok' })
    }
}

# ------------------------------------------------------------
#  Navegação
# ------------------------------------------------------------
function Add-NavHeader([string]$Text) {
    [void]$script:UI.NavPanel.Children.Add((New-XamlElement "<TextBlock $script:XmlNs Text=""$Text"" FontSize=""10.5"" FontWeight=""Bold"" Foreground=""{StaticResource FaintBrush}"" Margin=""12,18,0,6""/>"))
}

function Add-NavItem([string]$Key, [string]$Label, [string]$Icon) {
    $rb = New-XamlElement @"
<RadioButton $script:XmlNs Style="{StaticResource NavButton}" GroupName="Nav" Tag="$Key">
  <StackPanel Orientation="Horizontal">
    <TextBlock Text="&#x$Icon;" FontFamily="{StaticResource IconFont}" FontSize="15" Width="30" VerticalAlignment="Center"/>
    <TextBlock Text="$(ConvertTo-XamlText $Label)" FontSize="13.5" VerticalAlignment="Center"/>
  </StackPanel>
</RadioButton>
"@
    $rb.Add_Checked({ param($s, $e) Show-Page ([string]$s.Tag) })
    $script:NavButtons[$Key] = $rb
    [void]$script:UI.NavPanel.Children.Add($rb)
}

function Select-Nav([string]$Key) { $script:NavButtons[$Key].IsChecked = $true }

function Show-Page([string]$Key) {
    $script:CurrentPage = $Key
    foreach ($p in 'PageDashboard', 'PageTweaks', 'PageStartup', 'PageTools') { $script:UI[$p].Visibility = 'Collapsed' }
    switch ($Key) {
        'dashboard' { Update-Dashboard; $page = $script:UI.PageDashboard }
        'startup'   { Show-StartupItems; $page = $script:UI.PageStartup }
        'tools'     { $page = $script:UI.PageTools }
        default     { Show-Category $Key; $page = $script:UI.PageTweaks }
    }
    $page.Visibility = 'Visible'
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 0; $fade.To = 1
    $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(180))
    $page.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

# ------------------------------------------------------------
#  Painel
# ------------------------------------------------------------
function Update-Dashboard {
    $all   = @($global:VelocityTweaks.Values)
    $rec   = @($all | Where-Object { $_.Recommended })
    $recOn = @($rec | Where-Object { $script:States[$_.Id] }).Count
    $allOn = @($all | Where-Object { $script:States[$_.Id] }).Count
    $pct   = 0
    if ($rec.Count) { $pct = [int][math]::Round($recOn * 100 / $rec.Count) }

    $script:UI.ScoreText.Text = "$pct%"
    $script:UI.ScoreDetail.Text = "$recOn de $($rec.Count) otimizações recomendadas ativas  ·  $allOn de $($all.Count) no total"
    if (-not $script:StatesLoaded) {
        $script:UI.ScoreText.Text = '—'
        $script:UI.ScoreDetail.Text = 'Analisando o sistema...'
    }
    $label, $color = switch ($pct) {
        { $_ -ge 100 } { 'Otimizado', '3DDC97'; break }
        { $_ -ge 60 }  { 'Bom', '22D3EE'; break }
        { $_ -ge 25 }  { 'Pode melhorar', 'F5B13D'; break }
        default        { 'Não otimizado', 'FF5C6C' }
    }
    $script:UI.ScoreLabel.Text = $label
    $script:UI.ScoreLabel.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#$color"))
    $script:UI.ScoreLabelBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString("#22$color"))

    $grow = New-Object System.Windows.Media.Animation.DoubleAnimation
    $grow.To = $pct
    $grow.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(700))
    $grow.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
    $script:UI.ScoreBar.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $grow)

    $script:UI.CategorySummary.Children.Clear()
    foreach ($cat in $global:VelocityCategories.Values) {
        $list = Get-CategoryTweaks $cat.Id
        $on = @($list | Where-Object { $script:States[$_.Id] }).Count
        $p = 0
        if ($list.Count) { $p = [int]($on * 100 / $list.Count) }
        $row = New-XamlElement @"
<Border $script:XmlNs Style="{StaticResource RowCard}" Tag="$($cat.Id)">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="180"/><ColumnDefinition Width="64"/><ColumnDefinition Width="20"/>
    </Grid.ColumnDefinitions>
    <Border Width="32" Height="32" CornerRadius="8" Background="{StaticResource Surface2Brush}" HorizontalAlignment="Left">
      <TextBlock Text="&#x$($cat.Icon);" FontFamily="{StaticResource IconFont}" FontSize="15" Foreground="{StaticResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="4,0,20,0">
      <TextBlock Text="$(ConvertTo-XamlText $cat.Name)" FontWeight="SemiBold" FontSize="14"/>
      <TextBlock Text="$(ConvertTo-XamlText $cat.Description)" Foreground="{StaticResource MutedBrush}" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
    </StackPanel>
    <ProgressBar Grid.Column="2" Style="{StaticResource ScoreBar}" Height="6" Maximum="100" Value="$p" VerticalAlignment="Center"/>
    <TextBlock Grid.Column="3" Text="$on/$($list.Count)" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{StaticResource MutedBrush}" FontWeight="SemiBold"/>
    <TextBlock Grid.Column="4" Text="&#xE76C;" FontFamily="{StaticResource IconFont}" FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{StaticResource FaintBrush}"/>
  </Grid>
</Border>
"@
        $row.Add_MouseLeftButtonUp({ param($s, $e) Select-Nav ([string]$s.Tag) })
        [void]$script:UI.CategorySummary.Children.Add($row)
    }
}

function Update-SystemInfo {
    Invoke-Background -Operation 'sysinfo' -OnComplete {
        param($results, $ctx)
        $info = @($results)[0]
        if (-not $info -or -not $info.Cpu) { return }
        $script:UI.StatCpu.Text    = $info.Cpu;   $script:UI.StatCpu.ToolTip = $info.Cpu
        $script:UI.StatCpuSub.Text = $info.CpuDetail
        $script:UI.StatGpu.Text    = $info.Gpu;   $script:UI.StatGpu.ToolTip = $info.Gpu
        $script:UI.StatGpuSub.Text = $info.GpuDetail
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
function New-Badge([string]$Text, [string]$Color) {
    "<Border Background=""#22$Color"" CornerRadius=""5"" Padding=""8,3"" Margin=""0,0,6,0""><TextBlock Text=""$(ConvertTo-XamlText $Text)"" FontSize=""11"" FontWeight=""SemiBold"" Foreground=""#$Color""/></Border>"
}

$script:OnTweakToggle = {
    param($sender, $e)
    $tweak = $global:VelocityTweaks[[string]$sender.Tag]
    if ($sender.IsChecked -and $tweak.Risk -eq 'Alto') {
        # Risco alto: só aplica após confirmação explícita
        $sender.IsChecked = $false
        $script:PendingToggle = $sender
        Show-Dialog -Title "Ativar '$($tweak.Name)'?" -OkText 'Entendo, ativar' -Danger -Message (
            "Esta é uma otimização de RISCO ALTO.`n`n$($tweak.Description)`n`n" +
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

function New-TweakCard([hashtable]$Tweak) {
    $badges = New-Badge "Risco $($Tweak.Risk.ToLower())" $script:RiskColors[$Tweak.Risk]
    if ($Tweak.Recommended)    { $badges += New-Badge 'Recomendado' 'A08CFF' }
    if ($Tweak.RequiresReboot) { $badges += New-Badge 'Requer reinício' '22D3EE' }
    $checked = [string][bool]$script:States[$Tweak.Id]
    $card = New-XamlElement @"
<Border $script:XmlNs Style="{StaticResource Card}">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Margin="0,0,28,0">
      <TextBlock Text="$(ConvertTo-XamlText $Tweak.Name)" FontSize="15" FontWeight="SemiBold"/>
      <TextBlock Text="$(ConvertTo-XamlText $Tweak.Description)" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,5,0,12" LineHeight="20"/>
      <WrapPanel>$badges</WrapPanel>
    </StackPanel>
    <CheckBox Grid.Column="1" Style="{StaticResource ToggleSwitch}" VerticalAlignment="Center" IsChecked="$checked" IsEnabled="$([string][bool]$script:StatesLoaded)" Tag="$(ConvertTo-XamlText $Tweak.Id)"/>
  </Grid>
</Border>
"@
    $card.Child.Children[1].Add_Click($script:OnTweakToggle)
    return $card
}

function Show-Category([string]$CategoryId) {
    $cat = $global:VelocityCategories[$CategoryId]
    $script:UI.CatTitle.Text = $cat.Name
    $script:UI.CatDesc.Text = $cat.Description
    $script:UI.CatWarning.Visibility = $(if ($cat.Warning) { 'Visible' } else { 'Collapsed' })
    $script:UI.CatWarningText.Text = [string]$cat.Warning
    $hasRecommended = @(Get-CategoryTweaks $CategoryId | Where-Object { $_.Recommended }).Count -gt 0
    $script:UI.BtnCatApply.Visibility = $(if ($hasRecommended) { 'Visible' } else { 'Collapsed' })
    $script:UI.TweakList.Children.Clear()
    foreach ($t in Get-CategoryTweaks $CategoryId) { [void]$script:UI.TweakList.Children.Add((New-TweakCard $t)) }
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

function Show-StartupItems {
    $script:StartupItems = @(Get-VStartupItems | Sort-Object Display)
    $script:UI.StartupList.Children.Clear()
    if ($script:StartupItems.Count -eq 0) {
        [void]$script:UI.StartupList.Children.Add((New-XamlElement "<TextBlock $script:XmlNs Text=""Nenhum programa de inicialização encontrado."" Foreground=""{StaticResource MutedBrush}""/>"))
    }
    for ($i = 0; $i -lt $script:StartupItems.Count; $i++) {
        $it = $script:StartupItems[$i]
        $card = New-XamlElement @"
<Border $script:XmlNs Style="{StaticResource Card}" Padding="20,14">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Margin="0,0,28,0">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="$(ConvertTo-XamlText $it.Display)" FontSize="14.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <Border Background="{StaticResource Surface2Brush}" CornerRadius="5" Padding="7,2" Margin="10,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="$(ConvertTo-XamlText $it.Scope)" FontSize="10.5" Foreground="{StaticResource MutedBrush}"/>
        </Border>
      </StackPanel>
      <TextBlock Text="$(ConvertTo-XamlText $it.Command)" ToolTip="$(ConvertTo-XamlText $it.Command)" Foreground="{StaticResource FaintBrush}" FontFamily="Cascadia Mono, Consolas" FontSize="11.5" Margin="0,5,0,0" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <CheckBox Grid.Column="1" Style="{StaticResource ToggleSwitch}" VerticalAlignment="Center" IsChecked="$([string][bool]$it.Enabled)" Tag="$i"/>
  </Grid>
</Border>
"@
        $card.Child.Children[1].Add_Click($script:OnStartupToggle)
        [void]$script:UI.StartupList.Children.Add($card)
    }
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
        Show-Dialog -Title $r.Name -Message $r.Message -Info
        Set-Status "$($r.Name): $(($r.Message -split "`n")[0])" $(if ($r.Success) { 'ok' } else { 'error' })
        Update-SystemInfo
    }
}

function Show-Tools {
    foreach ($a in $global:VelocityActions.Values) {
        $card = New-XamlElement @"
<Border $script:XmlNs Style="{StaticResource Card}">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Border Width="42" Height="42" CornerRadius="10" Background="{StaticResource Surface2Brush}" VerticalAlignment="Center">
      <TextBlock Text="&#x$($a.Icon);" FontFamily="{StaticResource IconFont}" FontSize="17" Foreground="{StaticResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" Margin="16,0,24,0" VerticalAlignment="Center">
      <TextBlock Text="$(ConvertTo-XamlText $a.Name)" FontSize="15" FontWeight="SemiBold"/>
      <TextBlock Text="$(ConvertTo-XamlText $a.Description)" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="20"/>
    </StackPanel>
    <Button Grid.Column="2" Style="{StaticResource SecondaryButton}" Content="$(ConvertTo-XamlText $a.ButtonText)" Tag="$($a.Id)" MinWidth="100" VerticalAlignment="Center"/>
  </Grid>
</Border>
"@
        $card.Child.Children[2].Add_Click($script:OnActionClick)
        [void]$script:UI.ToolsList.Children.Add($card)
    }
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
    $script:UI.MaxGlyph.Text = [string][char]$(if ($max) { 0xE923 } else { 0xE922 })
})

$script:UI.DialogOk.Add_Click({
    $script:UI.DialogOverlay.Visibility = 'Collapsed'
    $action = $script:DialogAction
    $script:DialogAction = $null
    if ($action) { & $action }
})
$script:UI.DialogCancel.Add_Click({
    $script:UI.DialogOverlay.Visibility = 'Collapsed'
    $script:DialogAction = $null
})

$script:UI.BtnOptimize.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { $_.Recommended -and -not $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        Show-Dialog -Title 'Tudo otimizado' -Message 'Todas as otimizações recomendadas já estão ativas.' -Info
        return
    }
    Show-Dialog -Title 'Aplicar otimizações recomendadas' -OkText 'Otimizar' -Message (
        "Serão aplicadas $($script:PendingIds.Count) otimizações de baixo risco, selecionadas para dar mais desempenho em jogos sem efeitos colaterais relevantes.`n`n" +
        'Os valores originais ficam guardados e tudo pode ser revertido depois, item a item ou de uma vez.') -OnOk {
        Start-TweakBatch -Operation 'apply' -Ids $script:PendingIds -BusyText 'Aplicando otimizações recomendadas...' -RestorePoint ([bool]$script:UI.ChkRestore.IsChecked)
    }
})

$script:UI.BtnMaxMode.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { -not $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        Show-Dialog -Title 'Modo máximo ativo' -Message 'Todas as otimizações já estão aplicadas.' -Info
        return
    }
    $risky = @($global:VelocityTweaks.Values | Where-Object { $_.Risk -ne 'Baixo' -and -not $script:States[$_.Id] } | ForEach-Object { "• $($_.Name) (risco $($_.Risk.ToLower()))" })
    $msg = "Aplica TODAS as $($script:PendingIds.Count) otimizações pendentes, incluindo as deep, que reduzem proteções de segurança (VBS, mitigações de CPU, exclusões do Defender) e alteram boot e drivers:`n`n" + ($risky -join "`n") +
           "`n`nRevise-as antes nas categorias se não tiver certeza. Um ponto de restauração é fortemente recomendado. Tudo pode ser revertido."
    Show-Dialog -Title 'Ativar modo máximo?' -Message $msg -OkText 'Aplicar tudo' -Danger -OnOk {
        Start-TweakBatch -Operation 'apply' -Ids $script:PendingIds -BusyText 'Aplicando modo máximo...' -RestorePoint ([bool]$script:UI.ChkRestore.IsChecked)
    }
})

$script:UI.BtnRevertAll.Add_Click({
    if (-not (Test-Ready)) { return }
    $script:PendingIds = Get-TweakIds { $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) {
        Show-Dialog -Title 'Nada para reverter' -Message 'Nenhuma otimização está ativa no momento.' -Info
        return
    }
    Show-Dialog -Title 'Reverter tudo?' -OkText 'Reverter' -Danger -Message (
        "$($script:PendingIds.Count) otimizações voltarão aos valores originais do seu Windows.") -OnOk {
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
    $script:PendingIds = Get-TweakIds { $_.Category -eq $cat -and $script:States[$_.Id] }
    if ($script:PendingIds.Count -eq 0) { Set-Status 'Nenhuma otimização ativa nesta categoria.' 'info'; return }
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
function Add-ConsentLine([string]$Panel, [string]$Icon, [string]$Color, [string]$Text) {
    [void]$script:UI[$Panel].Children.Add((New-XamlElement @"
<DockPanel $script:XmlNs Margin="0,0,0,9">
  <TextBlock Text="&#x$Icon;" FontFamily="{StaticResource IconFont}" Foreground="$Color" FontSize="13" Width="26" Margin="0,2,0,0" VerticalAlignment="Top"/>
  <TextBlock Text="$(ConvertTo-XamlText $Text)" TextWrapping="Wrap" LineHeight="19" FontSize="13.5"/>
</DockPanel>
"@))
}
Add-ConsentLine 'ConsentList' 'E713' '#9B85FF' 'Alterar o registro do sistema, do kernel e do agendador de CPU'
Add-ConsentLine 'ConsentList' 'E7E8' '#9B85FF' 'Modificar a configuração de boot (BCD) e criar planos de energia com ajustes ocultos'
Add-ConsentLine 'ConsentList' 'E9F5' '#9B85FF' 'Desativar serviços, tarefas agendadas, telemetria e apps em segundo plano'
Add-ConsentLine 'ConsentList' 'E968' '#9B85FF' 'Reconfigurar o driver da placa de rede e o modo de interrupção da placa de vídeo'
Add-ConsentLine 'ConsentList' 'EA18' '#F5B13D' 'Reduzir proteções de segurança quando você escolher: Isolamento de Núcleo (VBS), mitigações Spectre/Meltdown e exclusões do Defender'
Add-ConsentLine 'ConsentList' 'E74D' '#F5B13D' 'Remover apps pré-instalados do Windows (sob confirmação)'
Add-ConsentLine 'ConsentSafety' 'E73E' '#3DDC97' 'O valor original de cada configuração é salvo antes de qualquer alteração'
Add-ConsentLine 'ConsentSafety' 'E73E' '#3DDC97' 'Tudo pode ser revertido: item a item, por categoria ou de uma vez'
Add-ConsentLine 'ConsentSafety' 'E73E' '#3DDC97' 'Ponto de restauração do Windows antes de otimizar (opção marcada por padrão)'
Add-ConsentLine 'ConsentSafety' 'E73E' '#3DDC97' 'Itens de risco alto exigem confirmação individual, e cada ação fica registrada em log'

$settings = Get-VSettings
if ([int]$settings['ConsentVersion'] -lt $script:ConsentVersion) { $script:UI.ConsentOverlay.Visibility = 'Visible' }
$script:UI.ChkConsent.Add_Click({ $script:UI.BtnConsentAccept.IsEnabled = [bool]$script:UI.ChkConsent.IsChecked })
$script:UI.BtnConsentExit.Add_Click({ $script:Window.Close() })
$script:UI.BtnConsentAccept.Add_Click({
    Set-VSetting 'ConsentVersion' $script:ConsentVersion
    Write-VLog "Termo de consentimento v$script:ConsentVersion aceito."
    $script:UI.ConsentOverlay.Visibility = 'Collapsed'
})

Add-NavHeader 'GERAL'
Add-NavItem 'dashboard' 'Painel' 'E80F'
Add-NavHeader 'OTIMIZAÇÕES'
foreach ($cat in $global:VelocityCategories.Values) { Add-NavItem $cat.Id $cat.Name $cat.Icon }
Add-NavHeader 'SISTEMA'
Add-NavItem 'startup' 'Inicialização' 'E7E8'
Add-NavItem 'tools' 'Ferramentas' 'E90F'
Show-Tools

$script:UI.VersionText.Text = "v$global:VelocityVersion"
Select-Nav 'dashboard'
$script:Window.Add_Loaded({ Update-AllStates; Update-SystemInfo })

Write-VLog "Velocity $global:VelocityVersion iniciado."
[void]$script:App.Run($script:Window)
