# Installation record

The tested reference build uses a KLI 313-compatible remote, a Wemos D1 mini,
direct soldered connections and a 3D-printed replacement back cover. The KLI
buttons and USB connector remain accessible.

## KLI contacts

| KLI contact | Function | Wemos connection | Wire colour in this build |
|---:|---|---|---|
| 1 | Common | GND | Black |
| 2 | Supply | 3V3 | Red |
| 3 | OPEN | D5 / GPIO14 | Blue |
| 4 | STOP | D6 / GPIO12 | Yellow |
| 5 | CLOSE | D7 / GPIO13 | Turquoise |

Each button line has a 10 kOhm pull-up to 3V3. The ESP pulls a selected line
LOW and otherwise leaves it high impedance. Contact positions are specific to
the KLI PCB revision shown here; inspect your board before soldering.

![KLI PCB before modification](../assets/kli-pcb-before-modification.jpg)

![Directly soldered KLI contacts](../assets/kli-soldered-contacts.jpg)

## Wemos and pull-ups

The three resistors sit at the Wemos pins. Their common end is 3V3; their
individual ends connect to D5, D6 and D7. This provides a defined inactive
state throughout ESP boot, reset and firmware upload.

![Wemos with the three pull-ups](../assets/wemos-pullups.jpg)

## Final assembly

The Wemos supplies the KLI from 3V3 instead of AAA cells. The USB cable exits
through the lower opening in the replacement cover.

![Completed installation with the cover open](../assets/completed-installation-open.jpg)

![Completed installation with USB power](../assets/completed-installation-powered.jpg)
