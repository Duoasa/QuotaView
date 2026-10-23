#Requires -Version 7.4
[CmdletBinding(DefaultParameterSetName='Sign')]
param(
    [Parameter(Mandatory,ParameterSetName='Initialize')][switch]$InitializeKey,
    [Parameter(Mandatory,ParameterSetName='Sign')][string]$Archive,
    [Parameter(Mandatory,ParameterSetName='Sign')][ValidatePattern('^\d{1,6}\.\d{1,6}\.\d{1,6}-win\.\d{1,6}$')][string]$Version,
    [Parameter(Mandatory,ParameterSetName='Sign')][string]$OutputPath,
    [string]$KeyPath = (Join-Path $env:APPDATA 'QuotaViewBuild/windows-update-signing.dpapi')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
$publicPath=Join-Path $PSScriptRoot 'public-key.pem'
$rsa=[Security.Cryptography.RSA]::Create(3072)
try {
    if($InitializeKey){
        if((Test-Path -LiteralPath $KeyPath) -or (Test-Path -LiteralPath $publicPath)){throw 'Signing key already exists. Never replace the update trust root during a normal build.'}
        $private=$rsa.ExportPkcs8PrivateKey()
        try {
            $protected=[Security.Cryptography.ProtectedData]::Protect($private,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($KeyPath))) | Out-Null
            [IO.File]::WriteAllBytes($KeyPath,$protected)
            [IO.File]::WriteAllText($publicPath,$rsa.ExportSubjectPublicKeyInfoPem()+"`n")
        } finally { [Array]::Clear($private,0,$private.Length) }
        Write-Output 'Created Windows update public key. Private key is encrypted for the current Windows account outside the repository.'
        return
    }
    $archivePath=(Resolve-Path -LiteralPath $Archive).Path
    $expected="QuotaView-Windows-$Version-x64.zip"
    if([IO.Path]::GetFileName($archivePath) -ne $expected){throw "Archive must be named $expected"}
    $length=(Get-Item -LiteralPath $archivePath).Length
    if($length -le 0 -or $length -gt 300MB){throw 'Invalid package size'}
    $zip=[IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entry=$zip.GetEntry('app/package.json')
        if(!$entry){throw 'Not a QuotaView standalone package'}
        $reader=[IO.StreamReader]::new($entry.Open())
        try { $identity=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if($identity.version -ne $Version -or !$zip.GetEntry('coreclr.dll')){throw 'Package version or standalone runtime mismatch'}
    } finally { $zip.Dispose() }
    $private=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($KeyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { $read=0; $rsa.ImportPkcs8PrivateKey($private,[ref]$read) } finally { [Array]::Clear($private,0,$private.Length) }
    if($rsa.ExportSubjectPublicKeyInfoPem().Trim() -cne [IO.File]::ReadAllText($publicPath).Trim()){throw 'Signing key does not match the public key pinned in this application'}
    $hash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $url="https://github.com/Duoasa/QuotaView/releases/download/v$Version/$expected"
    $canonical="QuotaView-Windows-v1`n$Version`nwindows`nx64`nstandalone`n$url`n$length`n$hash`n"
    $signature=[Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($canonical),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pss))
    $doc=[xml]@"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:qv="https://quotaview.app/windows-update/v1">
  <channel>
    <title>QuotaView Windows</title>
    <link>https://github.com/Duoasa/QuotaView/tree/main/Windows</link>
    <description>Windows x64 standalone updates</description>
    <item>
      <title>QuotaView $Version for Windows</title>
      <link>https://github.com/Duoasa/QuotaView/releases/tag/v$Version</link>
      <pubDate>$([DateTime]::UtcNow.ToString('r',[Globalization.CultureInfo]::InvariantCulture))</pubDate>
      <enclosure url="$url" length="$length" type="application/zip" qv:version="$Version" qv:os="windows" qv:arch="x64" qv:kind="standalone" qv:sha256="$hash" qv:signature="$signature" />
    </item>
  </channel>
</rss>
"@
    $doc.Save([IO.Path]::GetFullPath($OutputPath))
    Write-Output "Generated signed Windows appcast: $OutputPath (not published)"
} finally { $rsa.Dispose() }
