# v0.1.0 Wiring Reference

Disconnect USB power and remove the KLI batteries before soldering. This is a
reference for a KLI 313-compatible board, not a guarantee for every remote
revision.

![Wemos D1 mini to KLI 313 wiring](wiring.svg)

The contact numbers refer to the five pads in the KLI PCB photo in the
external [KLI 313 ESP8266 project](https://www.chrisbue.de/velux-esp8266-smart-home-mqtt/).
They are a practical board-layout reference, not labels printed by VELUX.

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

For a reversible spring-contact and printed-holder approach, see the external
[KLI 313 ESP8266 project](https://www.chrisbue.de/velux-esp8266-smart-home-mqtt/).

## Bill of materials

| Quantity | Part |
|---:|---|
| 1 | Wemos D1 mini / ESP8266-compatible board |
| 1 | VELUX KLI 313-compatible remote already paired to the target group |
| 3 | 10 kOhm resistor, 1/4 W |
| 1 | Suitable USB power supply and cable |
| 5 | Insulated hookup wires |
