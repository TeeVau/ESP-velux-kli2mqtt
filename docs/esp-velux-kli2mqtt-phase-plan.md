# ESP-velux-kli2mqtt — Phase Plan

## Phase 1 — Foundation

**Status: complete.**

- **Scope:** FSD, project structure, secrets template, hardware/BOM, GitHub
  metadata, build and MQTT helpers.
- **Files:** `docs/`, `hardware/`, `scripts/`, root community files, `.github/`.
- **Build:** `powershell -ExecutionPolicy Bypass -File .\\scripts\\build.ps1`
- **Exit:** tracked-tree secret scan is clean; Arduino CLI build is green.

## Phase 2 — Safe MQTT bridge

**Status: complete (build and live MQTT bridge evidence).**

- **Scope:** non-blocking ESP8266 firmware: high-impedance GPIO boot,
  button state machine, Wi-Fi/MQTT retry, diagnostics and LWT.
- **Files:** `firmware/velux_kli2mqtt/`, `tests/`.
- **Verification:** Arduino CLI compile; command-policy host test; manual
  `TC-1.1` through `TC-1.4` from the FSD.
- **Exit:** no `delay()` or persistent command queue; compilation and host test
  pass.

## Phase 3 — OTA and live acceptance

**Status: complete.**

- **Scope:** MQTT-armed 60-second HTTP upload, versioned BIN, USB flashing,
  live KLI and MQTT verification.
- **Files:** OTA firmware module, `scripts/ota-upload.ps1`, verification log.
- **Verification:** `TC-1.5` and `TC-1.7` with the actual Wemos/KLI/MQTT broker.
- **Exit:** build artefact exists; live evidence recorded or explicitly marked
  unavailable.
