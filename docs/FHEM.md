# FHEM, HomeKit and Alexa

This is an installation template for an `MQTT2_DEVICE`. It reflects the device
structure used by the reference installation, but is not a drop-in definition:
replace the broker, device name, room, group, MQTT topic and voice names first.
Apply it in a testable step on the local FHEM system, then decide whether to
persist it with `save`.

The device has command semantics only. `last_command` means that the ESP
accepted a command and pulsed a KLI contact; it does not mean that the shutter
moved. The transient `state` below exists solely to give HomeKit and FHEM a
short-lived presentation state.

## Template

```text
define <DEVICE_NAME> MQTT2_DEVICE
attr <DEVICE_NAME> IODev <MQTT2_CLIENT>
attr <DEVICE_NAME> devicetopic <MQTT_ROOT_TOPIC>
attr <DEVICE_NAME> alias VELUX Rollo-Gruppe
attr <DEVICE_NAME> room Rolladen
attr <DEVICE_NAME> group Rollos
attr <DEVICE_NAME> icon fts_shutter_1w
attr <DEVICE_NAME> readingList $DEVICETOPIC/availability:.* availability\
$DEVICETOPIC/last_command:.* last_command\
$DEVICETOPIC/rssi_dbm:.* rssi_dbm\
$DEVICETOPIC/firmware_version:.* firmware_version\
$DEVICETOPIC/ota/status:.* ota_status
attr <DEVICE_NAME> setList open:noArg $DEVICETOPIC/set OPEN\
stop:noArg $DEVICETOPIC/set STOP\
close:noArg $DEVICETOPIC/set CLOSE\
position:slider,0,100,100 { return "$DEVICETOPIC/set CLOSE" if $EVTPART1 == 0; return "$DEVICETOPIC/set OPEN" if $EVTPART1 == 100; return; }
attr <DEVICE_NAME> webCmd open:stop:close
attr <DEVICE_NAME> cmdIcon open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down
attr <DEVICE_NAME> event-on-change-reading .*
attr <DEVICE_NAME> event-on-update-reading last_command
attr <DEVICE_NAME> genericDeviceType blind
attr <DEVICE_NAME> alexaName <ALEXA_NAME>
attr <DEVICE_NAME> siriName <SIRI_NAME>
attr <DEVICE_NAME> homebridgeMapping clear CurrentPosition=state,values=/^open$/:100;/^close$/:0;/.*/:50,minValue=0,maxValue=100,minStep=100 TargetPosition=position::state,values=/^open$/:100;/^close$/:0;/.*/:50,minValue=0,maxValue=100,minStep=100
attr <DEVICE_NAME> stateFormat {ReadingsVal($name,"availability","offline") eq "online" ? ReadingsVal($name,"state","idle") : "offline"}
attr <DEVICE_NAME> devStateIcon offline:10px-kreis-rot idle:fts_shutter_automatic open:fts_shutter_up stop:fts_shutter_manual close:fts_shutter_down
defmod n_<DEVICE_NAME>_Idle notify <DEVICE_NAME>:last_command:.(OPEN|STOP|CLOSE) {
  my $command=lc(ReadingsVal("<DEVICE_NAME>","last_command","idle"));
  fhem("setreading <DEVICE_NAME> state $command");
  fhem("defmod at_<DEVICE_NAME>_Idle at +00:00:30 setreading <DEVICE_NAME> state idle");
}
setreading <DEVICE_NAME> state idle
```

Replace every placeholder consistently. Enter `setList` and `homebridgeMapping`
through FHEM's attribute editor when practical: the semicolons are literal
attribute contents. The template deliberately does not include `save`.

## UI behaviour

`open`, `stop` and `close` publish the respective MQTT command. The optional
`position` setter accepts only 0 and 100 and maps them to CLOSE and OPEN. It is
not shown in `webCmd`, does not infer travel time and must not be interpreted
as a position control.

The `n_<DEVICE_NAME>_Idle` notify is required for the presentation state: on a
new `last_command` event it writes `open`, `stop` or `close` and redefines the
same 30-second `at_<DEVICE_NAME>_Idle` timer. The last command therefore wins,
and `state` returns to `idle` 30 seconds later. HomeKit sees 100 for `open`, 0
for `close` and neutral 50 for `stop` or `idle`.

## HomeKit and Alexa

HomeKit requires a configured `homebridge-fhem` instance. Alexa discovery
requires `alexa-fhem`; alternatively use routines that call the FHEM controls.
Neither integration adds physical feedback. Verify the discovered controls and
spoken names in the local installation before routine use.
