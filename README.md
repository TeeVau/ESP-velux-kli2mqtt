# ESP-velux-kli2mqtt

> Early-stage hardware project — compile and live verification evidence is
> recorded in the [verification log](docs/esp-velux-kli2mqtt-verification-log.md).

An ESP8266 MQTT bridge for one existing VELUX KLI remote. A Wemos D1 mini
simulates short presses of the original remote's OPEN, STOP and CLOSE buttons.
The remote continues to perform the proprietary io-homecontrol radio work; this
project does not reverse engineer it and does not report shutter position.

## Scope

- Wemos D1 mini / ESP8266, Arduino CLI, Wi-Fi and MQTT.
- Open-drain button simulation on D5=OPEN, D6=STOP, D7=CLOSE.
- MQTT Last Will and retained technical status.
- MQTT-armed, single-use, 60-second HTTP OTA upload window.
- No position estimate, Home Assistant discovery, serial driving commands, or
  retained command support.

This is an independent community project and is not affiliated with VELUX.

## Hardware

The v0.1.0 reference uses direct soldered connections to a KLI 313-compatible
remote. See the illustrated [wiring reference](hardware/wiring.md) before
applying power. Every button line requires its own external 10 kOhm pull-up to
3.3 V.

For a later reversible contact-plate/printed-holder option, see the external
[KLI 313 ESP8266 project](https://www.chrisbue.de/velux-esp8266-smart-home-mqtt/).

## Configure and build

Install Arduino IDE with the ESP8266 board package and PubSubClient, then:

```powershell
Copy-Item firmware\velux_kli2mqtt\secrets.example.h firmware\velux_kli2mqtt\secrets.h
# Edit secrets.h locally; it is ignored by Git.
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
powershell -ExecutionPolicy Bypass -File .\tests\run-static-checks.ps1
```

The build target is `esp8266:esp8266:d1_mini` and the release artefact is
`bin/esp-velux-kli2mqtt-<version>.bin`.

Before USB flashing, identify the actual board and port; never assume a COM
number:

```powershell
& 'C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe' board list --json
powershell -ExecutionPolicy Bypass -File .\scripts\flash-usb.ps1 -Port COMx
```

Monitor at 115200 baud after the device reconnects.

## MQTT contract

The root topic defaults to `velux/rollladen` and may be changed in local
`secrets.h`.

| Topic | Direction | Retained | Payload |
|---|---|---:|---|
| `<root>/set` | to device | **no** | `OPEN`, `STOP`, `CLOSE` |
| `<root>/ota/set` | to device | **no** | `ENABLE`, `CANCEL` |
| `<root>/availability` | from device | yes | `online`, `offline` |
| `<root>/last_command` | from device | yes | last accepted button press |
| `<root>/rssi_dbm`, `/uptime_s`, `/free_heap_bytes` | from device | yes | diagnostics |
| `<root>/firmware_version` | from device | yes | installed version |
| `<root>/ota/status`, `/ota/upload_url` | from device | yes | OTA state and temporary URL |

`last_command` confirms only that the ESP pressed a KLI contact. It does not
prove that a shutter moved. Do **not** retain either set topic: an MQTT 3.x
ESP8266 client cannot safely distinguish a retained command replay.

Commands are 200 ms pulses. During a pulse/cooldown, OPEN/CLOSE are discarded;
STOP replaces a pending movement command and is executed next.

Use the helper rather than exposing credentials on the command line:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mqtt-client.ps1 -Action Publish -Topic velux/rollladen/set -Message OPEN
powershell -ExecutionPolicy Bypass -File .\scripts\mqtt-client.ps1 -Action Read -Topic velux/rollladen/#
```

## OTA

OTA has no separate password and is intended only for a trusted local network.
It is disabled unless MQTT explicitly opens the window. The helper publishes
`ENABLE`, waits for the retained upload URL, sends the versioned BIN with its
project/version headers, then verifies the reported firmware version:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\ota-upload.ps1
```

The device accepts `esp-velux-kli2mqtt` images with an equal or newer semantic
version. USB flashing remains the recovery method if OTA is unavailable.

## Development documents

- [Idea](docs/esp-velux-kli2mqtt-idea.md)
- [Functional specification](docs/esp-velux-kli2mqtt-fsd.md)
- [Phase plan](docs/esp-velux-kli2mqtt-phase-plan.md)
- [Verification log](docs/esp-velux-kli2mqtt-verification-log.md)
- [GitHub publication metadata](docs/esp-velux-kli2mqtt-github-metadata.md)

## License

MIT. See [LICENSE](LICENSE).
