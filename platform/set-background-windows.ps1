$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

try {
    $application = Join-Path $PSScriptRoot 'doodle_reef.exe'
    if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
        throw 'The wallpaper helper must be beside doodle_reef.exe. Rebuild the app and try again.'
    }
    if ([string]::IsNullOrWhiteSpace($env:DOODLE_REEF_BACKGROUND_DATA)) {
        throw 'Open DOODLE REEF and use its Set as desktop background button.'
    }
    $dataDirectory = [IO.Path]::GetFullPath($env:DOODLE_REEF_BACKGROUND_DATA)
    if (-not (Test-Path -LiteralPath (Join-Path $dataDirectory 'creatures.reef') -PathType Leaf)) {
        throw 'The aquarium has not been saved. Return to DOODLE REEF and try again.'
    }

    $candidates = @()
    $running = Get-Process -Name Lively -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running) { $candidates += $running.Path }
    $uninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{E3E43E1B-DEC8-44BF-84A6-243DBA3F2CB1}_is1'
    foreach ($hive in @('HKCU:', 'HKLM:')) {
        $installed = Get-ItemProperty -LiteralPath "$hive\$uninstallKey" -ErrorAction SilentlyContinue
        if ($installed.InstallLocation) { $candidates += Join-Path $installed.InstallLocation 'Lively.exe' }
    }
    $candidates += Join-Path $env:LOCALAPPDATA 'Programs\Lively Wallpaper\Lively.exe'
    $candidates += Join-Path $env:ProgramFiles 'Lively Wallpaper\Lively.exe'
    $lively = $candidates | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) -and $_ -notlike '*\WindowsApps\*'
    } | Select-Object -First 1
    if (-not $lively) {
        $choice = [Windows.Forms.MessageBox]::Show(
            'Lively Wallpaper desktop edition is required. Install it and finish its first-run setup, then click this button again. Open its download page?',
            'DOODLE REEF - Get Lively', [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Information)
        if ($choice -eq [Windows.Forms.DialogResult]::Yes) {
            Start-Process 'https://github.com/rocksdanister/lively/releases'
        }
        exit 0
    }

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Lively Wallpaper\Settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        Start-Process -FilePath $lively -WindowStyle Normal
        throw 'Finish Lively Wallpaper''s first-run setup, then return to DOODLE REEF and click Set as desktop background again.'
    }
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($settings.WallpaperDir) -or -not [IO.Path]::IsPathRooted($settings.WallpaperDir)) {
        throw 'Open Lively and choose its wallpaper library folder, then try again.'
    }
    $project = Join-Path $settings.WallpaperDir 'wallpapers\doodle-reef-managed'
    $metadataPath = Join-Path $project 'LivelyInfo.json'
    if (Test-Path -LiteralPath $metadataPath) {
        $existing = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        if ($existing.Title -ne 'DOODLE REEF') {
            throw 'The Lively folder doodle-reef-managed belongs to another wallpaper. Rename that folder in Lively before trying again.'
        }
    }
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    $metadata = [ordered]@{
        AppVersion = '1.3.0.0'
        Title = 'DOODLE REEF'
        Desc = 'Your doodles swimming in a quiet desktop aquarium.'
        Author = 'DOODLE REEF'
        Type = 0
        FileName = $application
        Arguments = "--wallpaper --fps 30 --data-dir `"$dataDirectory`""
        IsAbsolutePath = $true
    }
    [IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Start-Process -FilePath $lively -ArgumentList @('setwp', '--file', ('"{0}"' -f $project)) -WindowStyle Hidden
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'DOODLE REEF - Wallpaper setup',
        [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    exit 1
}
