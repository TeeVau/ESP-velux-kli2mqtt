# ESP-velux-kli2mqtt

An ESP8266 bridge that adds MQTT control to one existing VELUX KLI remote. The
Wemos D1 mini electrically simulates the OPEN, STOP and CLOSE buttons; the
original remote remains the io-homecontrol radio endpoint.

This is a reference build for a KLI 313-compatible remote. It is not affiliated
with VELUX, does not reverse engineer io-homecontrol, and does not measure or
estimate shutter position.

## What it provides

- ESP8266 / Wemos D1 mini firmware using D5=OPEN, D6=STOP and D7=CLOSE.
- Safe open-drain button simulation with one external 10 kOhm pull-up per line.
- Local Wi-Fi and MQTT, Last Will, retained availability and diagnostics.
- Non-retained `OPEN`, `STOP` and `CLOSE` commands with STOP priority.
- MQTT-armed, time-limited HTTP OTA upload.
- An optional FHEM `MQTT2_DEVICE` configuration with HomeKit and Alexa support.

The tested reference hardware accepts OPEN, STOP and CLOSE after reset, and
the original KLI buttons remain usable. Check the PCB contacts on your own KLI
revision before applying power.

## Hardware

| Part | Quantity | Notes |
|---|---:|---|
| Wemos D1 mini or compatible ESP8266 board | 1 | `esp8266:esp8266:d1_mini` |
| VELUX KLI 313-compatible remote | 1 | Already paired with the target shutter/group |
| 10 kOhm resistor | 3 | One pull-up for each button line |
| USB supply and cable | 1 | Powers the Wemos and KLI |
| Insulated hookup wire | 5 | GND, 3V3, OPEN, STOP, CLOSE |

| Wemos pin | KLI contact | Function |
|---|---|---|
| 3V3 | 2 | KLI supply |
| GND | 1 | Shared reference |
| D5 / GPIO14 | 3 | OPEN, with 10 kOhm pull-up to 3V3 |
| D6 / GPIO12 | 4 | STOP, with 10 kOhm pull-up to 3V3 |
| D7 / GPIO13 | 5 | CLOSE, with 10 kOhm pull-up to 3V3 |

The firmware pulls only the selected line LOW for 200 ms and otherwise returns
it to high impedance. Never drive a KLI button line high from a GPIO. The
[wiring reference](hardware/wiring.md) and [installation record](docs/INSTALLATION.md)
show the tested build.

## Build and flash

Install Arduino IDE or Arduino CLI, the ESP8266 board package and
[PubSubClient](https://github.com/knolleary/pubsubclient). Then create the
local configuration file and build:

```powershell
Copy-Item firmware\velux_kli2mqtt\secrets.example.h firmware\velux_kli2mqtt\secrets.h
# Edit secrets.h locally. It is ignored by Git.
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
powershell -ExecutionPolicy Bypass -File .\tests\run-static-checks.ps1
```

The build target is `esp8266:esp8266:d1_mini`; the versioned firmware image is
written to `bin/esp-velux-kli2mqtt-<version>.bin`.

Identify the actual USB port before flashing:

```powershell
& 'C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe' board list --json
powershell -ExecutionPolicy Bypass -File .\scripts\flash-usb.ps1 -Port COMx
```

Serial output uses 115200 baud. The helper scripts `mqtt-client.ps1`,
`ota-upload.ps1` and `serial-capture.ps1` prompt for MQTT credentials or use a
Windows DPAPI-protected credential outside this repository.

## MQTT contract

The root topic defaults to `velux/rollladen` and is configured in local
`secrets.h`.

| Topic | Direction | Retained | Payload |
|---|---|---:|---|
| `<root>/set` | to device | no | `OPEN`, `STOP`, `CLOSE` |
| `<root>/ota/set` | to device | no | `ENABLE`, `CANCEL` |
| `<root>/availability` | from device | yes | `online`, `offline` |
| `<root>/last_command` | from device | yes | Last accepted button press |
| `<root>/rssi_dbm` | from device | yes | RSSI on MQTT connection |
| `<root>/firmware_version` | from device | yes | Installed firmware version |
| `<root>/ota/status` | from device | yes | OTA state |
| `<root>/ota/upload_url` | from device | yes | Temporary upload URL while armed |

`last_command` proves only that the ESP asserted a KLI contact; it is not
shutter-position or movement feedback. Do not retain either command topic.
During a pulse/cooldown, OPEN and CLOSE are discarded; STOP replaces a pending
movement command and runs next.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mqtt-client.ps1 -Action Publish -Topic velux/rollladen/set -Message OPEN
powershell -ExecutionPolicy Bypass -File .\scripts\mqtt-client.ps1 -Action Read -Topic velux/rollladen/#
```

## OTA

OTA is disabled by default. On a trusted local network, the upload helper arms
one temporary HTTP endpoint by MQTT, uploads the latest compatible BIN, and
waits for the retained firmware version and availability state:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ota-upload.ps1
```

There is no separate OTA password. USB flashing remains the recovery path.
Read [SECURITY.md](SECURITY.md) before exposing the device beyond a protected
local network.

## FHEM, HomeKit and Alexa

This optional FHEM configuration deliberately exposes command semantics rather
than fabricated position feedback. Replace `myBroker`, device name, room,
group and MQTT topic to fit your installation.

```text
define velux_RolloGruppe MQTT2_DEVICE
attr velux_RolloGruppe IODev myBroker
attr velux_RolloGruppe devicetopic velux/rollladen
attr velux_RolloGruppe alias VELUX Rollo-Gruppe
attr velux_RolloGruppe room Rolladen
attr velux_RolloGruppe group Rollos
attr velux_RolloGruppe icon fts_shutter_1w
attr velux_RolloGruppe readingList $DEVICETOPIC/availability:.* availability\
$DEVICETOPIC/last_command:.* last_command\
$DEVICETOPIC/rssi_dbm:.* rssi_dbm\
$DEVICETOPIC/firmware_version:.* firmware_version\
$DEVICETOPIC/ota/status:.* ota_status
attr velux_RolloGruppe setList open:noArg $DEVICETOPIC/set OPEN\
stop:noArg $DEVICETOPIC/set STOP\
close:noArg $DEVICETOPIC/set CLOSE\
position:slider,0,100,100 { return "$DEVICETOPIC/set CLOSE" if $EVTPART1 == 0; return "$DEVICETOPIC/set OPEN" if $EVTPART1 == 100; return; }
attr velux_RolloGruppe webCmd open:stop:close:position
attr velux_RolloGruppe cmdIcon open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down
attr velux_RolloGruppe event-on-change-reading .*
attr velux_RolloGruppe event-on-update-reading last_command
attr velux_RolloGruppe genericDeviceType blind
attr velux_RolloGruppe homebridgeMapping clear CurrentPosition=state,values=/^open$/:100;/^close$/:0;/.*/:50,minValue=0,maxValue=100,minStep=100 TargetPosition=position::state,values=/^open$/:100;/^close$/:0;/.*/:50,minValue=0,maxValue=100,minStep=100
attr velux_RolloGruppe stateFormat {ReadingsVal($name,"availability","offline") eq "online" ? ReadingsVal($name,"state","idle") : "offline"}
attr velux_RolloGruppe devStateIcon offline:10px-kreis-rot idle:fts_shutter_automatic open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down
defmod n_velux_RolloGruppe_Idle notify velux_RolloGruppe:last_command:(OPEN|STOP|CLOSE) {my $command=lc(ReadingsVal("velux_RolloGruppe","last_command","idle"));;fhem("setreading velux_RolloGruppe state $command");;fhem("defmod at_velux_RolloGruppe_Idle at +00:00:30 setreading velux_RolloGruppe state idle")}
setreading velux_RolloGruppe state idle
save
```

Enter `setList` and `homebridgeMapping` through FHEM's attribute editor when
possible; the semicolons in the Perl setter and mapping are literal attribute
contents. The transient FHEM `state` is presentation only: it reflects the
last accepted bridge command for 30 seconds, then returns to `idle`. HomeKit
receives 100 for `open`, 0 for `close`, and neutral 50 for `stop` or `idle`.
The `position` setter accepts only 0 and 100 and sends CLOSE or OPEN directly.

For Alexa, use the exposed blind endpoints for open/close, or create routines
for the phrases and room names used in your home. Neither route adds physical
position feedback. HomeKit assumes a configured `homebridge-fhem` instance;
Alexa discovery assumes `alexa-fhem`. Both are external FHEM integrations and
are intentionally not bundled with this project.

## Project notes

- [Installation record](docs/INSTALLATION.md)
- [Wiring reference and BOM](hardware/wiring.md)
- [Changelog](CHANGELOG.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Acknowledgements

The KLI contact layout was cross-checked against Chris Bue's
[KLI 313 ESP8266 project](https://www.chrisbue.de/velux-esp8266-smart-home-mqtt/).
This project uses the ESP8266 Arduino Core, PubSubClient, and GitHub Actions
with `arduino/setup-arduino-cli` for compile validation.

Initial implementation and documentation were created with OpenAI Codex.

## License

MIT. See [LICENSE](LICENSE).
