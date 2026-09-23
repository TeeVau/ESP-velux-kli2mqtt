# Contributing

Please keep changes focused, documented and buildable for
`esp8266:esp8266:d1_mini`.

1. Never commit `secrets.h`, credentials, IP addresses, GPS-tagged photos or
   live logs.
2. Run `scripts/build.ps1` and `tests/run-static-checks.ps1` before a pull
   request.
3. Update the README, wiring reference or installation record when behaviour
   or the tested hardware changes.
4. Clearly separate bridge-level command confirmation from observed shutter
   movement, and state the KLI revision used for hardware reports.
