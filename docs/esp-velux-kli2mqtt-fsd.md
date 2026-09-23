# ESP-velux-kli2mqtt — Functional Specification Document (FSD)

## 1. System Overview

### Purpose and goals

ESP-velux-kli2mqtt shall expose the three existing functions of one VELUX KLI
313-compatible remote through local Wi-Fi and MQTT. It shall use the original
remote as the io-homecontrol radio endpoint and shall keep its physical buttons
usable. The project is a medium-complexity embedded system: ESP8266 firmware,
Wi-Fi, MQTT, a temporary HTTP OTA endpoint, and a low-voltage hardware bridge.

The system flow is: `MQTT -> ESP8266 -> KLI button contact -> io-homecontrol ->
shutter group`. It does not measure or estimate shutter position, confirm
movement, implement Home Assistant discovery, or provide serial driving
commands.

## 2. System Architecture

### 2.1 Logical architecture

`NetworkManager` reconnects Wi-Fi without blocking. `MqttManager` reconnects
to the broker, registers a retained Last Will, publishes diagnostics, and
passes payloads to `CommandController`. `CommandController` validates commands,
applies the stop-priority/cooldown policy, and asks `KliButtons` to simulate a
short button press. `OtaServer` starts only after the OTA MQTT command and
serves one temporary HTTP upload endpoint.

### 2.2 Hardware and platform architecture

| Component | Requirement |
|---|---|
| Controller | Wemos D1 mini, ESP8266, Arduino core |
| Remote | VELUX KLI 313 or electrically compatible KLI remote |
| Power | USB supply to Wemos; Wemos 3.3 V powers the KLI instead of AAA cells |
| Button lines | D5/GPIO14 OPEN, D6/GPIO12 STOP, D7/GPIO13 CLOSE |
| Electrical behaviour | Open-drain: inactive is high impedance; active pulls to shared GND |
| Pull-ups | One external 10 kOhm resistor per button line to KLI/ESP 3.3 V |

The v0.1.0 reference installation solders wires to KLI pads. The pinout is an
assumption verified by independent published KLI-313 builds; users must check
their remote revision before attaching power.

### 2.3 Software architecture and boot sequence

1. Configure all button GPIOs as inputs (high impedance) before network setup.
2. Start serial diagnostics at 115200 baud, then Wi-Fi station mode.
3. Retry Wi-Fi and MQTT with bounded retry intervals; no command is stored.
4. On MQTT connection, publish retained diagnostics, `availability=online`, and
   subscribe to the two command topics.
5. Run MQTT, button timing, diagnostics and OTA expiry from `loop()` without
   `delay()`.

Firmware has no persistent application state. `secrets.h` is compiled locally
and never committed. Firmware identity/version are compiled into the binary and
reported over MQTT.

## 3. Implementation Phases

### 3.1 Phase 1 — Repository and interface foundation

**Scope:** repository documents, ignore rules, configuration template, build,
MQTT helper, hardware reference, and GitHub compile workflow.

**Exit criteria:** documentation maps every Must/Should requirement to a test;
the project has no credentials in tracked files; CI can compile the documented
FQBN.

### 3.2 Phase 2 — Firmware core

**Scope:** safe GPIO control, non-blocking Wi-Fi/MQTT recovery, command policy,
diagnostics, and Last Will.

**Exit criteria:** the firmware compiles for `esp8266:esp8266:d1_mini`; static
tests cover command parsing and version comparison; the manual test protocol is
ready.

### 3.3 Phase 3 — OTA and hardware acceptance

**Scope:** MQTT-enabled one-shot OTA server, release BIN, USB flash, and
live MQTT/KLI test.

**Exit criteria:** OTA script completes a compatible upload when hardware is
available; all live observations are recorded instead of inferred.

## 4. Requirements

### 4.1 Functional requirements

- **FR-1.1 [Must]:** The firmware shall control one KLI remote through OPEN,
  STOP and CLOSE button contacts only.
- **FR-1.2 [Must]:** The firmware shall set D5, D6 and D7 high impedance when
  idle and pull exactly one selected button line to GND for 200 ms.
- **FR-1.3 [Must]:** The firmware shall never press a button during boot,
  reset, Wi-Fi/MQTT reconnect, or OTA upload unless it received a valid command.
- **FR-1.4 [Must]:** The firmware shall accept uppercase `OPEN`, `STOP`, and
  `CLOSE` on the documented set topic and reject every other payload.
- **FR-1.5 [Must]:** STOP shall replace a pending OPEN/CLOSE request; OPEN and
  CLOSE shall not be queued.
- **FR-1.6 [Must]:** The firmware shall enforce a 700 ms cooldown after a
  completed button press.
- **FR-1.7 [Must]:** The firmware shall reconnect Wi-Fi and MQTT automatically
  without replaying an old command after a network outage.
- **FR-1.8 [Must]:** The MQTT client shall publish an offline retained Last
  Will and an online retained availability value when connected.
- **FR-1.9 [Should]:** The firmware shall publish retained last command, RSSI,
  uptime, free heap, firmware version and OTA status diagnostics.
- **FR-1.10 [Must]:** A valid OTA enable command shall open a temporary 60 s
  HTTP upload endpoint and shall close it after one upload, cancel, timeout, or
  reboot.
- **FR-1.11 [Must]:** OTA shall reject a wrong project identity or a lower
  semantic version; an equal version shall be accepted.

### 4.2 Non-functional requirements

- **NFR-1.1 [Must]:** The main loop shall not use `delay()` or a blocking
  reconnect loop.
- **NFR-1.2 [Must]:** Wi-Fi and MQTT passwords shall exist only in local
  `secrets.h`; serial output and Git history shall not contain them.
- **NFR-1.3 [Must]:** MQTT command messages shall be documented and used as
  non-retained. The firmware shall not buffer or re-send commands.
- **NFR-1.4 [Should]:** The source shall compile with Arduino CLI for
  `esp8266:esp8266:d1_mini` and generate a versioned BIN.
- **NFR-1.5 [Should]:** Public documentation and source comments shall be in
  English and make electrical/revision assumptions explicit.

### 4.3 Constraints

- MQTT is plain TCP with username/password on a trusted local network; TLS is
  not required in v0.1.0.
- MQTT cannot reliably identify an accidentally retained command through the
  selected ESP8266 MQTT client. Publishers are responsible for not retaining
  set-topic messages.
- The device shall not claim actual shutter state or position.
- This independent community project has no affiliation with VELUX.

## 5. Risks, Assumptions & Dependencies

| Item | Risk | Mitigation |
|---|---|---|
| KLI PCB revision | Pad layout/polarity differs | Document KLI 313 assumption; inspect before wiring |
| GPIO boot state | Unwanted movement | External pull-ups and input mode before all setup |
| Retained command | Replayed on reconnect | Contract and examples prohibit retained set messages |
| Network failure | Missed action | Explicitly do not store or replay commands |
| OTA interruption | Device unavailable | One-shot window; USB flash remains recovery route |
| 3.3 V power budget | Remote resets | Use a suitable USB supply/Wemos and test under RF transmit |

Dependencies are the ESP8266 Arduino core, PubSubClient, an MQTT broker, and
the local `mosquitto_pub`/`mosquitto_sub` tools for helper scripts.

## 6. Interface Specifications

### 6.1 MQTT interface

`VK_MQTT_ROOT_TOPIC` defaults to `velux/rollladen`. The base may be changed in
local `secrets.h` without changing source.

| Topic suffix | Direction | Retained | Payload |
|---|---|---:|---|
| `/set` | broker -> device | no | `OPEN`, `STOP`, `CLOSE` |
| `/ota/set` | broker -> device | no | `ENABLE`, `CANCEL` |
| `/availability` | device -> broker | yes | `online`, `offline` |
| `/last_command` | device -> broker | yes | last accepted action |
| `/rssi_dbm` | device -> broker | yes | signed integer |
| `/uptime_s` | device -> broker | yes | unsigned integer |
| `/free_heap_bytes` | device -> broker | yes | unsigned integer |
| `/firmware_version` | device -> broker | yes | semantic version |
| `/ota/status` | device -> broker | yes | `disabled`, `armed`, `uploading`, `succeeded`, `failed`, `timed_out` |
| `/ota/upload_url` | device -> broker | yes | temporary HTTP URL or empty |

All messages use QoS 0. `availability=offline` is the retained MQTT Last Will.
The command topics deliberately carry no acknowledgement beyond
`last_command`, which means *the local KLI contact was pressed*, not that a
shutter moved.

### 6.2 HTTP OTA interface

When armed, `GET /update` serves a small upload form and `POST /update` accepts
one multipart field named `firmware`. The caller supplies headers
`X-Firmware-Project: esp-velux-kli2mqtt` and
`X-Firmware-Version: <major.minor.patch>`. The device accepts the identity and
an equal/newer version only. A successful upload sends HTTP 200 and reboots.

### 6.3 Configuration schema

```cpp
#define VK_WIFI_SSID "..."
#define VK_WIFI_PASSWORD "..."
#define VK_MQTT_HOST "192.0.2.10"
#define VK_MQTT_PORT 1883
#define VK_MQTT_USERNAME "..."
#define VK_MQTT_PASSWORD "..."
#define VK_MQTT_ROOT_TOPIC "velux/rollladen"
```

## 7. Operational Procedures

1. Copy `firmware/velux_kli2mqtt/secrets.example.h` to `secrets.h`, then enter
   local Wi-Fi/MQTT settings.
2. Wire only with power removed, then verify every button wire against the
   documented KLI reference.
3. Run `powershell -ExecutionPolicy Bypass -File .\\scripts\\build.ps1`.
4. Detect the actual USB port, then run `scripts\\flash-usb.ps1 -Port COMx`.
5. Observe serial logs at 115200 and retained MQTT diagnostics.
6. Publish non-retained commands with `scripts\\mqtt-client.ps1`.
7. For OTA, use `scripts\\ota-upload.ps1`; it arms OTA, discovers the URL,
   uploads the latest versioned BIN, and checks the reported version.

If Wi-Fi or MQTT fails, correct `secrets.h` and reset the device. If an OTA
attempt fails or the device is unreachable, use USB flashing. There is no
factory reset state to preserve.

## 8. Verification & Validation

| Test ID | Requirement(s) | Procedure | Success criterion |
|---|---|---|---|
| TC-1.1 | FR-1.1–1.3 | Compile, inspect boot log, measure button lines through reset | no low pulse without command |
| TC-1.2 | FR-1.4–1.6 | Send valid/invalid and rapid MQTT payloads | 200 ms action; STOP wins; invalid ignored |
| TC-1.3 | FR-1.7, NFR-1.1 | Disable/restore AP and broker | recovery without stored action |
| TC-1.4 | FR-1.8–1.9 | Subscribe then power-cycle/unplug device | correct retained diagnostics and LWT |
| TC-1.5 | FR-1.10–1.11 | Run OTA script using valid, wrong identity, lower/equal versions | only equal/newer matching identity accepted |
| TC-1.6 | NFR-1.2–1.5 | scan tracked files; run build and CI | no secret tracked; documented build passes |
| TC-1.7 | FR-1.1 | Wire KLI, publish each command, manually use KLI buttons | all three actions work; manual control remains |

### 8.1 Traceability matrix

| Requirement | Priority | Test case(s) | Status |
|---|---|---|---|
| FR-1.1 | Must | TC-1.2, TC-1.7 | Covered |
| FR-1.2 | Must | TC-1.1, TC-1.2 | Covered |
| FR-1.3 | Must | TC-1.1 | Covered |
| FR-1.4 | Must | TC-1.2 | Covered |
| FR-1.5 | Must | TC-1.2 | Covered |
| FR-1.6 | Must | TC-1.2 | Covered |
| FR-1.7 | Must | TC-1.3 | Covered |
| FR-1.8 | Must | TC-1.4 | Covered |
| FR-1.9 | Should | TC-1.4 | Covered |
| FR-1.10 | Must | TC-1.5 | Covered |
| FR-1.11 | Must | TC-1.5 | Covered |
| NFR-1.1 | Must | TC-1.3, TC-1.6 | Covered |
| NFR-1.2 | Must | TC-1.6 | Covered |
| NFR-1.3 | Must | TC-1.3, TC-1.6 | Covered |
| NFR-1.4 | Should | TC-1.6 | Covered |
| NFR-1.5 | Should | TC-1.6 | Covered |

## 9. Troubleshooting Guide

| Symptom | Likely cause | Diagnostic action | Corrective action |
|---|---|---|---|
| No MQTT online state | Wi-Fi/broker settings | serial log; inspect `secrets.h` locally | correct host/credentials |
| KLI acts at reset | wiring or pull-up fault | remove power; check GPIO and 10 kOhm paths | correct before reconnecting KLI |
| Command has no effect | wrong topic/payload or KLI pad | inspect retained diagnostics; continuity test unpowered | use uppercase payload; correct wiring |
| OTA endpoint unavailable | window expired | read `/ota/status` | run OTA helper again |
| OTA rejected | wrong header/version | inspect helper output | build matching equal/newer project image |

## 10. Appendix

| Constant | Value |
|---|---|
| Firmware version | `0.1.0` |
| Button press | 200 ms |
| Command cooldown | 700 ms |
| OTA window | 60 s |
| Serial baud rate | 115200 |
| FQBN | `esp8266:esp8266:d1_mini` |
