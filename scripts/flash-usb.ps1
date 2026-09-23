param(
  [Parameter(Mandatory = $true)][string]$Port,
  [string]$Fqbn = "esp8266:esp8266:d1_mini",
  [string]$ArduinoCli
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = if ($ArduinoCli) { $ArduinoCli } elseif (Get-Command arduino-cli -ErrorAction SilentlyContinue) {
  (Get-Command arduino-cli).Source
} else { "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe" }
if (-not (Test-Path -LiteralPath $cli)) { throw "arduino-cli was not found: $cli" }

$safeFqbn = $Fqbn -replace '[^A-Za-z0-9._-]', '_'
$inputDir = Join-Path $repoRoot ".arduino-build\$safeFqbn\output"
if (-not (Test-Path -LiteralPath $inputDir)) {
  & (Join-Path $PSScriptRoot "build.ps1") -Fqbn $Fqbn -ArduinoCli $cli
}
Write-Host "[flash] Checking detected boards before upload:"
& $cli board list --json
Write-Host "[flash] Uploading to $Port"
& $cli upload --port $Port --fqbn $Fqbn --input-dir $inputDir
exit $LASTEXITCODE
