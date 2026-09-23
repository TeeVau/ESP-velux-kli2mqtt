<#
.SYNOPSIS
Captures a bounded serial monitor session and optionally writes it to a UTF-8 file.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Port,
  [int]$Baud = 115200,
  [ValidateRange(1, 3600)][int]$DurationSec = 180,
  [string]$OutputPath = "",
  [switch]$ToggleDtr
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serial = [System.IO.Ports.SerialPort]::new(
  $Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.NewLine = "`n"
$serial.ReadTimeout = 500
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$writer = $null

try {
  $serial.Open()

  if ($ToggleDtr) {
    $serial.DtrEnable = $true
    Start-Sleep -Milliseconds 200
    $serial.DtrEnable = $false
  }

  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDir = Split-Path -Parent $resolvedOutputPath
    if ($outputDir) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }
    $writer = [System.IO.StreamWriter]::new($resolvedOutputPath, $false, [System.Text.Encoding]::UTF8)
  }

  Write-Host "[serial] Monitor active on $Port at $Baud baud for $DurationSec seconds"
  if ($writer) { Write-Host "[serial] Output: $resolvedOutputPath" }
  $deadline = (Get-Date).AddSeconds($DurationSec)

  while ((Get-Date) -lt $deadline) {
    try {
      $line = $serial.ReadLine().TrimEnd("`r")
      Write-Host $line
      if ($writer) {
        $writer.WriteLine($line)
        $writer.Flush()
      }
    } catch [System.TimeoutException] {
      continue
    }
  }
}
finally {
  if ($writer) { $writer.Dispose() }
  if ($serial.IsOpen) { $serial.Close() }
}
