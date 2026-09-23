# Changelog

All notable changes to this project are documented in this file.

## [0.1.2] - 2026-09-23

Initial public release.

- ESP8266/Wemos D1 mini firmware for safe open-drain KLI button simulation.
- MQTT `OPEN`, `STOP`, `CLOSE`, retained availability, RSSI, command and
  firmware diagnostics, plus Last Will.
- MQTT-armed, time-limited HTTP OTA with project and version checks.
- Arduino build, USB flash, MQTT, serial-capture and OTA PowerShell helpers.
- Wiring/BOM, installation photos, FHEM/HomeKit/Alexa integration, MIT license
  and GitHub compile workflow.
- Retired uptime and free-heap MQTT values are cleared on the next connection
  after upgrading from earlier firmware.
