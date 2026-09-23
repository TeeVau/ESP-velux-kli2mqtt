# ESP-velux-kli2mqtt — Idea

This document mirrors the initial project brief in [Idea.md](../Idea.md). It is
kept under `docs/` so the public engineering documents have one home.

The project turns one existing VELUX KLI 313 (or compatible) wall remote into
an MQTT-controlled bridge. A Wemos D1 mini electrically presses the remote's
OPEN, STOP and CLOSE buttons; it does not implement io-homecontrol and does not
claim to know shutter position.

## Decisions made before implementation

- Target: Wemos D1 mini / ESP8266 using Arduino CLI.
- KLI wiring: 3.3 V and GND from the Wemos; GPIO14/D5=OPEN,
  GPIO12/D6=STOP, GPIO13/D7=CLOSE.
- Every button line has an external 10 kOhm pull-up to 3.3 V. The ESP only
  pulls a line to GND via open-drain output.
- Configuration lives only in ignored `secrets.h`.
- MQTT commands are `OPEN`, `STOP`, and `CLOSE`; command messages must never
  be retained.
- OTA is enabled temporarily by MQTT, requires no separate password, and
  accepts this project identity at the same or a newer version.
- v0.1.0 documents direct soldering. A later mechanical revision may add a
  reversible contact plate or enclosure.
