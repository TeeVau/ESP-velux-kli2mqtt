param(
  [Parameter(Mandatory = $true)][string]$Port,
  [int]$Baud = 115200,
  [ValidateRange(1, 60)][int]$DurationSec = 20,
  [switch]$ToggleDtr
)

$ErrorActionPreference = "Stop"
$serial = [System.IO.Ports.SerialPort]::new(
  $Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.NewLine = "`n"
$serial.ReadTimeout = 500
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
  $serial.Open()
  if ($ToggleDtr) {
    $serial.DtrEnable = $true
    Start-Sleep -Milliseconds 200
    $serial.DtrEnable = $false
  }
  Write-Host "[serial] $Port at $Baud baud for $DurationSec seconds"
  $deadline = (Get-Date).AddSeconds($DurationSec)
  while ((Get-Date) -lt $deadline) {
    try { Write-Host $serial.ReadLine().TrimEnd("`r") } catch [System.TimeoutException] { }
  }
} finally {
  if ($serial.IsOpen) { $serial.Close() }
}
