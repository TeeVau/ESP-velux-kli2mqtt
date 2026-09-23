$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $repoRoot "firmware\velux_kli2mqtt\velux_kli2mqtt.ino")
$config = Get-Content -Raw (Join-Path $repoRoot "firmware\velux_kli2mqtt\config.h")

$checks = @(
  @{ Name = "GPIO mapping"; Pass = $config -match 'kOpenPin = D5' -and $config -match 'kStopPin = D6' -and $config -match 'kClosePin = D7' },
  @{ Name = "No blocking delay"; Pass = $source -notmatch '\bdelay\s*\(' },
  @{ Name = "Open-drain actuation"; Pass = $source -match 'OUTPUT_OPEN_DRAIN' -and $source -match 'pinMode\(activePin, INPUT\)' },
  @{ Name = "STOP priority"; Pass = $source -match 'command == Command::kStop' -and $source -match 'pendingCommand = Command::kStop' },
  @{ Name = "OTA version policy"; Pass = $source -match 'isSameOrNewerVersion' -and $source -match 'X-Firmware-Project' },
  @{ Name = "No periodic technical telemetry"; Pass = $source -notmatch 'millis\(\) / 1000UL' -and $source -notmatch 'ESP\.getFreeHeap\(\)' -and $source -notmatch 'kStatusIntervalMs' }
)

$failed = @($checks | Where-Object { -not $_.Pass })
$checks | ForEach-Object { Write-Host "[static] $($_.Name): $($(if ($_.Pass) { 'PASS' } else { 'FAIL' }))" }
if ($failed.Count -gt 0) { throw "Static contract checks failed." }
