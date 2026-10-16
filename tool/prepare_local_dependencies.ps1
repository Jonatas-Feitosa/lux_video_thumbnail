# Create development-only overrides; distribution manifests stay hosted.
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskPackages = @('lux_video_thumbnail_platform_interface', 'lux_video_thumbnail_android', 'lux_video_thumbnail_web')
foreach ($taskPackage in $taskPackages) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskRoot "packages/$taskPackage/pubspec.yaml"))) {
        throw 'Local overrides require the full source checkout with packages/. Use hosted dependencies in an extracted package.'
    }
}
$taskOverrides = @{}
$taskOverrides[$taskRoot] = "dependency_overrides:`n" + (($taskPackages | ForEach-Object { "  ${_}:`n    path: packages/$_`n" }) -join '')
$taskOverrides[(Join-Path $taskRoot 'example')] = "dependency_overrides:`n" + (($taskPackages | ForEach-Object { "  ${_}:`n    path: ../packages/$_`n" }) -join '')
foreach ($taskPlatform in @('android', 'web')) {
    $taskOverrides[(Join-Path $taskRoot "packages/lux_video_thumbnail_$taskPlatform")] = "dependency_overrides:`n  lux_video_thumbnail_platform_interface:`n    path: ../lux_video_thumbnail_platform_interface`n"
}
foreach ($taskDirectory in $taskOverrides.Keys) {
    $taskTarget = Join-Path $taskDirectory 'pubspec_overrides.yaml'
    $taskExpected = $taskOverrides[$taskDirectory]
    if (Test-Path -LiteralPath $taskTarget) {
        $taskExisting = [IO.File]::ReadAllText($taskTarget).Replace("`r`n", "`n").TrimEnd()
        if ($taskExisting -ne $taskExpected.TrimEnd()) {
            throw "Preserving custom overrides: $taskTarget. Merge local dependencies manually."
        }
    } else {
        [IO.File]::WriteAllText($taskTarget, $taskExpected)
    }
}
Write-Output 'Local overrides ready. Run flutter pub get in the desired package or example.'
