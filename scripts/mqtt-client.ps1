<#
.SYNOPSIS
Runs mosquitto_sub or mosquitto_pub without storing MQTT passwords in the project.

Credentials are prompted interactively or stored with Windows DPAPI below
%LOCALAPPDATA%\codex-arduino-tools\mqtt.
#>

[CmdletBinding()]
param(
  [ValidateSet("sub", "pub")][string]$Mode = "sub",
  [Alias("Server")][string]$BrokerHost = $env:MQTT_BROKER_HOST,
  [int]$Port = $(if ($env:MQTT_BROKER_PORT) { [int]$env:MQTT_BROKER_PORT } else { 0 }),
  [string]$RootTopic = $env:MQTT_ROOT_TOPIC,
  [string]$Topic = "",
  [string]$Message = "",
  [string]$Username = $env:MQTT_USERNAME,
  [string]$ClientId = "",
  [ValidateRange(0, 2)][int]$Qos = 0,
  [ValidateRange(0, 2147483647)][int]$Count = 0,
  [switch]$Retain,
  [switch]$NoCredential,
  [switch]$SaveCredential,
  [switch]$ForgetCredential,
  [switch]$VerboseMqtt,
  [string]$CredentialName = "default",
  [string]$ConfigPath = "firmware/velux_kli2mqtt/secrets.h",
  [string]$BrokerHostMacro = "VK_MQTT_HOST",
  [string]$PortMacro = "VK_MQTT_PORT",
  [string]$RootTopicMacro = "VK_MQTT_ROOT_TOPIC",
  [string]$UsernameMacro = "VK_MQTT_USERNAME",
  [string]$DefaultRootTopic = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $repoRoot $ConfigPath }

function Resolve-MosquittoTool {
  param([Parameter(Mandatory = $true)][string]$BaseName)

  $command = Get-Command "$BaseName.exe" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $fallback = Join-Path $env:ProgramFiles "mosquitto\$BaseName.exe"
  if (Test-Path -LiteralPath $fallback) { return $fallback }
  throw "$BaseName.exe wurde nicht gefunden. Installiere die Mosquitto-Clients oder ergänze PATH."
}

function Get-CredentialStorePath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $safeName = $Name -replace "[^A-Za-z0-9._-]", "_"
  $storeDir = Join-Path $env:LOCALAPPDATA "codex-arduino-tools\mqtt"
  return Join-Path $storeDir "$safeName.credential.xml"
}

function Convert-SecureStringToPlainText {
  param([Parameter(Mandatory = $true)][securestring]$SecureString)

  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Read-MqttCredential {
  param([string]$DefaultUsername)

  $promptUsername = $DefaultUsername
  if ([string]::IsNullOrWhiteSpace($promptUsername)) {
    $promptUsername = Read-Host "MQTT username"
  }
  $promptPassword = Read-Host "MQTT password" -AsSecureString
  return [pscredential]::new($promptUsername, $promptPassword)
}

function Get-ConfigMacroValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$MacroName
  )

  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $pattern = '^\s*#define\s+' + [regex]::Escape($MacroName) + '\s+(.+?)\s*$'
  $matches = @(Select-String -Path $Path -Pattern $pattern)
  if ($matches.Count -eq 0) { return $null }

  $value = $matches[-1].Matches[0].Groups[1].Value.Trim()
  if ($value.StartsWith('"') -and $value.EndsWith('"')) {
    return $value.Trim('"')
  }
  return $value
}

function Resolve-ConfigValue {
  param(
    [AllowEmptyString()][string]$CurrentValue,
    [Parameter(Mandatory = $true)][string]$MacroName,
    [string]$FallbackValue = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) { return $CurrentValue }
  $value = Get-ConfigMacroValue -Path $ConfigPath -MacroName $MacroName
  if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
  return $FallbackValue
}

$BrokerHost = Resolve-ConfigValue -CurrentValue $BrokerHost -MacroName $BrokerHostMacro
$Username = Resolve-ConfigValue -CurrentValue $Username -MacroName $UsernameMacro
$RootTopic = Resolve-ConfigValue -CurrentValue $RootTopic -MacroName $RootTopicMacro -FallbackValue $DefaultRootTopic
if ($Port -le 0) {
  $Port = [int](Resolve-ConfigValue -CurrentValue "" -MacroName $PortMacro -FallbackValue "1883")
}

if ([string]::IsNullOrWhiteSpace($BrokerHost)) { $BrokerHost = Read-Host "MQTT broker host" }
if ($Port -lt 1 -or $Port -gt 65535) { throw "MQTT port must be between 1 and 65535." }
if ([string]::IsNullOrWhiteSpace($RootTopic)) { throw "MQTT root topic is missing." }

$rootTopicClean = $RootTopic.TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($Topic)) {
  $Topic = if ($Mode -eq "sub") { "$rootTopicClean/#" } else { "$rootTopicClean/diagnostic/windows_client_test" }
}
if ($Mode -eq "pub" -and [string]::IsNullOrWhiteSpace($Message)) {
  $Message = "windows mqtt client test $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')"
}

$credentialPath = Get-CredentialStorePath -Name $CredentialName
if ($ForgetCredential) {
  if (Test-Path -LiteralPath $credentialPath) {
    Remove-Item -LiteralPath $credentialPath -Force
    Write-Host "Removed stored MQTT credential: $credentialPath"
  } else {
    Write-Host "No stored MQTT credential found at: $credentialPath"
  }
  if ($PSBoundParameters.Count -eq 1) { return }
}

$credential = $null
$plainPassword = $null
try {
  if (-not $NoCredential) {
    if (Test-Path -LiteralPath $credentialPath) {
      $credential = Import-Clixml -LiteralPath $credentialPath
      Write-Host "Using DPAPI-protected credential from: $credentialPath"
    } else {
      $credential = Read-MqttCredential -DefaultUsername $Username
      if ($SaveCredential) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $credentialPath) | Out-Null
        $credential | Export-Clixml -LiteralPath $credentialPath
        Write-Host "Saved DPAPI-protected credential to: $credentialPath"
      }
    }
  }

  $toolName = if ($Mode -eq "sub") { "mosquitto_sub" } else { "mosquitto_pub" }
  $toolPath = Resolve-MosquittoTool -BaseName $toolName
  $mqttArgs = @("-h", $BrokerHost, "-p", $Port.ToString(), "-t", $Topic, "-q", $Qos.ToString())

  if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $mqttArgs += @("-i", $ClientId) }
  if ($credential) {
    $plainPassword = Convert-SecureStringToPlainText -SecureString $credential.Password
    $mqttArgs += @("-u", $credential.UserName, "-P", $plainPassword)
  }
  if ($VerboseMqtt) { $mqttArgs += "-d" }

  if ($Mode -eq "sub") {
    if ($Count -gt 0) { $mqttArgs += @("-C", $Count.ToString()) }
    $mqttArgs += "-v"
    Write-Host "Subscribing to '$Topic' on ${BrokerHost}:$Port. Press Ctrl+C to stop."
  } else {
    if ($Retain) { $mqttArgs += "-r" }
    $mqttArgs += @("-m", $Message)
    Write-Host "Publishing to '$Topic' on ${BrokerHost}:$Port."
  }

  & $toolPath @mqttArgs
  exit $LASTEXITCODE
}
finally {
  $plainPassword = $null
}
