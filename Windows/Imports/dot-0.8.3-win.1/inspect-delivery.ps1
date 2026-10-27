param([string]$Source = 'F:/Codex Project/新建文件夹')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$auditRoot = $PSScriptRoot
$kit = [IO.Compression.ZipFile]::OpenRead((Join-Path $Source 'QuotaView-Windows-START-HERE-join-kit.zip'))
try {
    foreach ($name in @('START-HERE.txt','runtime-parts.json','WINDOWS_HANDOFF.md','Join-Runtime.ps1','Join-Runtime.cmd')) {
        $entry = $kit.GetEntry($name)
        if ($null -eq $entry -or $entry.Length -gt 65536) { throw "Unexpected join-kit entry: $name" }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $value = $reader.ReadToEnd() } finally { $reader.Dispose() }
        [IO.Directory]::CreateDirectory((Join-Path $auditRoot 'join-kit')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $auditRoot "join-kit/$name"),$value)
        if ($name -eq 'runtime-parts.json') { $manifest = $value | ConvertFrom-Json }
    }
} finally { $kit.Dispose() }
if ($manifest.parts.Count -ne 12 -or $manifest.bytes -ne 239424838 -or $manifest.sha256 -ne 'cf65a7b60e08e0167638c438ccf24ae13918ccf76f885a67faddecf9505ab614') { throw 'Unexpected delivery identity.' }
$combined = Join-Path $auditRoot 'verified-runtime.zip'
if (Test-Path -LiteralPath $combined) { throw 'Output exists. Inspect existing delivery instead of overwriting.' }
$checks = @()
$output = [IO.File]::Open($combined,[IO.FileMode]::CreateNew)
try {
    foreach ($part in $manifest.parts) {
        if ($part.archive -notmatch '^QuotaView-Windows-runtime-part-\d{2}\.zip$') { throw 'Unexpected part name.' }
        $path = Join-Path $Source $part.archive
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $part.archiveSHA256) { throw "Archive checksum mismatch: $path" }
        $zip = [IO.Compression.ZipFile]::OpenRead($path)
        try {
            $entry = $zip.GetEntry($part.entry)
            if ($null -eq $entry -or $entry.Length -ne $part.bytes) { throw 'Unexpected part size.' }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $rawHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($rawHash -ne $part.sha256) { throw 'Part data checksum mismatch.' }
            $stream = $entry.Open()
            try { $stream.CopyTo($output) } finally { $stream.Dispose() }
            $checks += [pscustomobject]@{archive=$part.archive;archiveSHA256=$hash;partSHA256=$rawHash;bytes=$part.bytes;verified=$true}
        } finally { $zip.Dispose() }
    }
} finally { $output.Dispose() }
$combinedHash = (Get-FileHash -LiteralPath $combined -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Get-Item -LiteralPath $combined).Length -ne $manifest.bytes -or $combinedHash -ne $manifest.sha256) { throw 'Combined archive mismatch.' }
$runtime = [IO.Path]::GetFullPath((Join-Path $auditRoot 'runtime'))
[IO.Directory]::CreateDirectory($runtime) | Out-Null
$prefix = $runtime + [IO.Path]::DirectorySeparatorChar
$zip = [IO.Compression.ZipFile]::OpenRead($combined)
$inventory = @()
try {
    $total = ($zip.Entries | Measure-Object Length -Sum).Sum
    if ($total -gt 2GB) { throw 'Unexpected expanded size.' }
    foreach ($entry in $zip.Entries) {
        $target = [IO.Path]::GetFullPath((Join-Path $runtime $entry.FullName))
        if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':')) { throw 'Unsafe archive path.' }
        if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Archive symlink not permitted.' }
        if ($entry.FullName.EndsWith('/')) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        $inputStream = $entry.Open(); $outputStream = [IO.File]::Open($target,[IO.FileMode]::CreateNew)
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose();$outputStream.Dispose() }
        $inventory += [pscustomobject]@{path=$entry.FullName;bytes=$entry.Length}
    }
} finally { $zip.Dispose() }
[pscustomobject]@{source=$Source;combinedSHA256=$combinedHash;combinedBytes=$manifest.bytes;expandedBytes=$total;parts=$checks;files=$inventory} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $auditRoot 'inventory.json') -Encoding utf8
Write-Output "Verified 12 archive hashes, 12 raw part hashes and combined hash. Expanded bytes: $total"
$inventory | Format-Table -AutoSize
