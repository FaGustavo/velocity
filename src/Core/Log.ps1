# ============================================================
#  Velocity · Log
# ============================================================

$global:VelocityDataDir = Join-Path $env:ProgramData 'Velocity'

function Write-VLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    try {
        if (-not (Test-Path $global:VelocityDataDir)) { [void](New-Item -ItemType Directory -Force -Path $global:VelocityDataDir) }
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
        [IO.File]::AppendAllText((Join-Path $global:VelocityDataDir 'velocity.log'), $line + [Environment]::NewLine)
    } catch { }
}
