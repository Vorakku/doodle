param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$env:GOOSE_HOME = Join-Path $PSScriptRoot '.tools\cache'
$compiler = Join-Path $PSScriptRoot '.tools\goose-v2026.3-windows-x64\goose.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'Extract the official Goose v2026.3 Windows x64 release into .tools first. See README.md.'
}
if (-not $SkipTests) {
    & $compiler reef_test.goose --debug
    if ($LASTEXITCODE -ne 0) { throw 'Reef checks failed.' }
    & $compiler build reef_ui_test.goose -o .test-data/reef_ui_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'UI check build failed.' }
    $previousHeadless = $env:GOOSE_GFX_HEADLESS
    try {
        $env:GOOSE_GFX_HEADLESS = '1'
        & .\.test-data\reef_ui_test.exe
        if ($LASTEXITCODE -ne 0) { throw 'UI interaction checks failed.' }
    } finally {
        if ($null -eq $previousHeadless) { Remove-Item Env:GOOSE_GFX_HEADLESS -ErrorAction SilentlyContinue }
        else { $env:GOOSE_GFX_HEADLESS = $previousHeadless }
    }
}
& $compiler build doodle_reef.goose -o build/doodle_reef.exe
if ($LASTEXITCODE -ne 0) { throw 'Goose build failed.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$editbin = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\editbin.exe' | Select-Object -First 1
if (-not $editbin) { throw 'Visual Studio editbin.exe was not found.' }
$appPath = Join-Path $PSScriptRoot 'build\doodle_reef.exe'
& $editbin /NOLOGO /SUBSYSTEM:WINDOWS $appPath
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the Windows GUI executable.' }
$appImage = [IO.File]::ReadAllBytes($appPath)
$peOffset = [BitConverter]::ToInt32($appImage, 60)
if ([BitConverter]::ToUInt16($appImage, $peOffset + 24 + 68) -ne 2) { throw 'The executable still requests a console.' }

$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $PSScriptRoot 'Doodle Reef.lnk'))
$shortcut.TargetPath = $appPath
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Save()
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'platform\set-background-windows.ps1') -Destination (Join-Path $PSScriptRoot 'build\set-background-windows.ps1') -Force

$packageDir = Join-Path $PSScriptRoot 'build\lively'
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build\doodle_reef.exe') -Destination $packageDir -Force
$dataDir = Join-Path $PSScriptRoot 'build\data'
$info = [ordered]@{
    AppVersion = '1.3.0.0'
    Title = 'DOODLE REEF'
    Desc = 'Your doodles swimming in a quiet desktop aquarium.'
    Author = 'DOODLE REEF'
    Type = 0
    FileName = 'doodle_reef.exe'
    Arguments = "--wallpaper --fps 30 --data-dir `"$dataDir`""
    IsAbsolutePath = $false
}
$jsonPath = Join-Path $packageDir 'LivelyInfo.json'
[IO.File]::WriteAllText($jsonPath, ($info | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath (Join-Path $PSScriptRoot 'build\doodle-reef-lively.zip') -Force
Write-Output 'Packaged build\doodle-reef-lively.zip. Import it into the standalone version of Lively Wallpaper.'
