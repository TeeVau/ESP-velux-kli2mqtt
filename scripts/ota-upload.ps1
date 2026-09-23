param(
  [string]$FirmwarePath,
  [string]$RootTopic,
  [int]$WaitSeconds = 45
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mqtt = Join-Path $PSScriptRoot "mqtt-client.ps1"
$secrets = Join-Path $repoRoot "firmware\velux_kli2mqtt\secrets.h"

function Read-Define([string]$Name) {
  $pattern = '^\s*#define\s+{0}\s+(?:"([^"]*)"|(\S+))' -f [regex]::Escape($Name)
  $match = Select-String -Path $secrets -Pattern $pattern | Select-Object -First 1
  if ($match) {
    $groups = $match.Matches[0].Groups
    return $(if ($groups[1].Success) { $groups[1].Value } else { $groups[2].Value })
  }
  return $null
}
if (-not (Test-Path -LiteralPath $secrets)) { throw "Create firmware/velux_kli2mqtt/secrets.h before OTA." }
if (-not $RootTopic) { $RootTopic = Read-Define "VK_MQTT_ROOT_TOPIC" }
if (-not $RootTopic) { throw "VK_MQTT_ROOT_TOPIC is missing from secrets.h." }
if (-not $FirmwarePath) {
  $FirmwarePath = (Get-ChildItem -LiteralPath (Join-Path $repoRoot "bin") -Filter "esp-velux-kli2mqtt-*.bin" -File |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
}
if (-not $FirmwarePath -or -not (Test-Path -LiteralPath $FirmwarePath)) { throw "No versioned firmware BIN found." }

$versionMatch = [regex]::Match((Split-Path -Leaf $FirmwarePath), '^esp-velux-kli2mqtt-(\d+\.\d+\.\d+)\.bin$')
if (-not $versionMatch.Success) { throw "Firmware name must be esp-velux-kli2mqtt-X.Y.Z.bin." }
$version = $versionMatch.Groups[1].Value

Write-Host "[ota] Arming OTA for $version"
& $mqtt -Action Publish -Topic "$RootTopic/ota/set" -Message "ENABLE"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$url = $null
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  $result = & $mqtt -Action Read -Topic "$RootTopic/ota/upload_url" -TimeoutSec 3 2>$null
  if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape("$RootTopic/ota/upload_url") + '\s+(http://\S+/update)') {
    $url = $Matches[1]
    break
  }
}
if (-not $url) { throw "Timed out waiting for the OTA upload URL." }

Write-Host "[ota] Uploading $FirmwarePath to $url"
& curl.exe --noproxy "*" -sS -f -H "X-Firmware-Project: esp-velux-kli2mqtt" -H "X-Firmware-Version: $version" -F "firmware=@$FirmwarePath" $url
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$verifyDeadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $verifyDeadline) {
  Start-Sleep -Seconds 2
  $result = & $mqtt -Action Read -Topic "$RootTopic/firmware_version" -TimeoutSec 3 2>$null
  if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape("$RootTopic/firmware_version") + "\s+$([regex]::Escape($version))$") {
    Write-Host "[ota] Verified firmware version $version"
    exit 0
  }
}
throw "OTA upload returned successfully but the MQTT version was not verified."
