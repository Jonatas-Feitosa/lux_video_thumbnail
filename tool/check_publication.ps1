param([string]$Dart = 'dart')

# Read-only publication simulation; never uploads, ignores warnings or forces publish.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskPackages = [ordered]@{
    lux_video_thumbnail_platform_interface = 'packages/lux_video_thumbnail_platform_interface'
    lux_video_thumbnail_android = 'packages/lux_video_thumbnail_android'
    lux_video_thumbnail_ios = 'packages/lux_video_thumbnail_ios'
    lux_video_thumbnail_web = 'packages/lux_video_thumbnail_web'
    lux_video_thumbnail = '.'
}
foreach ($taskRelative in $taskPackages.Values) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskRoot "$taskRelative/pubspec.yaml"))) {
        throw 'This script requires the full source checkout, including packages/.'
    }
}
$taskLogs = Join-Path $taskRoot '.dart_tool/publication/content'
New-Item -ItemType Directory -Force -Path $taskLogs | Out-Null
$taskCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub/Cache' }
$taskCacheLog = Join-Path $taskCache 'log/pub_log.txt'
$taskResults = @()
foreach ($taskName in $taskPackages.Keys) {
    Push-Location (Join-Path $taskRoot $taskPackages[$taskName])
    try {
        $taskStarted = [DateTime]::UtcNow
        $taskConsole = Join-Path $taskLogs "$taskName-pub-console.log"
        $ErrorActionPreference = 'Continue'
        & $Dart pub --verbose publish --dry-run *> $taskConsole
        $taskExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        # Serial execution is essential: Pub shares this cache log across commands.
        # Its event transcript preserves the entire tar list when stdout/stderr
        # console records would otherwise interleave and truncate it.
        if (-not (Test-Path -LiteralPath $taskCacheLog) -or
            (Get-Item -LiteralPath $taskCacheLog).LastWriteTimeUtc -lt $taskStarted) {
            throw "No fresh complete Pub log for $taskName; content was not validated."
        }
        $taskTranscript = Get-Content -LiteralPath $taskCacheLog -Raw -Encoding UTF8
        if (-not $taskTranscript.Contains('FINE: Creating .tar.gz stream containing:')) {
            throw "The Pub log for $taskName has no archive file list."
        }
        Copy-Item -LiteralPath $taskCacheLog -Destination (Join-Path $taskLogs "$taskName-pub-verbose.log") -Force
        $taskResults += [pscustomobject]@{ package = $taskName; exitCode = $taskExit }
        Write-Output "$taskName dry-run exit: $taskExit"
    } finally {
        $ErrorActionPreference = 'Stop'
        Pop-Location
    }
}
$taskResults | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskLogs 'dry-run-results.json') -Encoding UTF8
if (@($taskResults | Where-Object { $_.exitCode -ne 0 }).Count -gt 0) { exit 1 }
