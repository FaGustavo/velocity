# ============================================================
#  Velocity · Carregador (deve ser dot-sourced)
#  Carrega o núcleo e todos os módulos em Modules\ em ordem alfabética.
# ============================================================
param([Parameter(Mandatory)][string]$Root)

$global:VelocityRoot = $Root

foreach ($coreFile in 'Log', 'Registry', 'Backup', 'Settings', 'TweakEngine', 'System', 'Startup') {
    . (Join-Path $Root "Core\$coreFile.ps1")
}

foreach ($moduleFile in Get-ChildItem -Path (Join-Path $Root 'Modules') -Filter '*.ps1' | Sort-Object Name) {
    . $moduleFile.FullName
}
