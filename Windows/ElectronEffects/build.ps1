param([switch]$Test, [string]$NodePath)
$ErrorActionPreference = 'Stop'
if (-not $NodePath) {
    $effectsNodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($effectsNodeCommand) { $NodePath = $effectsNodeCommand.Source }
    else { $NodePath = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' }
}
if (-not (Test-Path -LiteralPath $NodePath)) { throw 'Node.js is required. Pass -NodePath with its executable path.' }
& $NodePath (Join-Path $PSScriptRoot 'build.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Electron effects build failed.' }
if ($Test) {
    & $NodePath --test (Join-Path $PSScriptRoot 'tests/model.test.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Effects model tests failed.' }
}
