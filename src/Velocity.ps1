# ============================================================
#  Velocity · Game Optimizer
#  Ponto de entrada: garante privilégios de administrador,
#  carrega o núcleo + módulos e abre a interface.
# ============================================================
param([switch]$ShowConsole)

$global:VelocityVersion = '1.2.0'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Elevação ------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoProfile -NoLogo -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    if ($ShowConsole) { $argList += ' -ShowConsole' }
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList } catch { }
    exit
}

# --- Esconde a janela do console -----------------------------
if (-not $ShowConsole) {
    Add-Type -Namespace Velocity -Name Console -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    [void][Velocity.Console]::ShowWindow([Velocity.Console]::GetConsoleWindow(), 0)
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# --- Instância única ------------------------------------------
$isFirstInstance = $false
$global:VelocityMutex = New-Object System.Threading.Mutex($true, 'Global\VelocityGameOptimizer', [ref]$isFirstInstance)
if (-not $isFirstInstance) {
    [void][System.Windows.MessageBox]::Show('O Velocity já está aberto.', 'Velocity', 'OK', 'Information')
    exit
}

try {
    . (Join-Path $root 'Core\Loader.ps1') -Root $root
    . (Join-Path $root 'UI\App.ps1')
} catch {
    $detail = "$($_.Exception.Message)`n`n$($_.InvocationInfo.PositionMessage)"
    if (Get-Command Write-VLog -ErrorAction SilentlyContinue) { Write-VLog "Erro fatal: $detail" 'ERROR' }
    [void][System.Windows.MessageBox]::Show("O Velocity encontrou um erro e precisa fechar.`n`n$detail", 'Velocity', 'OK', 'Error')
}
