# Wiring Reference

Disconnect USB power and remove the KLI batteries before soldering. This is a
reference for a KLI 313-compatible board, not a guarantee for every remote
revision.

The contact numbers refer to the five pads in the KLI PCB photo in the external
[KLI 313 ESP8266 project](https://www.chrisbue.de/velux-esp8266-smart-home-mqtt/).
Use that photo to find the pads; the numbers are a practical board-layout
reference, not labels printed by VELUX.

| Wemos D1 mini | KLI contact | External part | Meaning |
|---|---|---|---|
| 3V3 | 2 — battery positive | — | KLI supply |
| GND | 1 — battery negative/common | — | shared reference |
| D5 / GPIO14 | 3 — OPEN | 10 kOhm to 3V3 | open-drain OPEN |
| D6 / GPIO12 | 4 — STOP | 10 kOhm to 3V3 | open-drain STOP |
| D7 / GPIO13 | 5 — CLOSE | 10 kOhm to 3V3 | open-drain CLOSE |

The three resistors establish the inactive high state even while the ESP is
booting, resetting, or being updated. Do not connect a GPIO to a KLI button
line as a push-pull high output. Firmware releases a button by returning its
GPIO to input/high impedance.

## Installed build

The photographed reference build uses direct soldered wires and three 10 kOhm
pull-ups soldered at the Wemos. Wire colours are only an assembly aid; use the
table above as the electrical source of truth.

| Wire colour | Installed connection |
|---|---|
| Black | KLI contact 1 / Wemos GND |
| Red | KLI contact 2 / Wemos 3V3 |
| Blue | KLI contact 3 / Wemos D5 (OPEN) |
| Yellow | KLI contact 4 / Wemos D6 (STOP) |
| Turquoise | KLI contact 5 / Wemos D7 (CLOSE) |

See the [installation record](../docs/INSTALLATION.md) for
the photos of this build and the fitted cover.

## Bill of materials

| Quantity | Part |
|---:|---|
| 1 | Wemos D1 mini / ESP8266-compatible board |
| 1 | VELUX KLI 313-compatible remote already paired to the target group |
| 3 | 10 kOhm resistor, 1/4 W |
| 1 | Suitable USB power supply and cable |
| 5 | Insulated hookup wires |
