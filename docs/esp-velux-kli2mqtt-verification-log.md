# ESP-velux-kli2mqtt — Verification Log

| Date | Phase | Check | Result | Evidence |
|---|---|---|---|---|
| 2026-09-22 | 1 | FSD traceability review | PASS | Every Must/Should requirement maps to `TC-1.1`–`TC-1.7`. |
| 2026-09-22 | 1/2 | Static contract checks | PASS | GPIO map, no `delay()`, open-drain release, STOP priority and OTA version policy passed. |
| 2026-09-22 | 2 | Arduino CLI build | PASS | `esp8266:esp8266:d1_mini`; 313,309 B flash (29%), 29,572 B RAM (36%); `esp-velux-kli2mqtt-0.1.0.bin` SHA-256 `5ED0DB12A15182EEFDA2CBB5590DDF3D7E043CBB4549EECE147DDA1001A3DB05`. |
| 2026-09-22 | 3 | USB flash | PASS | Confirmed COM4; ESP8266EX, 4 MB flash, firmware upload completed. |
| 2026-09-22 | 3 | Wi-Fi/MQTT startup | PASS | Retained `availability=online` and `firmware_version=0.1.0` read through the project MQTT helper. |
| 2026-09-22 | 3 | MQTT button commands | PASS (bridge) | Non-retained `OPEN`, `STOP`, `CLOSE` each immediately updated retained `last_command` to the matching value. |
| 2026-09-22 | 3 | MQTT-enabled OTA | PASS | v0.1.0 armed its temporary HTTP endpoint, accepted the equal project version, rebooted and republished v0.1.0. |
| 2026-09-23 | 3 | Physical hardware acceptance | PASS | User confirmed: no unintended action after reset; OPEN, STOP and CLOSE moved the target as expected; the original KLI buttons remain functional. |

## Validation boundary

The installation is accepted for the tested KLI hardware: the user observed no
unwanted action after reset, correct OPEN/STOP/CLOSE behaviour, and continued
manual KLI operation. The acceptance does not generalise to untested KLI PCB
revisions. An oscilloscope-level GPIO/pad timing measurement remains optional,
not a release blocker for this installed device.
