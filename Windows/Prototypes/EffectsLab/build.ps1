param([switch]$Test)
$ErrorActionPreference = 'Stop'
$labRoot = $PSScriptRoot
$labFramework = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$labCompiler = Join-Path $labFramework 'csc.exe'
if (-not (Test-Path -LiteralPath $labCompiler)) { throw '.NET Framework 4.8 compiler is required.' }
$labOutput = Join-Path $labRoot 'bin'
New-Item -ItemType Directory -Path (Join-Path $labOutput 'shaders') -Force | Out-Null
$labArgs = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', '/codepage:65001', '/warn:4', ('/out:' + (Join-Path $labOutput 'QuotaView.EffectsLab.exe')), ('/win32manifest:' + (Join-Path $labRoot '../../app.manifest')))
foreach ($labRef in @('System.dll', 'System.Core.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll')) { $labArgs += '/reference:' + (Join-Path $labFramework $labRef) }
$labSources = Get-ChildItem -LiteralPath (Join-Path $labRoot 'src') -Filter '*.cs' | Select-Object -ExpandProperty FullName
& $labCompiler @labArgs @labSources
if ($LASTEXITCODE -ne 0) { throw 'Effects Lab build failed.' }
Get-ChildItem -LiteralPath (Join-Path $labRoot 'shaders') -File | Copy-Item -Destination (Join-Path $labOutput 'shaders') -Force
Copy-Item -LiteralPath (Join-Path $labRoot 'QuotaView.EffectsLab.exe.config') -Destination $labOutput -Force
Write-Output ('Built ' + (Join-Path $labOutput 'QuotaView.EffectsLab.exe'))
if ($Test) {
    $labTestArgs = @('/nologo', '/target:exe', '/platform:x64', '/codepage:65001', ('/out:' + (Join-Path $labOutput 'EffectsLab.Tests.exe')))
    & $labCompiler @labTestArgs (Join-Path $labRoot 'src/ReleaseProfiles.cs') (Join-Path $labRoot 'src/EffectsModel.cs') (Join-Path $labRoot 'tests/ModelTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Test build failed.' }
    & (Join-Path $labOutput 'EffectsLab.Tests.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Effects model checks failed.' }
}
