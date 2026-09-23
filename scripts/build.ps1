param(
  [string]$Fqbn = "esp8266:esp8266:d1_mini",
  [string]$SketchDir = "firmware/velux_kli2mqtt",
  [string]$BuildRoot = ".arduino-build",
  [string]$ReleaseDir = "bin",
  [string]$ArduinoCli
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-ArduinoCli([string]$ExplicitPath) {
  if ($ExplicitPath) { return $ExplicitPath }
  $command = Get-Command arduino-cli -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $fallback = "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
  if (Test-Path -LiteralPath $fallback) { return $fallback }
  throw "arduino-cli was not found. Install Arduino IDE or pass -ArduinoCli."
}

$cli = Resolve-ArduinoCli $ArduinoCli
$sketchPath = Join-Path $repoRoot $SketchDir
$sketchName = Split-Path -Leaf $sketchPath
$versionFile = Join-Path $sketchPath "config.h"
$versionMatch = Select-String -Path $versionFile -Pattern '^#define\s+VK_FIRMWARE_VERSION\s+"([^"]+)"' | Select-Object -First 1
if ($null -eq $versionMatch) { throw "VK_FIRMWARE_VERSION was not found in $versionFile." }
$version = $versionMatch.Matches[0].Groups[1].Value
$safeFqbn = $Fqbn -replace '[^A-Za-z0-9._-]', '_'
$buildPath = Join-Path $repoRoot "$BuildRoot\$safeFqbn\build"
$outputPath = Join-Path $repoRoot "$BuildRoot\$safeFqbn\output"
$releasePath = Join-Path $repoRoot $ReleaseDir

New-Item -ItemType Directory -Force -Path $buildPath,$outputPath,$releasePath | Out-Null
Write-Host "[build] Arduino CLI: $cli"
Write-Host "[build] FQBN: $Fqbn"
Write-Host "[build] Firmware version: $version"
& $cli compile --fqbn $Fqbn --build-path $buildPath --output-dir $outputPath $sketchPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$firmware = Join-Path $outputPath "$sketchName.ino.bin"
if (-not (Test-Path -LiteralPath $firmware)) { throw "Compiled BIN was not found: $firmware" }
$release = Join-Path $releasePath "esp-velux-kli2mqtt-$version.bin"
Copy-Item -LiteralPath $firmware -Destination $release -Force
Write-Host "[build] Versioned firmware: $release"
