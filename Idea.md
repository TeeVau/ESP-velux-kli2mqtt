# ESP-velux-kli2mqtt

**ESP-velux-kli2mqtt** ist ein kleines Open-Source-Projekt zur WLAN- und MQTT-Anbindung von VELUX-Rollläden über eine vorhandene VELUX-KLI-Fernbedienung.

## Ausgangslage

Mehrere VELUX-Solar-Rollläden werden bereits über eine gemeinsame KLI-Fernbedienung als Gruppe gesteuert. Die Rollläden selbst kommunizieren über das proprietäre VELUX-Funksystem io-homecontrol.

Statt dieses Funkprotokoll direkt nachzubilden, wird die originale VELUX-Fernbedienung weiterhin als Funkinterface verwendet.

## Grundidee

Ein ESP8266, vorzugsweise ein **Wemos D1 mini**, wird direkt mit den drei Tastenkontakten der VELUX-KLI-Fernbedienung verbunden:

* AUF
* STOP
* AB

Der ESP simuliert elektrisch einen normalen Tastendruck. Die KLI-Fernbedienung übernimmt anschließend wie bisher die Funkkommunikation mit den Rollläden.

Der Signalweg lautet damit:

**MQTT → WLAN → ESP8266 → KLI-Fernbedienung → io-homecontrol → VELUX-Rollläden**

Die bestehende VELUX-Technik wird nicht verändert und das io-homecontrol-Protokoll muss weder analysiert noch implementiert werden.

## Hardware

Geplant ist zunächst:

* Wemos D1 mini / ESP8266
* VELUX KLI 313 bzw. kompatible KLI-Fernbedienung
* USB-Netzteil
* Versorgung der KLI über den ESP statt über AAA-Batterien
* direkte Verbindung der drei Tasteneingänge mit ESP-GPIOs
* externe Pull-up-Widerstände zur definierten Pegelführung

Vorgesehene GPIOs:

* D5 / GPIO14 → AUF
* D6 / GPIO12 → STOP
* D7 / GPIO13 → AB

Die GPIOs sollen im Open-Drain-Betrieb arbeiten. Dadurch verhält sich der ESP elektrisch ähnlich wie ein zusätzlicher Taster: Im Ruhezustand bleibt der Eingang hochohmig, bei einem Befehl wird er kurz gegen Masse gezogen.

Die externe Pull-up-Beschaltung soll zusätzlich sicherstellen, dass während Boot, Reset oder Firmwareupdate kein unbeabsichtigter Rollladenbefehl ausgelöst wird.

## Software

Der ESP verbindet sich per WLAN mit dem lokalen Netzwerk und per MQTT mit einem MQTT-Broker.

Vorgesehene Befehle sind beispielsweise:

* `OPEN`
* `STOP`
* `CLOSE`

Beispiel:

`velux/rollladen/all/set`

Zusätzlich sollen Statusinformationen des ESP bereitgestellt werden, etwa:

* Online/Offline
* letzter ausgeführter Befehl
* WLAN-Signalstärke
* Laufzeit
* freier Speicher

Die Software soll robust und weitgehend nicht blockierend aufgebaut werden. Dazu gehören insbesondere:

* automatischer WLAN-Reconnect
* automatischer MQTT-Reconnect
* MQTT Last Will
* keine retained Fahrbefehle
* Priorisierung von STOP
* Schutz gegen mehrfach bzw. zu schnell eingehende Befehle
* OTA-Firmwareupdates
* sichere GPIO-Zustände während Boot und Update

## Wichtige Abgrenzung

Der ESP erhält keine echte Positionsrückmeldung vom Rollladen.

Das System weiß daher beispielsweise, dass zuletzt `OPEN` gesendet wurde, kann daraus aber nicht zuverlässig ableiten, dass der Rollladen tatsächlich vollständig geöffnet ist.

Das Projekt bildet deshalb zunächst bewusst nur die drei real vorhandenen Funktionen der KLI-Fernbedienung ab:

**AUF – STOP – AB**

Eine künstlich berechnete Prozentposition soll nicht vorgegeben werden.

## Vorteile des Ansatzes

Der wesentliche Vorteil besteht darin, dass die vorhandene und zuverlässige VELUX-Funktechnik unverändert weiterverwendet wird.

Es muss kein proprietäres Funkprotokoll reverse-engineered werden und es sind keine Eingriffe in die Rollläden selbst notwendig.

Gleichzeitig werden die Rollläden über ein offenes Standardprotokoll in bestehende Smart-Home-Systeme integrierbar.

Damit kann die Steuerung beispielsweise aus:

* Home Assistant
* ioBroker
* Node-RED
* openHAB
* eigener Hausautomation
* MQTT-Skripten

erfolgen.

Auch die originale KLI-Fernbedienung soll weiterhin manuell bedienbar bleiben.

## Open-Source-Ziel

Das Projekt soll unter dem Namen

**ESP-velux-kli2mqtt**

öffentlich auf GitHub veröffentlicht werden.

Neben der Firmware sollen dort perspektivisch auch folgende Bestandteile dokumentiert werden:

* Schaltplan
* Pinbelegung
* Stückliste
* MQTT-Schnittstelle
* Installationsanleitung
* Konfigurationsbeispiel
* Fotos des Umbaus
* optional ein 3D-druckbares Gehäuse bzw. eine kontaktierende Aufnahme für die KLI-Fernbedienung

Ziel ist eine einfache, günstige und nachvollziehbare DIY-Lösung, mit der vorhandene VELUX-KLI-Fernbedienungen als MQTT-Bridge weiterverwendet werden können.

Das Projekt ist ein unabhängiges Community-Projekt und steht in keiner Verbindung zu VELUX.
