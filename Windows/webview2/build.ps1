param([ValidateSet('build','run','test','publish')][string]$Action='build', [switch]$FrameworkDependent)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $dotnet=Get-Command dotnet -ErrorAction SilentlyContinue
    if(!$dotnet){throw '.NET 10 SDK is required. Install it or add dotnet.exe to PATH.'}
    & pnpm install --frozen-lockfile
    if($LASTEXITCODE -ne 0){throw 'Dependency restore failed'}
    & pnpm build
    if($LASTEXITCODE -ne 0){throw 'JavaScript build failed'}
    & dotnet restore --locked-mode
    if($LASTEXITCODE -ne 0){throw '.NET restore failed'}
    & dotnet build -c Release --no-restore
    if($LASTEXITCODE -ne 0){throw '.NET build failed'}
    $exe=Join-Path $PSScriptRoot 'bin/Release/net10.0-windows/QuotaView.Native.exe'
    if($Action -eq 'run'){Start-Process -FilePath $exe -WindowStyle Hidden}
    if($Action -eq 'test'){
        & dotnet run --project tests/updates/Updates.Tests.csproj -c Release
        if($LASTEXITCODE -ne 0){throw 'Windows update validation failed'}
        foreach($kind in @('smoke','adapter','approval')){
            $report=Join-Path $PSScriptRoot ('build/'+$kind+'-report.json')
            $started=Get-Date
            $process=Start-Process -FilePath $exe -ArgumentList @('--'+$kind+'-test',('"--'+$kind+'-report='+$report+'"')) -WindowStyle Hidden -PassThru
            if(!$process.WaitForExit(60000)){$process.Kill();throw ($kind+' test timed out')}
            if($process.ExitCode -ne 0 -or !(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started -or !(Get-Content $report -Raw|ConvertFrom-Json).ok){throw ($kind+' test failed. See '+$report)}
            Write-Output ($kind+' test passed: '+$report)
        }
        $env:QUOTAVIEW_HELPER=$exe
        $env:NODE_PATH=Join-Path $PSScriptRoot 'node_modules'
        & node --test ../ElectronEffects/tests/model.test.cjs ../windows/tests/*.test.cjs
        if($LASTEXITCODE -ne 0){throw 'Application regression tests failed'}
    }
    if($Action -eq 'publish'){
        $flavor=if($FrameworkDependent){'framework-dependent'}else{'standalone'}
        $dest=Join-Path $PSScriptRoot ('release/'+$flavor)
        $releaseRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'release'))
        $resolvedDest=[IO.Path]::GetFullPath($dest)
        if(!$resolvedDest.StartsWith($releaseRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid publish destination'}
        if(Test-Path -LiteralPath $resolvedDest){Remove-Item -LiteralPath $resolvedDest -Recurse -Force}
        & dotnet publish -c Release -r win-x64 --self-contained ($FrameworkDependent.IsPresent -eq $false).ToString().ToLower() -p:DebugType=none -o $dest
        if($LASTEXITCODE -ne 0){throw 'Publish failed'}
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../LICENSE') -Destination (Join-Path $dest 'LICENSE.txt')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $dest 'README.md')
        $version=(Get-Content (Join-Path $PSScriptRoot '../version.json') -Raw | ConvertFrom-Json).version
        $archive=Join-Path $PSScriptRoot $(if($FrameworkDependent){"release/QuotaView-Windows-$version-x64-framework-dependent.zip"}else{"release/QuotaView-Windows-$version-x64.zip"})
        Compress-Archive -Path ($dest+'/*') -DestinationPath $archive -Force
        Write-Output $archive
    }
} finally { Pop-Location }
