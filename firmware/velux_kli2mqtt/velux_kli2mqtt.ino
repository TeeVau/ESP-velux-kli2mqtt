#include <ESP8266WebServer.h>
#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <Updater.h>

#include "config.h"

namespace {

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
ESP8266WebServer otaServer(80);

enum class Command : uint8_t { kNone, kOpen, kStop, kClose };
enum class OtaState : uint8_t {
  kDisabled,
  kArmed,
  kUploading,
  kSucceeded,
  kFailed,
  kTimedOut,
};

Command activeCommand = Command::kNone;
Command pendingCommand = Command::kNone;
uint8_t activePin = 0;
uint32_t releaseAtMs = 0;
uint32_t cooldownUntilMs = 0;
uint32_t lastWifiAttemptMs = 0;
uint32_t lastMqttAttemptMs = 0;
uint32_t lastStatusPublishMs = 0;
uint32_t otaExpiresAtMs = 0;
uint32_t restartAtMs = 0;
bool otaUploadFailed = false;
bool otaUploadStarted = false;
OtaState otaState = OtaState::kDisabled;
char lastCommand[6] = "none";

void publish(const char* suffix, const char* value);

const char* commandName(Command command) {
  switch (command) {
    case Command::kOpen:
      return "OPEN";
    case Command::kStop:
      return "STOP";
    case Command::kClose:
      return "CLOSE";
    default:
      return "none";
  }
}

const char* otaStateName(OtaState state) {
  switch (state) {
    case OtaState::kArmed:
      return "armed";
    case OtaState::kUploading:
      return "uploading";
    case OtaState::kSucceeded:
      return "succeeded";
    case OtaState::kFailed:
      return "failed";
    case OtaState::kTimedOut:
      return "timed_out";
    default:
      return "disabled";
  }
}

String topic(const char* suffix) {
  String result(VK_MQTT_ROOT_TOPIC);
  result += suffix;
  return result;
}

void releaseButton() {
  if (activeCommand == Command::kNone) {
    return;
  }

  pinMode(activePin, INPUT);
  Serial.printf("[button] released %s\n", commandName(activeCommand));
  activeCommand = Command::kNone;
  activePin = 0;
  cooldownUntilMs = millis() + kCommandCooldownMs;
}

uint8_t pinFor(Command command) {
  switch (command) {
    case Command::kOpen:
      return kOpenPin;
    case Command::kStop:
      return kStopPin;
    case Command::kClose:
      return kClosePin;
    default:
      return 0;
  }
}

bool startButton(Command command) {
  if (command == Command::kNone || activeCommand != Command::kNone ||
      static_cast<int32_t>(millis() - cooldownUntilMs) < 0) {
    return false;
  }

  activeCommand = command;
  activePin = pinFor(command);
  pinMode(activePin, OUTPUT_OPEN_DRAIN);
  digitalWrite(activePin, LOW);
  releaseAtMs = millis() + kButtonPressMs;
  strncpy(lastCommand, commandName(command), sizeof(lastCommand));
  lastCommand[sizeof(lastCommand) - 1] = '\0';
  publish("/last_command", lastCommand);
  Serial.printf("[button] pressed %s\n", lastCommand);
  return true;
}

void updateButtons() {
  const uint32_t now = millis();
  if (activeCommand != Command::kNone &&
      static_cast<int32_t>(now - releaseAtMs) >= 0) {
    releaseButton();
  }
  if (activeCommand == Command::kNone && pendingCommand != Command::kNone &&
      static_cast<int32_t>(now - cooldownUntilMs) >= 0) {
    const Command command = pendingCommand;
    pendingCommand = Command::kNone;
    startButton(command);
  }
}

void queueCommand(Command command) {
  if (command == Command::kNone) {
    Serial.println(F("[mqtt] invalid command ignored"));
    return;
  }
  if (activeCommand == Command::kNone &&
      static_cast<int32_t>(millis() - cooldownUntilMs) >= 0) {
    startButton(command);
    return;
  }
  if (command == Command::kStop) {
    pendingCommand = Command::kStop;
    Serial.println(F("[button] STOP queued with priority"));
  } else {
    Serial.printf("[button] %s ignored during activity/cooldown\n",
                  commandName(command));
  }
}

bool parseVersion(const char* value, uint32_t parts[3]) {
  char tail = '\0';
  return sscanf(value, "%lu.%lu.%lu%c", &parts[0], &parts[1], &parts[2],
                &tail) == 3;
}

bool isSameOrNewerVersion(const char* candidate) {
  uint32_t current[3];
  uint32_t uploaded[3];
  if (!parseVersion(VK_FIRMWARE_VERSION, current) ||
      !parseVersion(candidate, uploaded)) {
    return false;
  }
  for (uint8_t index = 0; index < 3; ++index) {
    if (uploaded[index] != current[index]) {
      return uploaded[index] > current[index];
    }
  }
  return true;
}

bool startOtaUpdate() {
  const uint32_t freeSketchSpace = ESP.getFreeSketchSpace();
  if (freeSketchSpace <= 0x1000) {
    return false;
  }
  const uint32_t updateSpace = (freeSketchSpace - 0x1000) & 0xFFFFF000;
  return updateSpace > 0 && Update.begin(updateSpace);
}

void publish(const char* suffix, const char* value) {
  if (mqtt.connected()) {
    mqtt.publish(topic(suffix).c_str(), value, true);
  }
}

void publishOtaState() {
  publish("/ota/status", otaStateName(otaState));
  if (otaState != OtaState::kArmed && otaState != OtaState::kUploading) {
    publish("/ota/upload_url", "");
  }
}

void publishStatus() {
  if (!mqtt.connected()) {
    return;
  }
  char value[16];
  publish("/availability", "online");
  publish("/last_command", lastCommand);
  snprintf(value, sizeof(value), "%d", WiFi.RSSI());
  publish("/rssi_dbm", value);
  snprintf(value, sizeof(value), "%lu", millis() / 1000UL);
  publish("/uptime_s", value);
  snprintf(value, sizeof(value), "%u", ESP.getFreeHeap());
  publish("/free_heap_bytes", value);
  publish("/firmware_version", VK_FIRMWARE_VERSION);
  publishOtaState();
}

void stopOta(OtaState state) {
  otaServer.stop();
  otaState = state;
  otaExpiresAtMs = 0;
  publishOtaState();
}

void armOta() {
  if (!mqtt.connected() || WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[ota] ignored while offline"));
    return;
  }
  otaState = OtaState::kArmed;
  otaUploadStarted = false;
  otaExpiresAtMs = millis() + kOtaWindowMs;
  otaServer.begin();
  const String url = String(F("http://")) + WiFi.localIP().toString() +
                     F("/update");
  publish("/ota/upload_url", url.c_str());
  publishOtaState();
  Serial.printf("[ota] armed: %s\n", url.c_str());
}

void handleOtaForm() {
  otaServer.send(200, "text/html",
                 "<form method='POST' action='/update' enctype='multipart/form-data'>"
                 "<input type='file' name='firmware'><input type='submit'></form>");
}

void handleOtaUpload() {
  HTTPUpload& upload = otaServer.upload();
  if (upload.status == UPLOAD_FILE_START) {
    const String project = otaServer.header("X-Firmware-Project");
    const String version = otaServer.header("X-Firmware-Version");
    otaUploadStarted = true;
    otaUploadFailed = project != VK_FIRMWARE_PROJECT ||
                      !isSameOrNewerVersion(version.c_str()) ||
                      !startOtaUpdate();
    if (otaUploadFailed) {
      otaState = OtaState::kFailed;
      Serial.println(F("[ota] rejected identity, version, or flash start"));
      return;
    }
    otaState = OtaState::kUploading;
    publishOtaState();
  } else if (upload.status == UPLOAD_FILE_WRITE && !otaUploadFailed) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
      otaUploadFailed = true;
    }
  } else if (upload.status == UPLOAD_FILE_END && !otaUploadFailed) {
    otaUploadFailed = !Update.end(true);
  } else if (upload.status == UPLOAD_FILE_ABORTED) {
    otaUploadFailed = true;
    Update.end();
  }
}

void finishOtaUpload() {
  if (!otaUploadStarted || otaUploadFailed) {
    stopOta(OtaState::kFailed);
    otaServer.send(400, "text/plain", "OTA update rejected or failed.");
    return;
  }
  otaState = OtaState::kSucceeded;
  publishOtaState();
  otaServer.send(200, "text/plain", "OTA update accepted. Rebooting.");
  restartAtMs = millis() + 1000;
}

void updateOta() {
  if (otaState == OtaState::kArmed || otaState == OtaState::kUploading) {
    otaServer.handleClient();
    if (otaExpiresAtMs != 0 && static_cast<int32_t>(millis() - otaExpiresAtMs) >= 0 &&
        otaState != OtaState::kUploading) {
      stopOta(OtaState::kTimedOut);
    }
  }
  if (restartAtMs != 0 && static_cast<int32_t>(millis() - restartAtMs) >= 0) {
    ESP.restart();
  }
}

void onMqttMessage(char* incomingTopic, byte* payload, unsigned int length) {
  char message[16] = {};
  if (length >= sizeof(message)) {
    Serial.println(F("[mqtt] oversized payload ignored"));
    return;
  }
  memcpy(message, payload, length);

  if (strcmp(incomingTopic, topic("/set").c_str()) == 0) {
    if (strcmp(message, "OPEN") == 0) {
      queueCommand(Command::kOpen);
    } else if (strcmp(message, "STOP") == 0) {
      queueCommand(Command::kStop);
    } else if (strcmp(message, "CLOSE") == 0) {
      queueCommand(Command::kClose);
    } else {
      queueCommand(Command::kNone);
    }
  } else if (strcmp(incomingTopic, topic("/ota/set").c_str()) == 0) {
    if (strcmp(message, "ENABLE") == 0) {
      armOta();
    } else if (strcmp(message, "CANCEL") == 0) {
      stopOta(OtaState::kDisabled);
    } else {
      Serial.println(F("[ota] invalid command ignored"));
    }
  }
}

void updateWifi() {
#ifdef VK_CONFIG_PLACEHOLDER
  return;
#else
  if (WiFi.status() == WL_CONNECTED ||
      static_cast<int32_t>(millis() - lastWifiAttemptMs) < 0) {
    return;
  }
  lastWifiAttemptMs = millis() + kWifiRetryMs;
  Serial.println(F("[wifi] connecting"));
  WiFi.begin(VK_WIFI_SSID, VK_WIFI_PASSWORD);
#endif
}

void updateMqtt() {
#ifdef VK_CONFIG_PLACEHOLDER
  return;
#else
  if (WiFi.status() != WL_CONNECTED || mqtt.connected() ||
      static_cast<int32_t>(millis() - lastMqttAttemptMs) < 0) {
    return;
  }
  lastMqttAttemptMs = millis() + kMqttRetryMs;
  char clientId[32];
  snprintf(clientId, sizeof(clientId), "velux-kli-%06X", ESP.getChipId());
  const String availability = topic("/availability");
  if (!mqtt.connect(clientId, VK_MQTT_USERNAME, VK_MQTT_PASSWORD,
                    availability.c_str(), 0, true, "offline")) {
    Serial.printf("[mqtt] connect failed: %d\n", mqtt.state());
    return;
  }
  mqtt.subscribe(topic("/set").c_str());
  mqtt.subscribe(topic("/ota/set").c_str());
  Serial.println(F("[mqtt] connected"));
  publishStatus();
#endif
}

void setupOtaRoutes() {
  otaServer.collectHeaders("X-Firmware-Project", "X-Firmware-Version");
  otaServer.on("/update", HTTP_GET, handleOtaForm);
  otaServer.on("/update", HTTP_POST, finishOtaUpload, handleOtaUpload);
  otaServer.onNotFound([]() { otaServer.send(404, "text/plain", "Not found"); });
}

}  // namespace

void setup() {
  pinMode(kOpenPin, INPUT);
  pinMode(kStopPin, INPUT);
  pinMode(kClosePin, INPUT);
  Serial.begin(115200);
  Serial.println();
  Serial.printf("[boot] %s %s\n", VK_FIRMWARE_PROJECT, VK_FIRMWARE_VERSION);
#ifdef VK_CONFIG_PLACEHOLDER
  Serial.println(F("[boot] create secrets.h; network remains disabled"));
#endif
  WiFi.mode(WIFI_STA);
  mqtt.setServer(VK_MQTT_HOST, VK_MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  setupOtaRoutes();
}

void loop() {
  updateButtons();
  updateWifi();
  updateMqtt();
  if (mqtt.connected()) {
    mqtt.loop();
    if (static_cast<int32_t>(millis() - lastStatusPublishMs) >= 0) {
      lastStatusPublishMs = millis() + kStatusIntervalMs;
      publishStatus();
    }
  }
  updateOta();
}
