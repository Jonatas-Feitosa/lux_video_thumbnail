param([Parameter(Mandatory=$true)][string]$FlutterSdk)

# Flutter 3.38's Windows test runner converts URL paths to backslashes before
# checking the canvaskit/ prefix. Its normal test-directory static handler
# remains functional, so place renderer assets there without changing the SDK.
$taskAssetSource = Join-Path $FlutterSdk 'bin\cache\flutter_web_sdk\canvaskit'
$taskAssetTarget = Join-Path $PSScriptRoot '..\test\canvaskit'
New-Item -ItemType Directory -Path (Join-Path $taskAssetTarget 'chromium') -Force | Out-Null
foreach ($taskAssetName in @('canvaskit.js','canvaskit.wasm','chromium\canvaskit.js','chromium\canvaskit.wasm','skwasm.js','skwasm.wasm','skwasm_heavy.js','skwasm_heavy.wasm')) {
    Copy-Item -LiteralPath (Join-Path $taskAssetSource $taskAssetName) -Destination (Join-Path $taskAssetTarget $taskAssetName)
}
Write-Output 'Prepared local renderer assets for browser tests; SDK unchanged.'
