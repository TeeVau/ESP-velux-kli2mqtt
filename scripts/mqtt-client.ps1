param(
  [Parameter(Mandatory = $true)][ValidateSet("Publish", "Read")][string]$Action,
  [Parameter(Mandatory = $true)][string]$Topic,
  [string]$Message,
  [string]$BrokerHost,
  [int]$Port = 0,
  [string]$Username,
  [string]$Password,
  [int]$TimeoutSec = 5,
  [switch]$Retain,
  [switch]$NoCredential
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$secrets = Join-Path $repoRoot "firmware\velux_kli2mqtt\secrets.h"

function Read-Define([string]$Name) {
  if (-not (Test-Path -LiteralPath $secrets)) { return $null }
  $pattern = '^\s*#define\s+{0}\s+(?:"([^"]*)"|(\S+))' -f [regex]::Escape($Name)
  $match = Select-String -Path $secrets -Pattern $pattern | Select-Object -First 1
  if ($match) {
    $groups = $match.Matches[0].Groups
    return $(if ($groups[1].Success) { $groups[1].Value } else { $groups[2].Value })
  }
  return $null
}
function Resolve-Mosquitto([string]$CommandName) {
  $command = Get-Command $CommandName -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $fallback = Join-Path $env:ProgramFiles "mosquitto\$CommandName.exe"
  if (Test-Path -LiteralPath $fallback) { return $fallback }
  throw "$CommandName was not found. Install Mosquitto clients or add them to PATH."
}

if (-not $BrokerHost) { $BrokerHost = Read-Define "VK_MQTT_HOST" }
if ($Port -eq 0) { $Port = [int](Read-Define "VK_MQTT_PORT") }
if (-not $Username) { $Username = Read-Define "VK_MQTT_USERNAME" }
if (-not $Password) { $Password = Read-Define "VK_MQTT_PASSWORD" }
if (-not $BrokerHost -or $Port -eq 0) { throw "Set broker host and port in secrets.h or pass parameters." }

$args = @("-h", $BrokerHost, "-p", "$Port", "-t", $Topic)
if (-not $NoCredential) {
  if (-not $Username -or -not $Password) { throw "MQTT credentials are missing." }
  $args += @("-u", $Username, "-P", $Password)
}
if ($Action -eq "Publish") {
  if ($null -eq $Message) { throw "-Message is required for Publish." }
  $args += @("-m", $Message, "-q", "0")
  if ($Retain) { $args += "-r" }
  & (Resolve-Mosquitto "mosquitto_pub") @args
} else {
  $args += @("-C", "1", "-W", "$TimeoutSec", "-v")
  & (Resolve-Mosquitto "mosquitto_sub") @args
}
exit $LASTEXITCODE
