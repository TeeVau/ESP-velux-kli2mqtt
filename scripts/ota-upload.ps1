<#
.SYNOPSIS
Arms an MQTT-controlled OTA window, uploads a versioned BIN, and verifies it.

MQTT passwords are prompted or loaded from a Windows DPAPI credential store;
they are never read from the firmware secrets file or written to the project.
#>

[CmdletBinding()]
param(
  [string]$FirmwarePath,
  [string]$ProjectName = "esp-velux-kli2mqtt",
  [string]$BinDirectory = "bin",
  [string]$BrokerHost = $env:MQTT_BROKER_HOST,
  [int]$Port = $(if ($env:MQTT_BROKER_PORT) { [int]$env:MQTT_BROKER_PORT } else { 0 }),
  [string]$RootTopic = $env:MQTT_ROOT_TOPIC,
  [string]$Username = $env:MQTT_USERNAME,
  [string]$CredentialName = "default",
  [switch]$NoCredential,
  [switch]$SaveCredential,
  [string]$ConfigPath = "firmware/velux_kli2mqtt/secrets.h",
  [string]$BrokerHostMacro = "VK_MQTT_HOST",
  [string]$PortMacro = "VK_MQTT_PORT",
  [string]$RootTopicMacro = "VK_MQTT_ROOT_TOPIC",
  [string]$UsernameMacro = "VK_MQTT_USERNAME",
  [string]$OtaEnableTopicSuffix = "/ota/set",
  [string]$OtaEnableMessage = "ENABLE",
  [string]$OtaUrlTopicSuffix = "/ota/upload_url",
  [string]$OtaStatusTopicSuffix = "/ota/status",
  [string]$FirmwareVersionTopicSuffix = "/firmware_version",
  [string]$AvailabilityTopicSuffix = "/availability",
  [int]$UrlWaitTimeoutSec = 60,
  [int]$VerifyTimeoutSec = 180,
  [string]$UploadUrl,
  [switch]$SkipVerify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($UrlWaitTimeoutSec -lt 1 -or $VerifyTimeoutSec -lt 1) { throw "OTA timeouts must be at least 1 second." }

function Resolve-ToolPath {
  param(
    [Parameter(Mandatory = $true)][string]$CommandName,
    [string]$ProgramFilesFallback
  )

  $command = Get-Command $CommandName -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  if ($ProgramFilesFallback) {
    $fallback = Join-Path $env:ProgramFiles $ProgramFilesFallback
    if (Test-Path -LiteralPath $fallback) { return $fallback }
  }
  throw "$CommandName wurde nicht gefunden."
}

function Get-ConfigMacroValue {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$MacroName)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $pattern = '^\s*#define\s+' + [regex]::Escape($MacroName) + '\s+(.+?)\s*$'
  $matches = @(Select-String -Path $Path -Pattern $pattern)
  if ($matches.Count -eq 0) { return $null }
  $value = $matches[-1].Matches[0].Groups[1].Value.Trim()
  if ($value.StartsWith('"') -and $value.EndsWith('"')) { return $value.Trim('"') }
  return $value
}

function Resolve-ConfigValue {
  param([AllowEmptyString()][string]$CurrentValue, [Parameter(Mandatory = $true)][string]$MacroName, [string]$FallbackValue = "")
  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) { return $CurrentValue }
  $value = Get-ConfigMacroValue -Path $ConfigPath -MacroName $MacroName
  if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
  return $FallbackValue
}

function Get-CredentialStorePath {
  param([Parameter(Mandatory = $true)][string]$Name)
  $safeName = $Name -replace "[^A-Za-z0-9._-]", "_"
  return Join-Path (Join-Path $env:LOCALAPPDATA "codex-arduino-tools\mqtt") "$safeName.credential.xml"
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
  if ([string]::IsNullOrWhiteSpace($promptUsername)) { $promptUsername = Read-Host "MQTT username" }
  return [pscredential]::new($promptUsername, (Read-Host "MQTT password" -AsSecureString))
}

function Invoke-ProcessCapture {
  param([Parameter(Mandatory = $true)][string]$FilePath, [Parameter(Mandatory = $true)][string[]]$Arguments)
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.Arguments = (($Arguments | ForEach-Object {
    if ($_ -notmatch '[\s"]') { $_ } else { '"' + ($_ -replace '"', '\"') + '"' }
  }) -join " ")
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $lines = @()
  if ($stdout) { $lines += ($stdout -split "\r?\n") }
  if ($stderr) { $lines += ($stderr -split "\r?\n") }
  return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = @($lines | Where-Object { $_ -ne "" }) }
}

function Join-Topic { param([string]$Root, [string]$Suffix) return ($Root.TrimEnd('/') + $Suffix) }

function Get-NewestFirmwareFile {
  param([Parameter(Mandatory = $true)][string]$Directory)
  $files = Get-ChildItem -LiteralPath $Directory -Filter "$ProjectName-*.bin" -File |
    Sort-Object LastWriteTimeUtc, Name -Descending
  if ($null -eq $files -or $files.Count -eq 0) { throw "Keine versionierte Firmware in $Directory gefunden." }
  return $files[0].FullName
}

function Get-FirmwareVersionFromPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $escapedName = [regex]::Escape($ProjectName)
  $match = [regex]::Match((Split-Path -Leaf $Path), "^$escapedName-(.+)\.bin$")
  if (-not $match.Success) { throw "Firmware-Dateiname passt nicht zu $ProjectName-<version>.bin." }
  return $match.Groups[1].Value
}

function Test-OtaUploadUrl {
  param([string]$Value)
  $uri = $null
  if ([string]::IsNullOrWhiteSpace($Value) -or -not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { return $false }
  return (($uri.Scheme -eq "http" -or $uri.Scheme -eq "https") -and $uri.AbsolutePath -eq "/update")
}

function Invoke-MqttPublish {
  param([string]$ToolPath, [string[]]$BaseArgs, [string]$Topic, [string]$Message)
  return Invoke-ProcessCapture -FilePath $ToolPath -Arguments @($BaseArgs + @("-t", $Topic, "-m", $Message, "-q", "0"))
}

function Get-MqttRetainedValue {
  param([string]$ToolPath, [string[]]$BaseArgs, [string]$Topic, [int]$TimeoutSec)
  $result = Invoke-ProcessCapture -FilePath $ToolPath -Arguments @($BaseArgs + @("-t", $Topic, "-C", "1", "-W", $TimeoutSec.ToString(), "-v"))
  $value = $null
  foreach ($line in $result.Output) {
    $text = [string]$line
    if ($text.StartsWith("$Topic ")) { $value = $text.Substring($Topic.Length + 1) }
    elseif ($text -eq $Topic) { $value = "" }
  }
  return [pscustomobject]@{ Value = $value; ExitCode = $result.ExitCode; Output = @($result.Output) }
}

function Write-Diagnostics {
  param([hashtable]$Values)
  foreach ($key in $Values.Keys) { Write-Host "[ota] $key = $($Values[$key])" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
$resolvedFirmwarePath = if ([string]::IsNullOrWhiteSpace($FirmwarePath)) {
  Get-NewestFirmwareFile -Directory (Join-Path $repoRoot $BinDirectory)
} else {
  $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FirmwarePath)
}
if (-not (Test-Path -LiteralPath $resolvedFirmwarePath)) { throw "Firmware BIN nicht gefunden: $resolvedFirmwarePath" }

$targetVersion = Get-FirmwareVersionFromPath -Path $resolvedFirmwarePath
$BrokerHost = Resolve-ConfigValue -CurrentValue $BrokerHost -MacroName $BrokerHostMacro
$Username = Resolve-ConfigValue -CurrentValue $Username -MacroName $UsernameMacro
$RootTopic = Resolve-ConfigValue -CurrentValue $RootTopic -MacroName $RootTopicMacro
if ($Port -le 0) { $Port = [int](Resolve-ConfigValue -CurrentValue "" -MacroName $PortMacro -FallbackValue "1883") }
if ([string]::IsNullOrWhiteSpace($UploadUrl) -or -not $SkipVerify) {
  if ([string]::IsNullOrWhiteSpace($BrokerHost)) { throw "MQTT broker host fehlt." }
  if ([string]::IsNullOrWhiteSpace($RootTopic)) { throw "MQTT root topic fehlt." }
}
if ($Port -lt 1 -or $Port -gt 65535) { throw "MQTT port must be between 1 and 65535." }

$mqttPubPath = $null
$mqttSubPath = $null
$plainPassword = $null
$credential = $null
try {
  $mqttRequired = [string]::IsNullOrWhiteSpace($UploadUrl) -or -not $SkipVerify
  if ($mqttRequired) {
    $mqttPubPath = Resolve-ToolPath -CommandName "mosquitto_pub.exe" -ProgramFilesFallback "mosquitto\mosquitto_pub.exe"
    $mqttSubPath = Resolve-ToolPath -CommandName "mosquitto_sub.exe" -ProgramFilesFallback "mosquitto\mosquitto_sub.exe"
    if (-not $NoCredential) {
      $credentialPath = Get-CredentialStorePath -Name $CredentialName
      if (Test-Path -LiteralPath $credentialPath) {
        $credential = Import-Clixml -LiteralPath $credentialPath
        Write-Host "[ota] Using DPAPI-protected credential from: $credentialPath"
      } else {
        $credential = Read-MqttCredential -DefaultUsername $Username
        if ($SaveCredential) {
          New-Item -ItemType Directory -Force -Path (Split-Path -Parent $credentialPath) | Out-Null
          $credential | Export-Clixml -LiteralPath $credentialPath
          Write-Host "[ota] Saved DPAPI-protected credential to: $credentialPath"
        }
      }
      $plainPassword = Convert-SecureStringToPlainText -SecureString $credential.Password
    }
  }

  $mqttArgsBase = @("-h", $BrokerHost, "-p", $Port.ToString())
  if ($credential) { $mqttArgsBase += @("-u", $credential.UserName, "-P", $plainPassword) }
  $curlPath = Resolve-ToolPath -CommandName "curl.exe"
  Write-Host "[ota] Firmware: $resolvedFirmwarePath"
  Write-Host "[ota] Target version: $targetVersion"

  $resolvedUploadUrl = $UploadUrl
  $snapshot = @{}
  if ([string]::IsNullOrWhiteSpace($resolvedUploadUrl)) {
    $urlTopic = Join-Topic $RootTopic $OtaUrlTopicSuffix
    $urlResult = Get-MqttRetainedValue -ToolPath $mqttSubPath -BaseArgs $mqttArgsBase -Topic $urlTopic -TimeoutSec 5
    if (Test-OtaUploadUrl $urlResult.Value) {
      $resolvedUploadUrl = $urlResult.Value
      Write-Host "[ota] Reusing active OTA upload URL: $resolvedUploadUrl"
    } else {
      $enableTopic = Join-Topic $RootTopic $OtaEnableTopicSuffix
      Write-Host "[ota] Enabling OTA upload window via MQTT..."
      $publishResult = Invoke-MqttPublish -ToolPath $mqttPubPath -BaseArgs $mqttArgsBase -Topic $enableTopic -Message $OtaEnableMessage
      if ($publishResult.ExitCode -ne 0) { throw "OTA enable failed on ${enableTopic}: $($publishResult.Output -join ' | ')" }
      $deadline = (Get-Date).AddSeconds($UrlWaitTimeoutSec)
      while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $urlResult = Get-MqttRetainedValue -ToolPath $mqttSubPath -BaseArgs $mqttArgsBase -Topic $urlTopic -TimeoutSec 5
        if (Test-OtaUploadUrl $urlResult.Value) { $resolvedUploadUrl = $urlResult.Value; break }
      }
    }
  }
  if (-not (Test-OtaUploadUrl $resolvedUploadUrl)) { throw "Keine gültige OTA-URL erhalten: $resolvedUploadUrl" }

  $curlArgs = @("-s", "-S", "-i", "-F", "firmware=@$resolvedFirmwarePath", "-H", "X-Firmware-Project: $ProjectName", "-H", "X-Firmware-Version: $targetVersion", $resolvedUploadUrl)
  Write-Host "[ota] Uploading firmware..."
  $curlResult = Invoke-ProcessCapture -FilePath $curlPath -Arguments $curlArgs
  $curlText = $curlResult.Output -join [Environment]::NewLine
  $statusMatches = [regex]::Matches($curlText, 'HTTP/\d+(?:\.\d+)?\s+(\d{3})')
  $httpStatus = if ($statusMatches.Count -gt 0) { [int]$statusMatches[$statusMatches.Count - 1].Groups[1].Value } else { $null }
  if ($curlResult.ExitCode -ne 0 -or $null -eq $httpStatus -or $httpStatus -lt 200 -or $httpStatus -ge 300) {
    throw "OTA upload failed. curl exit=$($curlResult.ExitCode) http_status=$httpStatus`n$curlText"
  }
  Write-Host "[ota] Upload accepted with HTTP status $httpStatus."
  if ($SkipVerify) { Write-Host "[ota] Verification skipped."; return }

  Write-Host "[ota] Waiting for MQTT verification..."
  $verifyDeadline = (Get-Date).AddSeconds($VerifyTimeoutSec)
  $versionTopic = Join-Topic $RootTopic $FirmwareVersionTopicSuffix
  $availabilityTopic = Join-Topic $RootTopic $AvailabilityTopicSuffix
  while ((Get-Date) -lt $verifyDeadline) {
    Start-Sleep -Seconds 5
    $versionResult = Get-MqttRetainedValue -ToolPath $mqttSubPath -BaseArgs $mqttArgsBase -Topic $versionTopic -TimeoutSec 5
    $availabilityResult = Get-MqttRetainedValue -ToolPath $mqttSubPath -BaseArgs $mqttArgsBase -Topic $availabilityTopic -TimeoutSec 5
    if ($versionResult.Value -eq $targetVersion -and $availabilityResult.Value -eq "online") {
      Write-Host "[ota] OTA verification succeeded: version=$targetVersion availability=online"
      return
    }
  }
  throw "OTA verification timed out. Expected firmware_version=$targetVersion and availability=online."
}
finally {
  $plainPassword = $null
}
