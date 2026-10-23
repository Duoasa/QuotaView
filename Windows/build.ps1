param([ValidateSet('build','run','test','publish')][string]$Action='build', [switch]$FrameworkDependent)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'webview2/build.ps1') -Action $Action -FrameworkDependent:$FrameworkDependent
