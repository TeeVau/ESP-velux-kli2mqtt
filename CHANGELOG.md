# Changelog

All notable changes to this project are documented in this file.

## [0.1.2] - 2026-09-23

### Fixed

- Clear obsolete retained uptime and free-heap values after upgrading from
  v0.1.0, so brokers do not retain stale diagnostics.

## [0.1.1] - 2026-09-23

### Changed

- Removed retained uptime and free-heap MQTT telemetry.
- RSSI is retained when MQTT connects; functional state is published when it
  changes rather than periodically.

## [0.1.0] - 2026-09-22

### Added

- ESP8266/Wemos D1 mini firmware for safe open-drain KLI button simulation.
- MQTT `OPEN`, `STOP`, `CLOSE`, retained diagnostics and Last Will.
- MQTT-armed, time-limited HTTP OTA with project and equal-or-newer version
  checks.
- Arduino build, USB flash, MQTT, serial-capture and OTA PowerShell helpers.
- FSD, phase plan, verification log, wiring/BOM, MIT license and GitHub CI.

### Verified

- ESP8266 compile, USB flash, retained MQTT diagnostics, the three bridge
  commands, equal-version OTA, reset safety, shutter movement and continued
  manual KLI operation on the configured local device.
