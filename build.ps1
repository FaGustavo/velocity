# ============================================================
#  Velocity · Build
#  Empacota src\ em app.zip e compila o lançador (Velocity.exe)
#  com o compilador C# que já vem no Windows (.NET Framework 4).
#  Uso:  powershell -ExecutionPolicy Bypass -File build.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = Join-Path $here 'src'
$build = Join-Path $here 'build'
$out   = Join-Path $here 'Velocity.exe'
$fx    = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc   = Join-Path $fx 'csc.exe'

# Versão: a mesma declarada em Velocity.ps1
$entry = [IO.File]::ReadAllText((Join-Path $src 'Velocity.ps1'))
if ($entry -notmatch "VelocityVersion\s*=\s*'([\d.]+)'") { throw 'Versão não encontrada em src\Velocity.ps1' }
$version = $Matches[1]
$fileVersion = (($version.Split('.') + '0', '0', '0')[0..3]) -join '.'

if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory $build | Out-Null

# app.zip com caminhos usando "/"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipPath = Join-Path $build 'app.zip'
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($f in Get-ChildItem $src -Recurse -File) {
        $name = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $name, 'Optimal')
    }
} finally { $zip.Dispose() }

# Informações de versão do exe
@"
using System.Reflection;
[assembly: AssemblyTitle("Velocity Game Optimizer")]
[assembly: AssemblyDescription("Velocity Game Optimizer")]
[assembly: AssemblyProduct("Velocity")]
[assembly: AssemblyCompany("Velocity")]
[assembly: AssemblyVersion("$fileVersion")]
[assembly: AssemblyFileVersion("$fileVersion")]
[assembly: AssemblyInformationalVersion("$version")]
"@ | Set-Content (Join-Path $build 'AssemblyInfo.cs') -Encoding UTF8

$cscArgs = @(
    '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu', '/codepage:65001', "/out:$out",
    "/win32icon:$(Join-Path $src 'assets\velocity.ico')",
    "/win32manifest:$(Join-Path $here 'launcher\app.manifest')",
    "/resource:$zipPath,app.zip",
    "/reference:$(Join-Path $fx 'System.IO.Compression.dll')",
    "/reference:$(Join-Path $fx 'System.IO.Compression.FileSystem.dll')",
    '/reference:System.Windows.Forms.dll',
    (Join-Path $here 'launcher\Launcher.cs'),
    (Join-Path $build 'AssemblyInfo.cs')
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar (código $LASTEXITCODE)." }
Write-Host "Velocity $version compilado em $out"
